const std = @import("std");
const testing = std.testing;

const tcl = @cImport({
    //@cDefine("USE_TCL_STUBS", "1");
    //@cInclude("c:/tcltk/include/tcl.h");
    @cInclude("/usr/include/tcl.h");
});
usingnamespace tcl;

// TCL_OK is not represented as it is the result of a normal return.
// NOTE it is not clear to me that return/break/continue need to be in here.
pub const TclError = error{
    TCL_ERROR,
    TCL_RETURN,
    TCL_BREAK,
    TCL_CONTINUE,
};

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

pub const ZigTclCmd = fn (cdata: tcl.ClientData, interp: Interp, objv: []const [*c]tcl.Tcl_Obj) TclError!void;

pub fn ZigTcl_HandleReturn(result: c_int) TclError!void {
    if (result == tcl.TCL_ERROR) {
        return TclError.TCL_ERROR;
    } else if (result == tcl.TCL_RETURN) {
        return TclError.TCL_RETURN;
    } else if (result == tcl.TCL_BREAK) {
        return TclError.TCL_BREAK;
    } else if (result == tcl.TCL_CONTINUE) {
        return TclError.TCL_CONTINUE;
    }
}

pub fn ZigTcl_ErrorToInt(err: TclError) c_int {
    switch (err) {
        TclError.TCL_ERROR => return tcl.TCL_ERROR,
        TclError.TCL_RETURN => return tcl.TCL_RETURN,
        TclError.TCL_BREAK => return tcl.TCL_BREAK,
        TclError.TCL_CONTINUE => return tcl.TCL_CONTINUE,
    }
}

pub fn ZigTcl_TclResult(result: TclError!void) c_int {
    if (result) {
        return tcl.TCL_OK;
    } else |err| {
        return ZigTcl_ErrorToInt(err);
    }
}

pub fn ZigTcl_CallCmd(function: ZigTclCmd, cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    return ZigTcl_TclResult(function(cdata, interp, objv[0..@intCast(usize, objc)]));
}

///Tcl_GetIntFromObj wrapper.
pub fn GetIntFromObj(interp: Interp, obj: Obj) TclError!c_int {
    var int: c_int = 0;
    const result = tcl.Tcl_GetIntFromObj(interp, obj, &int);

    ZigTcl_HandleReturn(result) catch |err| return err;
    return int;
}

// Tcl_GetLongFromObj wrapper
pub fn GetLongFromObj(interp: Interp, obj: Obj) TclError!c_long {
    var long: c_long = 0;
    const result = tcl.Tcl_GetLongFromObj(interp, obj, &long);

    ZigTcl_HandleReturn(result) catch |err| return err;
    return long;
}

// Tcl_GetWideIntFromObj wrapper
pub fn GetWideIntFromObj(interp: Interp, obj: Obj) TclError!c_longlong {
    var wide: tcl.Tcl_WideInt = 0;
    const result = tcl.Tcl_GetWideIntFromObj(interp, obj, &wide);

    ZigTcl_HandleReturn(result) catch |err| return err;
    return wide;
}

///Tcl_GetDoubleFromObj wrapper.
pub fn GetDoubleFromObj(interp: Interp, obj: Obj) TclError!f64 {
    var int: f64 = 0;
    const result = tcl.Tcl_GetDoubleFromObj(interp, obj, &int);

    ZigTcl_HandleReturn(result) catch |err| return err;
    return int;
}

pub fn GetStringFromObj(obj: Obj) TclError![]const u8 {
    var length: c_int = undefined;
    const str = tcl.Tcl_GetStringFromObj(obj, &length);
    return str[0..@intCast(usize, length)];
}

/// Tcl_ListObjAppendElement wrapper.
pub fn ListObjAppendElement(interp: tcl.Tcl_Interp, list: tcl.Tcl_Obj, obj: tcl.Tcl_Obj) TclError!void {
    const result = tcl.Tcl_ListObjAppendElement(interp, list, obj);
    return ZigTcl_HandleReturn(result);
}

