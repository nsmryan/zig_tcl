const std = @import("std");

const testing = std.testing;

const err = @import("err.zig");
const obj = @import("obj.zig");
const call = @import("call.zig");
const utils = @import("utils.zig");
const tcl = @import("tcl.zig");

pub const EnumCmds = enum {
    call,
    value,
    name,
};

pub const EnumVariantCmds = enum {
    name,
    value,
    call,
};

pub fn RegisterEnum(comptime enm: type, comptime pkg: []const u8, interp: obj.Interp) c_int {
    const terminator: [1]u8 = .{0};
    const cmdName = pkg ++ "::" ++ @typeName(enm) ++ terminator;
    _ = obj.CreateObjCommand(interp, cmdName, EnumCommand(enm).command) catch |errResult| return err.ErrorToInt(errResult);

    inline for (@typeInfo(enm).Enum.fields) |variant| {
        const variantCmdName = pkg ++ "::" ++ @typeName(enm) ++ "::" ++ variant.name ++ terminator;
        _ = obj.CreateObjCommand(interp, variantCmdName, EnumVariantCommand(enm, variant.name, variant.value).command) catch |errResult| return err.ErrorToInt(errResult);
    }

    return tcl.TCL_OK;
}

pub fn EnumCommand(comptime enm: type) type {
    return struct {
        pub fn command(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objv: []const obj.Obj) err.TclError!void {
            _ = cdata;
            _ = enm;

            switch (try obj.GetIndexFromObj(EnumCmds, interp, objv[1], "commands")) {
                .call => {},

                .value => {
                    if (objv.len < 3) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "value variantName");
                        return err.TclError.TCL_ERROR;
                    }

                    const name = try obj.GetStringFromObj(objv[2]);
                    if (std.meta.stringToEnum(enm, name)) |enumValue| {
                        obj.SetObjResult(interp, obj.NewIntObj(@as(isize, @enumToInt(enumValue))));
                    } else {
                        obj.SetObjResult(interp, obj.NewStringObj("Enum variant not found"));
                        return err.TclError.TCL_ERROR;
                    }
                },

                .name => {
                    if (objv.len < 3) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "name variantValue");
                        return err.TclError.TCL_ERROR;
                    }

                    const value = try obj.GetIntFromObj(interp, objv[2]);

                    inline for (std.meta.fields(enm)) |field| {
                        if (field.value == value) {
                            obj.SetObjResult(interp, obj.NewStringObj(field.name));
                            return;
                        }
                    }
                },
            }
        }
    };
}

pub fn EnumVariantCommand(comptime enm: type, comptime name: []const u8, comptime value: comptime_int) type {
    return struct {
        pub fn command(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objv: []const obj.Obj) err.TclError!void {
            _ = cdata;

            if (objv.len == 1) {
                obj.SetObjResult(interp, obj.NewIntObj(@as(isize, value)));
            }

            switch (try obj.GetIndexFromObj(EnumVariantCmds, interp, objv[1], "commands")) {
                .name => {
                    obj.SetObjResult(interp, obj.NewStringObj(name));
                },

                .value => {
                    obj.SetObjResult(interp, obj.NewIntObj(@as(isize, value)));
                },

                .call => {
                    _ = enm;
                },
            }
        }
    };
}

test "enum variant name/value" {
    const e = enum(u8) {
        v0,
        v1,
        v2,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterEnum(e, "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v0 value"));
    try std.testing.expectEqual(@as(u8, 0), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v1 value"));
    try std.testing.expectEqual(@as(u8, 1), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v2 value"));
    try std.testing.expectEqual(@as(u8, 2), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v0 name"));
    try std.testing.expectEqualSlices(u8, "v0", try obj.GetStringFromObj(tcl.Tcl_GetObjResult(interp)));

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v1 name"));
    try std.testing.expectEqualSlices(u8, "v1", try obj.GetStringFromObj(tcl.Tcl_GetObjResult(interp)));

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v2 name"));
    try std.testing.expectEqualSlices(u8, "v2", try obj.GetStringFromObj(tcl.Tcl_GetObjResult(interp)));
}
