@echo off
rem  CHIMERA - Russian corpus auto-transcription (faster-whisper, language ru).
rem
rem  USAGE:
rem    1. Drag the corpus folder ONTO this file   (default: <repo>\corpus\ru)
rem    2. Or run:  ru-transcribe.bat "I:\chemera\corpus\ru"
rem    3. Double-clicking prints this help.
rem
rem  Everything stays inside the project folder: the venv lives in
rem  .tools\whisper-venv, pip runs with --no-cache-dir, the HF model cache goes
rem  to .tools\hf. Nothing installs system-wide or on drive C:.
rem  Downloads: faster-whisper + deps (~600 MB-1 GB) once, then the model once
rem  (small ~0.5 GB / medium ~1.5 GB / large-v3 ~3 GB).
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "TOOLS_DIR=%CD%\.tools"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
set "VENV_DIR=%TOOLS_DIR%\whisper-venv"
set "VP=%VENV_DIR%\Scripts\python.exe"
set "HF_HOME=%TOOLS_DIR%\hf"
set PY=

echo.
echo  CHIMERA - Russian corpus transcription
echo  =====================================

if "%~1"=="" goto usage
set "DST=%~1"
if not exist "%DST%" goto bad_dst
if not exist "%DST%\sentences.tsv" goto bad_dst

rem --- 1) Python to bootstrap the venv --------------------------------------
call :try_system_py
if defined PY goto py_ok
echo    [error] No usable Python 3 found. Install Python from https://www.python.org/downloads/
echo    (tick "Add python.exe to PATH") and re-run, or install the Microsoft Store build.
pause
exit /b 1
:py_ok
echo    using python: %PY%

rem --- 2) venv + faster-whisper ----------------------------------------------
if exist "%VP%" goto venv_ok
echo    creating venv in %VENV_DIR% ...
"%PY%" -m venv "%VENV_DIR%"
if errorlevel 1 goto venv_fail
:venv_ok
echo    venv: %VP%
echo    --- corpus status ---
"%VP%" tools\ru\transcribe.py --status
echo    ----------------------
if not exist "%VENV_DIR%\installed.txt" goto pip_install
echo    faster-whisper already installed (found installed.txt)
goto model_pick
:venv_fail
echo    [error] could not create the venv. If the Microsoft Store python is blocked,
echo    install python.org Python 3 with "Add to PATH" ticked and re-run.
pause
exit /b 1
:pip_install
echo    installing faster-whisper into the venv (progress below, Ctrl+C aborts) ...
"%VP%" -m pip install --no-cache-dir --upgrade pip
if errorlevel 1 goto pip_fail
"%VP%" -m pip install --no-cache-dir faster-whisper
if errorlevel 1 goto pip_fail
echo installed > "%VENV_DIR%\installed.txt"
goto model_pick
:pip_fail
echo    [error] pip failed. Scroll up for the real error (network/proxy?); re-run to retry.
pause
exit /b 1

rem --- 3) model + run ----------------------------------------------------------
:model_pick
echo.
echo    Pick a model (bigger = better Russian, slower on CPU):
echo      [S] small    ~0.5 GB, fastest
echo      [M] medium   ~1.5 GB, good default
echo      [L] large-v3 ~3 GB, best
choice /c SML /n /m "    Your choice [S/M/L]: "
if errorlevel 3 (set "MODEL=large-v3" & goto model_picked)
if errorlevel 2 (set "MODEL=medium" & goto model_picked)
set "MODEL=small"
:model_picked
echo    model: %MODEL% (downloads on first run, into .tools\hf)
echo.
echo    running: %VP% tools\ru\transcribe.py --corpus "%DST%" --model %MODEL%
"%VP%" tools\ru\transcribe.py --corpus "%DST%" --model %MODEL%
if errorlevel 1 goto run_fail
echo.
echo  Done. Open corpus\ru\sentences.tsv and eyeball the texts (auto-transcripts are
echo  usually good on clean AI narration, but rare words need a human eye).
pause
exit /b 0

:run_fail
echo.
echo    [error] transcription crashed - the traceback above is the real error.
echo    sentences.tsv is checkpointed per file, so already-done rows are kept.
echo    send the traceback to the developer; nothing else to clean up.
pause
exit /b 1

:bad_dst
echo    [error] no corpus found at: %DST%
echo    expected a folder with sentences.tsv inside (drag corpus\ru onto this file).
pause
exit /b 1

:usage
echo  How to use:
echo.
echo  1. Drag your corpus folder (the one containing sentences.tsv, e.g. %CD%\corpus\ru)
echo     ONTO this file, or
echo  2. Run from a terminal:  ru-transcribe.bat "I:\chemera\corpus\ru"
echo.
echo  Creates .tools\whisper-venv with faster-whisper and downloads the chosen model
echo  into .tools\hf - both inside the project folder, nothing on drive C:.
pause
exit /b 0

rem  Find a system-wide python 3: PATH first, then the py launcher.
:try_system_py
for /f "usebackq delims=" %%i in (`where python 2^>nul`) do if not defined PY set "PY=%%i"
if not defined PY goto py_launcher
"%PY%" -c "import sys" >nul 2>nul
if not errorlevel 1 exit /b 0
set "PY="
:py_launcher
py -3 -c "import sys; print(sys.executable)" > "%TOOLS_DIR%\pypath.txt" 2>nul
if errorlevel 1 goto py_none
for /f "usebackq delims=" %%i in ("%TOOLS_DIR%\pypath.txt") do set "PY=%%i"
del "%TOOLS_DIR%\pypath.txt" >nul 2>nul
if not defined PY goto py_none
"%PY%" -c "import sys" >nul 2>nul
if not errorlevel 1 exit /b 0
set "PY="
:py_none
exit /b 0
