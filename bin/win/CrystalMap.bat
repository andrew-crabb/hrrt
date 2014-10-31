@echo off

REM If input is a .l64 file, then it creates corresponding *.v file 
REM and displays it
REM If input is a .v file, it displays it

set input=%1

if /I %input:~-2% EQU .v (
copy %input% CrystalMap.v
D:\CrystalMap\CrystalMap.vpx
)
if /I %input:~-4% EQU .l64 (
REM set CrystalMapOutput=%input%.v
REM set CrystalMapOutput=10
echo %input%.v
REM echo %CrystalMapOutput%
REM pause
D:\CrystalMap\CrystalMap.exe -i %1 -v -o CrystalMap.v -t 300
copy CrystalMap.v %input%.v
D:\CrystalMap\CrystalMap.vpx
)

pause