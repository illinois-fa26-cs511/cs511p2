# CS 511: Project 2 PageRank and Search

Follow the [course handout](https://docs.google.com/document/d/1YxIiya4p1QaMEb19OTsFRgeu2UqeyrrPSnCWL01J_TM/edit?usp=sharing) for instructions and submission requirements.

Run commands from the repository root in a host Bash terminal. You need Docker
with Compose, GNU Make, Python 3, curl, zstd, and GNU command-line utilities.

## What you edit

| Files | Part |
|---|---|
| `cs511p2-common.Dockerfile`, `cs511p2-main.Dockerfile`, `cs511p2-worker.Dockerfile`, `setup-main.sh`, `setup-worker.sh`, `start-main.sh`, `start-worker.sh` | Part 0: copy your Project 1 cluster here |
| `pagerank.py` | Part 1: compute PageRank |
| `search/indexer.py`, `search/server.py`, `search/serve.sh` | Part 2: the search API and its database |
| `attack.jsonl` | Part 4: search engineering |

Do not modify `scripts/` (cluster and test scripts) or `resources/` (sample,
truth files and checkers). You may add new files.

## Commands

```bash
make                    # list all commands
make start              # build the images and start the cluster
make shell              # Bash on main (make shell NODE=worker1 for a worker)
make stop               # remove the cluster, including its HDFS data
```

Develop against the 10-article sample in `resources/sample/` (quick, ungraded):

```bash
make check              # all of the checks below
make check-pagerank     # Part 1
make check-search       # Part 2
make check-attack       # Part 4: validates attack.jsonl only
```

Grading runs on the full dataset, which the tests download and put into HDFS
the first time (`make data` does only that):

```bash
make test               # every graded test, with the score
make test-cluster       # Part 0
make test-pagerank      # Part 1
make test-search        # Part 2
make test-attack        # Part 4
```

The project is worth 100 points: 70 from these tests and 30 from the report.

Running your code yourself (Parts 3 and 4 of the report):

```bash
make pagerank                   # PageRank of the full dataset -> hdfs://main:9000/wiki/full/pagerank
make serve                      # index those ranks and start the API on localhost:8000
make query Q="computer science" # ask the API
```

`make pagerank` takes `OUT=<hdfs uri>` and `ARGS="--damping 0.7"`; `make serve`
takes `ARTICLES=<hdfs uri>` and `RANKS=<hdfs uri>`. Test logs and outputs are
saved in `out/` (`make clean` deletes them).

Search tests replace the running API with one built from reference ranks.
Before collecting report results, run `make pagerank` and `make serve` to
use your own ranks. Save the baseline results before testing your attack.
To query the attacked dataset after `make test-attack`, run:

```bash
make serve \
  ARTICLES=hdfs://main:9000/wiki/full/attack/input \
  RANKS=hdfs://main:9000/wiki/full/test-attack/ranks
make query Q="champaign"
```

Run `make serve` without overrides to restore the original dataset and your
baseline ranks. `make check-attack` validates the file format only; the full
attack test measures the target's position by PageRank, independently of any
keyword query. See the handout for the report questions and scoring thresholds.
