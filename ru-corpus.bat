@echo off
rem  CHIMERA - Russian reference corpus intake.
rem
rem  USAGE (no typing needed):
rem    1. Drag your folder of audio onto ru-corpus.bat  (corpus goes to <repo>\corpus\ru)
rem    2. Or run:  ru-corpus.bat "I:\path\to\audio" "G:\datasets\ru"   (destination optional)
rem    3. Double-clicking shows this help.
rem
rem  Nothing installs to drive C: - portable Python (.tools\python) and portable ffmpeg
rem  (.tools\ffmpeg) are downloaded there only if missing, and only if you say yes.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "TOOLS_DIR=%CD%\.tools"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
set CONV=0
set FFMPEG=
set PY=

echo.
echo  CHIMERA - Russian corpus intake
echo  ===============================

if "%~1"=="" goto usage
set "SRC=%~1"
if not exist "%SRC%" goto bad_src
set "DST=%~2"
if not defined DST set "DST=%CD%\corpus\ru"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
if "%DST:~-1%"=="\" set "DST=%DST:~0,-1%"
if /i "%DST%"=="%SRC%" goto dst_inside
set "DST_CHK=%DST%\"
if /i not "%DST_CHK:*%SRC%\=%"=="%DST_CHK%" goto dst_inside
goto dst_ok

:dst_inside
echo    [warn] destination would live INSIDE your audio folder - using the default instead.
set "DST=%CD%\corpus\ru"
if /i "%DST%"=="%SRC%" goto dst_refused
set "DST_CHK=%DST%\"
if /i not "%DST_CHK:*%SRC%\=%"=="%DST_CHK%" goto dst_refused
goto dst_ok

:dst_refused
echo    [error] the source folder swallows the default corpus location; pass a destination outside of it.
pause
exit /b 1

:dst_ok
echo    source : %SRC%
echo    corpus : %DST%

rem --- 1) Python ----------------------------------------------------------
if exist "%TOOLS_DIR%\python\python.exe" set "PY=%TOOLS_DIR%\python\python.exe"
if defined PY goto py_ok
call :try_system_py
if defined PY goto py_ok
echo    No Python 3 found. I can install a portable copy into %TOOLS_DIR%\python
echo    (~11 MB, no admin, drive C: untouched).
choice /c YN /n /m "    Download Python 3.12.10 now? [Y/N] "
if errorlevel 2 goto py_missing
echo    downloading python-3.12.10-embed-amd64.zip (~11 MB, usually seconds) ...
where curl.exe >nul 2>nul
if errorlevel 1 goto py_dl_ps
curl.exe -L --connect-timeout 10 --max-time 300 --progress-bar -o "%TOOLS_DIR%\python-embed.zip" https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip
if errorlevel 1 goto py_fail
goto py_expand
:py_dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip' -OutFile '%TOOLS_DIR%\python-embed.zip'"
if errorlevel 1 goto py_fail
:py_expand
if exist "%TOOLS_DIR%\python" rmdir /s /q "%TOOLS_DIR%\python"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force -Path '%TOOLS_DIR%\python-embed.zip' -DestinationPath '%TOOLS_DIR%\python'"
if errorlevel 1 goto py_fail
del "%TOOLS_DIR%\python-embed.zip"
set "PY=%TOOLS_DIR%\python\python.exe"
if not exist "%PY%" goto py_fail
goto py_ok
:py_fail
echo    [error] could not set up portable Python. Install Python 3 from https://www.python.org/downloads/ and re-run.
pause
exit /b 1
:py_missing
echo    Without Python the intake cannot run. Install Python 3 and re-run this file.
pause
exit /b 1
:py_ok
echo    using python: %PY%

