#!/usr/bin/env python3
"""CS 511 Project 2, Part 1: PageRank over the Wikipedia link graph.

Rank the articles stored in HDFS by their link structure. PageRank models a
random surfer: with probability DAMPING the surfer follows a random link of the
current page; otherwise (and always on a page without links) the surfer jumps
to a random article. The rank of a page is the long-run fraction of time the
surfer spends on it.

    spark-submit --master spark://main:7077 /pagerank.py \
        <input_uri> <output_uri> [--graph-only] [--damping C]

Both URIs must start with hdfs://main:9000/.

Input: one JSON article per line, as in Project 1, e.g.

    {"id":10,"title":"MapReduce","text":"Map maps data ...","links":[20,30]}

`links` lists the ids of the articles this article links to.

Output directories below <output_uri>:

    graph/        id<TAB>outdeg<TAB>t1,t2,...     (sorted by id)
    ranks/        id<TAB>rank                     (highest rank first, then id)
    convergence/  iteration<TAB>delta             (one line per iteration)

Only the functions marked TODO need to be written. `make pagerank` and the
tests submit this file through scripts/run-pagerank.sh.
"""
import argparse
import json
import sys
from operator import add

from pyspark.sql import SparkSession

DAMPING = 0.85          # c: the surfer follows a link with probability c
EPSILON = 1e-8          # stop once ||R_{i+1} - R_i||_1 <= EPSILON
MAX_ITERATIONS = 100    # ... or after this many iterations
CHECKPOINT_EVERY = 10   # checkpoint the ranks every this many iterations
CHECKPOINT_DIR = "hdfs://main:9000/spark/checkpoints"


# --- The link graph -------------------------------------------------------------

def is_integer(value):
    """True for JSON integers. bool is a subclass of int in Python: exclude it."""
    return isinstance(value, int) and not isinstance(value, bool)


def parse_article(line):
    """Parse one input line into an (article_id, links) pair.

    Return None unless the line is a JSON object whose `id` is an integer.
    A missing or non-list `links` counts as no links, and link entries that
    are not integers are dropped. Keep duplicates, self-links and links to
    unknown articles here: build_graph removes them.
    """
    # TODO: implement. json.loads raises ValueError on invalid JSON; use
    # is_integer() for the id and for each link.
    raise NotImplementedError("parse_article")


def build_graph(lines):
    """Turn an RDD of raw input lines into an RDD of (article_id, targets).

    Every valid article appears exactly once, including articles without
    out-links (dangling pages), whose targets list is empty. `targets` is the
    ascending list of distinct article ids the article links to, without the
    article itself and without ids that are not valid articles of the input
    (broken links). Article ids are unique.
    """
    # TODO: parse the lines and drop invalid ones, then build the edges.
    # A link to an unknown id can only be detected against the set of all
    # valid ids: join the candidate edges (keyed by target) with the ids.
    # Finally attach the kept targets to every article, keeping the articles
    # that have none (cogroup or leftOuterJoin), and sort/deduplicate them.
    raise NotImplementedError("build_graph")


# --- PageRank -------------------------------------------------------------------

def contributions(targets, rank, damping):
    """Return the (target, share) pairs a page with `rank` sends along its links.

    The page splits damping * rank evenly over its targets. A dangling page
    (no targets) sends nothing.
    """
    # TODO: implement.
    raise NotImplementedError("contributions")


def pagerank_step(links, ranks, num_pages, damping, num_partitions, checkpoint=False):
    """One PageRank iteration.

    `links` and `ranks` are (id, targets) and (id, rank) RDDs with the same
    partitioner. Compute

        R_{i+1}(u) = sum of the contributions u receives
        d          = 1 - ||R_{i+1}||_1        (rank not passed along links)
        R_{i+1}(u) = R_{i+1}(u) + d / num_pages

    and return (R_{i+1}, delta) where delta = ||R_{i+1} - R_i||_1 (the sum of
    absolute differences). The new ranks must contain every page, keep the
    partitioner of `ranks`, and be persisted. When `checkpoint` is true, also
    mark them for checkpointing; Spark only honours checkpoint() if it is
    called before the first action that computes the RDD.
    """
    # TODO: implement with RDD operations only (no collect of the ranks).
    # 1. Join `links` with `ranks` and flatMap through contributions(), then
    #    sum the shares per target with reduceByKey(add, num_partitions).
    # 2. Give every page its incoming sum (0.0 when it receives nothing):
    #    pages without in-links must not disappear.
    # 3. d = 1 - (sum of those values); add d / num_pages to every page.
    # 4. Keep the partitioner (mapValues), persist, call checkpoint() if
    #    asked, and only then run actions.
    # 5. delta = sum over pages of |new - old|.
    raise NotImplementedError("pagerank_step")


