#!/bin/bash
# Run the PageRank application (Parts 1-3) on the cluster.
#
#   bash scripts/run-pagerank.sh <input_uri> <output_uri> [--graph-only] [--damping C]
#
# The test scripts reach your application only through this file, so do not
# modify it. It submits pagerank.py; extra options are passed through to it.

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh

if [ "$#" -lt 2 ]; then
    echo "usage: bash scripts/run-pagerank.sh <input_uri> <output_uri> [options ...]" >&2
    exit 2
fi

INPUT_URI="$1"
OUTPUT_URI="${2%/}"
shift 2
hdfs_uri_ok "${INPUT_URI%/}" || { echo "Input must be a normalized path below hdfs://main:9000/" >&2; exit 2; }
hdfs_uri_ok "$OUTPUT_URI" || { echo "Output must be a normalized directory below hdfs://main:9000/" >&2; exit 2; }
case "${INPUT_URI%/}/" in "$OUTPUT_URI/"*) echo "Output must not contain the input" >&2; exit 2 ;; esac

[ -f pagerank.py ] || { echo "pagerank.py is not in the repository root" >&2; exit 1; }
dc cp pagerank.py main:/pagerank.py || exit 1

# Spark refuses to write into an existing directory.
dc exec -T main hdfs dfs -rm -r -f "$OUTPUT_URI" || exit 1

dc exec -T main spark-submit \
    --master spark://main:7077 \
    /pagerank.py "$INPUT_URI" "$OUTPUT_URI" "$@"
