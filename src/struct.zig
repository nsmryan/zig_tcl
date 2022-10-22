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
    fields,
    fromBytes,
    size,
    with,
};

pub const StructInstanceCmds = enum {
    get,
    set,
    call,
    bytes,
    setBytes,
    ptr,
};

pub fn RegisterStruct(comptime strt: type, comptime name: []const u8, comptime pkg: []const u8, interp: obj.Interp) c_int {
    if (@typeInfo(strt) != .Struct) {
        @compileError("Attempting to register a non-struct as a struct!");
    }

    const terminator: [1]u8 = .{0};
    var cmdName = pkg ++ "::" ++ name ++ terminator;
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
                    const result = tcl.Tcl_CreateObjCommand(interp, name.ptr, StructInstanceCommand, @ptrCast(tcl.ClientData, ptr), utils.TclDeallocateCallback);
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
                        // Ignore private decls
                        if (!decl.is_pub) {
                            continue;
                        }

                        const field = @field(strt, decl.name);
                        const field_info = call.FuncInfo(@typeInfo(@TypeOf(field))) orelse continue;

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

                .fields => {
                    comptime var fields = std.meta.fields(strt);
                    var resultList = obj.NewListObj(&.{});
                    inline for (fields) |field| {
                        try obj.ListObjAppendElement(interp, resultList, obj.NewStringObj(field.name));
                        try obj.ListObjAppendElement(interp, resultList, obj.NewStringObj(@typeName(field.field_type)));
                    }

                    obj.SetObjResult(interp, resultList);
                    return;
                },

                .fromBytes => {
                    if (objv.len < 4) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "fromBytes name bytes");
                        return err.TclError.TCL_ERROR;
                    }

                    const name = try obj.GetStringFromObj(objv[2]);

                    obj.IncrRefCount(objv[3]);

                    var length: c_int = undefined;
                    var bytes = tcl.Tcl_GetByteArrayFromObj(objv[3], &length);

                    if (length != @sizeOf(strt)) {
                        obj.SetStrResult(interp, "Byte array size does not match struct!");
                        return err.TclError.TCL_ERROR;
                    }

                    var ptr = tcl.Tcl_Alloc(@sizeOf(strt));
                    @memcpy(ptr, bytes, @sizeOf(strt));

                    const result = tcl.Tcl_CreateObjCommand(interp, name.ptr, StructInstanceCommand, @ptrCast(tcl.ClientData, ptr), utils.TclDeallocateCallback);
                    if (result == null) {
                        obj.SetStrResult(interp, "Could not create command!");
                        return err.TclError.TCL_ERROR;
                    } else {
                        return;
                    }
                },

                .size => {
                    obj.SetObjResult(interp, try obj.ToObj(@intCast(c_int, @sizeOf(strt))));
                    return;
                },

                .with => {
                    if (objv.len < 4) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "with pointer decl args...");
                        return err.TclError.TCL_ERROR;
                    }
                    const ptr = try obj.GetFromObj(*strt, interp, objv[2]);
                    const objc = @intCast(c_int, objv.len - 2);
                    var objv_subset = objv[2..].ptr;
                    var clientData = @ptrCast(tcl.ClientData, ptr);
                    try err.HandleReturn(StructInstanceCommand(clientData, interp, objc, objv_subset));
                    return;
                },
            }

            obj.SetStrResult(interp, "Unexpected subcommand name on struct type!");
            return err.TclError.TCL_ERROR;
        }

        pub fn StructInstanceCommand(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) callconv(.C) c_int {
            // TODO support the cget, configure interface in syntax.tcl
            if (@alignOf(strt) == 0) {
                obj.SetStrResult(interp, "Cannot instantiate struct!");
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

                .bytes => {
                    return err.TclResult(StructBytesCmd(strt_ptr, interp, obj.ObjSlice(objc, objv)));
                },

                .setBytes => {
                    return err.TclResult(StructSetBytesCmd(strt_ptr, interp, obj.ObjSlice(objc, objv)));
                },

                .ptr => {
                    return err.TclResult(StructPtrCmd(strt_ptr, interp, obj.ObjSlice(objc, objv)));
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
                comptime var fields = std.meta.fields(strt);
                inline for (fields) |field| {
                    if (std.mem.eql(u8, name, field.name)) {
                        found = true;
                        var fieldObj = try obj.ToObj(@field(ptr.*, field.name));

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
                comptime var fields = std.meta.fields(strt);
                inline for (fields) |field| {
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
                // Ignore private decls
                if (!decl.is_pub) {
                    continue;
                }

                const field = @field(strt, decl.name);
                const field_info = call.FuncInfo(@typeInfo(@TypeOf(field))) orelse continue;

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

        pub fn StructBytesCmd(ptr: *strt, interp: obj.Interp, objv: []const obj.Obj) err.TclError!void {
            _ = objv;
            obj.SetObjResult(interp, try obj.ToObj(ptr.*));
        }

        pub fn StructGetField(ptr: *strt, comptime fieldName: []const u8) err.TclError!obj.Obj {
            return obj.ToObj(@field(ptr.*, fieldName));
        }

        pub fn StructSetField(ptr: *strt, comptime fieldName: []const u8, interp: obj.Interp, fieldObj: obj.Obj) err.TclError!void {
            @field(ptr.*, fieldName) = try obj.GetFromObj(@TypeOf(@field(ptr.*, fieldName)), interp, fieldObj);
        }

        pub fn StructSetBytesCmd(ptr: *strt, interp: obj.Interp, objv: []const obj.Obj) err.TclError!void {
            if (objv.len < 3) {
                obj.WrongNumArgs(interp, objv, "fromBytes bytes");
                return err.TclError.TCL_ERROR;
            }

            var length: c_int = undefined;
            var bytes = tcl.Tcl_GetByteArrayFromObj(objv[2], &length);
            if (length == @sizeOf(strt)) {
                @memcpy(@ptrCast([*]u8, ptr), bytes, @intCast(usize, length));
                return;
            } else {
                obj.SetStrResult(interp, "Byte array size does not match struct!");
                return err.TclError.TCL_ERROR;
            }
        }

        pub fn StructPtrCmd(ptr: *strt, interp: obj.Interp, objv: []const obj.Obj) err.TclError!void {
            if (objv.len < 3) {
                obj.SetObjResult(interp, try obj.ToObj(ptr));
            } else if (objv.len == 3) {
                var length: c_int = undefined;
                const name = tcl.Tcl_GetStringFromObj(objv[2], &length);
                if (length == 0) {
                    obj.SetStrResult(interp, "An empty field name is not valid!");
                    return err.TclError.TCL_ERROR;
                }

                var found: bool = false;
                comptime var fields = std.meta.fields(strt);
                inline for (fields) |field| {
                    if (std.mem.eql(u8, name[0..@intCast(usize, length)], field.name)) {
                        found = true;
                        obj.SetObjResult(interp, try obj.ToObj(&@field(ptr.*, field.name)));
                        break;
                    }
                }

                if (!found) {
                    obj.SetStrResult(interp, "One or more field names not found in struct field call!");
                    return err.TclError.TCL_ERROR;
                }
            } else {
                tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "ptr [field]");
            }
        }
    };
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
    result = RegisterStruct(s, "s", "test", interp);
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
    result = RegisterStruct(s, "s", "test", interp);
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
    result = RegisterStruct(s, "s", "test", interp);
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
    result = RegisterStruct(s, "s", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s call decl1 1");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    const resultObj = tcl.Tcl_GetObjResult(interp);
    try std.testing.expectEqual(@as(u32, 11), try obj.GetFromObj(u32, interp, resultObj));
}

test "struct fields" {
    const s = struct {
        field0: u8,
        field1: f64,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "s", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::s fields"));

    var resultList = tcl.Tcl_GetObjResult(interp);

    var resultObj: obj.Obj = undefined;
    try err.HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 0, &resultObj));
    try std.testing.expectEqualSlices(u8, "field0", try obj.GetStringFromObj(resultObj));

    try err.HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 1, &resultObj));
    try std.testing.expectEqualSlices(u8, "u8", try obj.GetStringFromObj(resultObj));

    try err.HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 2, &resultObj));
    try std.testing.expectEqualSlices(u8, "field1", try obj.GetStringFromObj(resultObj));

    try err.HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 3, &resultObj));
    try std.testing.expectEqualSlices(u8, "f64", try obj.GetStringFromObj(resultObj));
}

