const builtin = @import("builtin");

pub usingnamespace @cImport({
    if (builtin.os.tag != .windows) {
        @cDefine("USE_TCL_STUBS", "1");
    }
    //@cInclude("c:/tcltk/include/tcl.h");
    @cInclude("tcl.h");
});
