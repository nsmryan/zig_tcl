const std = @import("std");
const testing = std.testing;

pub const err = @import("err.zig");
usingnamespace err;

pub const obj = @import("obj.zig");
usingnamespace obj;

pub const tcl = @import("tcl.zig");
usingnamespace tcl;

// NOTES
// create a command that is given a string name, and cdata is a pointer to an allocator,
// and creates a command of that name. The new command's cdata is a pointer to a struct and an allocator.
// its destroy function deallocates it, and perhaps the allocation containing the struct pointer and allocator.
// CData(T) = *T x Allocator. Maybe general purpose allocate this.
// or
// CData(T) = T x Allocator. The allocator's memory contains an allocator structure to use for dellocation.
//
// Consider adding another parameter to the CData- a pointer to the implementing function. All commands would use the same handler,
// which would pass arguments to the implementing function and handle error returns. If an error, turn to c_int and return, otherwise
// return TCL_OK. In this design, wrap used TCL C API functions in trivial ziggy versions that return error codes.
//
// Consider a global map from pointers to allocator used in destructors to deallocate instead of putting allocators into memory
// with the struct, which seems problematic for generic types without more pointers.
//
// Possible goals:
// Struct manager command using heavy comptime- given a type and allocator, allocate type and store allocator,
// try to fill in struct fields, register a destructor, and a command that comptime calls into decls of the struct, if possible.
//
// Interface- user defines their own init function and provides an allocator for smuggling things in. They can use another
// allocator for their structs.
// They can define wrapped commands, and define struct wrappers for passing calls on to decls.
// Maybe a wrapper for a pointer that just passes the cdata to the given function as well.

// TCL Allocator
// Need to figure out allocators and how to wrap TCL's
//pub fn TclAlloc(ptr: *u0, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Error![]u8 {
//    return tcl.Tcl_Alloc(len);
//}
//
//pub fn TclResize(ptr: *u0, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) ?usize {
//}
//
//pub fn TclFree(ptr: *u0, buf: []u8, buf_align: u29, ret_addr: usize) void {
//}
//
//pub fn TclAllocator() std.mem.Allocator {
//    return std.mem.Allocator.init(null, TclAlloc, TclResize, TclFree);
//}

// NOTE there seem to be two possible designs here:
// 1) try to pass a function at comptime, creating a function which calls this function, as a kind
//   of comptime closure
// 2) try to create a struct which has the user function as an argument. Allocate this struct,
// either with tcl or a given allocator, and use it as cdata.
//
// The first is likely preferable as it does not require allocation, and the comptime restriction doesn't
// seem all that bad for an extension, but I'm not positive.
//
// This implements the comptime wrapper concept.
pub fn WrapFunction(comptime function: anytype, name: [*:0]const u8, outer_interp: obj.Interp) err.TclError!void {
    const cmd = struct {
        pub fn cmd(cdata: tcl.ClientData, interp: obj.Interp, objv: []const [*c]tcl.Tcl_Obj) err.TclError!void {
            _ = cdata;
            var args: std.meta.ArgsTuple(@TypeOf(function)) = undefined;

            if ((args.len + 1) != objv.len) {
                return err.TclError.TCL_ERROR;
            }

            comptime var index = 0;
            inline while (index < args.len) : (index += 1) {
                args[index] = try obj.GetFromObj(@TypeOf(args[index]), interp, objv[index + 1]);
            }

            obj.SetObjResult(interp, try obj.NewObj(@call(.{}, function, args)));
        }
    }.cmd;
    _ = obj.CreateObjCommand(outer_interp, name, cmd);
}

test "function tuples" {
    const func = struct {
        fn testIntFunction(first: u8, second: u16) u32 {
            return (first + second);
        }
    }.testIntFunction;

    var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;

    comptime var index = 0;
    inline while (index < args.len) : (index += 1) {
        args[index] = std.mem.zeroes(@TypeOf(args[index]));
    }
    _ = @call(.{}, func, args);
}
