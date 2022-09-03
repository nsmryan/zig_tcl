const std = @import("std");
const testing = std.testing;

const err = @import("err.zig");

const tcl = @import("tcl.zig");

///Tcl_GetIntFromObj wrapper.
pub fn GetIntFromObj(interp: Interp, obj: Obj) err.TclError!c_int {
    var int: c_int = 0;
    const result = tcl.Tcl_GetIntFromObj(interp, obj, &int);

    err.HandleReturn(result) catch |errValue| return errValue;
    return int;
}

// Tcl_GetLongFromObj wrapper
pub fn GetLongFromObj(interp: Interp, obj: Obj) err.TclError!c_long {
    var long: c_long = 0;
    const result = tcl.Tcl_GetLongFromObj(interp, obj, &long);

    err.HandleReturn(result) catch |errValue| return errValue;
    return long;
}

// Tcl_GetWideIntFromObj wrapper
pub fn GetWideIntFromObj(interp: Interp, obj: Obj) err.TclError!c_longlong {
    var wide: tcl.Tcl_WideInt = 0;
    const result = tcl.Tcl_GetWideIntFromObj(interp, obj, &wide);

    err.HandleReturn(result) catch |errValue| return errValue;
    return wide;
}

///Tcl_GetDoubleFromObj wrapper.
pub fn GetDoubleFromObj(interp: Interp, obj: Obj) err.TclError!f64 {
    var int: f64 = 0;
    const result = tcl.Tcl_GetDoubleFromObj(interp, obj, &int);

    err.HandleReturn(result) catch |errValue| return errValue;
    return int;
}

pub fn NewObj() err.TclError!Obj {
    const result = tcl.Tcl_NewObj();
    if (result == null) {
        return err.TclError.TCL_ERROR;
    } else {
        return result;
    }
}

pub fn NewByteArrayObj(value: anytype) err.TclError!Obj {
    const ptr = @ptrCast([*c]const u8, &value);
    const result = tcl.Tcl_NewByteArrayObj(ptr, @sizeOf(@TypeOf(value)));
    if (result == null) {
        return err.TclError.TCL_ERROR;
    } else {
        return result;
    }
}

fn NullTerminatedNames(comptime enm: type) []const [*c]const u8 {
    comptime {
        const commandNames = std.meta.fieldNames(enm);

        var names: [commandNames.len][*c]const u8 = undefined;
        inline for (commandNames) |commandName, index| {
            names[index] = @ptrCast([*c]const u8, std.fmt.comptimePrint("{s}", .{commandName}));
        }
        return names[0..];
    }
}

pub fn GetIndexFromObj(comptime enm: type, interp: Interp, name: Obj, msg: [*c]const u8) err.TclError!enm {
    const commandNames = NullTerminatedNames(enm);

    var index: c_int = undefined;
    // NOTE fixing 0 as the flags: could take as parameter.
    if (tcl.Tcl_GetIndexFromObj(interp, name, @ptrCast([*c]const [*c]const u8, commandNames.ptr), msg, 0, &index) == tcl.TCL_OK) {
        return @intToEnum(enm, index);
    } else {
        return err.TclError.TCL_ERROR;
    }
}

pub fn ObjSlice(objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) []const Obj {
    return objv[0..@intCast(usize, objc)];
}

pub fn WrongNumArgs(interp: Interp, objv: []const Obj, errorString: [*c]const u8) void {
    tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, errorString);
}

// NOTE Should this slice to length - 1?
pub fn GetStringFromObj(obj: Obj) err.TclError![]const u8 {
    var length: c_int = undefined;
    const str = tcl.Tcl_GetStringFromObj(obj, &length);
    return str[0..@intCast(usize, length)];
}

/// Tcl_ListObjAppendElement wrapper.
pub fn ListObjAppendElement(interp: Interp, list: Obj, obj: Obj) err.TclError!void {
    const result = tcl.Tcl_ListObjAppendElement(interp, list, obj);
    return err.HandleReturn(result);
}

/// Tcl_NewStringObj wrapper.
pub fn NewStringObj(str: []const u8) Obj {
    return tcl.Tcl_NewStringObj(str.ptr, @intCast(c_int, str.len));
}

pub fn NewListWithCapacity(capacity: c_int) Obj {
    return tcl.Tcl_NewListObj(capacity, null);
}

// Tcl_NewListObj wrapper
pub fn NewListObj(objs: []Obj) Obj {
    return tcl.Tcl_NewListObj(@intCast(c_int, objs.len), objs.ptr);
}

