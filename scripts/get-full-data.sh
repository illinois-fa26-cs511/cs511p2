#!/bin/bash
# Put the full dataset into HDFS at hdfs://main:9000/wiki/full/input (once).
#
# Downloads the release into resources/wiki-full/ unless it is already there,
# verifies it against manifest.json, and uploads the JSONL to HDFS together
# with resources/full/extra.jsonl: a few hundred extra records that exercise
# the rules of Part 1 (the release itself is already clean). A marker
# file in the HDFS directory makes later calls return at once; `make data`
# runs this script and every full-dataset test calls it first.

cd "$(dirname "$0")/.." || exit 1
source scripts/test-lib.sh
set -o pipefail

DATA_DIR="${DATA_DIR:-resources/wiki-full}"
OUT_DIR=out/wiki-full
INPUT_URI="$FULL_INPUT_URI"

# The release is far too large for git, so it is fetched on demand into the
# (gitignored) data directory. Put the files there by hand to skip this.
WIKI_FULL_FILES="manifest.json:1o1Ds7Qt5QrlXgVCHPqMqFiC4T1MHARgT
ATTRIBUTION.md:1b9oT7VeC3ja_8wYwGWB-zhj3KreR1Zia
wiki-full.jsonl.zst:1iXfuueUHFGcC2Hzwc4IUSlGrpJqbZ3VT"
# Digest of the manifest above; every other file is checked against it. Update
# this line whenever the dataset is rebuilt.
MANIFEST_SHA256=fd5ac2570c6b6d5ca8748e03daa110d8916896425b71c15232f28c5161db8fa6
MARKER="${INPUT_URI}/_MANIFEST_SHA256"
EXTRA=resources/full/extra.jsonl
# The marker records both the release and the extra records.
INPUT_DIGEST="${MANIFEST_SHA256}-$(sha256sum "$EXTRA" | cut -c1-16)"

mkdir -p "$OUT_DIR"

function abort() {
    echo -e " ${RED}FAIL${NC}"
    echo "  $*" >&2
    exit 1
}

# Already uploaded? (Spark ignores files whose names start with "_".)
if [ "$(main_exec "hdfs dfs -cat '${MARKER}'" 2>/dev/null)" = "$INPUT_DIGEST" ]; then
    exit 0
fi

# --- 0. fetch the release if this is a fresh clone ----------------------------
if [ ! -f "$DATA_DIR/manifest.json" ] || [ ! -f "$DATA_DIR/ATTRIBUTION.md" ] ||
   ! compgen -G "$DATA_DIR/*.jsonl.zst" > /dev/null; then
    echo -n "Downloading the wiki-full release into ${DATA_DIR}/ ..."
    command -v curl >/dev/null 2>&1 || abort "curl is not installed."
    mkdir -p "$DATA_DIR"
    while IFS=: read -r name id; do
        [ -n "$name" ] || continue
        [ -f "$DATA_DIR/$name" ] && continue
        # The handout uses an underscore; the release manifest uses a hyphen.
        if [ "$name" = wiki-full.jsonl.zst ] && [ -f "$DATA_DIR/wiki_full.jsonl.zst" ]; then
            continue
        fi
        if ! curl -fsSL --retry 3 \
                "https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=t" \
                -o "$DATA_DIR/$name.partial"; then
            rm -f "$DATA_DIR/$name.partial"
            abort "could not download ${name}; put the release in ${DATA_DIR}/ by hand."
        fi
        mv "$DATA_DIR/$name.partial" "$DATA_DIR/$name" || abort "could not save ${name}."
    done <<< "$WIKI_FULL_FILES"
    pass
fi

# --- 1. the release is present and complete -----------------------------------
echo -n "Checking the wiki-full release ..."
[ -d "$DATA_DIR" ] || abort "${DATA_DIR}/ does not exist."
[ -f "$DATA_DIR/manifest.json" ] || abort "${DATA_DIR}/manifest.json is missing."
[ -f "$DATA_DIR/ATTRIBUTION.md" ] || abort "${DATA_DIR}/ATTRIBUTION.md is missing."
if [ "$(sha256sum "$DATA_DIR/manifest.json" | cut -d' ' -f1)" != "$MANIFEST_SHA256" ]; then
    abort "${DATA_DIR}/manifest.json is not the expected release manifest."
fi

