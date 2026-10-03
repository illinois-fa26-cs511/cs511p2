#!/bin/bash
# Part 1: the link graph and PageRank (30 points).
#
#   bash scripts/test_1_pagerank.sh [full|sample]
#
# `full` (the default) is graded; `sample` is a quick check on the small sample.

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh
use_dataset "$1"

OUTPUT_URI="${WORK_URI}/test-pagerank"
RUN_LOG="${OUT}/test_1_pagerank.out"
RANKS="${OUT}/ranks.txt"
score=0

echo -n "Running PageRank (${DATASET}) ..."
started=$SECONDS
if with_timeout bash scripts/run-pagerank.sh "$INPUT_URI" "$OUTPUT_URI" > "$RUN_LOG" 2>&1; then
    pass
    echo "  finished in $((SECONDS - started))s"
    ran=true
else
    fail
    echo "  the application failed; see ${RUN_LOG} (the graph may still be graded)" >&2
    ran=false
fi

# pagerank.py writes graph/ before it iterates, so the graph is graded even
# when the PageRank iteration fails.
echo -n "Testing graph records ..."
if [ "$DATASET" = sample ]; then
    fetch "${OUTPUT_URI}/graph" "${OUT}/graph.txt" 2>> "$RUN_LOG" && \
        diff --strip-trailing-cr "$(truth_file graph.truth)" "${OUT}/graph.txt" \
            > "${OUT}/graph.diff" 2>&1
else
    # The full graph is too large to keep as a truth file: compare digests.
    main_exec "hdfs dfs -cat '${OUTPUT_URI}/graph/part-*' | sha256sum | cut -d' ' -f1" \
        > "${OUT}/graph.sha256" 2>> "$RUN_LOG" && \
        diff "$(truth_file graph.sha256)" "${OUT}/graph.sha256" > "${OUT}/graph.diff" 2>&1
fi
if [ "$?" -eq 0 ]; then
    pass
    (( score += 5 ))
else
    fail
    echo "  see ${OUT}/graph.diff; 'make check-pagerank' shows the differing records" \
         "on the sample" >&2
fi

echo -n "Testing graph statistics ..."
grep -E '^GRAPH (NODES|EDGES|DANGLING): ' "$RUN_LOG" > "${OUT}/stats.txt"
if diff --strip-trailing-cr "$(truth_file stats.truth)" "${OUT}/stats.txt" \
        > "${OUT}/stats.diff" 2>&1; then
    pass
    (( score += 5 ))
else
    fail
    echo "  see ${OUT}/stats.diff (expected vs. printed statistics)" >&2
fi

truth="$(truth_file ranks.truth)"
if [ "$ran" = true ] && fetch "${OUTPUT_URI}/ranks" "$RANKS" 2>> "$RUN_LOG" && [ -s "$RANKS" ]; then
    echo -n "Testing rank values ..."
    if python3 resources/compare-ranks.py ranks "$truth" "$RANKS" --part values \
            > "${OUT}/ranks-values.diff" 2>&1; then
        pass
        (( score += 10 ))
    else
        fail
        echo "  see ${OUT}/ranks-values.diff" >&2
    fi

    echo -n "Testing rank order and normalization ..."
    if python3 resources/compare-ranks.py ranks "$truth" "$RANKS" --part order \
            > "${OUT}/ranks-order.diff" 2>&1; then
        pass
        (( score += 5 ))
    else
        fail
        echo "  see ${OUT}/ranks-order.diff" >&2
    fi

    # The iteration count may differ by one from the truth: the last delta is
    # close to EPSILON, where floating-point rounding can decide either way.
    echo -n "Testing convergence ..."
    expected=$(cat "$(truth_file iterations.truth)")
    printed=$(sed -n 's/^PAGERANK ITERATIONS: \([0-9]\{1,\}\)$/\1/p' "$RUN_LOG" | tail -n1)
    fetch "${OUTPUT_URI}/convergence" "${OUT}/convergence.txt" 2>> "$RUN_LOG"
    logged=$(wc -l < "${OUT}/convergence.txt" 2>/dev/null | tr -d ' ')
    {
        echo "expected iterations: ${expected} (+/- 1)"
        echo "printed PAGERANK ITERATIONS: ${printed:-none}"
        echo "lines in convergence/: ${logged:-none}"
    } > "${OUT}/convergence.diff"
    if [ -n "$printed" ] && [ "$printed" = "$logged" ] && \
       [ "$printed" -ge $((expected - 1)) ] && [ "$printed" -le $((expected + 1)) ]; then
        pass
        (( score += 5 ))
    else
        fail
        echo "  see ${OUT}/convergence.diff" >&2
    fi
fi

report_score "$score" 30
[ "$score" -eq 30 ]
