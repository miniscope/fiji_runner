# Preprocessing for Miniscope Zero 1P calcium imaging

Two steps, run in order. The output of step 2 goes straight into motion
correction / source extraction (minian) — no preprocessing there.

## 1. Fiji runner: FFT bandpass only
```bash
./minizero_process.sh /path/to/Fiji.app/ImageJ-linux64 INPUT_FILE OUTDIR NAME
```

- `INPUT_FILE`: video file (currently tested only with `mio` generated `.avi` files)
- Writes `{OUTDIR}/{NAME}_fftonly.avi` (+ `{NAME}_fftonly_sub20.avi` JPEG preview, `{NAME}_raw.avi` copy)
- Only step: `run("Bandpass Filter...", "filter_large=150 filter_small=1 suppress=Horizontal tolerance=1 autoscale process");`

## 2. Python: minizero_preprocess.py
Pedestal correction -> min-projection subtraction -> gaussian despeckle ->
tophat background removal -> linear gain. Streams in three passes, so memory
stays flat regardless of recording length. Same script for every animal.
```bash
python minizero_preprocess.py NAME_fftonly.avi NAME_fftonly_proc.avi --sigma 0.6 --tophat 8 --gain 2.5
```

- Requires `numpy`, `opencv-python`, `scikit-image` and `ffmpeg` on PATH
- Pin `--gain` per dataset (never `auto` across a batch); see `--help` for all options
