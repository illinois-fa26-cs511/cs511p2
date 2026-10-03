#!/bin/bash
# Part 2: the search API tests (20 points).
#
#   bash scripts/test_2_search.sh [full|sample]
#
# `full` (the default) is graded; `sample` is a quick check on the small sample.
# The index is built from the truth ranks, so that a mistake in Part 1 does
# not cost points here.

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh
use_dataset "$1"

RANKS_URI="${WORK_URI}/search-ranks"
RUN_LOG="${OUT}/test_2_search.out"
RESULTS="${OUT}/search.txt"
LATENCY_LIMIT_MS=200
score=0

echo -n "Building the index and starting the API (${DATASET}) ..."
started=$SECONDS
if upload "$(truth_file ranks.truth)" "${RANKS_URI}/part-00000" > "$RUN_LOG" 2>&1 && \
   with_timeout bash scripts/run-serve.sh "$INPUT_URI" "$RANKS_URI" >> "$RUN_LOG" 2>&1; then
    pass
    echo "  ready in $((SECONDS - started))s"
else
    fail
    echo "  the API did not start; see ${RUN_LOG}" >&2
    report_score 0 20
    exit 1
fi

echo -n "Querying the API ..."
python3 resources/query-api.py "${TRUTH}/queries.txt" "$RESULTS" > "${OUT}/latency.txt" 2>&1
python3 resources/compare-ranks.py search "$(truth_file search.truth)" "$RESULTS" \
    > "${OUT}/search.diff" 2>&1
passed=$(sed -n 's/^QUERIES PASSED: \([0-9]*\)\/\([0-9]*\)$/\1 \2/p' "${OUT}/search.diff")
read -r ok total <<< "${passed:-0 1}"
# The full dataset has 15 queries, worth one point each. Normalize the
# smaller, ungraded sample to the same point total for feedback.
points=$(( 15 * ok / total ))
if [ "$ok" -eq "$total" ]; then pass; else fail; fi
echo "  ${ok}/${total} queries correct: ${points}/15 points"
[ "$ok" -eq "$total" ] || echo "  see ${OUT}/search.diff" >&2
(( score += points ))

echo -n "Testing latency (p95 <= ${LATENCY_LIMIT_MS} ms) ..."
p95=$(sed -n 's/^LATENCY: .*p95 \([0-9.]*\) ms.*/\1/p' "${OUT}/latency.txt")
if [ -n "$p95" ] && [ "$ok" -gt 0 ] && \
   python3 -c "import sys; sys.exit(0 if float('$p95') <= $LATENCY_LIMIT_MS else 1)"; then
    pass
    (( score += 5 ))
else
    fail
fi
echo "  $(grep '^LATENCY' "${OUT}/latency.txt" || echo 'no latency measured')"

report_score "$score" 20
[ "$score" -eq 20 ]
