#!/bin/bash
# SimpleScript Build Script — fully self-hosted, no Rust needed
# Usage: ./build.sh          — build compiler from seed
#        ./build.sh bootstrap — rebuild compiler using itself (self-bootstrap)

set -e

SEED="bin/ss"
OUT="bin/ss"

if [ "$1" == "bootstrap" ]; then
    echo "=== Self-bootstrap ==="
    echo "Stage 1: seed → stage1"
    $SEED bootstrap/main.ss -o /tmp/ss_stage1
    echo "Stage 2: stage1 → stage2"
    /tmp/ss_stage1 bootstrap/main.ss -o /tmp/ss_stage2
    echo "Stage 3: stage2 → stage3 (verify fixed point)"
    /tmp/ss_stage2 bootstrap/main.ss -o /tmp/ss_stage3
    if diff <(xxd /tmp/ss_stage2) <(xxd /tmp/ss_stage3) > /dev/null 2>&1; then
        echo "Fixed point verified! Stage 2 = Stage 3"
        cp /tmp/ss_stage2 $OUT
        echo "Updated $OUT"
    else
        echo "ERROR: fixed point not reached!"
        exit 1
    fi
else
    echo "=== Building SimpleScript compiler ==="
    $SEED bootstrap/main.ss -o $OUT
    echo "Built: $OUT"
fi

echo ""
echo "Usage:"
echo "  bin/ss build file.ss -o output    # compile"
echo "  bin/ss run file.ss                # compile and run (not yet)"
echo "  ./build.sh bootstrap              # self-bootstrap"
