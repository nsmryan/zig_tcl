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

    var args: std.meta.ArgsTuple(@TypeOf(function)) = undefined;

    // The arguents will have an extra field for the cdata to pass into.
    // The objc starts with the command and and proc name.
    if (args.len + 1 != objc) {
        return err.TclError.TCL_ERROR;
    }

    // Fill in the first argument using cdata.
    // NOTE this assumes a pointer for now- perhaps a 'self' that is not a pointer could also be supported.
    const self_type = @typeInfo(@TypeOf(function)).Fn.args[0].arg_type.?;
    args[0] = @ptrCast(self_type, @alignCast(@alignOf(self_type), cdata));

    comptime var argIndex = 1;
    inline while (argIndex < args.len) : (argIndex += 1) {
        args[argIndex] = try obj.GetFromObj(@TypeOf(args[argIndex]), interp, objv[argIndex + 1]);
    }

    return CallZigFunction(function, interp, args);
}

pub fn CallZigFunction(comptime function: anytype, interp: obj.Interp, args: anytype) err.TclError!void {
    const func_info = @typeInfo(@TypeOf(function));
    if (func_info.Fn.return_type) |typ| {
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
        } else {
            // If no error return, just call and convert result to a TCL object.
            obj.SetObjResult(interp, try obj.ToObj(@call(.{}, function, args)));
        }
    } else {
        // If no return, just call the function.
        @call(.{}, function, args);
    }
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
    var objv: [3][*c]tcl.Tcl_Obj = .{ try obj.ToObj("obj"), try obj.ToObj("func"), try obj.ToObj(@as(u32, 2)) };
    try CallDecl(s.func, interp, &instance, objv.len, &objv);
}
