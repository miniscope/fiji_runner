# Preprocessing for Miniscope Zero 1P calcium imaging

Two steps, run in order. The output of step 2 goes straight into motion
correction / source extraction (minian) — no preprocessing there.

## Setup

You need, once:

- [Fiji](https://fiji.sc/) (step 1) — any recent download; the macro runs
  headless, no plugins beyond the stock install.
- `ffmpeg`/`ffprobe` on PATH (step 2), e.g. `apt install ffmpeg` /
  `brew install ffmpeg`.
- Python ≥ 3.9 with the packages in `requirements.txt`, ideally in a
  virtual environment:

```bash
git clone -b new_preprocessing https://github.com/miniscope/miniscope_preproc
cd miniscope_preproc
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 1. Fiji runner: destripe (FFT stripe removal)
```bash
./minizero_process.sh /path/to/Fiji.app/ImageJ-linux64 INPUT_FILE OUTDIR NAME [EXTRA_MACRO_ARGS]
```

- `INPUT_FILE`: video file (currently tested only with `mio` generated `.avi` files)
- Writes `{OUTDIR}/{NAME}_destripe.avi` (+ `{NAME}_destripe_sub{step}.avi` JPEG preview, default `_sub20`, `{NAME}_raw.avi` copy)
- Only step: `run("Bandpass Filter...", "filter_large=100000 filter_small=0 suppress=Horizontal tolerance=1 process");`

Removes the horizontal readout stripes with ImageJ's FFT Bandpass Filter,
used purely as a directional stripe suppressor: `filter_large` huge +
`filter_small=0` hold the bandpass wide open so only the directional
suppression acts, and with `autoscale`/`saturate` omitted the pixel values
keep their original scale (the range narrows slightly as stripe energy is
removed). All other preprocessing happens in step 2.

Two effects inherent to the method: stripe suppression also attenuates smooth
large-scale gradients perpendicular to the stripes, and the FFT's power-of-2
zero-padding shifts the frame mean by ~2%.

`EXTRA_MACRO_ARGS` is a `;`-separated override list, e.g.
`'tolerance=5;suppress=Vertical;step=10'`; see the header of
`minizero_process.ijm` for all keys. `step` sets the preview frame step and
names its file (`step=10` → `_destripe_sub10.avi`); the full `_destripe.avi`
is unaffected by it.

`_destripe.avi` is written to a temp name (`_destripe.part.avi`) and renamed
only after everything succeeded, so an interrupted run never leaves a partial
file that looks finished.

Reprocessing an existing `{NAME}_raw.avi` in place is supported — the runner
skips the raw copy when the input already is that file.

Set `FIJI_MEM` (e.g. `FIJI_MEM=16g`) to cap the JVM heap; unset uses Fiji's own
default.

### Batch over a whole tree
```bash
./minizero_process_batch.sh /path/to/Fiji.app/ImageJ-linux64 ROOT_DIR [JOBS]
```

Walks `ROOT_DIR` for every `<NAME>_raw.avi` and writes the step-1 outputs next
to it. `JOBS` (default 4) is how many Fiji instances run at once; `FIJI_MEM`
(default `16g`) is the per-job heap, kept modest because the jobs run
concurrently. Logs go to `$LOGDIR` (default `./destripe_logs`).

Inputs whose `_destripe.avi` already exists are skipped, so re-running is cheap
and safe — it doubles as a check that every `_raw.avi` has been processed
(interrupted runs only leave `_destripe.part.avi`, which is never mistaken for
a finished output). Exits nonzero if any job failed.

## 2. Python: minizero_preprocess.py
Pedestal correction -> min-projection subtraction -> gaussian despeckle ->
tophat background removal -> linear gain. Streams in three passes, so memory
stays flat regardless of recording length. Same script for every animal.
```bash
python minizero_preprocess.py NAME_destripe.avi NAME_destripe_proc.avi --sigma 0.6 --tophat 8 --gain 2.5
```

- Dependencies: see Setup above (`tifffile` is only needed for 16-bit TIFF output)
- Pin `--gain` per dataset (never `auto` across a batch); see `--help` for all options
