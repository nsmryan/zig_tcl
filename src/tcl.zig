const builtin = @import("builtin");

const tcl = @cImport({
    if (builtin.os.tag != .windows) {
        @cDefine("USE_TCL_STUBS", "1");
    }
    //@cInclude("c:/tcltk/include/tcl.h");
    @cInclude("/usr/include/tcl.h");
});
usingnamespace tcl;
