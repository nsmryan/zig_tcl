const std = @import("std");

const err = @import("err.zig");

const obj = @import("obj.zig");

const tcl = @import("tcl.zig");

pub fn CallableFunction(comptime fn_info: std.builtin.TypeInfo.Fn) bool {
    if (fn_info.is_generic) {
        return false;
    }

    if (fn_info.is_var_args) {
        return false;
    }

    return true;
}

pub fn CallableDecl(comptime typ: type, comptime fn_info: std.builtin.TypeInfo.Fn) bool {
    if (!CallableFunction(fn_info)) {
        return false;
    }

    if (fn_info.args.len > 0) {
        const first_arg = fn_info.args[0];
        if (first_arg.arg_type) |arg_type| {
            if (arg_type == typ or (@typeInfo(arg_type) == .Pointer and std.meta.Child(arg_type) == typ)) {
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }
    return false;
}

pub fn TclDeallocateCallback(cdata: tcl.ClientData) callconv(.C) void {
    tcl.Tcl_Free(@ptrCast([*c]u8, cdata));
}
