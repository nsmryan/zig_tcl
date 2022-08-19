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
pub fn GetIntFromObj(interp: Interp, obj: [*c]tcl.Tcl_Obj) TclError!c_int {
    var int: c_int = 0;
    const result = tcl.Tcl_GetIntFromObj(interp, obj, &int);

    ZigTcl_HandleReturn(result) catch |err| return err;
    return int;
}

///Tcl_GetDoubleFromObj wrapper.
pub fn GetDoubleFromObj(interp: Interp, obj: [*c]tcl.Tcl_Obj) TclError!f64 {
    var int: f64 = 0;
    const result = tcl.Tcl_GetDoubleFromObj(interp, obj, &int);

    ZigTcl_HandleReturn(result) catch |err| return err;
    return int;
}

/// Tcl_ListObjAppendElement wrapper.
pub fn ListObjAppendElement(interp: tcl.Tcl_Interp, list: tcl.Tcl_Obj, obj: tcl.Tcl_Obj) TclError!void {
    const result = tcl.Tcl_ListObjAppendElement(interp, list, obj);
    return ZigTcl_HandleReturn(result);
}

/// Tcl_NewStringObj wrapper.
pub fn NewStringObj(str: []u8) tcl.Tcl_Obj {
    return tcl.Tcl_NewStringObj(str.ptr, @intCast(c_int, str.len));
}

// Wrapping functions without returns does not seem that helpful. For now just re-export the underlying function.
// One option would be to raise the *c and c_ints to * and usize for ziggification.
//pub const Tcl_GetStringFromObj = tcl.Tcl_GetStringFromObj;
//pub const Tcl_NewIntObj = tcl.Tcl_NewIntObj;
//pub const Tcl_NewWideIntObj = tcl.Tcl_NewWideIntObj;
//pub const Tcl_StringObj = tcl.Tcl_StringObj;
//pub const Tcl_NewUnicodeObj = tcl.Tcl_NewUnicodeObj;
//pub const Tcl_SetStringObj = tcl.Tcl_SetStringObj;
//pub const Tcl_NewLongObj = tcl.Tcl_NewLongObj;
//pub const Tcl_SetObjResult = tcl.Tcl_SetObjResult;
//pub const Tcl_PkgRequire = tcl.Tcl_PkgRequire;
//pub const Tcl_PkgProvide = tcl.Tcl_PkgProvide;
//pub const Tcl_NewListObj = tcl.Tcl_NewListObj;
pub const Interp = [*c]tcl.Tcl_Interp;
//pub const ClientData = tcl.ClientData;
//pub const Obj = [*c]tcl.Tcl_Obj;
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
