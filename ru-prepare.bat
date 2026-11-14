@echo off
rem  CHIMERA - prepare the Russian corpus for alignment. Drag the corpus folder
rem  (the one containing sentences.tsv and wav\) onto this file, or pass it as an
rem  argument. Steps: 16 kHz mono conversion (PyAV, no ffmpeg download needed),
rem  then text normalization into sentences.mfa.tsv (sentences.tsv untouched).
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
set "TOOLS_DIR=%CD%\.tools"
set "VP=%TOOLS_DIR%\whisper-venv\Scripts\python.exe"

echo.
echo  CHIMERA - Russian corpus preparation
echo  ==================================

if "%~1"=="" goto usage
set "DST=%~1"
if not exist "%DST%\sentences.tsv" goto bad_dst
if not exist "%DST%\wav" goto bad_dst
if not exist "%VP%" goto no_venv

echo    [1/2] 16 kHz mono WAV into %DST%\wav16k  (skip: files already there) ...
"%VP%" tools\ru\convert16k.py --corpus "%DST%"
if errorlevel 1 goto step_fail
echo.
echo    [2/2] digits/symbols -^> Russian words into %DST%\sentences.mfa.tsv ...
"%VP%" tools\ru\normalize.py --corpus "%DST%"
if errorlevel 1 goto step_fail
echo.
echo  Done: %DST%\wav16k\ and %DST%\sentences.mfa.tsv
echo  sentences.tsv is untouched. Next: MFA with the Russian MFA model v3.1.0
echo  (see tools/ru/README.md).
pause
exit /b 0

:no_venv
echo    [error] .tools\whisper-venv not found. Run ru-transcribe.bat once first
echo    (it creates the venv with PyAV inside), then re-run this file.
pause
exit /b 1

:step_fail
echo.
echo    [error] a step failed - see the output above and send it to the developer.
pause
exit /b 1

:bad_dst
echo    [error] not a corpus folder (expected sentences.tsv and wav\ inside): %DST%
pause
exit /b 1

:usage
echo  How to use:
echo    1. Drag your corpus folder (the one with sentences.tsv and wav\) ONTO this file, or
echo    2. Run from a terminal:  ru-prepare.bat "I:\chemera\corpus\ru"
echo.
echo  Writes wav16k\ (16 kHz mono, for MFA) and sentences.mfa.tsv (normalized text).
echo  Never modifies sentences.tsv.
pause
exit /b 0
