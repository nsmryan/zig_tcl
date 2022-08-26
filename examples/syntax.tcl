# type 'create' functions should return the given name. If no name is provided, create one and return it.
# What about a way to turn into a string? These are command style, but maybe there could be a
# 'show' subcommand that uses Zig's standard print? or this is optional?

## Example usage code for structs, for a struct called 'strt'
#   with field 'a', decl 'func', and type level decl 'decl'
#
#  create a new instance
strt create s
# get a field from the struct
s cget -a

# set a field in the struct
s configure -a 9
# print out fields and values
s configure 

# call a function using the struct as the first argument
s call func 1 "test"

# call a function which does not take the struct as the first argument.
struct call decl 1 2 3

# Alternate struct field concept
# get a field value
s field a

# set a field value
s field a 5

## Example usage code for enums, for an enum called 'enm'
#  create a new enum command. if not given, use the default value
enm create e E1

#  get the value from the enum
e value

#  get the string name from the enum
e name

#  call a decl that takes the enum as the first argument
e call decl 1 2 3

#  return the value of the enum if used without argument, for convienence
puts [e]
# 
#   convert from value to name
enm name 1

#   convert from name to value
enm value E1

#  call a decl that does not take the enum as an argument
enm call decl 1


## Example usage code for unions, for a tagged union called 'unn'
#  create an instance. ideally could specify a variant and its value
unn create u un1 1.5
#
#  get the name of the current variant
u variant

#  change the variant
u variant un2 1

#  get the value of the current variant
u value

#  change the value
u value 1.5
u call decl
unn call decl


