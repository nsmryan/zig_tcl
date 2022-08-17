const std = @import("std");
const testing = std.testing;

//usingnamespace @import("zigtcl");
const zt = @import("zigtcl");
const tcl = @cImport({
    //@cDefine("USE_TCL_STUBS", "1");
    @cInclude("/usr/include/tcl.h");
});

const Struct = struct {
    int: c_int = 0,
    zig_int: u8 = 0,
    string: [64]u8 = undefined,
    float: f32 = 0.0,
};

fn Struct_TclCmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    _ = objc;

    var s = @intToPtr(*Struct, cdata);

    var name_length: c_int = undefined;
    const name = zt.Tcl_GetStringFromObj(objv[1], &name_length);

    if (std.mem.eql(u8, name, "int")) {
        s.int = try zt.Tcl_GetIntFromObj(interp, objv[2]);
        std.debug.print("int = {}\n", .{s.int});
    } else if (std.mem.eql(u8, name, "zig_int")) {
        s.zig_int = try zt.Tcl_GetIntFromObj(interp, objv[2]);
        std.debug.print("zig_int = {}\n", .{s.zig_int});
    } else if (std.mem.eql(u8, name, "string")) {
        var length: c_int = undefined;
        const str = zt.Tcl_GetStringFromObj(objv[2], &length);
        std.debug.print("str = {s}\n", .{str});
        std.mem.copy(u8, s.string[0..], str[0..@intCast(usize, length)]);
    } else if (std.mem.eql(u8, name, "float")) {
        s.float = try zt.Tcl_GetDoubleFromObj(interp, objv[2]);
        std.debug.print("float = {}\n", .{s.float});
    }

    return tcl.TCL_OK;
}

fn StructFree_TclCmd(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
    _ = objc;
    _ = objv;
    _ = interp;

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    gpa.destroy(@intToPtr(*Struct, cdata));
}

fn Hello_ZigTclCmd(cdata: zt.ClientData, interp: zt.Tcl_Interp, objv: []const zt.Tcl_Obj) zt.TclError!void {
    _ = cdata;

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var s: *Struct = gpa.create(Struct) catch return zt.TclError.TCL_ERROR;

    var length: c_int = undefined;
    const name = zt.Tcl_GetStringFromObj(objv[1], &length);

    const result = tcl.Tcl_CreateObjCommand(interp, name, Struct_TclCmd, @intToPtr(tcl.ClientData, @ptrToInt(s)), StructFree_TclCmd);

    return result;
}

export fn Zigexample_Init(interp: zt.Tcl_Interp) c_int {
    std.debug.print("\nStarting Zig TCL Test {d}\n", .{interp});

    //var rc = tcl.Tcl_InitStubs(interp, "8.6", 0);
    var rc = zt.Tcl_PkgRequire(interp, "Tcl", "8.6", 0);
    std.debug.print("\nInit result {s}\n", .{rc});

    _ = zt.ZigTcl_CreateObjCommand(interp, "zigcreate", Hello_ZigTclCmd);

    return zt.Tcl_PkgProvide(interp, "zigtcl", "0.1.0");
}