// Tcl_SetObjResult wrapper
pub fn SetObjResult(interp: Interp, obj: Obj) void {
    tcl.Tcl_SetObjResult(interp, obj);
}

// Tcl_SetObjResult wrapper
pub fn SetStrResult(interp: Interp, str: [*c]const u8) void {
    SetObjResult(interp, tcl.Tcl_NewStringObj(str, -1));
}

/// Tcl_NewIntObj wrapper for all int types (Int, Long, WideInt).
pub fn NewIntObj(value: anytype) Obj {
    switch (@typeInfo(@TypeOf(value))) {
        .Int => |info| {
            if (info.bits < @bitSizeOf(c_int)) {
                return tcl.Tcl_NewIntObj(@intCast(c_int, value));
            } else if (info.bits == @bitSizeOf(c_int)) {
                return tcl.Tcl_NewIntObj(@bitCast(c_int, value));
            } else if (info.bits < @bitSizeOf(c_long)) {
                return tcl.Tcl_NewLongObj(@intCast(c_long, value));
            } else if (info.bits == @bitSizeOf(c_long)) {
                return tcl.Tcl_NewLongObj(@bitCast(c_long, value));
            } else if (info.bits < @bitSizeOf(tcl.Tcl_WideInt)) {
                return tcl.Tcl_NewWideObj(@intCast(tcl.Tcl_WideInt, value));
            } else if (info.bits == @bitSizeOf(tcl.Tcl_WideInt)) {
                return tcl.Tcl_NewWideObj(@bitCast(tcl.Tcl_WideInt, value));
            } else {
                @compileError("Int type too wide for a Tcl_WideInt!");
            }
        },

        .ComptimeInt => {
            @compileError("Integer must not be comptime! It must have a specific runtime type");
        },

        else => {
            @compileError("NewIntObj expects an integer type!");
        },
    }
}

pub const Interp = [*c]tcl.Tcl_Interp;
//pub const ClientData = tcl.ClientData;
pub const Obj = [*c]tcl.Tcl_Obj;
//pub const Command = tcl.Tcl_Command;

pub const ZigTclCmd = fn (cdata: tcl.ClientData, interp: Interp, objv: []const Obj) err.TclError!void;

pub fn CallCmd(function: ZigTclCmd, cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    return err.TclResult(function(cdata, interp, objv[0..@intCast(usize, objc)]));
}

/// Call a ZigTclCmd function, passing in the TCL C API style arguments and returning a c_int result.
pub export fn Wrap_ZigCmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    var function = @ptrCast(ZigTclCmd, cdata);
    return CallCmd(function, cdata, interp, objc, objv);
}

/// Create a new TCL command that executes a Zig function.
/// The Zig function is given using the ziggy ZigTclCmd signature.
pub fn CreateObjCommand(interp: Interp, name: [*:0]const u8, function: ZigTclCmd) err.TclError!tcl.Tcl_Command {
    const result = tcl.Tcl_CreateObjCommand(interp, name, Wrap_ZigCmd, @intToPtr(tcl.ClientData, @ptrToInt(function)), null);
    if (result == null) {
        return err.TclError.TCL_ERROR;
    }
    return result;
}

