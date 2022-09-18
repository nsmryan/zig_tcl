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
    variants,
};

pub const EnumVariantCmds = enum {
    name,
    value,
    call,
};

pub fn RegisterEnum(comptime enm: type, comptime name: []const u8, comptime pkg: []const u8, interp: obj.Interp) c_int {
    if (@typeInfo(enm) != .Enum) {
        @compileError("Attempting to register a non-enum as an enum!");
    }

    const terminator: [1]u8 = .{0};
    const cmdName = pkg ++ "::" ++ name ++ terminator;
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

            switch (try obj.GetIndexFromObj(EnumCmds, interp, objv[1], "commands")) {
                .call => {
                    if (objv.len < 3) {
                        obj.WrongNumArgs(interp, objv, "call name [args]");
                        return err.TclError.TCL_ERROR;
                    }

                    const name = try obj.GetStringFromObj(objv[2]);

                    // Search for a decl of the given name.
                    comptime var decls = std.meta.declarations(enm);
                    inline for (decls) |decl| {
                        // Ignore privatve decls
                        if (!decl.is_pub) {
                            continue;
                        }

                        // If the name matches attempt to call it.
                        if (std.mem.eql(u8, name, decl.name)) {
                            const field = @field(enm, decl.name);
                            const field_info = call.FuncInfo(@typeInfo(@TypeOf(field)));

                            comptime {
                                if (!utils.CallableFunction(field_info)) {
                                    continue;
                                }
                            }

                            try call.CallDecl(field, interp, @intCast(c_int, objv.len), objv.ptr);

                            return;
                        }
                    }

                    obj.SetStrResult(interp, "One or more field names not found in struct call!");
                    return err.TclError.TCL_ERROR;
                },

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

                .variants => {
                    if (objv.len < 2) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "variants");
                        return err.TclError.TCL_ERROR;
                    }

                    comptime var fields = std.meta.fields(enm);
                    var resultList = obj.NewListWithCapacity(@intCast(c_int, fields.len));

                    inline for (std.meta.fields(enm)) |field| {
                        try obj.ListObjAppendElement(interp, resultList, obj.NewStringObj(field.name));
                        try obj.ListObjAppendElement(interp, resultList, obj.NewIntObj(@intCast(isize, field.value)));
                    }

                    obj.SetObjResult(interp, resultList);
                },
            }
        }
    };
}

pub fn EnumVariantCommand(comptime enm: type, comptime variantName: []const u8, comptime value: comptime_int) type {
    return struct {
        pub fn command(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objv: []const obj.Obj) err.TclError!void {
            _ = cdata;

            if (objv.len == 1) {
                obj.SetObjResult(interp, obj.NewIntObj(@as(isize, value)));
                return;
            }

            switch (try obj.GetIndexFromObj(EnumVariantCmds, interp, objv[1], "commands")) {
                .name => {
                    obj.SetObjResult(interp, obj.NewStringObj(variantName));
                    return;
                },

                .value => {
                    obj.SetObjResult(interp, obj.NewIntObj(@as(isize, value)));
                    return;
                },

                .call => {
                    if (objv.len < 3) {
                        obj.WrongNumArgs(interp, objv, "call name [args]");
                        return err.TclError.TCL_ERROR;
                    }

                    const name = try obj.GetStringFromObj(objv[2]);

                    // Search for a decl of the given name.
                    comptime var decls = std.meta.declarations(enm);
                    inline for (decls) |decl| {
                        // Ignore privatve decls
                        if (!decl.is_pub) {
                            continue;
                        }

                        const field = @field(enm, decl.name);
                        const field_info = call.FuncInfo(@typeInfo(@TypeOf(field)));

                        comptime {
                            if (!utils.CallableDecl(enm, field_info)) {
                                continue;
                            }
                        }

                        // If the name matches attempt to call it.
                        if (std.mem.eql(u8, name, decl.name)) {
                            var enumValue = @intToEnum(enm, value);
                            try call.CallBound(field, interp, @ptrCast(tcl.ClientData, &enumValue), @intCast(c_int, objv.len), objv.ptr);

                            return;
                        }
                    }

                    obj.SetStrResult(interp, "One or more field names not found in struct call!");
                    return err.TclError.TCL_ERROR;
                },
            }

            obj.SetStrResult(interp, "Struct command not found!");
            return err.TclError.TCL_ERROR;
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
    result = RegisterEnum(e, "e", "test", interp);
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

test "enum variant call" {
    const e = enum(u8) {
        v0,
        v1,

        pub fn decl1(self: *@This()) u8 {
            return @enumToInt(self.*);
        }

        pub fn decl2(self: @This()) u8 {
            return @enumToInt(self);
        }
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterEnum(e, "e", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v0 call decl1"));
    try std.testing.expectEqual(@as(u8, 0), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v1 call decl2"));
    try std.testing.expectEqual(@as(u8, 1), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));

    // The enum itself returns its value.
    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e::v1"));
    try std.testing.expectEqual(@as(u8, 1), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));
}

test "enum call" {
    const e = enum(u8) {
        v0,
        v1,

        pub fn decl1() u8 {
            return 0;
        }

        pub fn decl2() @This() {
            return .v1;
        }
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterEnum(e, "e", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e call decl1"));
    try std.testing.expectEqual(@as(u8, 0), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e call decl2"));
    try std.testing.expectEqual(@as(u8, 1), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));
}

test "enum name/value" {
    const e = enum(u8) {
        v0,
        v1,

        pub fn decl1() u8 {
            return 0;
        }

        pub fn decl2() @This() {
            return .v1;
        }
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterEnum(e, "e", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e value v0"));
    try std.testing.expectEqual(@as(u8, 0), try obj.GetFromObj(u8, interp, tcl.Tcl_GetObjResult(interp)));

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e name 1"));
    try std.testing.expectEqualSlices(u8, "v1", try obj.GetStringFromObj(tcl.Tcl_GetObjResult(interp)));
}

test "enum variants" {
    const e = enum(u8) {
        v0,
        v1,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterEnum(e, "e", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::e variants"));
    var resultList = tcl.Tcl_GetObjResult(interp);

    var resultObj: obj.Obj = undefined;
    try err.HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 0, &resultObj));
    std.debug.print("{s}\n", .{try obj.GetStringFromObj(resultObj)});
    try std.testing.expectEqualSlices(u8, "v0", try obj.GetStringFromObj(resultObj));
}
