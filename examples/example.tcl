load zig-out/lib/libzigexample.so

package require zigtcl


proc runTests { } {
    zigtcl::zigcreate struct

    checkField bl 1
    checkField int 10
    checkField long 10
    checkField wide 10

    struct string hello
    set result [struct string]
    if { [string compare -length 5 $result "hello"] } { throw ZIGTCLINVALID "string '$result' did not match" } 

    set flt 1.4
    struct float $flt
    set result [struct float]
    if { abs($result - $flt) > 0.000001 } { throw ZIGTCLINVALID "float '$result' did not match" } 

    set ptr [struct]
    checkField ptr $ptr

    set value [struct enm E2]
    set result [struct enm]
    if { $value != $result } { throw ZIGTCLINVALID "enm '$result' did not match '$value'"  }

    set value 3
    set result [zigtcl::zig_function 1 2]
    if { $value != $result } { throw ZIGTCLINVALID "test function '$result' did not match '$value'"   }

    struct bl 0
    struct call decl1
    set value 1
    set result [struct get bl]
    if { $value != $result } { throw ZIGTCLINVALID "decl1 '$result' did not match '$value'"   }

    struct call decl2 100
    set value 100
    set result [struct get int]
    if { $value != $result } { throw ZIGTCLINVALID "decl2 '$result' did not match '$value'"   }

    puts "Tests Passed!"
}

proc checkField { name value } {
    struct $name $value
    set result [struct $name]
    if { $result != $value } { throw ZIGTCLINVALID "$name '$result' did not match '$value'" }
}

zigtcl::Struct create s
puts "bl [s set bl 1]"
puts "bl [s get bl]"
s call decl1
puts "!bl [s get bl]"

puts "enm [s set enm 1]"
puts "enm [s get enm]"

s set long 10
s set int 11
s set wide 12
puts "multiple [s get long int wide]"


#runTests
