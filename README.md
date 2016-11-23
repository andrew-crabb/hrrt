11/22/16

Changing smoothing from motion_correct_recon to if2e7

Smoothing in either process adds '_2mm' to the file name
If '-g 0' is set in if2e7, it does not try to run gsmooth
if '-g 2' is set in if2e7, it tries to run 'gsmooth'.  But the executable is called 'gsmooth_ps'.  A symlink is required.
Will need several name changes through the program to accommodate the _2mm being added to each frame.i file (old way), or to the files produced by if2e7 (new, postsmooth way: m9p).

