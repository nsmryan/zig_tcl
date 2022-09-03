const std = @import("std");

const err = @import("err.zig");

const obj = @import("obj.zig");

const tcl = @import("tcl.zig");

pub fn CallableFunction(comptime fn_info: std.builtin.TypeInfo.Fn, interp: obj.Interp) bool {
    if (fn_info.is_generic) {
        obj.SetStrResult(interp, "Cannot call generic function!");
        return false;
    }

    if (fn_info.is_var_args) {
        obj.SetStrResult(interp, "Cannot call var args function!");
        return false;
    }

    return true;
}
