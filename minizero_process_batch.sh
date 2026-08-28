#!/usr/bin/env bash
# Batch-run minizero_process.sh over every *_raw.avi under a root directory.
#
#   ./minizero_process_batch.sh /path/to/ImageJ-linux64 ROOT_DIR [JOBS]
#
# For each  <dir>/<NAME>_raw.avi  it writes  <dir>/<NAME>_destripe.avi
# and <dir>/<NAME>_destripe_sub20.avi. Inputs whose _destripe.avi already
# exists are skipped, so re-running is cheap and doubles as a check that
# every _raw.avi has been processed.

set -uo pipefail

FIJI_BIN="${1:?usage: $0 FIJI_BIN ROOT_DIR [JOBS]}"
ROOT="${2:?usage: $0 FIJI_BIN ROOT_DIR [JOBS]}"
JOBS="${3:-4}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/minizero_process.sh"
LOGDIR="${LOGDIR:-$PWD/destripe_logs}"
mkdir -p "$LOGDIR"

# Per-job heap; several jobs run concurrently so keep it modest.
export FIJI_MEM="${FIJI_MEM:-16g}"

run_one() {
    local raw="$1"
    local dir name log
    dir="$(dirname "$raw")"
    name="$(basename "$raw")"; name="${name%_raw.avi}"
    log="$LOGDIR/${name}.log"

    if [[ -s "$dir/${name}_destripe.avi" ]]; then
        echo "SKIP (exists)  $dir/${name}_destripe.avi"
        return 0
    fi

    echo "START  $name"
    if "$RUNNER" "$FIJI_BIN" "$raw" "$dir" "$name" >"$log" 2>&1; then
        echo "OK     $name  -> $dir/${name}_destripe.avi"
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
status=$?

if [[ $status -ne 0 ]]; then
    echo "Batch finished with failures (see FAIL lines above)."
    exit 1
fi
echo "Batch finished."
