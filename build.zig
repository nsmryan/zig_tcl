const std = @import("std");
const Version = @import("std").builtin.Version;
const builtin = @import("builtin");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("zigexample", "examples/example.zig", b.version(0, 1, 0));
    lib.setBuildMode(mode);
    lib.linkLibC();

    const main_tests = b.addTest("src/zigtcl.zig");
    main_tests.setBuildMode(mode);
    main_tests.linkLibC();

    if (builtin.os.tag == .windows) {
        lib.addLibPath("c:/tcltk/bin");
        lib.addLibPath("c:/tcltk/lib");
        lib.addIncludeDir("c:/tcltk/include");

        // Stubs does not work- can't seem to get Zig to pick up the .a archive file.
        // TODO try with addObjectFile directly and include this file in build.
        // Building with zig itself also doesn't work- some issue with 'zig cc'
        // Building with MagicSplat's tclstub86.lib file also doesn't work.
        //lib.linkSystemLibraryName("tclstub86");
        lib.linkSystemLibraryName("tcl86");
    } else {
        lib.addIncludeDir("include");
        // On Linux build with stubs.
        //lib.linkSystemLibraryName("tcl8.6");
        //lib.linkSystemLibraryName("tclstub8.6");
        lib.addObjectFile("lib/libtclstub8.6.a");

        // The tests link TCL directly, as we are not building an extension.
        main_tests.addIncludeDir("/usr/include");
        main_tests.linkSystemLibraryName("tcl8.6");
    }
    lib.addPackagePath("zigtcl", "src/zigtcl.zig");

    lib.install();

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
