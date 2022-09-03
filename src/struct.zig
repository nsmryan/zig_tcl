const std = @import("std");

const testing = std.testing;

const err = @import("err.zig");
const obj = @import("obj.zig");
const call = @import("call.zig");
const utils = @import("utils.zig");
const tcl = @import("tcl.zig");

pub const StructCmds = enum {
    create,
    call,
};

pub const StructInstanceCmds = enum {
    get,
    set,
    call,
};

pub fn RegisterStruct(comptime strt: type, comptime pkg: []const u8, interp: obj.Interp) c_int {
    const terminator: [1]u8 = .{0};
    const cmdName = pkg ++ "::" ++ @typeName(strt) ++ terminator;
    _ = obj.CreateObjCommand(interp, cmdName, StructCommand(strt).command) catch |errResult| return err.ErrorToInt(errResult);

    return tcl.TCL_OK;
}

pub fn StructCommand(comptime strt: type) type {
    return struct {
        pub fn command(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objv: []const obj.Obj) err.TclError!void {
            _ = cdata;

            // NOTE(zig) It is quite nice that std.meta can give us this array. This makes things easier then in C.
            // The following switch is also better then the C version.
            switch (try obj.GetIndexFromObj(StructCmds, interp, objv[1], "commands")) {
                .create => {
                    if (objv.len < 3) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "create name");
                        return err.TclError.TCL_ERROR;
                    }

                    const name = try obj.GetStringFromObj(objv[2]);

                    var ptr = tcl.Tcl_Alloc(@sizeOf(strt));
                    const result = tcl.Tcl_CreateObjCommand(interp, name.ptr, StructInstanceCommand, @ptrCast(tcl.ClientData, ptr), TclDeallocateCallback);
                    if (result == null) {
                        obj.SetStrResult(interp, "Could not create command!");
                        return err.TclError.TCL_ERROR;
                    } else {
                        return;
                    }
                },

                .call => {
                    if (objv.len < 3) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "call decl");
                        return err.TclError.TCL_ERROR;
                    }

                    const name = try obj.GetStringFromObj(objv[2]);

                    // Search for a decl of the given name.
                    comptime var decls = std.meta.declarations(strt);
                    inline for (decls) |decl| {
                        // Ignore privatve decls
                        if (!decl.is_pub) {
                            continue;
                        }

                        const field = @field(strt, decl.name);
                        const field_info = call.FuncInfo(@typeInfo(@TypeOf(field)));

                        comptime {
                            if (!utils.CallableFunction(field_info)) {
                                continue;
                            }
                        }

                        // If the name matches attempt to call it.
                        if (std.mem.eql(u8, name, decl.name)) {
                            try call.CallDecl(field, interp, @intCast(c_int, objv.len), objv.ptr);
                            return;
                        }
                    }

                    obj.SetStrResult(interp, "One or more field names not found in struct call!");
                    return err.TclError.TCL_ERROR;
                },
            }

            obj.SetStrResult(interp, "Unexpected subcommand name when creating struct!");
            return err.TclError.TCL_ERROR;
        }

        fn StructInstanceCommand(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) callconv(.C) c_int {
            _ = cdata;
            // support the cget, field, call, configure interface in syntax.tcl
            if (objc < 2) {
                tcl.Tcl_WrongNumArgs(interp, objc, objv, "field name [value]");
                return tcl.TCL_ERROR;
            }

            var strt_ptr = @ptrCast(*strt, @alignCast(@alignOf(strt), cdata));
            const cmd = obj.GetIndexFromObj(StructInstanceCmds, interp, objv[1], "commands") catch |errResult| return err.TclResult(errResult);
            switch (cmd) {
                .get => {
                    return err.TclResult(StructGetFieldCmd(strt_ptr, interp, obj.ObjSlice(objc, objv)));
                },

                .set => {
                    return err.TclResult(StructSetFieldCmd(strt_ptr, interp, obj.ObjSlice(objc, objv)));
                },

                .call => {
                    return err.TclResult(StructCallCmd(strt_ptr, interp, obj.ObjSlice(objc, objv)));
                },
            }
            obj.SetStrResult(interp, "Unexpected subcommand!");
            return tcl.TCL_ERROR;
        }

        pub fn StructGetFieldCmd(ptr: *strt, interp: obj.Interp, objv: []const obj.Obj) err.TclError!void {
            if (objv.len < 3) {
                obj.WrongNumArgs(interp, objv, "get name ...");
                return err.TclError.TCL_ERROR;
            }

            // Preallocate enough space for all requested fields, and replace elements as we go.
            var resultList = obj.NewListWithCapacity(@intCast(c_int, objv.len) - 2);
            var index: usize = 2;
            while (index < objv.len) : (index += 1) {
                const name = try obj.GetStringFromObj(objv[index]);

                var found: bool = false;
                inline for (@typeInfo(strt).Struct.fields) |field| {
                    if (std.mem.eql(u8, name, field.name)) {
                        found = true;
                        var fieldObj = try StructGetField(ptr, field.name);
                        const result = tcl.Tcl_ListObjReplace(interp, resultList, @intCast(c_int, index), 1, 1, &fieldObj);
                        if (result != tcl.TCL_OK) {
                            obj.SetStrResult(interp, "Failed to retrieve a field from a struct!");
                            return err.TclError.TCL_ERROR;
                        }
                        break;
                    }
                }

                if (!found) {
                    obj.SetStrResult(interp, "One or more field names not found in struct get!");
                    return err.TclError.TCL_ERROR;
                }
            }

            obj.SetObjResult(interp, resultList);
        }

        pub fn StructSetFieldCmd(ptr: *strt, interp: obj.Interp, objv: []const obj.Obj) err.TclError!void {
            if (objv.len < 4) {
                obj.WrongNumArgs(interp, objv, "set name value ... name value");
                return err.TclError.TCL_ERROR;
            }

            var index: usize = 2;
            while (index < objv.len) : (index += 2) {
                var length: c_int = undefined;
                const name = tcl.Tcl_GetStringFromObj(objv[index], &length);
                if (length == 0) {
                    continue;
                }

                var found: bool = false;
                inline for (@typeInfo(strt).Struct.fields) |field| {
                    if (std.mem.eql(u8, name[0..@intCast(usize, length)], field.name)) {
                        found = true;
                        try StructSetField(ptr, field.name, interp, objv[index + 1]);
                        break;
                    }
                }

                if (!found) {
                    obj.SetStrResult(interp, "One or more field names not found in struct set!");
                    return err.TclError.TCL_ERROR;
                }
            }
        }

        pub fn StructCallCmd(ptr: *strt, interp: obj.Interp, objv: []const obj.Obj) err.TclError!void {
            if (objv.len < 3) {
                obj.WrongNumArgs(interp, objv, "call name [args]");
                return err.TclError.TCL_ERROR;
            }

            const name = try obj.GetStringFromObj(objv[2]);

            // Search for a decl of the given name.
            comptime var decls = std.meta.declarations(strt);
            inline for (decls) |decl| {
                // Ignore privatve decls
                if (!decl.is_pub) {
                    continue;
                }

                const field = @field(strt, decl.name);
                const field_info = call.FuncInfo(@typeInfo(@TypeOf(field)));

                comptime {
                    if (!utils.CallableDecl(strt, field_info)) {
                        continue;
                    }
                }

                // If the name matches attempt to call it.
                if (std.mem.eql(u8, name, decl.name)) {
                    try call.CallBound(field, interp, @ptrCast(tcl.ClientData, ptr), @intCast(c_int, objv.len), objv.ptr);

                    return;
                }
            }

            obj.SetStrResult(interp, "One or more field names not found in struct call!");
            return err.TclError.TCL_ERROR;
        }

        pub fn StructGetField(ptr: *strt, comptime fieldName: []const u8) err.TclError!obj.Obj {
            return obj.ToObj(@field(ptr.*, fieldName));
        }

        pub fn StructSetField(ptr: *strt, comptime fieldName: []const u8, interp: obj.Interp, fieldObj: obj.Obj) err.TclError!void {
            @field(ptr.*, fieldName) = try obj.GetFromObj(@TypeOf(@field(ptr.*, fieldName)), interp, fieldObj);
        }
    };
}