pub fn GetFromObj(comptime T: type, interp: Interp, obj: Obj) err.TclError!T {
    switch (@typeInfo(T)) {
        .Bool => return (try GetIntFromObj(interp, obj)) != 0,

        .Int => |info| {
            if (info.bits < @bitSizeOf(c_int)) {
                return @intCast(T, try GetIntFromObj(interp, obj));
            } else if (info.bits == @bitSizeOf(c_int)) {
                return @bitCast(T, try GetIntFromObj(interp, obj));
            } else if (info.bits < @bitSizeOf(c_long)) {
                return @intCast(T, try GetLongFromObj(interp, obj));
            } else if (info.bits == @bitSizeOf(c_long)) {
                return @bitCast(T, try GetLongFromObj(interp, obj));
            } else if (info.bits < @bitSizeOf(tcl.Tcl_WideInt)) {
                return @intCast(T, try GetWideIntFromObj(interp, obj));
            } else if (info.bits == @bitSizeOf(tcl.Tcl_WideInt)) {
                return @bitCast(T, try GetWideIntFromObj(interp, obj));
            } else {
                @compileError("Int type too wide for a Tcl_WideInt!");
            }
        },

        .Void => {
            return;
        },

        .Float => |info| {
            const dbl = try GetDoubleFromObj(interp, obj);
            if (32 == info.bits) {
                return @floatCast(f32, dbl);
            } else {
                return dbl;
            }
        },

        // TODO this is not necessarily the correct thing to do. A pointer can be a string, a block,
        // or an integer pointer. Perhaps provide separate functions for these?
        .Pointer => return @intToPtr(T, @intCast(usize, try GetWideIntFromObj(interp, obj))),

        // NOTE This implementation may result in more work then necessary! I'm not sure that it actually shimmers
        // the enum, but by using it as a string, the string of the integer representation will be constructed and
        // matched. Unforunately there is not way to know that an object is an integer that I know of, except perhaps
        // by inspecting its internals. The other option is to register some Zig specific types that have a fixed
        // internal representation, perhaps with both a pointer to a (static) string and an integer value.
        .Enum => {
            const str = try GetStringFromObj(obj);
            if (std.meta.stringToEnum(T, str)) |enm| {
                return enm;
            } else {
                return @intToEnum(T, try GetIntFromObj(interp, obj));
            }
        },

        .Array => {
            var length: c_int = undefined;
            var bytes = tcl.Tcl_GetByteArrayFromObj(obj, &length);

            const ptr = @ptrCast(*T, bytes);
            return ptr.*;
        },

        // This may not be the only way to do this. Passing pointers to TCL like this is not generally
        // a good idea. A similar comment applies to Struct.
        .Union => {
            var length: c_int = undefined;
            var bytes = tcl.Tcl_GetByteArrayFromObj(obj, &length);

            const ptr = @ptrCast(*T, @alignCast(@alignOf(T), bytes));
            return ptr.*;
        },

        .Struct => {
            var length: c_int = undefined;
            var bytes = tcl.Tcl_GetByteArrayFromObj(obj, &length);

            const ptr = @ptrCast(*T, @alignCast(@alignOf(T), bytes));
            return ptr.*;
        },

        // NOTE optional may be convertable. There are likely edge cases here-
        // how to represent null? For child types like string, an empty string and null are the same.
        // A pointer to a global static null object also doesn't work- it is identical to an integer.
        // Potentially this could be an actual pointer, null == 0, and we need to dereference for any
        // optional. This seems like a comprimise, but might work.
        // Another option is a unique value of a new type.

        // NOTE error union may be convertable

        // NOTE vector may be convertable
        //.Vector => |info| return comptime hasUniqueRepresentation(info.child) and
        //@sizeOf(T) == @sizeOf(info.child) * info.len,

        // Fn may be convertable as a function pointer? This is untested.
        .Fn => return @intToPtr(T, @intCast(usize, try GetWideIntFromObj(interp, obj))),

        // NOTE error set may be convertable
        //.ErrorSet,

        // These do not seem convertable.
        //.Frame,
        //.AnyFrame,
        //.EnumLiteral,
        //.BoundFn,
        //.Opaque,
        else => {
            @compileError("Can not convert type " ++ @typeName(T) ++ " to a TCL value");
        },
    }
}

pub fn ToObj(value: anytype) err.TclError!Obj {
    switch (@typeInfo(@TypeOf(value))) {
        .Bool => return tcl.Tcl_NewIntObj(@boolToInt(value)),

        .Int => {
            return NewIntObj(value);
        },

        .Float => |info| {
            if (32 == info.bits) {
                return tcl.Tcl_NewDoubleObj(@floatCast(f64, value));
            } else {
                return tcl.Tcl_NewDoubleObj(value);
            }
        },

        .Enum => {
            return NewIntObj(@enumToInt(value));
            // NOTE this finds the string instead of the integer.
            //inline for (std.meta.fields(@Type(value))) |field| {
            //    if (field.value == value) {
            //        return NewStringObj(field.name);
            //    }
            //}
            //return err.TclError.TCL_ERROR;
        },

        .Array => {
            return NewByteArrayObj(value);
        },

        .Struct => {
            return NewByteArrayObj(value);
        },

        .Union => {
            return NewByteArrayObj(value);
        },

        .Pointer => {
            return NewIntObj(@ptrToInt(value));
        },

        // Void results in an empty TCL object.
        .Void => {
            // NOTE most likely should check for null result and report allocation error here.
            return NewObj();
        },

        .Fn => {
            return NewIntObj(@ptrToInt(value));
        },

        // NOTE for complex types, maybe allocate and return pointer obj.
        // There may be some design in which a string handle is return instead, and looked
        // up within the extension. This may be safer?

        else => {
            @compileError("Can not create a TCL object from a value of type " ++ @typeName(@TypeOf(value)));
        },
    }
}

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

