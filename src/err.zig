const std = @import("std");
const testing = std.testing;

const obj = @import("obj.zig");
const tcl = @import("tcl.zig");

// TCL_OK is not represented as it is the result of a normal return.
// NOTE it is not clear to me that return/break/continue need to be in here.
pub const TclError = error{
    TCL_ERROR,
    TCL_RETURN,
    TCL_BREAK,
    TCL_CONTINUE,
};

pub fn ErrorToInt(errValue: TclError) c_int {
    switch (errValue) {
        TclError.TCL_ERROR => return tcl.TCL_ERROR,
        TclError.TCL_RETURN => return tcl.TCL_RETURN,
        TclError.TCL_BREAK => return tcl.TCL_BREAK,
        TclError.TCL_CONTINUE => return tcl.TCL_CONTINUE,
    }
}

pub fn TclResult(result: TclError!void) c_int {
    if (result) {
        return tcl.TCL_OK;
    } else |errValue| {
        return ErrorToInt(errValue);
    }
}

pub fn HandleReturn(result: c_int) TclError!void {
    if (result == tcl.TCL_ERROR) {
        return TclError.TCL_ERROR;
    } else if (result == tcl.TCL_RETURN) {
        return TclError.TCL_RETURN;
    } else if (result == tcl.TCL_BREAK) {
        return TclError.TCL_BREAK;
    } else if (result == tcl.TCL_CONTINUE) {
        return TclError.TCL_CONTINUE;
    }
}

pub const ErrorSetCmds = enum {
    variants,
};

pub const ErrorSetVariantCmds = enum {
    name,
};

pub fn RegisterErrorSet(comptime es: type, comptime name: []const u8, comptime pkg: []const u8, interp: obj.Interp) c_int {
    if (!std.meta.trait.is(.ErrorSet)(es)) {
        obj.SetObjResult(interp, obj.NewStringObj("Attempting to register a non-error set as an error set!"));
        return tcl.TCL_ERROR;
    }

    if (@typeInfo(es).ErrorSet) |errorNames| {
        const terminator: [1]u8 = .{0};
        const cmdName = pkg ++ "::" ++ name ++ terminator;
        _ = obj.CreateObjCommand(interp, cmdName, ErrorSetCommand(es).command) catch |errResult| return ErrorToInt(errResult);

        inline for (errorNames) |errorName| {
            const variantCmdName = pkg ++ "::" ++ name ++ "::" ++ errorName.name ++ terminator;
            _ = obj.CreateObjCommand(interp, variantCmdName, ErrorSetVariantCommand(errorName.name).command) catch |errResult| return ErrorToInt(errResult);
        }
    } else {
        obj.SetObjResult(interp, obj.NewStringObj("Attempting to register global error set?"));
        return tcl.TCL_ERROR;
    }

    return tcl.TCL_OK;
}

pub fn ErrorSetCommand(comptime es: type) type {
    return struct {
        pub fn command(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objv: []const obj.Obj) TclError!void {
            _ = cdata;

            switch (try obj.GetIndexFromObj(ErrorSetCmds, interp, objv[1], "commands")) {
                .variants => {
                    if (objv.len < 2) {
                        tcl.Tcl_WrongNumArgs(interp, @intCast(c_int, objv.len), objv.ptr, "variants");
                        return TclError.TCL_ERROR;
                    }

                    comptime var fields = std.meta.fields(es);
                    var resultList = obj.NewListWithCapacity(@intCast(c_int, fields.len));

                    inline for (fields) |errorName| {
                        try obj.ListObjAppendElement(interp, resultList, obj.NewStringObj(errorName.name));
                    }

                    obj.SetObjResult(interp, resultList);
                },
            }
        }
    };
}

pub fn ErrorSetVariantCommand(comptime errorName: []const u8) type {
    return struct {
        pub fn command(cdata: tcl.ClientData, interp: [*c]tcl.Tcl_Interp, objv: []const obj.Obj) TclError!void {
            _ = cdata;

            // When used as a command, error sets throw an exception.
            if (objv.len == 1) {
                obj.SetObjResult(interp, obj.NewStringObj(errorName));
                return TclError.TCL_ERROR;
            }

            switch (try obj.GetIndexFromObj(ErrorSetVariantCmds, interp, objv[1], "commands")) {
                .name => {
                    obj.SetObjResult(interp, obj.NewStringObj(errorName));
                    return;
                },
            }

            obj.SetStrResult(interp, "ErrorSet command not found!");
            return TclError.TCL_ERROR;
        }
    };
}

test "error set variants" {
    const er = error{
        e0,
        e1,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterErrorSet(er, "er", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::er variants"));
    var resultList = tcl.Tcl_GetObjResult(interp);

    var resultObj: obj.Obj = undefined;
    try HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 0, &resultObj));
    try std.testing.expectEqualSlices(u8, "e0", try obj.GetStringFromObj(resultObj));

    try HandleReturn(tcl.Tcl_ListObjIndex(interp, resultList, 1, &resultObj));
    try std.testing.expectEqualSlices(u8, "e1", try obj.GetStringFromObj(resultObj));
}

test "error set command" {
    const er = error{
        e0,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterErrorSet(er, "er", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_OK, tcl.Tcl_Eval(interp, "test::er::e0 name"));
    try std.testing.expectEqualSlices(u8, "e0", try obj.GetStringFromObj(tcl.Tcl_GetObjResult(interp)));
}

test "error set throw" {
    const er = error{
        e0,
    };
    var interp = tcl.Tcl_CreateInterp();
    defer tcl.Tcl_DeleteInterp(interp);

    var result: c_int = undefined;
    result = RegisterErrorSet(er, "er", "test", interp);
    try std.testing.expectEqual(tcl.TCL_OK, result);

    try std.testing.expectEqual(tcl.TCL_ERROR, tcl.Tcl_Eval(interp, "test::er::e0"));
    //std.debug.print("\n{s}\n", .{try obj.GetStringFromObj(tcl.Tcl_GetObjResult(interp))});
    try std.testing.expectEqualSlices(u8, "e0", try obj.GetStringFromObj(tcl.Tcl_GetObjResult(interp)));
}
