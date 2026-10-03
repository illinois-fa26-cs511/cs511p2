# CS 511 Project 2: PageRank and search. Run `make` to list the commands.
SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose -f scripts/cs511p2-compose.yaml
NODE ?= main
FULL := hdfs://main:9000/wiki/full
IN ?= $(FULL)/input
OUT ?= $(FULL)/pagerank
ARTICLES ?= $(FULL)/input
RANKS ?= $(FULL)/pagerank/ranks

.PHONY: help start stop shell data check check-pagerank check-search check-attack \
        test test-cluster test-pagerank test-search test-attack pagerank serve query clean

help: ## List the commands
	@echo "Usage: make <command>"
	@echo
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | \
	    awk 'BEGIN { FS = ":.*## " } { printf "  %-16s %s\n", $$1, $$2 }'

start: ## Build the images and start main, worker1 and worker2
	@bash scripts/start-all.sh

stop: ## Stop and remove the cluster, including its HDFS data
	@bash scripts/stop-all.sh

shell: ## Open a Bash shell on a node (NODE=main|worker1|worker2)
	@$(COMPOSE) exec $(NODE) bash

data: ## Download the full dataset and put it in HDFS (the tests do this too)
	@bash scripts/get-full-data.sh

# Quick, ungraded checks on the 10-article sample in resources/sample/.
check: ## Run every quick check (ungraded)
	@bash scripts/test_1_pagerank.sh sample; echo; \
	 bash scripts/test_2_search.sh sample; echo; \
	 bash scripts/test_4_attack.sh check

check-pagerank: ## Part 1 on the sample
	@bash scripts/test_1_pagerank.sh sample

check-search: ## Part 2 on the sample
	@bash scripts/test_2_search.sh sample

check-attack: ## Part 4: validate attack.jsonl
	@bash scripts/test_4_attack.sh check

# Graded tests: the full dataset.
test: ## Run every graded test on the full dataset and print the score
	@bash scripts/test-all.sh

test-cluster: ## Part 0: the cluster
	@bash scripts/test_0_cluster.sh

test-pagerank: ## Part 1 on the full dataset
	@bash scripts/test_1_pagerank.sh full

test-search: ## Part 2 on the full dataset
	@bash scripts/test_2_search.sh full

test-attack: ## Part 4 on the full dataset
	@bash scripts/test_4_attack.sh full

# Running your code yourself (for the report).
pagerank: ## Run pagerank.py on the full dataset [OUT=<hdfs uri>] [ARGS="--damping 0.7"]
	@bash scripts/run-pagerank.sh "$(IN)" "$(OUT)" $(ARGS)

serve: ## Build the index and start the API (uses the ranks of make pagerank)
	@bash scripts/run-serve.sh "$(ARTICLES)" "$(RANKS)"

query: ## Ask the running API: make query Q="computer science"
	@python3 -c 'import json, sys, urllib.parse, urllib.request; \
	    body = json.load(urllib.request.urlopen("http://localhost:8000/search?q=" + urllib.parse.quote(sys.argv[1]))); \
	    [print("%2d  %-10d %-12.6g %s" % (i, r["id"], r["score"], r["title"])) for i, r in enumerate(body["results"], 1)] \
	    or print("no results")' "$(Q)"

clean: ## Delete test logs and outputs (out/)
	rm -rf out
