const std = @import("std");
const testing = std.testing;

const err = @import("err.zig");

const obj = @import("obj.zig");

const tcl = @import("tcl.zig");

// NOTE there seem to be two possible designs here:
// 1) try to pass a function at comptime, creating a function which calls this function, as a kind
//   of comptime closure
// 2) try to create a struct which has the user function as an argument. Allocate this struct,
// either with tcl or a given allocator, and use it as cdata.
//
// The first is likely preferable as it does not require allocation, and the comptime restriction doesn't
// seem all that bad for an extension, but I'm not positive.
//
// This implements the comptime wrapper concept.
pub fn WrapFunction(comptime function: anytype, name: [*:0]const u8, outer_interp: obj.Interp) err.TclError!void {
    const cmd = struct {
        pub fn cmd(cdata: tcl.ClientData, interp: obj.Interp, objv: []const [*c]tcl.Tcl_Obj) err.TclError!void {
            _ = cdata;
            var args: std.meta.ArgsTuple(@TypeOf(function)) = undefined;

            if ((args.len + 1) != objv.len) {
                return err.TclError.TCL_ERROR;
            }

            comptime var index = 0;
            inline while (index < args.len) : (index += 1) {
                args[index] = try obj.GetFromObj(@TypeOf(args[index]), interp, objv[index + 1]);
            }

            return CallZigFunction(function, interp, args);
        }
    }.cmd;
    _ = try obj.CreateObjCommand(outer_interp, name, cmd);
}

// Wrap a declaration taking a pointer to self as the first argument.
// The 'self' pointer comes from cdata, rather then getting passed in with objv.
// NOTE this is untested! make a decl in the example, register it, and try.
pub fn CallDecl(comptime function: anytype, interp: obj.Interp, cdata: tcl.ClientData, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) err.TclError!void {
    // This tests seems to fail for Fn and BoundFn.
    //if (!std.meta.trait.is(.Fn)(@TypeOf(function))) {
    //    @compileError("Cannot wrap a decl that is not a function!");
    //}

    var args: ArgsTuple(@TypeOf(function)) = undefined;

    // The arguents will have an extra field for the cdata to pass into.
    // The objc starts with the command and and proc name.
    if (args.len + 2 != objc) {
        std.debug.print("objc error {} {}\n", .{ args.len, objc });
        return err.TclError.TCL_ERROR;
    }

    // Fill in the first argument using cdata.
    // NOTE this assumes a pointer for now- perhaps a 'self' that is not a pointer could also be supported.
    const func_info = FuncInfo(@typeInfo(@TypeOf(function)));
    const self_type = func_info.args[0].arg_type.?;
    args[0] = @ptrCast(self_type, @alignCast(@alignOf(self_type), cdata));

    comptime var argIndex = 2;
    inline while (argIndex < args.len) : (argIndex += 1) {
        args[argIndex] = try obj.GetFromObj(@TypeOf(args[argIndex]), interp, objv[argIndex + 2]);
    }

    std.debug.print("calling \n", .{});
    return CallZigFunction(function, interp, args);
}

pub fn FuncInfo(comptime func_info: std.builtin.TypeInfo) std.builtin.TypeInfo.Fn {
    if (func_info == .Fn) {
        return func_info.Fn;
    } else if (func_info == .BoundFn) {
        return func_info.BoundFn;
    } else {
        @compileError("Cannot get function info from a non-function!");
    }
}

pub fn CallZigFunction(comptime function: anytype, interp: obj.Interp, args: anytype) err.TclError!void {
    const func_info = @typeInfo(@TypeOf(function));
    const return_type = FuncInfo(func_info).return_type;
    if (return_type) |typ| {
        // If the function has a return value, check if it is an error.
        if (@typeInfo(typ) == .ErrorUnion) {
            if (@typeInfo(@typeInfo(typ).ErrorUnion.payload) != .Void) {
                // If the function returns an error, expose this to TCL as a string name,
                // and return TCL_ERROR to trigger an exception.
                // NOTE I'm not sure whether void will work here, or if we need to check explicitly for it.
                if (@call(.{}, function, args)) |result| {
                    obj.SetObjResult(interp, try obj.ToObj(result));
                } else |errResult| {
                    obj.SetObjResult(interp, obj.NewStringObj(@errorName(errResult)));
                    return err.TclError.TCL_ERROR;
                }
            } else {
                // Otherwise only error, void return. This case may not be strictly necessary,
                // but it should avoid an object allocation in this path, even an empty one.
                @call(.{}, function, args) catch |errResult| {
                    obj.SetObjResult(interp, obj.NewStringObj(@errorName(errResult)));
                };
            }
            std.debug.print("error return\n", .{});
        } else {
            std.debug.print("No error return\n", .{});
            // NOTE called with help from Tetralux and Der Teufel
            // If no error return, just call and convert result to a TCL object.
            const result = @call(.{}, function, args);
            std.debug.print("{}\n", .{result});
            obj.SetObjResult(interp, try obj.ToObj(result));
        }
    } else {
        std.debug.print("No return\n", .{});
        // If no return, just call the function.
        @call(.{}, function, args);
    }
}

pub fn ArgsTuple(comptime Function: type) type {
    const info = @typeInfo(Function);
    //if (info != .Fn)
    //@compileError("ArgsTuple expects a function type");

    const function_info = FuncInfo(info);
    if (function_info.is_generic)
        @compileError("Cannot create ArgsTuple for generic function");
    if (function_info.is_var_args)
        @compileError("Cannot create ArgsTuple for variadic function");

    var argument_field_list: [function_info.args.len]type = undefined;
    inline for (function_info.args) |arg, i| {
        const T = arg.arg_type.?;
        argument_field_list[i] = T;
    }

    return CreateUniqueTuple(argument_field_list.len, argument_field_list);
}

fn CreateUniqueTuple(comptime N: comptime_int, comptime types: [N]type) type {
    var tuple_fields: [types.len]std.builtin.Type.StructField = undefined;
    inline for (types) |T, i| {
        @setEvalBranchQuota(10_000);
        var num_buf: [128]u8 = undefined;
        tuple_fields[i] = .{
            .name = std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch unreachable,
            .field_type = T,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(T) > 0) @alignOf(T) else 0,
        };
    }

    return @Type(.{
        .Struct = .{
            .is_tuple = true,
            .layout = .Auto,
            .decls = &.{},
            .fields = &tuple_fields,
        },
    });
}

test "call zig function with return" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const func = struct {
        fn testIntFunction(first: u8, second: u16) u32 {
            return (first + second);
        }
    }.testIntFunction;

    try CallZigFunction(func, interp, .{ 1, 2 });
    try std.testing.expectEqual(@as(u32, 3), try obj.GetFromObj(u32, interp, tcl.Tcl_GetObjResult(interp)));
}

test "call zig function without return" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const func = struct {
        fn testIntFunction() void {
            return;
        }
    }.testIntFunction;

    try CallZigFunction(func, interp, .{});
    try obj.GetFromObj(void, interp, tcl.Tcl_GetObjResult(interp));
}

test "call decl" {
    const s = struct {
        field: u32 = 1,

        pub fn init() @This() {
            return .{};
        }

        pub fn func(self: *@This(), arg: u32) u32 {
            return arg + self.field;
        }
    };

    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var instance: s = s.init();
    var objv: [4][*c]tcl.Tcl_Obj = .{ try obj.ToObj("obj"), try obj.ToObj("call"), try obj.ToObj("func"), try obj.ToObj(@as(u32, 2)) };
    try CallDecl(s.func, interp, &instance, objv.len, &objv);
}