def run_pagerank(links, num_pages, damping=DAMPING, epsilon=EPSILON,
                 max_iterations=MAX_ITERATIONS, checkpoint_every=CHECKPOINT_EVERY):
    """Iterate pagerank_step from R_0(u) = 1 / num_pages until delta <= epsilon.

    Stop after max_iterations at the latest. Checkpoint the ranks every
    `checkpoint_every` iterations so that the lineage does not grow without
    bound, and unpersist ranks that are no longer needed.
    Return (ranks, deltas), where deltas[i] is the delta of iteration i + 1.
    """
    # TODO: start from R_0(u) = 1 / num_pages with the partitioner of `links`
    # (mapValues), call pagerank_step until delta <= epsilon or
    # max_iterations iterations, pass checkpoint=True every
    # `checkpoint_every` iterations, and unpersist the previous ranks.
    # Printing the delta of each iteration helps debugging.
    raise NotImplementedError("run_pagerank")


# --- Given code -----------------------------------------------------------------

def format_graph_record(article_id, targets):
    return "%d\t%d\t%s" % (article_id, len(targets), ",".join(map(str, targets)))


def format_rank_record(article_id, rank):
    return "%d\t%.12e" % (article_id, rank)


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("input_uri")
    parser.add_argument("output_uri")
    parser.add_argument("--graph-only", action="store_true",
                        help="stop after writing graph/")
    parser.add_argument("--damping", type=float, default=DAMPING)
    parser.add_argument("--epsilon", type=float, default=EPSILON)
    parser.add_argument("--max-iterations", type=int, default=MAX_ITERATIONS)
    parser.add_argument("--checkpoint-dir", default=CHECKPOINT_DIR)
    return parser.parse_args(argv[1:])


def main(argv):
    args = parse_args(argv)
    output = args.output_uri.rstrip("/")

    spark = SparkSession.builder.appName("PageRank").getOrCreate()
    sc = spark.sparkContext
    sc.setCheckpointDir(args.checkpoint_dir)
    try:
        # Partition the graph once and keep it in memory: every iteration
        # joins against it, and a shared partitioner avoids reshuffling it.
        num_partitions = max(sc.defaultParallelism, 2)
        links = build_graph(sc.textFile(args.input_uri)) \
            .partitionBy(num_partitions) \
            .persist()

        links.sortByKey(numPartitions=1) \
            .map(lambda kv: format_graph_record(kv[0], kv[1])) \
            .saveAsTextFile(output + "/graph")
        num_pages = links.count()
        print("GRAPH NODES: %d" % num_pages)
        print("GRAPH EDGES: %d" % links.values().map(len).sum())
        print("GRAPH DANGLING: %d" % links.filter(lambda kv: not kv[1]).count())
        if args.graph_only:
            return 0

        ranks, deltas = run_pagerank(links, num_pages, args.damping, args.epsilon,
                                     args.max_iterations)
        ranks.sortBy(lambda kv: (-kv[1], kv[0]), numPartitions=1) \
            .map(lambda kv: format_rank_record(kv[0], kv[1])) \
            .saveAsTextFile(output + "/ranks")
        sc.parallelize(["%d\t%.6e" % (i + 1, d) for i, d in enumerate(deltas)], 1) \
            .saveAsTextFile(output + "/convergence")
        print("PAGERANK ITERATIONS: %d" % len(deltas))
    finally:
        spark.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
