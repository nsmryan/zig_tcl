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
// For TCL function wrappers, consider converting to slices, *, usize, isize, etc, for ziggification.

const ZigTclCmd = fn (cdata: ClientData, interp: Tcl_Interp, objv: []const Tcl_Obj) TclError!void;

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
    return ZigTcl_TclResult(function(cdata, interp, objv[0..@intCast(usize, objc)]));
}

fn Tcl_GetIntFromObj(interp: Tcl_Interp, obj: Tcl_Obj) TclError!c_int {
    var int: c_int = 0;
    const result = tcl.Tcl_GetIntFromObj(interp, obj, &int);

    if (ZigTcl_HandleReturn(result)) {
        return int;
    } else |err| {
        return err;
    }
}

fn Tcl_ListObjAppendElement(interp: Tcl_Interp, list: Tcl_Obj, obj: Tcl_Obj) TclError!void {
    const result = tcl.Tcl_ListObjAppendElement(interp, list, obj);
    return ZigTcl_HandleReturn(result);
}

// Wrapping functions without returns does not seem that helpful. For now just re-export the underlying function.
// One option would be to raise the *c and c_ints to * and usize for ziggification.
const Tcl_GetStringFromObj = tcl.Tcl_GetStringFromObj;
const Tcl_NewStringObj = tcl.Tcl_NewStringObj;
const Tcl_NewIntObj = tcl.Tcl_NewIntObj;
const Tcl_SetObjResult = tcl.Tcl_SetObjResult;
const Tcl_Interp = *tcl.Tcl_Interp;
const ClientData = tcl.ClientData;
const Tcl_Obj = [*c]tcl.Tcl_Obj;
const Tcl_Command = tcl.Tcl_Command;

fn Hello_ZigTclCmd(cdata: ClientData, interp: Tcl_Interp, objv: []const Tcl_Obj) TclError!void {
    _ = cdata;

    var s: Struct = Struct{};
    s.int = try Tcl_GetIntFromObj(interp, objv[1]);
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

// TODO consider using cdata to smuggle the function pointer in so this can be made generic.
// Then the user just writes the underlying ZigTcl function and gets this call without effort.
export fn Hello_Cmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    return ZigTcl_CallCmd(Hello_ZigTclCmd, cdata, interp, objc, objv);
}

export fn Wrap_ZigCmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    var function = @ptrCast(ZigTclCmd, cdata);
    return ZigTcl_CallCmd(function, cdata, interp, objc, objv);
}

fn ZigTcl_CreateObjCommand(interp: Tcl_Interp, name: [*:0]const u8, function: ZigTclCmd) tcl.Tcl_Command {
    return tcl.Tcl_CreateObjCommand(interp, name, Wrap_ZigCmd, @intToPtr(tcl.ClientData, @ptrToInt(function)), null);
}

export fn Zigtcl_Init(interp: Tcl_Interp) c_int {
    std.debug.print("\nStarting Zig TCL Test {d}\n", .{interp});

    //var rc = tcl.Tcl_InitStubs(interp, "8.6", 0);
    var rc = tcl.Tcl_PkgRequire(interp, "Tcl", "8.6", 0);
    std.debug.print("\nInit result {s}\n", .{rc});

    //var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //const gpa = general_purpose_allocator.allocator();

    _ = tcl.Tcl_CreateObjCommand(interp, "hello", Hello_Cmd, null, null);
    //_ = tcl.Tcl_CreateObjCommand(interp, "zigTclHello", Wrap_ZigCmd, @intToPtr(tcl.ClientData, @ptrToInt(Hello_ZigTclCmd)), null);
    _ = ZigTcl_CreateObjCommand(interp, "zigTclHello", Hello_ZigTclCmd);

    return tcl.Tcl_PkgProvide(interp, "zigtcl", "0.1.0");
}
