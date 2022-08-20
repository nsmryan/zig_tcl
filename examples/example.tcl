load zig-out/lib/libzigexample.so

zigcreate struct

struct int 10
set result [struct int]
if { $result != 10 } { throw ZIGTCLINVALID "int '$result' did not match" }

struct string hello
set result [struct string]
if { [string compare -length 5 $result "hello"] } { throw ZIGTCLINVALID "string '$result' did not match" } 

set flt 1.4
struct float $flt
set result [struct float]
if { abs($result - $flt) > 0.000001 } { throw ZIGTCLINVALID "float '$result' did not match" } 

puts "Tests Passed!"
