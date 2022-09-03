const std = @import("std");

const err = @import("err.zig");

const obj = @import("obj.zig");

const tcl = @import("tcl.zig");

pub fn CallableFunction(comptime fn_info: std.builtin.TypeInfo.Fn, interp: obj.Interp) err.TclError!void {
    if (fn_info.is_generic) {
        obj.SetStrResult(interp, "Cannot call generic function!");
        return err.TclError.TCL_ERROR;
    }

    if (fn_info.is_var_args) {
        obj.SetStrResult(interp, "Cannot call var args function!");
        return err.TclError.TCL_ERROR;
    }
}

pub fn CallableDecl(comptime typ: type, comptime fn_info: std.builtin.TypeInfo.Fn, interp: obj.Interp) err.TclError!void {
    try CallableFunction(fn_info, interp);

    const first_arg = fn_info.args[0];
    if (first_arg.arg_type) |arg_type| {
        if (arg_type == typ or (@typeInfo(arg_type) == .Pointer and std.meta.Child(arg_type) == typ)) {
            return;
        } else {
            obj.SetStrResult(interp, "Decl does not take a pointer to the struct as its first argument!");
            return err.TclError.TCL_ERROR;
        }
    } else {
        obj.SetStrResult(interp, "Function does not have a first argument!");
        return err.TclError.TCL_ERROR;
    }
}
