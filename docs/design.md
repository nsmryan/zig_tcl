
## Pointers and Allocation

There are some unresolved design issues around pointers and allocation.

First, should pointers be provided to TCL as integers? This is generally
considered a bad idea, but it is easy and fast.

Second, should complex types be passed back and forth as pointers, or
should they be byte arrays? Or perhaps a custom type?

Pointers are fast, but unsafe.
Byte Arrays are safer, but require copying.
A custom type would be a little more complex, but might allow a Zig allocator to be used.


## Errors

Consider making TclError reflect specific error situations.
Translate all of them into TCL_ERROR, but ideally append to result a string name before returning.


## Syntax

See syntax.tcl for the concept of TCL syntax to use.

## Conveniences

Consider some additional struct options:

```tcl
# To get size
structType size
structName size

# to get byte buffer
structName bytes

# to create from byte buffer
structType fromBytes name bytes 

# to get all fields and values
structName configure

# to get/configure more idiomatically
structName cget -field0 -field 1
structName configure -field0 10 -field1 200

# to list fields and their types - name type pairs
structType fields
```

## Zig Thoughts

### Zig Compared to C for TCL Extensions

The enum trick with std.meta.fieldNames is quite nice. This is much better
then what I do in C with an array of names and an enum.

### Comptime

I ran into some situations where comptime is somewhat limited. Inline loops can be required
when simpler code like 'std.meta.declarations' creates a runtime value.
I was not able to factor out some repeated code because it needed to expand correctly at comptime-
if the factored out code returned a comptime value it would be okay, but instead I needed
to determine something at runtime.