test "uint objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    {
        const int: u8 = std.math.maxInt(u8);
        try std.testing.expectEqual(int, try GetFromObj(u8, interp, try ToObj(int)));
    }

    {
        const int: u16 = std.math.maxInt(u16);
        try std.testing.expectEqual(int, try GetFromObj(u16, interp, try ToObj(int)));
    }

    {
        const int: u32 = std.math.maxInt(u32);
        try std.testing.expectEqual(int, try GetFromObj(u32, interp, try ToObj(int)));
    }

    {
        const int: u64 = std.math.maxInt(u64);
        try std.testing.expectEqual(int, try GetFromObj(u64, interp, try ToObj(int)));
    }
}

test "int objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    {
        const int: i8 = std.math.minInt(i8);
        try std.testing.expectEqual(int, try GetFromObj(i8, interp, try ToObj(int)));
    }

    {
        const int: i16 = std.math.minInt(i16);
        try std.testing.expectEqual(int, try GetFromObj(i16, interp, try ToObj(int)));
    }

    {
        const int: i32 = std.math.minInt(i32);
        try std.testing.expectEqual(int, try GetFromObj(i32, interp, try ToObj(int)));
    }

    {
        const int: i64 = std.math.minInt(i64);
        try std.testing.expectEqual(int, try GetFromObj(i64, interp, try ToObj(int)));
    }
}

test "bool objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);
    var bl: bool = true;
    try std.testing.expectEqual(bl, try GetFromObj(bool, interp, try ToObj(bl)));
    bl = false;
    try std.testing.expectEqual(bl, try GetFromObj(bool, interp, try ToObj(bl)));
}

test "float objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const flt: f32 = std.math.f32_max;
    try std.testing.expectEqual(flt, try GetFromObj(f32, interp, try ToObj(flt)));

    const dbl: f64 = std.math.f64_max;
    try std.testing.expectEqual(dbl, try GetFromObj(f64, interp, try ToObj(dbl)));
}

test "enum objs" {
    const enm = enum {
        A,
    };

    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const enm_value: enm = .A;
    try std.testing.expectEqual(enm_value, try GetFromObj(enm, interp, try ToObj(enm_value)));
}

test "array objs" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const arr: [3]u8 = .{ 1, 2, 3 };
    try std.testing.expectEqual(arr, try GetFromObj([3]u8, interp, try ToObj(arr)));
}

test "union objs" {
    const un = union(enum) {
        flt: f32,
        int: u64,
    };

    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const un_value: un = .{ .flt = 0.1 };
    try std.testing.expectEqual(un_value, try GetFromObj(un, interp, try ToObj(un_value)));
}

test "struct objs" {
    const strt = struct {
        flt: f32,
        int: u64,
    };

    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const strt_value: strt = .{ .flt = 0.1, .int = 1 };
    try std.testing.expectEqual(strt_value, try GetFromObj(strt, interp, try ToObj(strt_value)));
}

test "fn obj" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    const func = struct {
        fn test_func(arg: u8) u8 {
            return arg + 1;
        }
    }.test_func;

    try std.testing.expectEqual(func, try GetFromObj(fn (u8) u8, interp, try ToObj(func)));
}

test "ptr obj" {
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var value: u8 = 255;

    try std.testing.expectEqual(&value, try GetFromObj(*u8, interp, try ToObj(&value)));
}

// TODO these were supposed to compile out called to Tcl_IncrRefCount and decr if they do not
// exist, but this does not seem to work.
pub fn IncrRefCount(obj: Obj) void {
    if (@hasDecl(tcl, "Tcl_IncrRefCount")) {
        //tcl.Tcl_IncrRefCount(obj);
        tcl.Tcl_DbIncrRefCount(obj, "", 0);
    } else {
        // NOTE __LINE__ and __FILE__ not implemented in Zig: https://github.com/ziglang/zig/issues/2029
        tcl.Tcl_DbIncrRefCount(obj, "", 0);
    }
}

pub fn DecrRefCount(obj: Obj) void {
    if (@hasDecl(tcl, "Tcl_DecrRefCount")) {
        //tcl.Tcl_DecrRefCount(obj);
        tcl.Tcl_DbDecrRefCount(obj, "", 0);
    } else {
        // NOTE __LINE__ and __FILE__ not implemented in Zig: https://github.com/ziglang/zig/issues/2029
        tcl.Tcl_DbDecrRefCount(obj, "", 0);
    }
}