/// Tcl_NewStringObj wrapper.
pub fn NewStringObj(str: []const u8) Obj {
    return tcl.Tcl_NewStringObj(str.ptr, @intCast(c_int, str.len));
}

/// Tcl_NewIntObj wrapper for all int types (Int, Long, WideInt).
pub fn NewIntObj(value: anytype) Obj {
    switch (@typeInfo(@TypeOf(value))) {
        .Int => |info| {
            if (info.bits <= @bitSizeOf(c_int)) {
                return tcl.Tcl_NewIntObj(@intCast(c_int, value));
            } else if (info.bits <= @bitSizeOf(c_long)) {
                return tcl.Tcl_NewLongObj(@intCast(c_long, value));
            } else if (info.bits <= @bitSizeOf(tcl.Tcl_WideInt)) {
                return tcl.Tcl_NewWideObj(@intCast(c_longlong, value));
            } else {
                @compileError("Int type too wide for a Tcl_WideInt!");
            }
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

pub fn GetFromObj(comptime T: type, interp: Interp, obj: Obj) TclError!T {
    switch (@typeInfo(T)) {
        .Bool => return (try GetIntFromObj(interp, obj)) != 0,

        .Int => |info| {
            if (info.bits <= @bitSizeOf(c_int)) {
                return @intCast(T, try GetIntFromObj(interp, obj));
            } else if (info.bits <= @bitSizeOf(c_long)) {
                return @intCast(T, try GetLongFromObj(interp, obj));
            } else if (info.bits <= @bitSizeOf(tcl.Tcl_WideInt)) {
                return @intCast(T, try GetWideIntFromObj(interp, obj));
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

        // NOTE ideally we could first check for strings, then fall back to integers, to allow
        // either to be passed between TCL and Zig.
        .Enum => {
            const str = try GetStringFromObj(obj);
            if (std.meta.stringToEnum(T, str)) |enm| {
                return enm;
            } else {
                // TODO ideally return a more expressive error, and use in the obj result.
                return TclError.TCL_ERROR;
            }
        },

        // NOTE untested
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

        // NOTE error union may be convertable

        // NOTE vector may be convertable
        //.Vector => |info| return comptime hasUniqueRepresentation(info.child) and
        //@sizeOf(T) == @sizeOf(info.child) * info.len,

        // NOTE error set may be convertable
        //.ErrorSet,
        //.Fn,
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

pub fn NewObj(value: anytype) TclError!Obj {
    switch (@typeInfo(@TypeOf(value))) {
        .Bool => return tcl.Tcl_NewIntObj(@boolToInt(value)),

        .Int => |info| {
            if (info.bits <= @bitSizeOf(c_int)) {
                return tcl.Tcl_NewIntObj(@intCast(c_int, value));
            } else if (info.bits <= @bitSizeOf(c_long)) {
                return tcl.Tcl_NewLongObj(@intCast(c_long, value));
            } else if (info.bits <= @bitSizeOf(tcl.Tcl_WideInt)) {
                return tcl.Tcl_NewWideIntObj(@intCast(c_longlong, value));
            } else {
                @compileError("Int type too wide for a Tcl_WideInt!");
            }
        },

        .Float => |info| {
            if (32 == info.bits) {
                return tcl.Tcl_NewDoubleObj(@floatCast(f64, value));
            } else {
                return tcl.Tcl_NewDoubleObj(value);
            }
        },

        .Enum => {
            return NewIntObj(value);
            // NOTE this finds the string instead of the integer.
            //inline for (std.meta.fields(@Type(value))) |field| {
            //    if (field.value == value) {
            //        return NewStringObj(field.name);
            //    }
            //}
            //return TclError.TCL_ERROR;
        },

        // NOTE untested
        .Pointer => {
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
