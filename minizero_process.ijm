// minizero_process.ijm
// FFT bandpass (incl. horizontal-stripe suppression) ONLY — all further
// preprocessing moved to minizero_preprocess.py.
// Runs in GUI and headless (pyimagej).
// RAW full output + JPEG sub20 preview.
//
// Usage:
//   ImageJ-linux64 --headless -macro minizero_process.ijm "input=/path/in.avi;outdir=/path/out;name=NAME"

setBatchMode(true);

args = getArgument();
inputPath = getArgValue(args, "input");
outdir    = getArgValue(args, "outdir");
name      = getArgValue(args, "name");

if (inputPath=="" || outdir=="" || name=="") {
    exit("Missing args. Need: input=...; outdir=...; name=...");
}

File.makeDirectory(outdir);

outFft   = pathJoin(outdir, name + "_fftonly.avi");
outFft20 = pathJoin(outdir, name + "_fftonly_sub20.avi");

// Open the input
open(inputPath);
origTitle = getTitle();
origID = getImageID();

// Duplicate virtual stack into memory
run("Duplicate...", "title=" + origTitle + "_work duplicate");
workID = getImageID();

// Close original
selectImage(origID);
close();

selectImage(workID);

// Bandpass filter — the only processing step in Fiji
run("Bandpass Filter...",
    "filter_large=150 filter_small=1 suppress=Horizontal tolerance=1 autoscale process");

// Save full stack as RAW AVI (Compression=None)
saveAVI_none20ByID(workID, outFft);

// sub20 preview (1 out of 20 frames) as JPEG AVI
selectImage(workID);
n = nSlices();
run("Make Substack...", "slices=1-" + n + "-20");
sub20ID = getImageID();
saveAVI_jpeg20ByID(sub20ID, outFft20);

// Cleanup
selectImage(sub20ID); close();
selectImage(workID); close();

print("Done. Wrote:");
print("  " + outFft + " (RAW)");
print("  " + outFft20 + " (JPEG)");

// Exit cleanly
run("Close All");
eval("script", "System.exit(0);");

// ---- Helpers ----

// From your Macro Recorder (Compression=None, Frame Rate=20).
// Keep "AVI... " (with trailing space).
function saveAVI_none20ByID(id, outPath) {
    cur = getImageID();
    selectImage(id);
    run("AVI... ", "compression=None frame=20 save=" + outPath);
    selectImage(cur);
}

// From your Macro Recorder (Compression=JPEG, Frame Rate=20).
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

function pathJoin(dir, leaf) {
    sep = File.separator;
    if (endsWith(dir, sep)) return dir + leaf;
    else return dir + sep + leaf;
}
