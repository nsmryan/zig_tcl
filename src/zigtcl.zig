const std = @import("std");
const testing = std.testing;

pub const err = @import("err.zig");
usingnamespace err;

pub const obj = @import("obj.zig");
usingnamespace obj;

pub const tcl = @import("tcl.zig");
usingnamespace tcl;

// NOTES
// create a command that is given a string name, and cdata is a pointer to an allocator,
// and creates a command of that name. The new command's cdata is a pointer to a struct and an allocator.
// its destroy function deallocates it, and perhaps the allocation containing the struct pointer and allocator.
// CData(T) = *T x Allocator. Maybe general purpose allocate this.
// or
// CData(T) = T x Allocator. The allocator's memory contains an allocator structure to use for dellocation.
//
// Consider adding another parameter to the CData- a pointer to the implementing function. All commands would use the same handler,
// which would pass arguments to the implementing function and handle error returns. If an error, turn to c_int and return, otherwise
// return TCL_OK. In this design, wrap used TCL C API functions in trivial ziggy versions that return error codes.
//
// Consider a global map from pointers to allocator used in destructors to deallocate instead of putting allocators into memory
// with the struct, which seems problematic for generic types without more pointers.
//
// Possible goals:
// Struct manager command using heavy comptime- given a type and allocator, allocate type and store allocator,
// try to fill in struct fields, register a destructor, and a command that comptime calls into decls of the struct, if possible.
//
// Interface- user defines their own init function and provides an allocator for smuggling things in. They can use another
// allocator for their structs.
// They can define wrapped commands, and define struct wrappers for passing calls on to decls.
// Maybe a wrapper for a pointer that just passes the cdata to the given function as well.

// TCL Allocator
// Need to figure out allocators and how to wrap TCL's
//pub fn TclAlloc(ptr: *u0, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Error![]u8 {
//    return tcl.Tcl_Alloc(len);
//}
//
//pub fn TclResize(ptr: *u0, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) ?usize {
//}
//
//pub fn TclFree(ptr: *u0, buf: []u8, buf_align: u29, ret_addr: usize) void {
//}
//
//pub fn TclAllocator() std.mem.Allocator {
//    return std.mem.Allocator.init(null, TclAlloc, TclResize, TclFree);
//}

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

pub const StructCmds = enum {
    create,
};

pub fn StructCommand(comptime strt: type) type {
    return struct {
        pub fn command(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objv: []const obj.Obj) err.TclError!void {
            _ = cdata;

            if (objv.len < 2) {
                try obj.WrongNumArgs(interp, objv, "create name");
                return err.TclError.TCL_ERROR;
            }

            // NOTE(zig) It is quite nice that std.meta can give us this array. This makes things easier then in C.
            // The following switch is also better then the C version.
            switch (try obj.GetIndexFromObj(StructCmds, interp, objv[1], "commands")) {
                .create => {
                    if (objv.len < 3) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "create name");
                        return err.TclError.TCL_ERROR;
                    }

                    var length: c_int = undefined;
                    const name = tcl.Tcl_GetStringFromObj(objv[2], &length);
                    var ptr = tcl.Tcl_Alloc(@sizeOf(strt));
                    const result = tcl.Tcl_CreateObjCommand(interp, name, StructInstanceCommand, @ptrCast(tcl.ClientData, ptr), TclDeallocateCallback);
                    if (result == null) {
                        obj.SetStrResult(interp, "Could not create command!");
                        return err.TclError.TCL_ERROR;
                    } else {
                        return;
                    }
                    //return tcl.Tcl_CreateObjCommand(interp, name, StructInstanceCommand, @intToPtr(tcl.ClientData, @ptrToInt(ptr)), null);
                },
            }

            obj.SetStrResult(interp, "Unexpected subcommand name when creating struct!");
            return err.TclError.TCL_ERROR;
        }

        fn StructInstanceCommand(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) callconv(.C) c_int {
            _ = cdata;
            // support the cget, field, call, configure interface in syntax.tcl
            if (objc < 2) {
                tcl.Tcl_WrongNumArgs(interp, objc, objv, "field name [value]");
                return tcl.TCL_ERROR;
            }

            var strt_ptr = @ptrCast(*strt, @alignCast(@alignOf(strt), cdata));
            const cmd = obj.GetIndexFromObj(StructInstanceCmds, interp, objv[1], "commands") catch |errResult| return err.TclResult(errResult);
            switch (cmd) {
                .get => {
                    return StructGetFieldCmd(strt_ptr, interp, objc, objv);
                },
            }
            obj.SetStrResult(interp, "Unexpected subcommand!");
            return tcl.TCL_ERROR;
        }

        pub fn StructGetFieldCmd(ptr: *strt, interp: obj.Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
            if (objc < 3) {
                tcl.Tcl_WrongNumArgs(interp, objc, objv, "get name ...");
                return tcl.TCL_ERROR;
            }

            // Preallocate enough space for all requested fields, and replace elements
            // as we go.
            var resultList = obj.NewListWithCapacity(objc - 2);
            var index: usize = 2;
            while (index < objc) : (index += 1) {
                var length: c_int = undefined;
                const name = tcl.Tcl_GetStringFromObj(objv[index], &length);
                if (length == 0) {
                    continue;
                }

                var found: bool = false;
                inline for (@typeInfo(strt).Struct.fields) |field| {
                    if (std.mem.eql(u8, name[0..@intCast(usize, length)], field.name)) {
                        found = true;
                        var fieldObj = StructGetField(ptr, field.name) catch |errResult| return err.TclResult(errResult);
                        const result = tcl.Tcl_ListObjReplace(interp, resultList, @intCast(c_int, index), 1, 1, &fieldObj);
                        if (result != tcl.TCL_OK) {
                            obj.SetStrResult(interp, "Failed to retrieve a field from a struct!");
                            return result;
                        }
                        break;
                    }
                }

                if (!found) {
                    obj.SetStrResult(interp, "One or more field names not found in struct get!");
                    return tcl.TCL_ERROR;
                }
            }

            obj.SetObjResult(interp, resultList);

            return tcl.TCL_OK;
        }

        pub fn StructGetField(ptr: *strt, comptime fieldName: []const u8) err.TclError!obj.Obj {
            return obj.ToObj(@field(ptr.*, fieldName));
        }
    };
}

pub const StructInstanceCmds = enum {
    get,
};

pub fn TclDeallocateCallback(cdata: tcl.ClientData) callconv(.C) void {
    tcl.Tcl_Free(@ptrCast([*c]u8, cdata));
}

pub fn RegisterStruct(comptime strt: type, comptime pkg: []const u8, interp: obj.Interp) c_int {
    const terminator: [1]u8 = .{0};
    const cmdName = pkg ++ "::" ++ @typeName(strt) ++ terminator;
    _ = obj.CreateObjCommand(interp, cmdName, StructCommand(strt).command) catch |errResult| return err.ErrorToInt(errResult);

    return tcl.TCL_OK;
}
