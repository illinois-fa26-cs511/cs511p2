#!/bin/bash
# Part 4: search engineering tests (10 points).
#
#   bash scripts/test_4_attack.sh [full|check]
#
# Adds the pages of attack.jsonl to the full dataset, runs your pagerank.py on
# it, and measures the PageRank position of the target page (1 = highest).
# `check` only validates attack.jsonl.

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh

MODE="${1:-full}"
ATTACK=attack.jsonl
TRUTH_FILE=resources/full/attack.truth
truth_value() { sed -n "s/^$1\t//p" "$TRUTH_FILE"; }
TARGET=$(truth_value target)
BUDGET=$(truth_value budget)
BASE=$(truth_value base)
BASELINE=$(truth_value baseline)
OPTIMAL=$(truth_value optimal)
mkdir -p out/full

echo -n "Validating ${ATTACK} (at most ${BUDGET} pages, ids ${BASE}..$((BASE + BUDGET - 1))) ..."
if python3 - "$ATTACK" "$BUDGET" "$BASE" > out/full/attack-check.out 2>&1 <<'PY'
import json, sys
path, budget, base = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
lines = [line for line in open(path) if line.strip()]
assert 0 < len(lines) <= budget, "%d pages; between 1 and %d allowed" % (len(lines), budget)
ids = set()
for number, line in enumerate(lines, 1):
    page = json.loads(line)
    assert isinstance(page, dict), "line %d is not a JSON object" % number
    pid = page.get("id")
    assert isinstance(pid, int) and not isinstance(pid, bool), "line %d: id must be an integer" % number
    assert base <= pid < base + budget, "line %d: id %d outside %d..%d" % (number, pid, base, base + budget - 1)
    assert pid not in ids, "line %d: duplicate id %d" % (number, pid)
    ids.add(pid)
    links = page.get("links", [])
    assert isinstance(links, list) and all(isinstance(t, int) and not isinstance(t, bool)
                                           for t in links), "line %d: links must be integers" % number
    for key in ("title", "text"):
        assert isinstance(page.get(key, ""), str), "line %d: %s must be a string" % (number, key)
    assert len(line) <= 10000, "line %d is longer than 10000 characters" % number
print("ATTACK FILE OK: %d pages" % len(lines))
PY
then
    pass
else
    fail
    sed 's/^/  /' out/full/attack-check.out | tail -n 3 >&2
    [ "$MODE" = check ] && exit 1
    print_score "0/10 points"
    exit 1
fi
if [ "$MODE" = check ]; then
    echo "  (the graded run adds these pages to the full dataset: make test-attack)"
    exit 0
fi

use_dataset full
ATTACK_URI="${WORK_URI}/attack/input"
OUTPUT_URI="${WORK_URI}/test-attack"
RUN_LOG="${OUT}/test_4_attack.out"

echo -n "Running PageRank with your pages added ..."
if main_exec "hdfs dfs -rm -r -f '${ATTACK_URI}' && hdfs dfs -mkdir -p '${ATTACK_URI}' && \
              hdfs dfs -cp '${INPUT_URI}/*.jsonl' '${ATTACK_URI}/'" > "$RUN_LOG" 2>&1 && \
   upload "$ATTACK" "${ATTACK_URI}/attack.jsonl" >> "$RUN_LOG" 2>&1 && \
   with_timeout bash scripts/run-pagerank.sh "$ATTACK_URI" "$OUTPUT_URI" >> "$RUN_LOG" 2>&1 && \
   fetch "${OUTPUT_URI}/ranks" "${OUT}/attack-ranks.txt" 2>> "$RUN_LOG"; then
    pass
else
    fail
    echo "  see ${RUN_LOG}" >&2
    print_score "0/10 points"
    exit 1
fi

# Position = 1 + the pages with a clearly higher rank (relative margin 1e-6).
position=$(python3 - "${OUT}/attack-ranks.txt" "$TARGET" <<'PY'
import sys
ranks = {}
for line in open(sys.argv[1]):
    if line.strip():
        page, rank = line.split("\t")
        ranks[int(page)] = float(rank)
target = ranks.get(int(sys.argv[2]))
print(-1 if target is None else 1 + sum(1 for r in ranks.values() if r > target * (1 + 1e-6)))
PY
)
full_marks=$(( OPTIMAL + OPTIMAL / 100 ))
echo "Target ${TARGET}: position ${position} (without your pages: ${BASELINE};" \
     "full points at <= ${full_marks})"
echo -n "Testing the target's new position ..."
if [ "$position" -gt 0 ] && [ "$position" -le "$full_marks" ]; then
    pass
    score=10
elif [ "$position" -gt 0 ] && [ "$position" -le $(( BASELINE - BASELINE / 100 )) ]; then
    fail
    echo "  improved, but not by as much as possible: 5/10 points"
    score=5
else
    fail
    score=0
fi
print_score "${score}/10 points"
[ "$score" -eq 10 ]
