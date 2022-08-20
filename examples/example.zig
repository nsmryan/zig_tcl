const std = @import("std");
const testing = std.testing;

//usingnamespace @import("zigtcl");
const zt = @import("zigtcl");
//const tcl = @cImport({
//    //@cDefine("USE_TCL_STUBS", "1");
//    @cInclude("/usr/include/tcl.h");
//});

const Struct = struct {
    bl: bool = false,
    int: c_int = 0,
    long: c_long = 0,
    wide: c_longlong = 0,
    zig_int: u8 = 0,
    string: [64]u8 = undefined,
    float: f32 = 0.0,
};

export fn Struct_TclCmd(cdata: zt.ClientData, interp: [*c]zt.Tcl_Interp, objc: c_int, objv: [*c]const [*c]zt.Tcl_Obj) c_int {
    _ = objc;

    var s = @ptrCast(*Struct, @alignCast(@alignOf(Struct), cdata));

    var name_length: c_int = undefined;
    const name = zt.Tcl_GetStringFromObj(objv[1], &name_length);

    if (std.mem.eql(u8, std.mem.span(name), "bl")) {
        if (objc > 2) {
            s.bl = zt.GetFromObj(bool, interp, objv[2]) catch return zt.TCL_ERROR;
        }
        zt.Tcl_SetObjResult(interp, zt.Tcl_NewIntObj(@boolToInt(s.bl)));
    } else if (std.mem.eql(u8, std.mem.span(name), "int")) {
        if (objc > 2) {
            s.int = zt.GetFromObj(c_int, interp, objv[2]) catch return zt.TCL_ERROR;
        }
        zt.Tcl_SetObjResult(interp, zt.Tcl_NewIntObj(s.int));
    } else if (std.mem.eql(u8, std.mem.span(name), "long")) {
        if (objc > 2) {
            s.long = zt.GetFromObj(c_long, interp, objv[2]) catch return zt.TCL_ERROR;
        }
        zt.Tcl_SetObjResult(interp, zt.Tcl_NewLongObj(s.long));
    } else if (std.mem.eql(u8, std.mem.span(name), "wide")) {
        if (objc > 2) {
            s.wide = zt.GetFromObj(c_longlong, interp, objv[2]) catch return zt.TCL_ERROR;
        }
        zt.Tcl_SetObjResult(interp, zt.Tcl_NewWideIntObj(s.wide));
    } else if (std.mem.eql(u8, std.mem.span(name), "zig_int")) {
        if (objc > 2) {
            s.zig_int = zt.GetFromObj(u8, interp, objv[2]) catch return zt.TCL_ERROR;
        }
        zt.Tcl_SetObjResult(interp, zt.Tcl_NewIntObj(s.zig_int));
    } else if (std.mem.eql(u8, std.mem.span(name), "string")) {
        if (objc > 2) {
            var length: c_int = undefined;
            const str = zt.Tcl_GetStringFromObj(objv[2], &length);

            if (length > s.string.len) {
                return zt.TCL_ERROR;
            }
            std.mem.copy(u8, s.string[0..], str[0..@intCast(usize, length)]);
            const len = @intCast(usize, length);
            std.mem.set(u8, s.string[len..s.string.len], 0);
        }
        zt.Tcl_SetObjResult(interp, zt.Tcl_NewStringObj(&s.string, s.string.len));
    } else if (std.mem.eql(u8, std.mem.span(name), "float")) {
        if (objc > 2) {
            s.float = zt.GetFromObj(f32, interp, objv[2]) catch return zt.TCL_ERROR;
        }
        zt.Tcl_SetObjResult(interp, zt.Tcl_NewDoubleObj(@floatCast(f64, s.float)));
    }

    return zt.TCL_OK;
}

export fn StructFree_TclCmd(cdata: zt.ClientData) void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    gpa.destroy(@ptrCast(*Struct, @alignCast(@alignOf(Struct), cdata)));
}

fn Hello_ZigTclCmd(cdata: zt.ClientData, interp: zt.Interp, objv: []const [*c]zt.Tcl_Obj) zt.TclError!void {
    _ = cdata;

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var s: *Struct = gpa.create(Struct) catch return zt.TclError.TCL_ERROR;

    var length: c_int = undefined;
    const name = zt.Tcl_GetStringFromObj(objv[1], &length);

    const result = zt.Tcl_CreateObjCommand(interp, name, Struct_TclCmd, @intToPtr(zt.ClientData, @ptrToInt(s)), StructFree_TclCmd);
    _ = result;
}

export fn Zigexample_Init(interp: zt.Interp) c_int {
    //std.debug.print("\nStarting Zig TCL Test {d}\n", .{interp});

    //var rc = zt.Tcl_InitStubs(interp, "8.6", 0);
    var rc = zt.Tcl_PkgRequire(interp, "Tcl", "8.6", 0);
    std.debug.print("\nInit result {s}\n", .{rc});

    _ = zt.CreateObjCommand(interp, "zigcreate", Hello_ZigTclCmd);

    return zt.Tcl_PkgProvide(interp, "zigtcl", "0.1.0");
}
