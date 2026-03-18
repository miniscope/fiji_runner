#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 4 ]]; then
	  echo "Usage: $0 /path/to/Fiji.app/ImageJ-linux64 INPUT_FILE OUTDIR NAME"
	    exit 1
fi

FIJI_BIN="$1"
INPUT="$2"
OUTDIR="$3"
NAME="$4"

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

# Exact raw copy (fast, no re-encode)
if [[ "${INPUT_ABS,,}" == *.avi ]]; then
	  cp -f "$INPUT_ABS" "$OUTDIR_ABS/${NAME}_raw.avi"
fi

# Run headless ImageJ/Fiji macro
"$FIJI_BIN" --headless -macro "$MACRO" \
	  "input=$INPUT_ABS;outdir=$OUTDIR_ABS;name=$NAME"

