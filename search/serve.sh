#!/bin/bash
# CS 511 Project 2, Part 2: build the index and start the search API on main.
#
#   bash serve.sh <articles_uri> <ranks_uri>
#
# `make serve` and the tests copy this directory to /search on main and run
# this script there (so hdfs, spark-submit and python3 are at hand). It must
# (re)build everything from the given inputs, start the server in the
# background on port 8000, and return once GET /health answers. Run it twice
# and the second run must replace the first server.
set -e
cd "$(dirname "$0")"

ARTICLES_URI="$1"
RANKS_URI="$2"
INDEX_URI="hdfs://main:9000/search/index"
DATABASE=/data/search.db

# 0. Stop a server started earlier.
pkill -f '[s]erver.py' || true

# 1. Build the index with Spark.
hdfs dfs -rm -r -f "$INDEX_URI"
spark-submit --master spark://main:7077 indexer.py "$ARTICLES_URI" "$RANKS_URI" "$INDEX_URI"

# 2. Load it into your database.
# TODO: start your database if it runs as a service (or install it in the
# Dockerfiles and start it in start-main.sh), and load the index into it,
# e.g. hdfs dfs -cat "${INDEX_URI}/postings/part-*" | <your loader>.
echo "TODO: load the index into your database (search/serve.sh)" >&2
exit 1

# 3. Start the server in the background and wait until it answers.
setsid nohup python3 server.py --port 8000 > /search/server.log 2>&1 < /dev/null &
for _ in $(seq 1 120); do
    if python3 -c 'import urllib.request; urllib.request.urlopen("http://localhost:8000/health", timeout=2)' \
            2>/dev/null; then
        echo "search API ready on port 8000"
        exit 0
    fi
    sleep 1
done
echo "the server did not start; see /search/server.log" >&2
exit 1