test "struct bytes" {
    const s = struct {
        field0: u8,
        field1: f64,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "s", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s create instance");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance bytes");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    var byteObj = tcl.Tcl_GetObjResult(interp);

    var length: c_int = undefined;
    var bytes = tcl.Tcl_GetByteArrayFromObj(byteObj, &length);

    var cmdInfo: tcl.Tcl_CmdInfo = undefined;
    _ = tcl.Tcl_GetCommandInfo(interp, "instance", &cmdInfo);

    try std.testing.expectEqualSlices(u8, bytes[0..@intCast(usize, length)], @ptrCast([*]u8, cmdInfo.objClientData)[0..@sizeOf(s)]);

    result = tcl.Tcl_Eval(interp, "test::s fromBytes instance2 [instance bytes]");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance2 set field0 123");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance setBytes [instance2 bytes]");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance get field0");
    try std.testing.expectEqual(tcl.TCL_OK, result);
    const resultObj = tcl.Tcl_GetObjResult(interp);
    try std.testing.expectEqual(@as(u32, 123), try obj.GetFromObj(u32, interp, resultObj));
}

test "struct ptr" {
    const s = struct {
        field0: u64,
        field1: u64,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "s", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s create instance");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance set field0 101");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance set field1 202");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance ptr");
    try std.testing.expectEqual(tcl.TCL_OK, result);
    var s_ptr = try obj.GetFromObj(*s, interp, tcl.Tcl_GetObjResult(interp));

    try std.testing.expectEqual(@as(u64, 101), s_ptr.field0);
    try std.testing.expectEqual(@as(u64, 202), s_ptr.field1);

    result = tcl.Tcl_Eval(interp, "instance ptr field0");
    try std.testing.expectEqual(tcl.TCL_OK, result);
    var field0_ptr = try obj.GetFromObj(*u64, interp, tcl.Tcl_GetObjResult(interp));
    try std.testing.expectEqual(@as(u64, 101), field0_ptr.*);

    result = tcl.Tcl_Eval(interp, "instance ptr field1");
    try std.testing.expectEqual(tcl.TCL_OK, result);
    var field1_ptr = try obj.GetFromObj(*u64, interp, tcl.Tcl_GetObjResult(interp));
    try std.testing.expectEqual(@as(u64, 202), field1_ptr.*);
}

test "struct size" {
    const s = struct {
        field0: f64,
        field1: f64,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "s", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s size");
    try std.testing.expectEqual(tcl.TCL_OK, result);
    const resultObj = tcl.Tcl_GetObjResult(interp);
    try std.testing.expectEqual(@as(u32, @sizeOf(s)), try obj.GetFromObj(u32, interp, resultObj));
}

test "struct with" {
    const s = struct {
        field0: f64,
        field1: u32,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterStruct(s, "s", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s create instance");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "test::s with [instance ptr] set field1 101");
    try std.testing.expectEqual(tcl.TCL_OK, result);

    result = tcl.Tcl_Eval(interp, "instance get field1");
    try std.testing.expectEqual(tcl.TCL_OK, result);
    const resultObj = tcl.Tcl_GetObjResult(interp);
    try std.testing.expectEqual(@as(u32, 101), try obj.GetFromObj(u32, interp, resultObj));
}
