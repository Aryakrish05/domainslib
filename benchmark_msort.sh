#!/bin/bash

# Benchmark merge sort implementations

NUM_DOMAINS=4
ARRAY_SIZE=1000000
CUTOFF=10
WARMUP=2
RUNS=5

echo "======================================"
echo "Merge Sort Benchmark Comparison"
echo "Domains: $NUM_DOMAINS"
echo "Array Size: $ARRAY_SIZE"
echo "Cutoff: $CUTOFF"
echo "======================================"
echo ""

hyperfine \
    --warmup $WARMUP \
    --runs $RUNS \
    --export-markdown "benchmark_msort.md" \
    "./_build/default/test/msort.exe $ARRAY_SIZE" \
    "./_build/default/test/msort_hb.exe $NUM_DOMAINS $ARRAY_SIZE $CUTOFF" \
    "./_build/default/test/msort_hb_vec.exe $NUM_DOMAINS $ARRAY_SIZE $CUTOFF"

echo ""
echo "======================================"
echo "Benchmark Complete!"
echo "Results saved to benchmark_msort.md"
echo "======================================"
