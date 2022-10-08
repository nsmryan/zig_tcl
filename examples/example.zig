const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const zt = @import("zigtcl");

const Struct = struct {
    bl: bool = false,
    int: c_int = 0,
    long: c_long = 0,
    wide: c_longlong = 0,
    zig_int: u8 = 0,
    string: [64]u8 = undefined,
    float: f32 = 0.0,
    ptr: *u8 = undefined,
    enm: Enum,
    nested: struct { f0: u32, f1: u8 },
    slice: []u8,

    pub fn decl1(s: *Struct) void {
        s.bl = !s.bl;
    }

    pub fn decl2(s: *Struct, arg: c_int) void {
        s.int = arg;
    }

    const Inner = struct {
        field0: usize,
    };
};

const Enum = enum {
    E1,
    E2,
    E3,
};

fn Struct_TclCmd(cdata: zt.tcl.ClientData, interp: [*c]zt.tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]zt.tcl.Tcl_Obj) callconv(.C) c_int {
    _ = objc;

    var s = @ptrCast(*Struct, @alignCast(@alignOf(Struct), cdata));

    // If given no arguments, return a pointer to the value.
    if (objc == 1) {
        // I believe wide int should be long enough for a pointer on all platforms.
        const ptr_obj = zt.obj.ToObj(@ptrToInt(cdata)) catch return zt.tcl.TCL_ERROR;

        //const struct_copy = zt.GetFromObj(Struct, interp, ptr_obj) catch return zt.tcl.TCL_ERROR;
        //std.testing.expect(std.meta.eql(s.*, struct_copy)) catch @panic("struct ptr copy did not work!");

        zt.obj.SetObjResult(interp, ptr_obj);
        return zt.tcl.TCL_OK;
    }

    var name_length: c_int = undefined;
    const name = zt.tcl.Tcl_GetStringFromObj(objv[1], &name_length);

    if (std.mem.eql(u8, std.mem.span(name), "decl1")) {
        zt.CallDecl(Struct.decl1, interp, objc, objv) catch return zt.tcl.TCL_ERROR;
    } else if (std.mem.eql(u8, std.mem.span(name), "decl2")) {
        zt.CallDecl(Struct.decl2, interp, objc, objv) catch return zt.tcl.TCL_ERROR;
    } else if (std.mem.eql(u8, std.mem.span(name), "bl")) {
        if (objc > 2) {
            s.bl = zt.GetFromObj(bool, interp, objv[2]) catch return zt.tcl.TCL_ERROR;
        }
        zt.obj.SetObjResult(interp, zt.ToObj(s.bl) catch return zt.tcl.TCL_ERROR);
    } else if (std.mem.eql(u8, std.mem.span(name), "int")) {
        if (objc > 2) {
            s.int = zt.GetFromObj(c_int, interp, objv[2]) catch return zt.tcl.TCL_ERROR;
        }
        zt.obj.SetObjResult(interp, zt.ToObj(s.int) catch return zt.tcl.TCL_ERROR);
    } else if (std.mem.eql(u8, std.mem.span(name), "long")) {
        if (objc > 2) {
            s.long = zt.GetFromObj(c_long, interp, objv[2]) catch return zt.tcl.TCL_ERROR;
        }
        zt.obj.SetObjResult(interp, zt.ToObj(s.long) catch return zt.tcl.TCL_ERROR);
    } else if (std.mem.eql(u8, std.mem.span(name), "wide")) {
        if (objc > 2) {
            s.wide = zt.GetFromObj(c_longlong, interp, objv[2]) catch return zt.tcl.TCL_ERROR;
        }
        zt.obj.SetObjResult(interp, zt.NewIntObj(s.wide));
    } else if (std.mem.eql(u8, std.mem.span(name), "zig_int")) {
        if (objc > 2) {
            s.zig_int = zt.GetFromObj(u8, interp, objv[2]) catch return zt.tcl.TCL_ERROR;
        }
        zt.obj.SetObjResult(interp, zt.ToObj(s.zig_int) catch return zt.tcl.TCL_ERROR);
    } else if (std.mem.eql(u8, std.mem.span(name), "string")) {
        if (objc > 2) {
            const str = zt.GetStringFromObj(objv[2]) catch return zt.tcl.TCL_ERROR;

            if (str.len > s.string.len) {
                return zt.tcl.TCL_ERROR;
            }
            std.mem.copy(u8, s.string[0..], str);
            const len = @intCast(usize, str.len);
            std.mem.set(u8, s.string[len..s.string.len], 0);
        }
        zt.obj.SetObjResult(interp, zt.NewStringObj(s.string[0..]));
    } else if (std.mem.eql(u8, std.mem.span(name), "float")) {
        if (objc > 2) {
            s.float = zt.GetFromObj(f32, interp, objv[2]) catch return zt.tcl.TCL_ERROR;
        }
        zt.obj.SetObjResult(interp, zt.ToObj(s.float) catch return zt.tcl.TCL_ERROR);
    } else if (std.mem.eql(u8, std.mem.span(name), "ptr")) {
        if (objc > 2) {
            s.ptr = zt.GetFromObj(*u8, interp, objv[2]) catch return zt.tcl.TCL_ERROR;
        }
        zt.obj.SetObjResult(interp, zt.ToObj(s.ptr) catch return zt.tcl.TCL_ERROR);
    } else if (std.mem.eql(u8, std.mem.span(name), "enm")) {
        if (objc > 2) {
            s.enm = zt.GetFromObj(Enum, interp, objv[2]) catch return zt.tcl.TCL_ERROR;
        }

        // NOTE ToObj is not used here, as it returns the integer value of the enum rather then
        // the string.
        var found: bool = false;
        inline for (@typeInfo(Enum).Enum.fields) |field| {
            if (field.value == @enumToInt(s.enm)) {
                zt.obj.SetObjResult(interp, zt.NewIntObj(@enumToInt(s.enm)));
                found = true;
                break;
            }
        }

        if (!found) {
            zt.obj.SetObjResult(interp, zt.NewStringObj("Enum field value not found"[0..]));
            return zt.tcl.TCL_ERROR;
        }
    }

    return zt.tcl.TCL_OK;
}

