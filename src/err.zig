const std = @import("std");
const testing = std.testing;

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
