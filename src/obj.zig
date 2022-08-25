const std = @import("std");
const testing = std.testing;

const err = @import("err.zig");
usingnamespace err;

const tcl = @import("tcl.zig");

///Tcl_GetIntFromObj wrapper.
pub fn GetIntFromObj(interp: Interp, obj: Obj) err.TclError!c_int {
    var int: c_int = 0;
    const result = tcl.Tcl_GetIntFromObj(interp, obj, &int);

    err.ZigTcl_HandleReturn(result) catch |errValue| return errValue;
    return int;
}

// Tcl_GetLongFromObj wrapper
pub fn GetLongFromObj(interp: Interp, obj: Obj) err.TclError!c_long {
    var long: c_long = 0;
    const result = tcl.Tcl_GetLongFromObj(interp, obj, &long);

    err.ZigTcl_HandleReturn(result) catch |errValue| return errValue;
    return long;
}

// Tcl_GetWideIntFromObj wrapper
pub fn GetWideIntFromObj(interp: Interp, obj: Obj) err.TclError!c_longlong {
    var wide: tcl.Tcl_WideInt = 0;
    const result = tcl.Tcl_GetWideIntFromObj(interp, obj, &wide);

    err.ZigTcl_HandleReturn(result) catch |errValue| return errValue;
    return wide;
}

///Tcl_GetDoubleFromObj wrapper.
pub fn GetDoubleFromObj(interp: Interp, obj: Obj) err.TclError!f64 {
    var int: f64 = 0;
    const result = tcl.Tcl_GetDoubleFromObj(interp, obj, &int);

    err.ZigTcl_HandleReturn(result) catch |errValue| return errValue;
    return int;
}

pub fn GetStringFromObj(obj: Obj) err.TclError![]const u8 {
    var length: c_int = undefined;
    const str = tcl.Tcl_GetStringFromObj(obj, &length);
    return str[0..@intCast(usize, length)];
}

/// Tcl_ListObjAppendElement wrapper.
pub fn ListObjAppendElement(interp: tcl.Tcl_Interp, list: tcl.Tcl_Obj, obj: tcl.Tcl_Obj) err.TclError!void {
    const result = tcl.Tcl_ListObjAppendElement(interp, list, obj);
    return err.ZigTcl_HandleReturn(result);
}

/// Tcl_NewStringObj wrapper.
pub fn NewStringObj(str: []const u8) Obj {
    return tcl.Tcl_NewStringObj(str.ptr, @intCast(c_int, str.len));
}

// Tcl_SetObjResult wrapper
pub fn SetObjResult(interp: Interp, obj: Obj) void {
    tcl.Tcl_SetObjResult(interp, obj);
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

pub const ZigTclCmd = fn (cdata: tcl.ClientData, interp: Interp, objv: []const [*c]tcl.Tcl_Obj) err.TclError!void;

pub fn ZigTcl_CallCmd(function: ZigTclCmd, cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    return err.ZigTcl_TclResult(function(cdata, interp, objv[0..@intCast(usize, objc)]));
}

/// Call a ZigTclCmd function, passing in the TCL C API style arguments and returning a c_int result.
pub export fn Wrap_ZigCmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    var function = @ptrCast(ZigTclCmd, cdata);
    return ZigTcl_CallCmd(function, cdata, interp, objc, objv);
}
/// Create a new TCL command that executes a Zig function.
/// The Zig function is given using the ziggy ZigTclCmd signature.
pub fn CreateObjCommand(interp: Interp, name: [*:0]const u8, function: ZigTclCmd) tcl.Tcl_Command {
    return tcl.Tcl_CreateObjCommand(interp, name, Wrap_ZigCmd, @intToPtr(tcl.ClientData, @ptrToInt(function)), null);
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

        .Float => |info| {
            const dbl = try GetDoubleFromObj(interp, obj);
            if (32 == info.bits) {
                return @floatCast(f32, dbl);
            } else {
                return dbl;
            }
        },

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

        // This may not be the only way to do this. Passing pointers to TCL like this is not generally
        // a good idea. A similar comment applies to Union and Struct.
        .Array => {
            const ptr = @intToPtr(*T, @intCast(usize, try GetWideIntFromObj(interp, obj)));
            return ptr.*;
        },

        // NOTE untested
        .Union => {
            const ptr = @intToPtr(*T, @intCast(usize, try GetWideIntFromObj(interp, obj)));
            return ptr.*;
        },

        .Struct => {
            const ptr = @intToPtr(*T, @intCast(usize, try GetWideIntFromObj(interp, obj)));
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

pub fn NewObj(value: anytype) err.TclError!Obj {
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

        .Pointer => {
            return NewIntObj(@ptrToInt(value));
        },

        // Void results in an empty TCL object.
        .Void => {
            // NOTE most likely should check for null result and report allocation error here.
            return tcl.Tcl_NewObj();
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
