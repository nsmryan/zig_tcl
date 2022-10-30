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

pub fn test_function(arg0: u8, arg1: u8) u32 {
    return arg0 + arg1;
}

export fn Zigexample_Init(interp: zt.Interp) c_int {
    if (builtin.os.tag != .windows) {
        var rc = zt.tcl.Tcl_InitStubs(interp, "8.6", 0);
        std.debug.print("\nInit result {s}\n", .{rc});
    } else {
        var rc = zt.tcl.Tcl_PkgRequire(interp, "Tcl", "8.6", 0);
        std.debug.print("\nInit result {s}\n", .{rc});
    }

    var ns = zt.tcl.Tcl_CreateNamespace(interp, "zigtcl", null, null);

    zt.WrapFunction(test_function, "zigtcl::zig_function", interp) catch return zt.tcl.TCL_ERROR;

    _ = zt.RegisterStruct(Struct, "Struct", "zigtcl", interp);

    const Inner = Struct.Inner;
    _ = zt.RegisterStruct(Inner, "Inner", "zigtcl", interp);

    _ = zt.RegisterStruct(std.mem.Allocator, "Allocator", "zigtcl", interp);
    _ = zt.tcl.Tcl_CreateObjCommand(interp, "zigtcl::tcl_allocator", zt.StructCommand(std.mem.Allocator).StructInstanceCommand, @ptrCast(zt.tcl.ClientData, &zt.alloc.tcl_allocator), null);
    _ = zt.RegisterEnum(Enum, "Enum", "zigtcl", interp);

    _ = zt.tcl.Tcl_Export(interp, ns, "*", 0);

    return zt.tcl.Tcl_PkgProvide(interp, "zigtcl", "0.1.0");
}
