#!/bin/bash
# Build the search index and start the search API (Part 2) on main.
#
#   bash scripts/run-serve.sh <articles_uri> <ranks_uri>
#
# Copies search/ to /search on main and runs /search/serve.sh there, then
# waits until http://localhost:8000/health answers on the host. `make serve`
# and the tests call it; do not modify it.

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh

if [ "$#" -ne 2 ]; then
    echo "usage: bash scripts/run-serve.sh <articles_uri> <ranks_uri>" >&2
    exit 2
fi
for uri in "${1%/}" "${2%/}"; do
    hdfs_uri_ok "$uri" || { echo "${uri} is not a normalized path below hdfs://main:9000/" >&2; exit 2; }
done
[ -f search/serve.sh ] || { echo "search/serve.sh is missing" >&2; exit 1; }

main_exec 'rm -rf /search' || exit 1
dc cp search main:/search || exit 1
dc exec -T main bash /search/serve.sh "${1%/}" "${2%/}" || exit 1

for _ in $(seq 1 60); do
    if python3 -c 'import urllib.request; urllib.request.urlopen("http://localhost:8000/health", timeout=2)' \
            2>/dev/null; then
        echo "SEARCH API READY"
        exit 0
    fi
    sleep 1
done
echo "http://localhost:8000/health does not answer" >&2
exit 1
