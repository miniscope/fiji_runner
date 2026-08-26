// minizero_process.ijm
// Runs in GUI and headless (pyimagej).
// RAW full outputs + JPEG sub20 outputs.
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

outBleach   = pathJoin(outdir, name + ".avi");
outBleach20 = pathJoin(outdir, name + "_sub20.avi");
outBg       = pathJoin(outdir, name + "_bg.avi");
outBg20     = pathJoin(outdir, name + "_bg_sub20.avi");

// Open the input
open(inputPath);

// ---- ORIGINAL PIPELINE ----

origTitle = getTitle();
origID = getImageID();

// Duplicate virtual stack into memory
run("Duplicate...", "title=" + origTitle + "_work duplicate");
workID = getImageID();

// Close original
selectImage(origID);
close();

selectImage(workID);

// Bandpass filter
run("Bandpass Filter...",
    "filter_large=150 filter_small=1 suppress=Horizontal tolerance=1 autoscale process");

// 3D Gaussian blur
run("Gaussian Blur 3D...", "x=1 y=1 z=1");

// Bleach correction
run("Bleach Correction", "correction=[Histogram Matching]");
bleachID = getImageID();

// Save bleach corrected full stack as RAW AVI (Compression=None)
saveAVI_none20ByID(bleachID, outBleach);

// raw20 BEFORE background subtraction (1 out of 20 frames)
selectImage(bleachID);
n = nSlices();
run("Make Substack...", "slices=1-" + n + "-20");
raw20ID = getImageID();
rename(origTitle + "_raw20");

// Save bleach sub20 as JPEG AVI
saveAVI_jpeg20ByID(raw20ID, outBleach20);

// Background subtraction via min Z-projection
selectImage(bleachID);
run("Z Project...", "projection=[Min Intensity]");
minProjID = getImageID();

bleachTitle  = getTitleOfImage(bleachID);
minProjTitle = getTitleOfImage(minProjID);

selectImage(bleachID);
run("Image Calculator...",
    "image1=[" + bleachTitle + "] operation=Subtract image2=[" + minProjTitle + "] create 32-bit stack");
resultID = getImageID();

// Cleanup intermediates
selectImage(minProjID); close();
selectImage(bleachID); close();
selectImage(raw20ID); close();

// Display-only contrast
selectImage(resultID);
run("Enhance Contrast...", "saturated=0");
rename(origTitle + "_proc");

// Save bg full stack as RAW AVI
saveAVI_none20ByID(resultID, outBg);

// bg20 AFTER background subtraction (1 out of 20 frames)
selectImage(resultID);
n = nSlices();
run("Make Substack...", "slices=1-" + n + "-20");
bg20ID = getImageID();
rename(origTitle + "_bg20");

// Save bg sub20 as JPEG AVI
saveAVI_jpeg20ByID(bg20ID, outBg20);

// Cleanup
selectImage(bg20ID); close();
selectImage(resultID); close();

print("Done. Wrote:");
print("  " + outBleach + " (RAW)");
print("  " + outBleach20 + " (JPEG)");
print("  " + outBg + " (RAW)");
print("  " + outBg20 + " (JPEG)");

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

function getTitleOfImage(id) {
    cur = getImageID();
    selectImage(id);
    t = getTitle();
    selectImage(cur);
    return t;
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

