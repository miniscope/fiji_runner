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

# JVM heap for Fiji; override with FIJI_MEM=32g
FIJI_MEM="${FIJI_MEM:-64g}"

# Macro lives next to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACRO="$SCRIPT_DIR/minizero_fftonly.ijm"

# Resolve absolute paths so Fiji can always find them
INPUT_ABS="$(realpath "$INPUT")"
OUTDIR_ABS="$(realpath -m "$OUTDIR")"
mkdir -p "$OUTDIR_ABS"

# Sanity checks
[[ -x "$FIJI_BIN" ]] || { echo "Fiji binary not executable: $FIJI_BIN" >&2; exit 2; }
[[ -f "$MACRO" ]]    || { echo "Macro not found: $MACRO" >&2; exit 2; }
[[ -f "$INPUT_ABS" ]]|| { echo "Input not found: $INPUT_ABS" >&2; exit 2; }

MACRO_ARGS="input=$INPUT_ABS;outdir=$OUTDIR_ABS;name=$NAME"
[[ -n "$EXTRA" ]] && MACRO_ARGS="$MACRO_ARGS;$EXTRA"

# Run headless ImageJ/Fiji macro
"$FIJI_BIN" --mem="$FIJI_MEM" --headless -macro "$MACRO" "$MACRO_ARGS"
