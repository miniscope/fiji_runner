#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 4 ]]; then
	  echo "Usage: $0 /path/to/Fiji.app/ImageJ-linux64 INPUT_FILE OUTDIR NAME [EXTRA_MACRO_ARGS]"
	    echo "  EXTRA_MACRO_ARGS e.g. 'tolerance=5;suppress=Vertical'"
	    exit 1
fi

FIJI_BIN="$1"
INPUT="$2"
OUTDIR="$3"
NAME="$4"
EXTRA="${5:-}"

# Macro lives next to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACRO="$SCRIPT_DIR/minizero_process.ijm"

# Resolve absolute paths so Fiji can always find them
INPUT_ABS="$(realpath "$INPUT")"
OUTDIR_ABS="$(realpath -m "$OUTDIR")"
mkdir -p "$OUTDIR_ABS"

# Sanity checks
[[ -x "$FIJI_BIN" ]] || { echo "Fiji binary not executable: $FIJI_BIN" >&2; exit 2; }
[[ -f "$MACRO" ]]    || { echo "Macro not found: $MACRO" >&2; exit 2; }
[[ -f "$INPUT_ABS" ]]|| { echo "Input not found: $INPUT_ABS" >&2; exit 2; }

# Exact raw copy (fast, no re-encode).
# Skipped when the input already IS the raw copy, i.e. when reprocessing
# an existing {NAME}_raw.avi in place -- cp would fail on same-file.
RAW_COPY="$OUTDIR_ABS/${NAME}_raw.avi"
if [[ "${INPUT_ABS,,}" == *.avi && "$INPUT_ABS" != "$RAW_COPY" ]]; then
	  cp -f "$INPUT_ABS" "$RAW_COPY"
fi

# Run headless ImageJ/Fiji macro.
# FIJI_MEM (e.g. 16g) caps the JVM heap; unset means Fiji's own default.
# Useful when several instances run concurrently -- see minizero_process_batch.sh.
"$FIJI_BIN" ${FIJI_MEM:+--mem="$FIJI_MEM"} --headless -macro "$MACRO" \
	  "input=$INPUT_ABS;outdir=$OUTDIR_ABS;name=$NAME${EXTRA:+;$EXTRA}"

