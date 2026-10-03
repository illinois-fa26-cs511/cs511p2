#!/bin/bash
# Grade the autograded parts of the project on the full dataset: cluster,
# PageRank, the search API and search engineering.
# Run `make start` first; `make test` runs this script.

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh

mkdir -p out
total=0

# Run a test script, show its output, and leave the score it printed in
# SUITE_SCORE.
SUITE_SCORE=0
function run_suite() {
    local script="$1" log="$2"
    bash "$script" 2>&1 | tee "$log"
    SUITE_SCORE=$(sed -n 's/^Result: \([0-9]\{1,\}\)\/[0-9]\{1,\} points.*/\1/p' "$log" | tail -n1)
    SUITE_SCORE="${SUITE_SCORE:-0}"
}

scores=()
for suite in test_0_cluster test_1_pagerank test_2_search test_4_attack; do
    run_suite "scripts/${suite}.sh" "out/${suite}.log"
    scores+=("$SUITE_SCORE")
    (( total += SUITE_SCORE ))
    echo
done

# --- Summary ------------------------------------------------------------------
echo "-----------------------------------"
printf "Part 0  Cluster              %3d/10\n" "${scores[0]}"
printf "Part 1  PageRank             %3d/30\n" "${scores[1]}"
printf "Part 2  Search API           %3d/20\n" "${scores[2]}"
printf "Part 4  Search engineering   %3d/10\n" "${scores[3]}"
echo "-----------------------------------"
echo "Total Test Points: ${total}/70"
echo "(The report is worth another 30 points, graded by hand; project total: 100.)"
[ "$total" -eq 70 ]
