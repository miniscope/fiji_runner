# Fiji runner for 1P Calcium imaging

## Usage
```bash
./minizero_process.sh /path/to/Fiji.app/ImageJ-linux64 INPUT_FILE OUTDIR NAME
```

- `INPUT_FILE`: Video file (currently tested only with `mio` generated `.avi` files)
- `OUTDIR`, `NAME`: The exports will be {OUTDIR}/{NAME}_{PROCESSING_TYPE}

## Steps
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
