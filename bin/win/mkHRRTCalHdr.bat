REM This file takes a reconstructed phantom image and scales it so that the average value is an input by the -a option in Bq/cc which one 
REM should know from the calibration phantom: the rest are things not to be played with unless one has a good idea.
REM This file is only to be used once the scatter background parameters (ErgRatio... in GM328 have been tuned)
 
c:\cps\bin\mkHRRTCalHdr -a 1223.8 -e 6.67e-6 -p 66 -m 1 75 175 %1
pause 
