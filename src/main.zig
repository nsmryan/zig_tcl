const std = @import("std");
const testing = std.testing;

const tcl = @cImport({
    //@cDefine("USE_TCL_STUBS", "1");
    @cInclude("c:/tcltk/include/tcl.h");
});

// TCL_OK is not represented as it is the result of a normal return.
// NOTE it is not clear to me that return/break/continue need to be in here.
const TclError = error{
    TCL_ERROR,
    TCL_RETURN,
    TCL_BREAK,
    TCL_CONTINUE,
};

const Struct = struct {
    int: c_int = 0,
    zig_int: u8 = 0,
    string: [64]u8 = undefined,
    float: f32 = 0.0,
};

// NOTES
// create a command that is given a string name, and cdata is a pointer to an allocator,
// and creates a command of that name. The new command's cdata is a pointer to a struct and an allocator.
// its destroy function deallocates it, and perhaps the allocation containing the struct pointer and allocator.
// CData(T) = *T x Allocator. Maybe general purpose allocate this.
// or
// CData(T) = T x Allocator. The allocator's memory contains an allocator structure to use for dellocation.
//
// Consider an error set with all TCL errors. Then wrap calls in a 'if' that checks for error returns and returns back a c_int.
// This would allow code to be more ziggy within functions using error returns.
//
// Consider adding another parameter to the CData- a pointer to the implementing function. All commands would use the same handler,
// which would pass arguments to the implementing function and handle error returns. If an error, turn to c_int and return, otherwise
// return TCL_OK. In this design, wrap used TCL C API functions in trivial ziggy versions that return error codes.
//
// If wrapping all TCL functions, or just ones that I use, this would result in general ziggy TCL interface, as well as the more
// advanced options, which should be kept optional, to manage a struct and comptime call its decls.
// If wrap TCL functions, try to write a generic handler that calls a function and handles error set results.
//
// Consider a global map from pointers to allocator used in destructors to deallocate instead of putting allocators into memory
// with the struct, which seems problematic for generic types without more pointers.
//
// Possible goals:
// TCL C API wrapper functions for easier extension writing.
// Struct manager command using heavy comptime- given a type and allocator, allocate type and store allocator,
// try to fill in struct fields, register a destructor, and a command that comptime calls into decls of the struct, if possible.
//
const ZigTclCmd = fn (cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) TclError!void;

fn ZigTcl_HandleReturn(result: c_int) TclError!void {
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

fn ZigTcl_ErrorToInt(err: TclError) c_int {
    switch (err) {
        TclError.TCL_ERROR => return tcl.TCL_ERROR,
        TclError.TCL_RETURN => return tcl.TCL_RETURN,
        TclError.TCL_BREAK => return tcl.TCL_BREAK,
        TclError.TCL_CONTINUE => return tcl.TCL_CONTINUE,
    }
}

fn ZigTcl_TclResult(result: TclError!void) c_int {
    if (result) {
        return tcl.TCL_OK;
    } else |err| {
        return ZigTcl_ErrorToInt(err);
    }
}

fn ZigTcl_CallCmd(function: ZigTclCmd, cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    return ZigTcl_HandleReturn(function(cdata, interp, objc, objv));
}

fn Tcl_GetIntFromObj(interp: [*c]tcl.Tcl_Interp, obj: [*c]tcl.Tcl_Obj, int: [*c]c_int) TclError!void {
    const result = tcl.Tcl_GetIntFromObj(interp, obj, int);
    return ZigTcl_HandleReturn(result);
}

fn Tcl_ListObjAppendElement(interp: [*c]tcl.Tcl_Interp, list: [*c]tcl.Tcl_Obj, obj: [*c]tcl.Tcl_Obj) TclError!void {
    const result = tcl.Tcl_ListObjAppendElement(interp, list, obj);
    return ZigTcl_HandleReturn(result);
}

// Wrapping functions without returns does not seem that helpful. For now just re-export the underlying function.
// One option would be to raise the *c and c_ints to * and usize for ziggification.
const Tcl_GetStringFromObj = tcl.Tcl_GetStringFromObj;
const Tcl_NewStringObj = tcl.Tcl_NewStringObj;
const Tcl_NewIntObj = tcl.Tcl_NewIntObj;
const Tcl_SetObjResult = tcl.Tcl_SetObjResult;

fn Hello_ZigTclCmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) TclError!void {
    _ = cdata;
    _ = objc;

    var s: Struct = Struct{};
    try Tcl_GetIntFromObj(interp, objv[1], &s.int);
    std.debug.print("int = {}\n", .{s.int});

    var length: c_int = undefined;
    const str = Tcl_GetStringFromObj(objv[2], &length);
    std.debug.print("str = {s}\n", .{str});
    std.mem.copy(u8, s.string[0..], str[0..@intCast(usize, length)]);

    var list = tcl.Tcl_NewListObj(0, null);
    try Tcl_ListObjAppendElement(interp, list, Tcl_NewIntObj(s.int));
    try Tcl_ListObjAppendElement(interp, list, Tcl_NewStringObj(s.string[0..], s.string.len));

    Tcl_SetObjResult(interp, list);
}

export fn Hello_Cmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    return ZigTcl_TclResult(Hello_ZigTclCmd(cdata, interp, objc, objv));
}

export fn Zigtcl_Init(interp: *tcl.Tcl_Interp) c_int {
    std.debug.print("\nStarting Zig TCL Test {d}\n", .{interp});

    //var rc = tcl.Tcl_InitStubs(interp, "8.6", 0);
    var rc = tcl.Tcl_PkgRequire(interp, "Tcl", "8.6", 0);
    std.debug.print("\nInit result {s}\n", .{rc});

    //var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //const gpa = general_purpose_allocator.allocator();

    _ = tcl.Tcl_CreateObjCommand(interp, "hello", Hello_Cmd, null, null);

    return tcl.Tcl_PkgProvide(interp, "zigtcl", "0.1.0");
}
