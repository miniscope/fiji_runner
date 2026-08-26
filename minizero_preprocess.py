#!/usr/bin/env python3
"""
Complete preprocessing for wireless Miniscope Zero recordings.

    pedestal correction -> min-projection subtraction -> gaussian despeckle
                        -> tophat background removal

Input is the Fiji `_fftonly` output (bandpass / horizontal-stripe suppression
stays in Fiji). The output is ready for motion correction and source
extraction directly - no further background handling is assumed downstream.
Streams in three passes so memory stays flat regardless of recording length.

    python minizero_preprocess.py IN.avi OUT.avi
    python minizero_preprocess.py IN_DIR OUT_DIR --skip-existing
"""
import argparse, subprocess, sys
from pathlib import Path

import cv2
import numpy as np


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,nb_frames,r_frame_rate",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True).stdout.split()
    w, h = int(out[0]), int(out[1])
    num, den = out[2].split("/")
    fps = float(num) / float(den)
    nframes = int(out[3]) if len(out) > 3 and out[3].isdigit() else None
    return w, h, fps, nframes


def frames(path, w, h, chunk=500):
    """Yield (nchunk, h, w) uint8 blocks."""
    fr = w * h
    p = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo",
         "-pix_fmt", "gray", "-"], stdout=subprocess.PIPE, bufsize=1 << 27)
    try:
        while True:
            buf = p.stdout.read(fr * chunk)
            if not buf:
                break
            k = len(buf) // fr
            if k == 0:
                break
            yield np.frombuffer(buf[:k * fr], np.uint8).reshape(k, h, w)
    finally:
        p.stdout.close()
        p.wait()


