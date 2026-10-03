#!/usr/bin/env python3
"""CS 511 Project 2, Part 2: build the search index with Spark.

    spark-submit --master spark://main:7077 indexer.py \
        <articles_uri> <ranks_uri> <index_uri>

<articles_uri>  the JSONL articles (the input of pagerank.py)
<ranks_uri>     a ranks/ directory written by pagerank.py (id<TAB>rank)
<index_uri>     output directory, with two parts:

    docs/       id<TAB>rank<TAB>title            one line per valid article
    postings/   term<TAB>id:weight,id:weight,... one line per term

where weight = tf(term, id) * ln(N / df(term)): tf is the number of times the
term occurs in the article's text, df the number of articles whose text
contains it, and N the number of valid articles. The search score of an
article for a query is its rank times the sum of the weights of the query
terms (see server.py).

This is a suggested layout: you may change what the indexer writes, as long as
serve.sh loads it into your database.
"""
import json
import math
import re
import sys
from collections import Counter

from pyspark.sql import SparkSession

# Tokenization rules of Project 1.
TOKEN_PATTERN = re.compile(r"[a-z]+(?:'[a-z]+)?")
MIN_TOKEN_LENGTH = 2
STOPWORDS = frozenset(
    "a an and are as at be by for from in is it of on or that the to was with".split()
)


def tokenize(text):
    """Project 1 tokenizer: lowercase, match TOKEN_PATTERN, drop short words and stopwords."""
    return [word for word in TOKEN_PATTERN.findall(text.lower())
            if len(word) >= MIN_TOKEN_LENGTH and word not in STOPWORDS]


def parse_article(line):
    """Return (article_id, title, text) for a valid article line, else None.

    Valid articles are those of pagerank.py: JSON objects with an integer id.
    A missing or non-string title or text counts as empty.
    """
    try:
        article = json.loads(line)
    except ValueError:
        return None
    if not isinstance(article, dict):
        return None
    article_id = article.get("id")
    if not isinstance(article_id, int) or isinstance(article_id, bool):
        return None
    title, text = article.get("title"), article.get("text")
    return (article_id,
            title if isinstance(title, str) else "",
            text if isinstance(text, str) else "")


def parse_rank(line):
    article_id, rank = line.split("\t")
    return (int(article_id), float(rank))


def build_postings(articles, num_articles):
    """Return an RDD of (term, [(article_id, weight), ...]) from (id, title, text).

    weight = tf * ln(num_articles / df), as described in the module docstring.
    """
    # TODO: count the terms of each article's text (tokenize, then e.g.
    # collections.Counter), group the (article_id, tf) pairs by term, and
    # turn each tf into tf * ln(num_articles / df), where df is the number
    # of articles in the term's group.
    raise NotImplementedError("build_postings")


def build_docs(articles, ranks):
    """Return an RDD of (article_id, (rank, title)) for every valid article."""
    # TODO: join each article's title with its rank.
    raise NotImplementedError("build_docs")


# --- Given code -----------------------------------------------------------------

def clean(title):
    return " ".join(title.split())


def main(argv):
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    articles_uri, ranks_uri, index_uri = argv[1], argv[2], argv[3].rstrip("/")

    spark = SparkSession.builder.appName("SearchIndexer").getOrCreate()
    sc = spark.sparkContext
    try:
        articles = sc.textFile(articles_uri).map(parse_article) \
            .filter(lambda a: a is not None).cache()
        num_articles = articles.count()
        ranks = sc.textFile(ranks_uri).map(parse_rank)

        build_docs(articles, ranks) \
            .map(lambda kv: "%d\t%.12e\t%s" % (kv[0], kv[1][0], clean(kv[1][1]))) \
            .saveAsTextFile(index_uri + "/docs")
        build_postings(articles, num_articles) \
            .map(lambda kv: "%s\t%s" % (kv[0], ",".join("%d:%.10g" % p for p in kv[1]))) \
            .saveAsTextFile(index_uri + "/postings")
        print("INDEXED ARTICLES: %d" % num_articles)
    finally:
        spark.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
