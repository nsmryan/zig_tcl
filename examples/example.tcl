load zig-out/lib/libzigexample.so

package require zigtcl
namespace import zigtcl::*



proc checkField { name value } {
    struct $name $value
    set result [struct $name]
    if { $result != $value } { throw ZIGTCLINVALID "$name '$result' did not match '$value'" }
}

Struct create s
puts "bl [s set bl 1]"
puts "bl [s get bl]"
s call decl1
puts "!bl [s get bl]"

set ptr [s ptr]
Struct with $ptr set bl 0
puts "[s get bl] == 0"
Struct with $ptr set bl 1
puts "[s get bl] == 1"

s set slice "world"
puts "s get slice [s get slice] == 'world'"

s set nested [binary decode hex 01234567AB]
puts [binary encode hex [s get nested]]

puts "enm [s set enm 1]"
puts "enm [s get enm]"

s set long 10
s set int 11
s set wide 12
puts "multiple [s get long int wide]"


puts "E1 value [Enum value E1]"
puts [namespace children zigtcl]
puts "E1 value [zigtcl::Enum::E1 name]"

