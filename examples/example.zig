const std = @import("std");
const testing = std.testing;

//usingnamespace @import("zigtcl");
const zt = @import("zigtcl");

const Struct = struct {
    int: c_int = 0,
    zig_int: u8 = 0,
    string: [64]u8 = undefined,
    float: f32 = 0.0,
};

fn Hello_ZigTclCmd(cdata: zt.ClientData, interp: zt.Tcl_Interp, objv: []const zt.Tcl_Obj) zt.TclError!void {
    _ = cdata;

    var s: Struct = Struct{};
    s.int = try zt.Tcl_GetIntFromObj(interp, objv[1]);
    std.debug.print("int = {}\n", .{s.int});

    var length: c_int = undefined;
    const str = zt.Tcl_GetStringFromObj(objv[2], &length);
    std.debug.print("str = {s}\n", .{str});
    std.mem.copy(u8, s.string[0..], str[0..@intCast(usize, length)]);

    var list = zt.Tcl_NewListObj(0, null);
    try zt.Tcl_ListObjAppendElement(interp, list, zt.Tcl_NewIntObj(s.int));
    try zt.Tcl_ListObjAppendElement(interp, list, zt.Tcl_NewStringObj(s.string[0..]));

    zt.Tcl_SetObjResult(interp, list);
}

export fn Hello_Cmd(cdata: zt.ClientData, interp: zt.Tcl_Interp, objc: c_int, objv: [*c]const zt.Tcl_Obj) c_int {
    return zt.ZigTcl_CallCmd(Hello_ZigTclCmd, cdata, interp, objc, objv);
}

export fn Zigexample_Init(interp: zt.Tcl_Interp) c_int {
    std.debug.print("\nStarting Zig TCL Test {d}\n", .{interp});

    //var rc = tcl.Tcl_InitStubs(interp, "8.6", 0);
    var rc = zt.Tcl_PkgRequire(interp, "Tcl", "8.6", 0);
    std.debug.print("\nInit result {s}\n", .{rc});

    //var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //const gpa = general_purpose_allocator.allocator();

    _ = zt.ZigTcl_CreateObjCommand(interp, "zigTclHello", Hello_ZigTclCmd);

    return zt.Tcl_PkgProvide(interp, "zigtcl", "0.1.0");
}