def process(src, dst, sigma=0.6, tophat=8, gain=None, fmt=None, qc=True,
            verbose=True):
    src, dst = Path(src), Path(dst)
    if fmt is None:
        fmt = "avi8" if dst.suffix.lower() == ".avi" else "tif16"
    if gain is None:
        gain = 4.0
    w, h, fps, _ = probe(src)
    log = (lambda *a: print(*a, flush=True)) if verbose else (lambda *a: None)
    log(f"[{src.name}] {w}x{h} @ {fps:g} Hz | {fmt} gain={gain}")

    # ---- pass 1: per-frame medians -------------------------------------
    # The charging noise is an additive, whole-frame offset that is WHITE in
    # time, so no temporal filter can remove it - only per-frame normalisation.
    # Median (not mean) so sparse calcium transients survive.
    med = []
    for blk in frames(src, w, h):
        med.append(np.median(blk.reshape(len(blk), -1), axis=1))
    fmed = np.concatenate(med).astype(np.float32)
    gmed = float(np.median(fmed))
    n = len(fmed)
    log(f"  frames {n} | global median {gmed:.1f} | "
        f"frame-median range {np.ptp(fmed):.1f} counts")

    # ---- pass 2: min projection of the pedestal-corrected movie ---------
    # Pass 1 must come first: without the pedestal correction every pixel
    # attains its minimum in the same globally-dimmest frame, and the min
    # projection collapses into a copy of that one frame.
    minproj = np.full((h, w), np.inf, np.float32)
    # Keep a spread of ~800 pedestal-corrected frames so the output range can
    # be estimated once minproj is final - this makes --gain auto free rather
    # than needing another read pass.
    step = max(1, n // 800)
    sub, i = [], 0
    for blk in frames(src, w, h):
        k = len(blk)
        cor = blk.astype(np.float32) - fmed[i:i + k, None, None] + gmed
        np.minimum(minproj, cor.min(0), out=minproj)
        sel = np.nonzero(np.arange(i, i + k) % step == 0)[0]
        if len(sel):
            sub.append(cor[sel].copy())
        i += k
    log(f"  min projection {minproj.min():.1f} - {minproj.max():.1f}")

    # ---- pass 3: apply and write ---------------------------------------
    # Subtracting the per-pixel minimum in SENSOR coordinates (i.e. before
    # motion correction) is the only ordering in which the static glow and
    # fixed-pattern noise cancel exactly instead of being smeared by the
    # displacement trajectory.
    #
    # The min projection is static, so it cannot remove the time-varying
    # out-of-focus background (~22% of temporal variance here). That is what
    # the tophat is for: with 6 px FWHM somata, disk radius 8 retains 94% of
    # soma amplitude while cutting background variance ~12x.
    ker = None
    if tophat:
        from skimage.morphology import disk
        ker = disk(tophat).astype(np.uint8)
    else:
        log("  NOTE: tophat disabled - time-varying background is NOT removed")

    def chain(a):
        """gaussian + tophat, the scale-affecting part of the pipeline."""
        if sigma:
            a = np.stack([cv2.GaussianBlur(f, (0, 0), sigma) for f in a])
        if ker is not None:
            a = np.stack([cv2.morphologyEx(f, cv2.MORPH_TOPHAT, ker) for f in a])
        return a

    vlim = 65535 if fmt == "tif16" else 255
    est = float(chain(np.concatenate(sub) - minproj).max())
    del sub
    if gain == "auto":
        # Per-recording gain. Convenient for a one-off, but do NOT use it
        # across a dataset: absolute-intensity parameters downstream
        # (seeds_init diff_thres, sparse_penal) would then mean something
        # different in every recording. Pin a constant instead.
        gain = (0.88 * vlim / est) if est > 0 else 1.0
        log(f"  auto gain: sampled max {est:.1f} -> gain {gain:.2f}")
        log("  NOTE: auto gain varies per recording - pin --gain for a batch")
    else:
        # Headroom check against the ~800 sampled frames. The true max lies
        # above this, so warn well before the ceiling rather than at it.
        proj = est * gain
        frac = proj / vlim
        log(f"  sampled max {est:.1f} x gain {gain:g} = {proj:.0f}"
            f" ({100 * frac:.0f}% of {vlim})")
        if frac > 1.0:
            log(f"  ** CLIPPING: sampled max already exceeds {vlim}."
                f" Re-run with --gain {0.8 * vlim / est:.1f} or lower **")
        elif frac > 0.85:
            log(f"  ** WARNING: only {100 * (1 - frac):.0f}% headroom left."
                f" Unsampled transients are likely to clip."
                f" Consider --gain {0.8 * vlim / est:.1f} **")

    # Minian's load_videos dispatches on extension and requires exactly ".tif"
    # (not ".tiff"); _load_tif_lazy preserves dtype, so uint16 survives.
    #
    # Classic TIFF, never BigTIFF: ImageJ1's built-in TiffDecoder cannot read
    # BigTIFF. Recordings that would exceed the 4 GB classic limit are split
    # into _000, _001, ... files; load_videos natsorts and concatenates them,
    # and each part opens normally in ImageJ.
    if fmt == "tif16":
        from tifffile import TiffWriter
        dtype = np.uint16
        max_fr = max(1, int(3_500_000_000 // (w * h * 2)))
        st = {"w": None, "k": 0, "cnt": 0, "files": []}
        if n > max_fr:
            log(f"  splitting into {-(-n // max_fr)} parts of <= {max_fr} frames")

        def emit(a):
            j = 0
            while j < len(a):
                if st["w"] is None:
                    p = (dst if n <= max_fr
                         else dst.with_name(f"{dst.stem}_{st['k']:03d}.tif"))
                    st["w"] = TiffWriter(str(p), bigtiff=False)
                    st["files"].append(p)
                take = min(len(a) - j, max_fr - st["cnt"])
                st["w"].write(a[j:j + take], contiguous=True,
                              photometric="minisblack")
                st["cnt"] += take
                j += take
                if st["cnt"] >= max_fr:
                    st["w"].close()
                    st["w"], st["cnt"] = None, 0
                    st["k"] += 1

        def finish():
            if st["w"] is not None:
                st["w"].close()
    else:
        dtype = np.uint8
        enc = subprocess.Popen(
            ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "gray",
             "-s", f"{w}x{h}", "-r", f"{fps:g}", "-i", "-",
             "-c:v", "rawvideo", "-pix_fmt", "gray", str(dst)],
            stdin=subprocess.PIPE)
        emit = lambda a: enc.stdin.write(a.tobytes())

        def finish():
            enc.stdin.close(); enc.wait()

    i, vmax, clipped = 0, 0.0, 0
    for blk in frames(src, w, h):
        k = len(blk)
        cor = blk.astype(np.float32) - fmed[i:i + k, None, None] + gmed
        cor -= minproj
        cor = chain(cor)
        # A linear gain is a constant scaling: it does not change any relative
        # measurement, but it keeps quantisation well below the shot noise.
        # NOTE: absolute-intensity parameters downstream must be scaled to
        # match (e.g. Minian's seeds_init diff_thres); ratio-based ones
        # (min_pnr, thres_corr) are unaffected.
        if gain != 1.0:
            cor = cor * gain
        vmax = max(vmax, float(cor.max()))
        clipped += int((cor > vlim).sum())
        emit(np.clip(cor, 0, vlim).astype(dtype))
        i += k
    finish()
    log(f"  output max {vmax:.1f} of {vlim}" +
        (f"  WARNING {clipped} px clipped" if clipped else ""))

    if qc:
        np.save(dst.with_name(dst.stem + "_minproj.npy"), minproj)
        np.savetxt(dst.with_name(dst.stem + "_qc_medians.csv"),
                   np.c_[np.arange(1, n + 1), fmed],
                   fmt="%d,%.3f", header="frame,median_raw", comments="")
    log(f"  wrote {dst}")
    return dict(n=n, gmed=gmed, flicker_ptp=float(np.ptp(fmed)), vmax=vmax)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="video file or directory of *.avi")
    ap.add_argument("output", help="output file or directory")
    ap.add_argument("--sigma", type=float, default=0.6,
                    help="gaussian despeckle sigma, 0 disables (default 0.6)")
    ap.add_argument("--tophat", type=int, default=8,
                    help="tophat disk radius (default 8; must exceed the soma "
                         "radius, ~3 px here). 0 disables background removal")
    ap.add_argument("--format", choices=["avi8", "tif16"], default="avi8",
                    help="output format (default avi8: 8-bit raw AVI. "
                         "tif16 = 16-bit TIFF, split at 4 GB)")
    ap.add_argument("--gain", default="4",
                    help="linear scaling before quantisation (default 4). "
                         "Keep this FIXED across a dataset so absolute-intensity "
                         "parameters downstream stay comparable. 'auto' picks "
                         "per-recording - fine for a one-off, not for a batch")
    ap.add_argument("--no-qc", action="store_true")
    ap.add_argument("--skip-existing", action="store_true")
    a = ap.parse_args()
    if a.gain != "auto":
        a.gain = float(a.gain)

    ext = ".tif" if a.format == "tif16" else ".avi"
    src = Path(a.input)
    if src.is_dir():
        out = Path(a.output); out.mkdir(parents=True, exist_ok=True)
        files = sorted(f for f in src.rglob("*.avi")
                       if not f.stem.endswith(("_proc", "_sub20")))
        if not files:
            sys.exit(f"no .avi found under {src}")
        for f in files:
            dst = out / f"{f.stem}_proc{ext}"
            if a.skip_existing and dst.exists():
                print(f"[skip] {f.name}"); continue
            process(f, dst, a.sigma, a.tophat, a.gain, a.format, not a.no_qc)
    else:
        dst = Path(a.output)
        dst.parent.mkdir(parents=True, exist_ok=True)
        process(src, dst, a.sigma, a.tophat, a.gain, a.format, not a.no_qc)


if __name__ == "__main__":
    main()
