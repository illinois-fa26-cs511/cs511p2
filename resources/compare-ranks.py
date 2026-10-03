#!/usr/bin/env python3
"""Compare PageRank or search output with a truth file (host side, stdlib only).

    python3 compare-ranks.py ranks  <truth> <produced> --part values|order
    python3 compare-ranks.py search <truth> <produced>

Spark may compute the last digits differently from the truth, so a value v
matches its truth t when |v - t| <= ABSOLUTE + RELATIVE * |t|, and values that
match each other are ties that may appear in either order. Prints what differs
and exits 0 when the checked part matches.
"""
import sys

ABSOLUTE = 1e-10
RELATIVE = 1e-4
SUM_TOLERANCE = 1e-6


def close(value, truth):
    return abs(value - truth) <= ABSOLUTE + RELATIVE * abs(truth)


def read_lines(path):
    with open(path) as stream:
        return [line.rstrip("\r\n") for line in stream if line.strip()]


def parse_ranks(path, problems):
    records = []
    for number, line in enumerate(read_lines(path), 1):
        fields = line.split("\t")
        try:
            if len(fields) != 2:
                raise ValueError
            records.append((int(fields[0]), float(fields[1])))
        except ValueError:
            problems.append("line %d is not id<TAB>rank: %r" % (number, line[:80]))
    return records


def check_ranks(truth_path, produced_path, part):
    problems = []
    truth = dict(parse_ranks(truth_path, []))
    produced = parse_ranks(produced_path, problems)
    if not produced:
        return ["no ranks were produced"]
    ids = [article_id for article_id, _ in produced]

    if part == "values":
        if len(set(ids)) != len(ids):
            problems.append("some article ids appear more than once")
        missing = sorted(set(truth) - set(ids))
        extra = sorted(set(ids) - set(truth))
        if missing:
            problems.append("%d article ids are missing (e.g. %s)" % (len(missing), missing[:5]))
        if extra:
            problems.append("%d unexpected article ids (e.g. %s)" % (len(extra), extra[:5]))
        wrong = [(a, r, truth[a]) for a, r in produced if a in truth and not close(r, truth[a])]
        if wrong:
            problems.append("%d of %d ranks differ from the truth, e.g.:" % (len(wrong), len(truth)))
            problems += ["  article %d: rank %.12e, expected %.12e" % w for w in wrong[:5]]
    else:
        total = sum(rank for _, rank in produced)
        if abs(total - 1.0) > SUM_TOLERANCE:
            problems.append("ranks sum to %.9f, expected 1" % total)
        for (id1, r1), (id2, r2) in zip(produced, produced[1:]):
            if r2 > r1 and not close(r2, r1):
                problems.append("not sorted by descending rank: %d (%.12e) before %d (%.12e)"
                                % (id1, r1, id2, r2))
                break
    return problems


def parse_search(path, problems):
    """{query: [(position, id, score, title)]}; a query without results maps to []."""
    groups = {}
    for number, line in enumerate(read_lines(path), 1):
        fields = line.split("\t")
        try:
            if len(fields) != 5:
                raise ValueError
            query, position = fields[0], int(fields[1])
            rows = groups.setdefault(query, [])
            if position > 0:
                rows.append((position, int(fields[2]), float(fields[3]), fields[4]))
            elif position < 0:
                raise ValueError
        except ValueError:
            problems.append("line %d is not query<TAB>position<TAB>id<TAB>score<TAB>title: %r"
                            % (number, line[:80]))
    return {query: sorted(rows) for query, rows in groups.items()}


def check_search(truth_path, produced_path):
    """Compare query by query; print QUERIES PASSED: <passed>/<total>."""
    problems = []
    truth = parse_search(truth_path, [])
    produced = parse_search(produced_path, problems)
    passed = 0
    for query in truth:
        want, got = truth[query], produced.get(query)
        label = "query %r" % query
        if got is None:
            problems.append("%s: no answer" % label)
            continue
        if [p for p, _, _, _ in got] != list(range(1, len(got) + 1)):
            problems.append("%s: positions are not 1..%d" % (label, len(got)))
            continue
        if len(got) != len(want):
            problems.append("%s: %d results, expected %d" % (label, len(got), len(want)))
            continue
        # Position by position the scores must match; an article may differ
        # from the truth only where it ties with the truth's score there.
        expected = {article_id: (score, title) for _, article_id, score, title in want}
        ok = True
        for (_, want_id, want_score, _), (_, got_id, got_score, got_title) in zip(want, got):
            same = expected.get(got_id)
            if not close(got_score, want_score) or \
                    (got_id != want_id and not (same and close(same[0], want_score))) or \
                    (same and got_title != same[1]):
                ok = False
        if ok:
            passed += 1
        else:
            problems.append("%s: got %s, expected %s"
                            % (label, [(a, "%.6g" % s) for _, a, s, _ in got],
                               [(a, "%.6g" % s) for _, a, s, _ in want]))
    print("QUERIES PASSED: %d/%d" % (passed, len(truth)))
    return problems


def main(argv):
    if len(argv) < 4 or argv[1] not in ("ranks", "search"):
        print(__doc__, file=sys.stderr)
        return 2
    options = dict(zip(argv[4::2], argv[5::2]))
    if argv[1] == "ranks":
        problems = check_ranks(argv[2], argv[3], options.get("--part", "values"))
    else:
        problems = check_search(argv[2], argv[3])
    for problem in problems[:20]:
        print("  - " + problem)
    if len(problems) > 20:
        print("  ... and %d more" % (len(problems) - 20))
    print("COMPARE: %s" % ("FAIL" if problems else "PASS"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
