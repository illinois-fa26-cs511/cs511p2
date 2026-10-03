#!/usr/bin/env python3
"""Query the search API with every line of a queries file (host side, stdlib only).

    python3 query-api.py <queries.txt> <results.txt> [--url http://localhost:8000]

Writes one line per result, query<TAB>position<TAB>id<TAB>score<TAB>title, and
query<TAB>0<TAB><TAB><TAB> for a query without results (the format of the
search.truth files). Every query is sent twice; the latency of the second
round is reported, so that a cold cache does not count:

    LATENCY: median <ms> ms, p95 <ms> ms, max <ms> ms
"""
import json
import sys
import time
from urllib.parse import quote
from urllib.request import urlopen


def ask(url, query):
    started = time.perf_counter()
    with urlopen("%s/search?q=%s" % (url, quote(query)), timeout=30) as response:
        body = json.loads(response.read().decode())
    return body, (time.perf_counter() - started) * 1000


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    url = argv[argv.index("--url") + 1] if "--url" in argv else "http://localhost:8000"
    queries = []
    for line in open(argv[1]):
        if line.strip() and line.strip() not in queries:
            queries.append(line.strip())

    lines, latencies = [], []
    for query in queries:                    # warm-up round
        try:
            ask(url, query)
        except Exception:
            pass
    for query in queries:
        try:
            body, millis = ask(url, query)
            results = body["results"]
            latencies.append(millis)
            if not results:
                lines.append("%s\t0\t\t\t" % query)
            for position, result in enumerate(results, 1):
                lines.append("%s\t%d\t%d\t%.12e\t%s" % (
                    query, position, int(result["id"]), float(result["score"]),
                    " ".join(str(result.get("title", "")).split())))
        except Exception as error:          # report and keep going
            print("query %r failed: %s" % (query, error))
            lines.append("%s\t-1\t\t\terror" % query)
    with open(argv[2], "w") as out:
        out.write("".join(line + "\n" for line in lines))

    if latencies:
        ordered = sorted(latencies)
        p95 = ordered[min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1))))]
        print("LATENCY: median %.1f ms, p95 %.1f ms, max %.1f ms"
              % (ordered[len(ordered) // 2], p95, ordered[-1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
