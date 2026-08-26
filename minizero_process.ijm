// minizero_process.ijm
// Step 1 of preprocessing: FFT stripe removal, and nothing else.
// Runs in GUI and headless (pyimagej).
//
// filter_large huge + filter_small=0 holds the bandpass wide open, so only
// the stripe suppression acts. autoscale/saturate are omitted so intensities
// are not renormalized.
//
// Usage:
//   ImageJ-linux64 --headless -macro minizero_process.ijm "input=/path/in.avi;outdir=/path/out;name=NAME"
//
// Optional args (defaults shown):
//   suppress=Horizontal   stripe direction to suppress (Horizontal|Vertical|None)
//   tolerance=1           tolerance of direction, %
//   filter_large=100000   large-structure cutoff; huge == no high-pass
//   filter_small=0        small-structure cutoff; 0 == no low-pass
//   step=20               frame step for the sub20 preview

setBatchMode(true);

args      = getArgument();
inputPath = getArgValue(args, "input");
outdir    = getArgValue(args, "outdir");
name      = getArgValue(args, "name");

if (inputPath=="" || outdir=="" || name=="") {
    exit("Missing args. Need: input=...; outdir=...; name=...");
}

suppress    = getArgValueOr(args, "suppress",     "Horizontal");
tolerance   = getArgValueOr(args, "tolerance",    "1");
filterLarge = getArgValueOr(args, "filter_large", "100000");
filterSmall = getArgValueOr(args, "filter_small", "0");
step        = parseInt(getArgValueOr(args, "step", "20"));

File.makeDirectory(outdir);

outFull = pathJoin(outdir, name + "_fftonly.avi");
outSub  = pathJoin(outdir, name + "_fftonly_sub20.avi");

// ---- Open ----
open(inputPath);
origTitle = getTitle();
origID    = getImageID();

// Bandpass Filter cannot write into a virtual stack; pull into RAM only if needed.
if (is("Virtual Stack")) {
    run("Duplicate...", "title=" + origTitle + "_work duplicate");
    workID = getImageID();
    selectImage(origID); close();
    selectImage(workID);
} else {
    workID = origID;
}

print("Input: " + inputPath);
print("Frames: " + nSlices() + "  " + getWidth() + "x" + getHeight() + "  bitDepth=" + bitDepth());

// ---- Stripe removal only ----
bpOpts = "filter_large=" + filterLarge +
         " filter_small=" + filterSmall +
         " suppress=" + suppress +
         " tolerance=" + tolerance +
         " process";
print("Bandpass Filter...: " + bpOpts);
run("Bandpass Filter...", bpOpts);

// ---- Save full stack (uncompressed) ----
saveAVI_none20ByID(workID, outFull);

// ---- Save 1-in-{step} preview (JPEG) ----
selectImage(workID);
n = nSlices();
run("Make Substack...", "slices=1-" + n + "-" + step);
subID = getImageID();
rename(origTitle + "_fftonly_sub" + step);
saveAVI_jpeg20ByID(subID, outSub);

selectImage(subID);  close();
selectImage(workID); close();

print("Done. Wrote:");
print("  " + outFull + " (RAW)");
print("  " + outSub + " (JPEG)");

// Exit cleanly
run("Close All");
eval("script", "System.exit(0);");

// ---- Helpers ----

// From the Macro Recorder (Compression=None, Frame Rate=20).
// Keep "AVI... " (with trailing space).
function saveAVI_none20ByID(id, outPath) {
    cur = getImageID();
    selectImage(id);
    run("AVI... ", "compression=None frame=20 save=" + outPath);
    selectImage(cur);
}

// From the Macro Recorder (Compression=JPEG, Frame Rate=20).
function saveAVI_jpeg20ByID(id, outPath) {
    cur = getImageID();
    selectImage(id);
    run("AVI... ", "compression=JPEG frame=20 save=" + outPath);
    selectImage(cur);
}

function getArgValue(argString, key) {
    keyEq = key + "=";
    parts = split(argString, ";");
    for (i=0; i<parts.length; i++) {
        p = trim(parts[i]);
        if (startsWith(p, keyEq)) return substring(p, lengthOf(keyEq));
    }
    return "";
}

function getArgValueOr(argString, key, fallback) {
    v = getArgValue(argString, key);
    if (v=="") return fallback;
    return v;
}

function pathJoin(dir, leaf) {
    sep = File.separator;
    if (endsWith(dir, sep)) return dir + leaf;
    else return dir + sep + leaf;
}
