#!/bin/bash
dune build
for i in {1..5}
do
    echo "Running test iteration $i"
    rr-record ./_build/default/test/test_hb_simple.exe
    #./_build/default/test/test_hb_simple.exe
done