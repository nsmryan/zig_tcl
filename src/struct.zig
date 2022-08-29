const std = @import("std");
const testing = std.testing;

const err = @import("err.zig");

const obj = @import("obj.zig");

const tcl = @import("tcl.zig");

pub const StructCmds = enum {
    create,
};

pub fn StructCommand(comptime strt: type) type {
    return struct {
        pub fn command(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objv: []const obj.Obj) err.TclError!void {
            _ = cdata;

            if (objv.len < 2) {
                try obj.WrongNumArgs(interp, objv, "create name");
                return err.TclError.TCL_ERROR;
            }

            // NOTE(zig) It is quite nice that std.meta can give us this array. This makes things easier then in C.
            // The following switch is also better then the C version.
            switch (try obj.GetIndexFromObj(StructCmds, interp, objv[1], "commands")) {
                .create => {
                    if (objv.len < 3) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "create name");
                        return err.TclError.TCL_ERROR;
                    }

                    var length: c_int = undefined;
                    const name = tcl.Tcl_GetStringFromObj(objv[2], &length);
                    var ptr = tcl.Tcl_Alloc(@sizeOf(strt));
                    const result = tcl.Tcl_CreateObjCommand(interp, name, StructInstanceCommand, @ptrCast(tcl.ClientData, ptr), TclDeallocateCallback);
                    if (result == null) {
                        obj.SetStrResult(interp, "Could not create command!");
                        return err.TclError.TCL_ERROR;
                    } else {
                        return;
                    }
                    //return tcl.Tcl_CreateObjCommand(interp, name, StructInstanceCommand, @intToPtr(tcl.ClientData, @ptrToInt(ptr)), null);
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
                    return StructGetFieldCmd(strt_ptr, interp, objc, objv);
                },

                .set => {
                    return StructSetFieldCmd(strt_ptr, interp, objc, objv);
                },
            }
            obj.SetStrResult(interp, "Unexpected subcommand!");
            return tcl.TCL_ERROR;
        }

        pub fn StructGetFieldCmd(ptr: *strt, interp: obj.Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
            if (objc < 3) {
                tcl.Tcl_WrongNumArgs(interp, objc, objv, "get name ...");
                return tcl.TCL_ERROR;
            }

            // Preallocate enough space for all requested fields, and replace elements
            // as we go.
            var resultList = obj.NewListWithCapacity(objc - 2);
            var index: usize = 2;
            while (index < objc) : (index += 1) {
                var length: c_int = undefined;
                const name = tcl.Tcl_GetStringFromObj(objv[index], &length);
                if (length == 0) {
                    continue;
                }

                var found: bool = false;
                inline for (@typeInfo(strt).Struct.fields) |field| {
                    if (std.mem.eql(u8, name[0..@intCast(usize, length)], field.name)) {
                        found = true;
                        var fieldObj = StructGetField(ptr, field.name) catch |errResult| return err.TclResult(errResult);
                        const result = tcl.Tcl_ListObjReplace(interp, resultList, @intCast(c_int, index), 1, 1, &fieldObj);
                        if (result != tcl.TCL_OK) {
                            obj.SetStrResult(interp, "Failed to retrieve a field from a struct!");
                            return result;
                        }
                        break;
                    }
                }

                if (!found) {
                    obj.SetStrResult(interp, "One or more field names not found in struct get!");
                    return tcl.TCL_ERROR;
                }
            }

            obj.SetObjResult(interp, resultList);

            return tcl.TCL_OK;
        }

        pub fn StructSetFieldCmd(ptr: *strt, interp: obj.Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) c_int {
            if (objc < 4) {
                tcl.Tcl_WrongNumArgs(interp, objc, objv, "set name value ... name value");
                return tcl.TCL_ERROR;
            }

            var index: usize = 2;
            while (index < objc) : (index += 2) {
                var length: c_int = undefined;
                const name = tcl.Tcl_GetStringFromObj(objv[index], &length);
                if (length == 0) {
                    continue;
                }

                var found: bool = false;
                inline for (@typeInfo(strt).Struct.fields) |field| {
                    if (std.mem.eql(u8, name[0..@intCast(usize, length)], field.name)) {
                        found = true;
                        StructSetField(ptr, field.name, interp, objv[index + 1]) catch |errResult| return err.TclResult(errResult);
                        break;
                    }
                }

                if (!found) {
                    obj.SetStrResult(interp, "One or more field names not found in struct set!");
                    return tcl.TCL_ERROR;
                }
            }

            return tcl.TCL_OK;
        }

        pub fn StructGetField(ptr: *strt, comptime fieldName: []const u8) err.TclError!obj.Obj {
            return obj.ToObj(@field(ptr.*, fieldName));
        }

        pub fn StructSetField(ptr: *strt, comptime fieldName: []const u8, interp: obj.Interp, fieldObj: obj.Obj) err.TclError!void {
            @field(ptr.*, fieldName) = try obj.GetFromObj(@TypeOf(@field(ptr.*, fieldName)), interp, fieldObj);
        }
    };
}

pub const StructInstanceCmds = enum {
    get,
    set,
};

pub fn TclDeallocateCallback(cdata: tcl.ClientData) callconv(.C) void {
    tcl.Tcl_Free(@ptrCast([*c]u8, cdata));
}

pub fn RegisterStruct(comptime strt: type, comptime pkg: []const u8, interp: obj.Interp) c_int {
    const terminator: [1]u8 = .{0};
    const cmdName = pkg ++ "::" ++ @typeName(strt) ++ terminator;
    _ = obj.CreateObjCommand(interp, cmdName, StructCommand(strt).command) catch |errResult| return err.ErrorToInt(errResult);

    return tcl.TCL_OK;
}
