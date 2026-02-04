#!/bin/bash

# Benchmark parallel map implementations with different work functions

NUM_DOMAINS=4
ARRAY_SIZE=1000000
CUTOFF=1
WARMUP=2
RUNS=5

WORK_FUNCTIONS=("fib" "prime" "poly" "trig" "hash")

echo "======================================"
echo "Parallel Map Benchmark Comparison"
echo "Domains: $NUM_DOMAINS"
echo "Array Size: $ARRAY_SIZE"
echo "Cutoff: $CUTOFF"
echo "======================================"
echo ""

for work in "${WORK_FUNCTIONS[@]}"; do
    echo "======================================"
    echo "Work Function: $work"
    echo "======================================"
    
    hyperfine \
        --warmup $WARMUP \
        --runs $RUNS \
        --export-markdown "benchmark_pmap_${work}.md" \
        "./_build/default/test/pmap.exe $work $ARRAY_SIZE" \
        "./_build/default/test/pmap_hb.exe $work $NUM_DOMAINS $ARRAY_SIZE $CUTOFF" \
        "./_build/default/test/pmap_hb_vec.exe $work $NUM_DOMAINS $ARRAY_SIZE $CUTOFF"
    
    echo ""
    echo ""
done

echo "======================================"
echo "Benchmark Complete!"
echo "Results saved to benchmark_pmap_*.md"
echo "======================================"
