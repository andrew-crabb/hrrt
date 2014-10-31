REM In the next lines, we must cd to the local folder where .l64 is (very important; so change for each study)

cd D:\SCS_Scans\Norm_Scan

pause

REM lmhistogram %1 -o D:\SCS_Scans\Norm_Scan\norm.s -span 3 -notimetag

REM compute_norm D:\SCS_Scans\Norm_Scan\norm.s -o D:\SCS_Scans\Norm_Scan\norm.n -span 3

norm_process %1 -s 3,67 -o D:\SCS_Scans\Norm_Scan\norm_CBN_span3.n
norm_process %1 -s 9,67 -o D:\SCS_Scans\Norm_Scan\norm_CBN_span9.n

pause


REM
REM IGNORE COMMENTS BELOW
REM

REM norm_process %1 
REM -s 9,67 -o test -v 
REM -s 3,67 

REM To do above: one needs to first histogram .l64 into span3, 
then run standard compute_norm to generate 
intermediate .dat files (even if it fails afterwards 
as it can't write temporary files), 
and then run norm_process on the original list-mode file 
(on this computer .ce file is generated, 
but the resulting .n file MAY look smaller than  
what it's supposed to be; so take the .dat files and the .ce file 
and process upstairs using both span3 and span9 options using norm_process!!

pause