pub fn TclDeallocateCallback(cdata: tcl.ClientData) callconv(.C) void {
    tcl.Tcl_Free(@ptrCast([*c]u8, cdata));
}

test "struct create/set/get" {
    const s = struct {
        field0: u32,
        field1: [4]u8,
        field2: f64,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s create instance");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    {
        result = tcl.Tcl_Eval(interp, "instance set field0 100");
        try std.testing.expectEqual(tcl.TCL_OK, result);

        result = tcl.Tcl_Eval(interp, "instance get field0");
        try std.testing.expectEqual(tcl.TCL_OK, result);
        const resultObj = tcl.Tcl_GetObjResult(interp);
        try std.testing.expectEqual(@as(u32, 100), try obj.GetFromObj(u32, interp, resultObj));
    }

    {
        result = tcl.Tcl_Eval(interp, "instance set field1 test");
        try std.testing.expectEqual(tcl.TCL_OK, result);

        result = tcl.Tcl_Eval(interp, "instance get field1");
        try std.testing.expectEqual(tcl.TCL_OK, result);
        const resultObj = tcl.Tcl_GetObjResult(interp);
        const expected: [4]u8 = .{ 't', 'e', 's', 't' };
        try std.testing.expectEqual(expected, try obj.GetFromObj([4]u8, interp, resultObj));
    }

    {
        result = tcl.Tcl_Eval(interp, "instance set field2 1.4");
        try std.testing.expectEqual(tcl.TCL_OK, result);

        result = tcl.Tcl_Eval(interp, "instance get field2");
        try std.testing.expectEqual(tcl.TCL_OK, result);
        const resultObj = tcl.Tcl_GetObjResult(interp);
        try std.testing.expectEqual(@as(f64, 1.4), try obj.GetFromObj(f64, interp, resultObj));
    }
}