rem --- 2) ffmpeg, only for 16 kHz conversion ------------------------------
where ffmpeg >nul 2>nul
if not errorlevel 1 set "FFMPEG=ffmpeg"
if exist "%TOOLS_DIR%\ffmpeg\bin\ffmpeg.exe" goto ff_have_local
goto ff_no_local
:ff_have_local
set "FFMPEG=%TOOLS_DIR%\ffmpeg\bin\ffmpeg.exe"
set "PATH=%TOOLS_DIR%\ffmpeg\bin;%PATH%"
goto ff_ready
:ff_no_local
if defined FFMPEG goto ff_ready
echo    ffmpeg NOT found. Needed only for the 16 kHz mono conversion for MFA;
echo    the basic intake works without it.
choice /c YN /n /m "    Download a portable ffmpeg into %TOOLS_DIR%\ffmpeg now? [Y/N] "
if errorlevel 2 goto conv_done
if exist "%TOOLS_DIR%\ffmpeg.zip" del /f "%TOOLS_DIR%\ffmpeg.zip"
echo    downloading ffmpeg (~100 MB - watch the progress bar; Ctrl+C aborts) ...
where curl.exe >nul 2>nul
if errorlevel 1 goto ff_dl_ps
curl.exe -L --connect-timeout 10 --max-time 900 --progress-bar -o "%TOOLS_DIR%\ffmpeg.zip" https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip
if errorlevel 1 goto ff_dl_ps_fallback
goto ff_expand
:ff_dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 900 -Uri 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile '%TOOLS_DIR%\ffmpeg.zip'"
if errorlevel 1 goto ff_dl_ps_fallback
goto ff_expand
:ff_dl_ps_fallback
echo    gyan.dev failed; trying the BtbN GitHub mirror ...
where curl.exe >nul 2>nul
if errorlevel 1 goto ff_mirror_ps
curl.exe -L --connect-timeout 10 --max-time 900 --progress-bar -o "%TOOLS_DIR%\ffmpeg.zip" https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip
if errorlevel 1 goto ff_fail
goto ff_expand
:ff_mirror_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 900 -Uri 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' -OutFile '%TOOLS_DIR%\ffmpeg.zip'"
if errorlevel 1 goto ff_fail
:ff_expand
if exist "%TOOLS_DIR%\ffmpeg-tmp" rmdir /s /q "%TOOLS_DIR%\ffmpeg-tmp"
if exist "%TOOLS_DIR%\ffmpeg" rmdir /s /q "%TOOLS_DIR%\ffmpeg"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force -Path '%TOOLS_DIR%\ffmpeg.zip' -DestinationPath '%TOOLS_DIR%\ffmpeg-tmp'"
if errorlevel 1 goto ff_fail
for /d %%d in ("%TOOLS_DIR%\ffmpeg-tmp\*") do move "%%d" "%TOOLS_DIR%\ffmpeg" >nul
rmdir /s /q "%TOOLS_DIR%\ffmpeg-tmp"
del "%TOOLS_DIR%\ffmpeg.zip"
if not exist "%TOOLS_DIR%\ffmpeg\bin\ffmpeg.exe" goto ff_fail
set "FFMPEG=%TOOLS_DIR%\ffmpeg\bin\ffmpeg.exe"
set "PATH=%TOOLS_DIR%\ffmpeg\bin;%PATH%"
goto ff_ready
:ff_fail
echo    [warn] could not set up portable ffmpeg; continuing WITHOUT 16 kHz conversion.
goto conv_done
:ff_ready
echo    using ffmpeg: %FFMPEG%
choice /c YN /n /m "    Convert the audio to 16 kHz mono WAV for MFA now? [Y/N] "
if errorlevel 2 goto conv_done
set CONV=1
:conv_done

rem --- 3) run the intake ---------------------------------------------------
echo.
if "%CONV%"=="1" goto run_conv
echo    running: %PY% tools\ru\intake.py --src "%SRC%" --dst "%DST%"
"%PY%" tools\ru\intake.py --src "%SRC%" --dst "%DST%"
goto run_end
:run_conv
echo    running: %PY% tools\ru\intake.py --src "%SRC%" --dst "%DST%" --convert
"%PY%" tools\ru\intake.py --src "%SRC%" --dst "%DST%" --convert
:run_end
echo.
echo  Done. Your corpus is in: %DST%
echo  Next: check sentences.tsv there (empty text = needs transcription), then see tools\ru\README.md
pause
exit /b 0

:bad_src
echo    [error] that folder does not exist: %SRC%
pause
exit /b 1

:usage
echo  No folder given. How to use:
echo.
echo  1. Drag your folder of audio ONTO this ru-corpus.bat file, or
echo  2. Run from a terminal:
echo       ru-corpus.bat "I:\химера\ru_voice"
echo       ru-corpus.bat "I:\химера\ru_voice" "G:\datasets\ru"   (destination optional)
echo.
echo  Corpus defaults to: %CD%\corpus\ru  (gitignored; raw audio never enters git)
pause
exit /b 0

rem  Find a system-wide python 3: py launcher first (most reliable on Windows), then PATH.
:try_system_py
for /f "usebackq delims=" %%i in (`where python 2^>nul`) do if not defined PY set "PY=%%i"
if not defined PY goto py_try_launcher
"%PY%" -c "import sys" >nul 2>nul
if not errorlevel 1 exit /b 0
set "PY="
:py_try_launcher
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
