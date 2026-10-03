#!/bin/bash
# Part 0: the Project 1 cluster, carried over (10 points).

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh

# Q1: containers up, commands on PATH, 3 live datanodes, NameNode reachable.
function test_cluster_q1() {
    local node
    for node in main worker1 worker2; do
        node_running "$node" || { echo "container ${node} is not running"; return 1; }
    done
    main_exec 'hdfs version' || { echo "hdfs is not on PATH on main"; return 1; }
    main_exec 'spark-submit --version' || { echo "spark-submit is not on PATH on main"; return 1; }
    main_exec 'command -v spark-shell' || { echo "spark-shell is not on PATH on main"; return 1; }
    wait_for_datanodes 3 any "${STARTUP_TIMEOUT:-600}" /dev/stdout || {
        echo "HDFS did not report 3 live DataNodes"
        return 1
    }
    main_exec 'hdfs dfs -ls /' || { echo "the namenode at hdfs://main:9000 is unreachable"; return 1; }
    echo "CLUSTER READY"
}

# Q2: the Spark context has 3 executors, on main, worker1 and worker2.
function test_cluster_q2() {
    dc cp resources/active_executors.scala main:/active_executors.scala || return 1
    dc exec -T main bash -ex -o pipefail -c '\
        cat /active_executors.scala | spark-shell --master spark://main:7077'
}

# Q3: the checkpoint directory of Part 2 exists after startup.
function test_cluster_q3() {
    main_exec 'hdfs dfs -test -d /spark/checkpoints && echo "CHECKPOINT DIR READY"'
}

function grade_cluster() {
    local n="$1"
    local out="out/test_0_cluster_q${n}.out"
    echo -n "Testing cluster Q${n} ..."
    "test_cluster_q${n}" > "$out" 2>&1 || return 1
    case "$n" in
        1) grep -q '^CLUSTER READY$' "$out" ;;
        2) grep -q '^ACTIVE EXECUTORS: 3$' "$out" ;;
        3) grep -q '^CHECKPOINT DIR READY$' "$out" ;;
    esac
}

mkdir -p out
score=0
points=(0 4 4 2)

for q in 1 2 3; do
    if grade_cluster "$q"; then
        pass
        (( score += points[q] ))
    else
        fail
        echo "  see out/test_0_cluster_q${q}.out" >&2
    fi
done

print_score "${score}/10 points"
[ "$score" -eq 10 ]
