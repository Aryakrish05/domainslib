#!/bin/bash
# Loop rr record runs until crash or timeout (>10s), save output and trace
dune build
ITER=0
CRASHED=0
TRACE_DIR=""

echo "Running with rr record until failure..."
while [ $CRASHED -eq 0 ]; do
    ITER=$((ITER + 1))
    
    # Run with rr record and timeout (10s)taskset -c 0-3 rr record
    RR_OUTPUT=$(timeout 10s ./_build/default/test/test_hb_simple.exe 4 30 2>&1)
    EXIT_CODE=$?
    
    # Get the latest trace directory
    TRACE_DIR=$(ls -td ~/.local/share/rr/*/ 2>/dev/null | head -1)
    
    printf "Iteration %d [%s]... " $ITER "$TRACE_DIR"
    
    # Save output
    echo "$RR_OUTPUT" > /tmp/hb_output_$ITER.txt
    
    # Try to extract trace directory from rr output (update if new one was created)
    if echo "$RR_OUTPUT" | grep -q "rr:"; then
        TRACE_DIR=$(ls -td ~/.local/share/rr/*/ 2>/dev/null | head -1)
    fi
    
    # Check exit codes:
    # 0 = success
    # 124 = timeout killed it  
    # other = crash/error
    if [ $EXIT_CODE -ne 0 ]; then
        if [ $EXIT_CODE -eq 124 ]; then
            echo "TIMEOUT"
        else
            echo "CRASH (exit $EXIT_CODE)"
        fi
        CRASHED=1
    else
        echo "ok"
    fi
done

echo ""
echo "========================================"
echo "Failed at iteration: $ITER"
echo "Exit code: $EXIT_CODE"
echo "Output file: /tmp/hb_output_$ITER.txt"
if [ -n "$TRACE_DIR" ]; then
    echo "RR trace directory: $TRACE_DIR"
fi
echo "========================================"
echo ""
echo "Output from failed run:"
cat /tmp/hb_output_$ITER.txt
echo ""

if [ -n "$TRACE_DIR" ]; then
    echo "To replay the recorded trace:"
    echo "  rr replay $TRACE_DIR"
    echo "  or just: rr replay"
fi
