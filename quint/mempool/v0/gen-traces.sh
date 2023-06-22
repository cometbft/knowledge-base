#!/usr/bin/env bash

set -u

PROP=${1:-notFullChain}
[[ ! -z "${PROP}" ]] && echo "Generating trace for ${PROP}..." || (echo "PROP is empty" && exit 1)

TRACES_DIR="traces/$PROP"
mkdir -p "$TRACES_DIR"

function nextFilename() {
    local dir=$1
    local name=$2
    local ext=$3
    i=1
    while [[ -e "$dir/$name-$i.$ext" || -L "$dir/$name-$i.$ext" ]] ; do
        let i++
    done
    name=$name-$i
    echo $name.$ext
}

FILE_NAME=$(nextFilename $TRACES_DIR "${PROP}_trace" "itf.json")
TRACE_PATH="$TRACES_DIR/$FILE_NAME"
echo "Generating trace: $TRACE_PATH"

time quint run \
    --verbosity 5 \
    --max-steps=100 \
    --max-samples=3 \
    --invariant "$PROP" \
    --out-itf "$TRACE_PATH" \
    mempoolv0.qnt