export fn StructFree_TclCmd(cdata: zt.tcl.ClientData) void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    gpa.destroy(@ptrCast(*Struct, @alignCast(@alignOf(Struct), cdata)));
}

fn Hello_ZigTclCmd(cdata: zt.tcl.ClientData, interp: zt.Interp, objv: []const [*c]zt.tcl.Tcl_Obj) zt.TclError!void {
    _ = cdata;

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var s: *Struct = gpa.create(Struct) catch return zt.TclError.TCL_ERROR;

    var length: c_int = undefined;
    const name = zt.tcl.Tcl_GetStringFromObj(objv[1], &length);

    const result = zt.tcl.Tcl_CreateObjCommand(interp, name, Struct_TclCmd, @intToPtr(zt.tcl.ClientData, @ptrToInt(s)), StructFree_TclCmd);
    _ = result;
}

pub fn test_function(arg0: u8, arg1: u8) u32 {
    return arg0 + arg1;
}

export fn Zigexample_Init(interp: zt.Interp) c_int {
    //std.debug.print("\nStarting Zig TCL Test {d}\n", .{interp});

    if (builtin.os.tag != .windows) {
        var rc = zt.tcl.Tcl_InitStubs(interp, "8.6", 0);
        std.debug.print("\nInit result {s}\n", .{rc});
    } else {
        var rc = zt.tcl.Tcl_PkgRequire(interp, "Tcl", "8.6", 0);
        std.debug.print("\nInit result {s}\n", .{rc});
    }

    _ = zt.CreateObjCommand(interp, "zigtcl::zigcreate", Hello_ZigTclCmd) catch return zt.tcl.TCL_ERROR;

    zt.WrapFunction(test_function, "zigtcl::zig_function", interp) catch return zt.tcl.TCL_ERROR;

    _ = zt.RegisterStruct(Struct, "Struct", "zigtcl", interp);

    const Inner = Struct.Inner;
    _ = zt.RegisterStruct(Inner, "Inner", "zigtcl", interp);

    //_ = zt.RegisterStruct(std.mem.Allocator, "Allocator", "zigtcl", interp);

    return zt.tcl.Tcl_PkgProvide(interp, "zigtcl", "0.1.0");
}
