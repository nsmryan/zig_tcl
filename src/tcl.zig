const tcl = @cImport({
    //@cDefine("USE_TCL_STUBS", "1");
    //@cInclude("c:/tcltk/include/tcl.h");
    @cInclude("/usr/include/tcl.h");
});
usingnamespace tcl;
