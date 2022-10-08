const std = @import("std");
const Allocator = std.mem.Allocator;

const tcl = @import("tcl.zig");

pub const tcl_allocator = Allocator{
    .ptr = undefined,
    .vtable = &tcl_allocator_vtable,
};
const tcl_allocator_vtable = Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .free = free,
};

fn alloc(_: *anyopaque, len: usize, ptr_align: u29, len_align: u29, ra: usize) error{OutOfMemory}![]u8 {
    _ = len_align;
    _ = ra;

    const adjusted_len = len + ptr_align;
    var ptr = tcl.Tcl_AttemptAlloc(@intCast(c_uint, adjusted_len));
    if (ptr == null) {
        return error.OutOfMemory;
    } else {
        const adjusted_ptr_loc = std.mem.alignForward(@ptrToInt(ptr), ptr_align);
        const adjusted_ptr = @intToPtr([*]u8, adjusted_ptr_loc);

        return adjusted_ptr[0..len];
    }
}

fn resize(_: *anyopaque, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ra: usize) ?usize {
    _ = buf;
    _ = buf_align;
    _ = len_align;
    _ = ra;
    if (new_len > buf.len) {
        return null;
    }
    return new_len;
}

fn free(_: *anyopaque, buf: []u8, buf_align: u29, ret_addr: usize) void {
    _ = buf_align;
    _ = ret_addr;
    tcl.Tcl_Free(buf.ptr);
}

test "tcl allocator" {
    const ptr = try tcl_allocator.create(u8);
    tcl_allocator.destroy(ptr);
}
