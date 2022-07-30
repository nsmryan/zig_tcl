const std = @import("std");
const testing = std.testing;

const tcl = @cImport({
    //@cDefine("USE_TCL_STUBS", "1");
    @cInclude("c:/tcltk/include/tcl.h");
});

export fn Hello_Cmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    _ = cdata;
    _ = objc;
    _ = objv;
    tcl.Tcl_SetObjResult(interp, tcl.Tcl_NewStringObj("Hello zig!", -1));
    return tcl.TCL_OK;
}

export fn Zigtcl_Init(interp: *tcl.Tcl_Interp) c_int {
    std.debug.print("\nStarting Zig TCL Test {d}\n", .{interp});

    //var rc = tcl.Tcl_InitStubs(interp, "8.6", 0);
    var rc = tcl.Tcl_PkgRequire(interp, "Tcl", "8.6", 0);
    std.debug.print("\nInit result {s}\n", .{rc});

    _ = tcl.Tcl_CreateObjCommand(interp, "hello", Hello_Cmd, null, null);

    return tcl.Tcl_PkgProvide(interp, "zigtcl", "0.1.0");
}
