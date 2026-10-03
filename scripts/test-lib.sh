#!/bin/bash
# Helpers shared by start-all.sh, stop-all.sh and the test_*.sh scripts.
# Source this file, do not execute it.

COMPOSE_FILE="${COMPOSE_FILE:-scripts/cs511p2-compose.yaml}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Compose V2 (`docker compose`) is the default on Ubuntu 22.04; fall back to the
# standalone V1 binary (`docker-compose`) when that is what is installed.
if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose -f "$COMPOSE_FILE")
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose -f "$COMPOSE_FILE")
else
    echo "ERROR: neither 'docker compose' nor 'docker-compose' is available." >&2
    exit 1
fi

# dc <compose args ...>
function dc() {
    "${COMPOSE[@]}" "$@"
}

# node_exec <node> <bash command ...>: run a command on a node. -T is required
# because the test scripts do not run on a terminal.
function node_exec() {
    local node="$1"
    shift
    dc exec -T "$node" bash -c "$*"
}

# main_exec <bash command ...>
function main_exec() {
    node_exec main "$@"
}

function pass() { echo -e " ${GREEN}PASS${NC}"; }
function fail() { echo -e " ${RED}FAIL${NC}"; }
function skip() { echo -e " ${YELLOW}SKIP${NC}"; }

function print_score() {
    echo "-----------------------------------"
    echo "Result: $*"
}

# node_running <node>: true when the container is up.
function node_running() {
    [ -n "$(dc ps -q "$1" 2>/dev/null)" ] && \
        dc ps "$1" 2>/dev/null | grep -Eq 'Up|running'
}

# hdfs_report: dump `hdfs dfsadmin -report` (empty when HDFS is unreachable).
function hdfs_report() {
    main_exec 'hdfs dfsadmin -report' 2>/dev/null
}

# datanode_count <live|dead> [report file]: number reported by the NameNode.
function datanode_count() {
    local kind="$1" report="${2:-}" count temporary=false
    if [ -z "$report" ]; then
        report="$(mktemp)"
        temporary=true
        hdfs_report > "$report"
    fi
    case "$kind" in
        live) count=$(sed -n 's/^Live datanodes (\([0-9]\+\)).*/\1/p' "$report" | head -n1) ;;
        dead) count=$(sed -n 's/^Dead datanodes (\([0-9]\+\)).*/\1/p' "$report" | head -n1) ;;
    esac
    [ "$temporary" = false ] || rm -f "$report"
    echo "${count:-0}"
}

# wait_for_datanodes <live count> <dead count|any> <timeout seconds> [log file]
function wait_for_datanodes() {
    local want_live="$1" want_dead="$2" timeout="$3" log="${4:-/dev/null}"
    local deadline=$((SECONDS + timeout)) report live dead
    report="$(mktemp)"
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ! hdfs_report > "$report" 2>&1; then
            sleep 5
            continue
        fi
        live=$(datanode_count live "$report")
        dead=$(datanode_count dead "$report")
        {
            echo "[$(date +%T)] live=${live} dead=${dead} (want live=${want_live} dead=${want_dead})"
        } >> "$log"
        if [ "$live" = "$want_live" ] && { [ "$want_dead" = "any" ] || [ "$dead" = "$want_dead" ]; }; then
            cat "$report" >> "$log"
            rm -f "$report"
            return 0
        fi
        sleep 5
    done
    cat "$report" >> "$log"
    rm -f "$report"
    return 1
}

# hdfs_uri_ok <uri>: true for a normalized path below hdfs://main:9000/.
function hdfs_uri_ok() {
    case "$1" in hdfs://main:9000/?*) ;; *) return 1 ;; esac
    case "/${1#hdfs://main:9000/}/" in
        *'/../'*|*'/./'*|*'//'*) return 1 ;;
    esac
}

# upload <local file> <hdfs uri>: copy a host file into HDFS through main.
function upload() {
    local name
    name="/upload-$(basename "$1")"
    dc cp "$1" "main:${name}" || return 1
    main_exec "hdfs dfs -mkdir -p '$(dirname "$2")' && hdfs dfs -put -f '${name}' '$2'"
}

# fetch <hdfs directory uri> <local file>: concatenate its part files, drop
# blank lines and carriage returns. Errors go to stderr.
function fetch() {
    main_exec "hdfs dfs -cat '$1/part-*'" > "$2.raw" || { rm -f "$2.raw"; return 1; }
    sed -e 's/\r$//' -e '/^[[:space:]]*$/d' "$2.raw" > "$2"
    rm -f "$2.raw"
}

FULL_INPUT_URI="hdfs://main:9000/wiki/full/input"

# use_dataset <sample|full>: set DATASET, TRUTH (truth directory), INPUT_URI
# and WORK_URI (where outputs go), and make sure the input is in HDFS.
function use_dataset() {
    DATASET="${1:-full}"
    case "$DATASET" in
        sample)
            TRUTH=resources/sample
            INPUT_URI="hdfs://main:9000/wiki/sample/articles.jsonl"
            WORK_URI="hdfs://main:9000/wiki/sample"
            upload resources/sample/articles.jsonl "$INPUT_URI" > /dev/null 2>&1 || {
                echo "could not upload the sample to ${INPUT_URI}; is the cluster running?" >&2
                exit 1
            } ;;
        full)
            TRUTH=resources/full
            INPUT_URI="$FULL_INPUT_URI"
            WORK_URI="hdfs://main:9000/wiki/full"
            bash scripts/get-full-data.sh || exit 1 ;;
        *)
            echo "unknown dataset '${DATASET}': use sample or full" >&2
            exit 2 ;;
    esac
    OUT="out/${DATASET}"
    mkdir -p "$OUT"
}

# truth_file <name>: path of a truth file of the current dataset, decompressed
# into out/ when it is stored as <name>.zst.
function truth_file() {
    if [ -f "${TRUTH}/$1.zst" ]; then
        zstd -dcqf "${TRUTH}/$1.zst" -o "${OUT}/$1" && echo "${OUT}/$1"
    else
        echo "${TRUTH}/$1"
    fi
}

# report_score <score> <points>: the last line of every part's test. Only the
# full dataset is graded; the sample is a quick, ungraded check.
function report_score() {
    if [ "$DATASET" = full ]; then
        print_score "$1/$2 points"
    else
        print_score "$1/$2 on the sample (ungraded: run 'make test' for the graded full dataset)"
    fi
}

# PageRank on the full dataset takes a few minutes; this is a generous limit.
APP_TIMEOUT="${APP_TIMEOUT:-3600}"

# with_timeout <command ...>: GNU timeout when available. Stopping
# `docker compose exec` does not stop the application inside main, so a run
# that times out also has its Spark driver killed there.
function with_timeout() {
    local status
    if ! command -v timeout >/dev/null 2>&1; then
        "$@"
        return
    fi
    timeout "$APP_TIMEOUT" "$@"
    status=$?
    if [ "$status" -eq 124 ]; then
        echo "timed out after ${APP_TIMEOUT}s" >&2
        main_exec "pkill -f '[o]rg.apache.spark.deploy.SparkSubmit'" >/dev/null 2>&1
    fi
    return "$status"
}
