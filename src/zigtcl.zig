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
    _ = obj.CreateObjCommand(outer_interp, name, cmd);
}

// Wrap a declaration taking a pointer to self as the first argument.
// The 'self' pointer comes from cdata, rather then getting passed in with objv.
// NOTE this is untested! make a decl in the example, register it, and try.
// TODO modify this to call the function, rather then register it. This is for decls, which will
// be called in a registered function, not registered themselves this way.
pub fn WrapDecl(comptime function: anytype, interp: obj.Interp, cdata: tcl.ClientData, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) err.TclError!void {
    _ = cdata;

    // This tests seems to fail for Fn and BoundFn.
    //if (!std.meta.trait.is(.Fn)(@TypeOf(function))) {
    //    @compileError("Cannot wrap a decl that is not a function!");
    //}

    var args: std.meta.ArgsTuple(@TypeOf(function)) = undefined;

    if ((args.len + 1) != objc) {
        return err.TclError.TCL_ERROR;
    }

    // Fill in the first argument using cdata.
    // NOTE this assumes a pointer for now- perhaps a 'self' that is not a pointer could also be supported.
    const self_type = @typeInfo(@TypeOf(function)).Fn.args[0].arg_type.?;
    args[0] = @ptrCast(self_type, @alignCast(@alignOf(self_type), cdata));

    comptime var index = 1;
    inline while (index < args.len) : (index += 1) {
        args[index] = try obj.GetFromObj(@TypeOf(args[index]), interp, objv[index + 1]);
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
                    obj.SetObjResult(interp, try obj.NewObj(result));
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
            // If not, just call and convert result to a TCL object.
            obj.SetObjResult(interp, try obj.NewObj(@call(.{}, function, args)));
        }
    } else {
        // If no return, just call the function.
        @call(.{}, function, args);
    }
}

test "function tuples" {
    const func = struct {
        fn testIntFunction(first: u8, second: u16) u32 {
            return (first + second);
        }
    }.testIntFunction;

    var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;

    comptime var index = 0;
    inline while (index < args.len) : (index += 1) {
        args[index] = std.mem.zeroes(@TypeOf(args[index]));
    }
    _ = @call(.{}, func, args);
}

test "uint objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    {
        const int: u8 = std.math.maxInt(u8);
        try std.testing.expectEqual(int, try obj.GetFromObj(u8, interp, try obj.NewObj(int)));
    }

    {
        const int: u16 = std.math.maxInt(u16);
        try std.testing.expectEqual(int, try obj.GetFromObj(u16, interp, try obj.NewObj(int)));
    }

    {
        const int: u32 = std.math.maxInt(u32);
        try std.testing.expectEqual(int, try obj.GetFromObj(u32, interp, try obj.NewObj(int)));
    }

    {
        const int: u64 = std.math.maxInt(u64);
        try std.testing.expectEqual(int, try obj.GetFromObj(u64, interp, try obj.NewObj(int)));
    }
}

test "int objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    {
        const int: i8 = std.math.minInt(i8);
        try std.testing.expectEqual(int, try obj.GetFromObj(i8, interp, try obj.NewObj(int)));
    }

    {
        const int: i16 = std.math.minInt(i16);
        try std.testing.expectEqual(int, try obj.GetFromObj(i16, interp, try obj.NewObj(int)));
    }

    {
        const int: i32 = std.math.minInt(i32);
        try std.testing.expectEqual(int, try obj.GetFromObj(i32, interp, try obj.NewObj(int)));
    }

    {
        const int: i64 = std.math.minInt(i64);
        try std.testing.expectEqual(int, try obj.GetFromObj(i64, interp, try obj.NewObj(int)));
    }
}

test "bool objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);
    var bl: bool = true;
    try std.testing.expectEqual(bl, try obj.GetFromObj(bool, interp, try obj.NewObj(bl)));
    bl = false;
    try std.testing.expectEqual(bl, try obj.GetFromObj(bool, interp, try obj.NewObj(bl)));
}

test "float objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const flt: f32 = std.math.f32_max;
    try std.testing.expectEqual(flt, try obj.GetFromObj(f32, interp, try obj.NewObj(flt)));

    const dbl: f64 = std.math.f64_max;
    try std.testing.expectEqual(dbl, try obj.GetFromObj(f64, interp, try obj.NewObj(dbl)));
}

test "enum objs" {
    const enm = enum {
        A,
    };

    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const enm_value: enm = .A;
    try std.testing.expectEqual(enm_value, try obj.GetFromObj(enm, interp, try obj.NewObj(enm_value)));
}

test "array objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const arr: [3]u8 = .{ 1, 2, 3 };
    try std.testing.expectEqual(arr, try obj.GetFromObj([3]u8, interp, try obj.NewObj(&arr)));
}

test "union objs" {
    const un = union(enum) {
        flt: f32,
        int: u64,
    };

    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const un_value: un = .{ .flt = 0.1 };
    try std.testing.expectEqual(un_value, try obj.GetFromObj(un, interp, try obj.NewObj(&un_value)));
}

test "struct objs" {
    const strt = struct {
        flt: f32,
        int: u64,
    };

    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const strt_value: strt = .{ .flt = 0.1, .int = 1 };
    try std.testing.expectEqual(strt_value, try obj.GetFromObj(strt, interp, try obj.NewObj(&strt_value)));
}

test "fn obj" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const func = struct {
        fn test_func(arg: u8) u8 {
            return arg + 1;
        }
    }.test_func;

    try std.testing.expectEqual(func, try obj.GetFromObj(fn (u8) u8, interp, try obj.NewObj(func)));
}

test "ptr obj" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var value: u8 = 255;

    try std.testing.expectEqual(&value, try obj.GetFromObj(*u8, interp, try obj.NewObj(&value)));
}