# One "<sha256>  <name>" line per chunk, in manifest order.
if ! python3 - "$DATA_DIR/manifest.json" "$DATA_DIR" > "$OUT_DIR/checksums.sha256" 2>"$OUT_DIR/manifest.err" <<'PY'
import json, sys
from pathlib import Path
manifest = json.load(open(sys.argv[1]))
chunks = manifest["chunks"]
declared = manifest.get("chunk_count", len(chunks))
if declared != len(chunks):
    sys.exit("manifest declares chunk_count=%d but lists %d chunks"
             % (declared, len(chunks)))
for chunk in chunks:
    # The release manifest names a chunk "file"; "name" is accepted as well.
    name, sha = chunk.get("file") or chunk["name"], chunk["sha256"]
    if not name.endswith(".jsonl.zst"):
        sys.exit("chunk %r is not a .jsonl.zst file" % name)
    # Verify the same pinned content under either documented filename.
    # If both copies are present, verify both but upload only the manifest name.
    alias = Path(sys.argv[2]) / "wiki_full.jsonl.zst"
    canonical = Path(sys.argv[2]) / name
    if name == "wiki-full.jsonl.zst" and alias.is_file():
        if canonical.is_file():
            import hashlib
            digest = hashlib.sha256()
            with alias.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            if digest.hexdigest() != sha:
                sys.exit("wiki_full.jsonl.zst does not match the release checksum")
        else:
            name = alias.name
    print("%s  %s" % (sha, name))
PY
then
    abort "manifest.json is unusable: $(cat "$OUT_DIR/manifest.err")"
fi

declared_chunks=$(wc -l < "$OUT_DIR/checksums.sha256")
found_chunks=$(find "$DATA_DIR" -maxdepth 1 -name '*.jsonl.zst' | wc -l)
# The underscore and hyphen names represent one chunk, not two.
if [ -f "$DATA_DIR/wiki-full.jsonl.zst" ] && [ -f "$DATA_DIR/wiki_full.jsonl.zst" ]; then
    found_chunks=$((found_chunks - 1))
fi
[ "$declared_chunks" -gt 0 ] || abort "manifest.json lists no chunks."
[ "$declared_chunks" -eq "$found_chunks" ] || \
    abort "manifest.json lists ${declared_chunks} chunks but ${DATA_DIR}/ holds ${found_chunks}."

command -v sha256sum >/dev/null 2>&1 || abort "sha256sum is not installed."
checksums="$(pwd)/${OUT_DIR}/checksums.sha256"
if ! (cd "$DATA_DIR" && sha256sum -c "$checksums") \
        > "$OUT_DIR/checksums.out" 2>&1; then
    abort "checksum verification failed; see ${OUT_DIR}/checksums.out."
fi
pass

# --- 2. decompress and upload the JSONL --------------------------------------
echo -n "Uploading ${declared_chunks} chunks to ${INPUT_URI} ..."
command -v zstd >/dev/null 2>&1 || abort "zstd is not installed (apt install zstd)."
main_exec "hdfs dfs -rm -r -f '${INPUT_URI}' && hdfs dfs -mkdir -p '${INPUT_URI}'" \
    > "$OUT_DIR/upload.out" 2>&1 || abort "could not prepare ${INPUT_URI}."

while read -r _sha name; do
    jsonl="${name%.zst}"
    if ! zstd -dcq "$DATA_DIR/$name" \
            | dc exec -T main bash -c "hdfs dfs -put -f - '${INPUT_URI}/${jsonl}'" \
            >> "$OUT_DIR/upload.out" 2>&1; then
        abort "uploading ${name} failed; see ${OUT_DIR}/upload.out."
    fi
done < "$OUT_DIR/checksums.sha256"
upload "$EXTRA" "${INPUT_URI}/extra.jsonl" >> "$OUT_DIR/upload.out" 2>&1 || \
    abort "uploading ${EXTRA} failed; see ${OUT_DIR}/upload.out."

main_exec "hdfs dfs -ls '${INPUT_URI}'" > "$OUT_DIR/input-listing.out" 2>&1
uploaded=$(grep -c '\.jsonl$' "$OUT_DIR/input-listing.out")
[ "$uploaded" -eq $((declared_chunks + 1)) ] || \
    abort "${uploaded} of $((declared_chunks + 1)) JSONL files reached HDFS; see ${OUT_DIR}/input-listing.out."
! grep -q '\.zst' "$OUT_DIR/input-listing.out" || abort "compressed chunks were uploaded to HDFS."
pass

main_exec "echo ${INPUT_DIGEST} | hdfs dfs -put -f - '${MARKER}'" >> "$OUT_DIR/upload.out" 2>&1 || \
    abort "could not write ${MARKER}."
exit 0