test "struct create/set/get multiple" {
    const s = struct {
        field0: u32,
        field1: f64,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s create instance");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance set field0 99 field1 1.4");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance get field0 field1");
    try std.testing.expectEqual(tcl.TCL_OK, result);
    const resultList = tcl.Tcl_GetObjResult(interp);

    var resultObj: obj.Obj = undefined;

    try err.HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 0, &resultObj));
    try std.testing.expectEqual(@as(u32, 99), try obj.GetFromObj(u32, interp, resultObj));

    try err.HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 1, &resultObj));
    try std.testing.expectEqual(@as(f64, 1.4), try obj.GetFromObj(f64, interp, resultObj));
}

test "struct create/call" {
    const s = struct {
        field0: u32,

        pub fn decl1(self: *@This(), newFieldValue: u32) u32 {
            const old: u32 = self.field0;
            self.field0 = newFieldValue;
            return old;
        }

        pub fn decl2(self: @This()) u32 {
            return self.field0;
        }
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s create instance");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance set field0 99");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    var cmd_info: tcl.Tcl_CmdInfo = undefined;
    _ = tcl.Tcl_GetCommandInfo(interp, "instance", &cmd_info);

    {
        result = tcl.Tcl_Eval(interp, "instance call decl1 200");
        try std.testing.expectEqual(tcl.TCL_OK, result);
        const resultObj = tcl.Tcl_GetObjResult(interp);
        try std.testing.expectEqual(@as(u32, 99), try obj.GetFromObj(u32, interp, resultObj));
    }

    {
        result = tcl.Tcl_Eval(interp, "instance get field0");
        try std.testing.expectEqual(tcl.TCL_OK, result);
        const resultObj = tcl.Tcl_GetObjResult(interp);
        try std.testing.expectEqual(@as(u32, 200), try obj.GetFromObj(u32, interp, resultObj));
    }

    {
        result = tcl.Tcl_Eval(interp, "instance call decl2");
        try std.testing.expectEqual(tcl.TCL_OK, result);
        const resultObj = tcl.Tcl_GetObjResult(interp);
        try std.testing.expectEqual(@as(u32, 200), try obj.GetFromObj(u32, interp, resultObj));
    }
}

test "struct type call decl" {
    const s = struct {
        field0: u8,

        pub fn decl1(value: u32) u32 {
            return value + 10;
        }
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s call decl1 1");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    const resultObj = tcl.Tcl_GetObjResult(interp);
    try std.testing.expectEqual(@as(u32, 11), try obj.GetFromObj(u32, interp, resultObj));
}
