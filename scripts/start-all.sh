#!/bin/bash
# Build and start the three containers for Part 0 and the grading workflow.
# Wait for their SSH services, not the HDFS/Spark services students implement.
# `make test` waits for HDFS readiness before grading a completed submission.

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh

# Retain the old optional spelling; `make start` is the handout command.
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--containers-only" ]; }; then
    echo "usage: bash scripts/start-all.sh [--containers-only]" >&2
    exit 2
fi

SSH_STARTUP_TIMEOUT="${SSH_STARTUP_TIMEOUT:-60}"

docker build -t cs511p2-common -f cs511p2-common.Dockerfile . || exit 1
docker build -t cs511p2-main -f cs511p2-main.Dockerfile . || exit 1
docker build -t cs511p2-worker -f cs511p2-worker.Dockerfile . || exit 1

dc up -d || exit 1
mkdir -p out
for node in main worker1 worker2; do
    deadline=$((SECONDS + SSH_STARTUP_TIMEOUT))
    until node_exec "$node" '/etc/init.d/ssh status' > "out/start-${node}.log" 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "SSH on ${node} did not start; see out/start-${node}.log and container logs." >&2
            exit 1
        fi
        sleep 1
    done
done

echo "Containers started. Run the handout commands from the host repository root ('make' lists them)."
echo "After porting your cluster and completing the parts, run 'make check' or 'make test'."
echo "Run 'make stop' to remove the cluster."
