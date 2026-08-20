# Fiji runner for 1P Calcium imaging

## Full pipeline

### Usage
```bash
./minizero_process.sh /path/to/Fiji.app/ImageJ-linux64 INPUT_FILE OUTDIR NAME
```

- `INPUT_FILE`: Video file (currently tested only with `mio` generated `.avi` files)
- `OUTDIR`, `NAME`: The exports will be {OUTDIR}/{NAME}_{PROCESSING_TYPE}

### Steps
To do: Write more details

- Bandpass filter + autoscale
  - `run("Bandpass Filter...", "filter_large=150 filter_small=1 suppress=Horizontal tolerance=1 autoscale process");`
- 3D Gaussian blur
  - `run("Gaussian Blur 3D...", "x=1 y=1 z=1");`
- Bleach correction
  - `run("Bleach Correction", "correction=[Histogram Matching]");`
- Substack (for `_*20`)
  - `run("Make Substack...", "slices=1-" + n + "-20");`
- Background subtraction (for `*_bg*`)

## Stripe removal only

Just the first step of the pipeline: FFT stripe suppression, nothing else.
No structure filtering, no autoscale/saturate, no blur, no bleach correction,
no background subtraction — intensities are left as-is.

### Usage
```bash
./minizero_fftonly.sh /path/to/Fiji.app/ImageJ-linux64 INPUT_FILE OUTDIR NAME [EXTRA_MACRO_ARGS]
```

Outputs `{OUTDIR}/{NAME}_fftonly.avi` (full stack, uncompressed) and
`{OUTDIR}/{NAME}_fftonly_sub20.avi` (every 20th frame, JPEG).

### Step
- `run("Bandpass Filter...", "filter_large=100000 filter_small=0 suppress=Horizontal tolerance=1 process");`
  - `filter_large` huge + `filter_small=0` leaves the bandpass wide open, so no
    structure filtering happens. Verified pixel-exact identity with
    `suppress=None`, i.e. stripe suppression is the only operation.
  - `autoscale` / `saturate` are deliberately omitted so intensities are not
    renormalized.
  - Note: horizontal-stripe suppression zeroes a wedge around the vertical
    frequency axis, so smooth large-scale vertical gradients are attenuated too.
    That is inherent to FFT stripe removal, not a side effect of the settings.

`EXTRA_MACRO_ARGS` is a `;`-separated override list, e.g.
`'tolerance=5;suppress=Vertical;step=10'`. Set `FIJI_MEM=32g` to change the JVM heap
(default `64g`).

### Batch over a whole tree
```bash
./minizero_fftonly_batch.sh /path/to/Fiji.app/ImageJ-linux64 ROOT_DIR [JOBS]
```

Walks `ROOT_DIR` for every `<NAME>_raw.avi` and writes `<NAME>_fftonly.avi` /
`<NAME>_fftonly_sub20.avi` next to it. `JOBS` (default 4) is how many Fiji
instances run at once; `FIJI_MEM` (default `16g`) is the per-job heap, kept
modest because the jobs run concurrently. Logs go to `$LOGDIR` (default
`./fftonly_logs`).

Inputs whose `_fftonly.avi` already exists are skipped, so re-running is cheap
and safe — it doubles as a check that every `_raw.avi` has been processed.
