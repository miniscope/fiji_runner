#!/usr/bin/env bash
# Batch-run minizero_fftonly.sh over every *_raw.avi under a root directory.
#
#   ./minizero_fftonly_batch.sh /path/to/ImageJ-linux64 ROOT_DIR [JOBS]
#
# For each  <dir>/<NAME>_raw.avi  it writes  <dir>/<NAME>_fftonly.avi
# and <dir>/<NAME>_fftonly_sub20.avi. Files whose _fftonly.avi already
# exists are skipped, so the script is safe to re-run.

set -uo pipefail

FIJI_BIN="${1:?usage: $0 FIJI_BIN ROOT_DIR [JOBS]}"
ROOT="${2:?usage: $0 FIJI_BIN ROOT_DIR [JOBS]}"
JOBS="${3:-4}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/minizero_fftonly.sh"
LOGDIR="${LOGDIR:-$PWD/fftonly_logs}"
mkdir -p "$LOGDIR"

# Per-job heap; several jobs run concurrently so keep it modest.
export FIJI_MEM="${FIJI_MEM:-16g}"

run_one() {
    local raw="$1"
    local dir name log
    dir="$(dirname "$raw")"
    name="$(basename "$raw")"; name="${name%_raw.avi}"
    log="$LOGDIR/${name}.log"

    if [[ -s "$dir/${name}_fftonly.avi" ]]; then
        echo "SKIP (exists)  $dir/${name}_fftonly.avi"
        return 0
    fi

    echo "START  $name"
    if "$RUNNER" "$FIJI_BIN" "$raw" "$dir" "$name" >"$log" 2>&1; then
        echo "OK     $name  -> $dir/${name}_fftonly.avi"
    else
        echo "FAIL   $name  (see $log)"
        return 1
    fi
}
export -f run_one
export FIJI_BIN RUNNER LOGDIR

find "$ROOT" -name "*_raw.avi" -print0 \
  | sort -z \
  | xargs -0 -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

echo "Batch finished."
