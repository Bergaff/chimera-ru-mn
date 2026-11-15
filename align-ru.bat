@echo off
rem  CHIMERA - align the Russian corpus with MFA.
rem  USAGE: drag the corpus folder (it must contain sentences.mfa.tsv and wav16k\)
rem         onto this file, or: align-ru.bat "I:\path\corpus\ru"
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
set "MFA_DIR=%CD%\.tools\mfa"
set "ENV_DIR=%MFA_DIR%\env"
set "MAMBA_ROOT_PREFIX=%MFA_DIR%\root"
set "PIXI_CACHE_DIR=%CD%\.tools\pixi-cache"
set "MFA_ROOT_DIR=%MFA_DIR%\cache"
set "PIXI_HOME=%CD%\.tools\pixi"
set "TOOLS_DIR=%CD%\.tools"
set "VP=%TOOLS_DIR%\whisper-venv\Scripts\python.exe"
set "MFABIN="
set "MFAROUTE="

echo.
echo  CHIMERA - Russian corpus alignment (MFA)
echo  =======================================

if "%~1"=="" goto usage
set "DST=%~1"
if not exist "%DST%\sentences.mfa.tsv" goto bad_mfa
if not exist "%DST%\wav16k" goto bad_mfa

set "MFABIN="
if exist "%PIXI_HOME%\mfa-bin.txt" for /f "usebackq delims=" %%i in ("%PIXI_HOME%\mfa-bin.txt") do set "MFABIN=%%i"
if defined MFABIN if not exist "%MFABIN%" set "MFABIN="
if not defined MFABIN if exist "%PIXI_HOME%\bin\mfa.exe" set "MFABIN=%PIXI_HOME%\bin\mfa.exe"
if defined MFABIN set "MFAROUTE=pixi"
if not defined MFABIN if exist "%ENV_DIR%\Scripts\mfa.exe" (set "MFABIN=%ENV_DIR%\Scripts\mfa.exe" & set "MFAROUTE=micromamba")
if not defined MFABIN goto no_env
echo    mfa route: %MFAROUTE%  (%MFABIN%)

if exist "%VP%" goto py_ok
for /f "usebackq delims=" %%i in (`where python 2^>nul`) do (set "VP=%%i" & goto py_ok)
echo    [error] no python found for the alignment collector (whisper venv missing?).
pause
exit /b 1
:py_ok
echo    python (collector): %VP%

echo    [1/3] building the MFA corpus (one folder per utterance) ...
"%VP%" tools\ru\align.py prepare "%DST%" "%DST%\mfa\corpus"
if errorlevel 1 goto step_fail
echo.
echo    [2/3] mfa align (Russian acoustic model + dictionary; dither 0) ...
"%MFABIN%" align -q --clean -c "tools\ru\mfa.yaml" -j "%NUMBER_OF_PROCESSORS%" --output_format json "%DST%\mfa\corpus" russian_mfa russian_mfa "%DST%\mfa\aligned"
if errorlevel 1 goto step_fail
echo.
echo    [3/3] collecting word/phone tiers into tools\ru\alignment.tsv.gz ...
"%VP%" tools\ru\align.py collect "%DST%\mfa\aligned" "%DST%"
if errorlevel 1 goto step_fail
echo.
echo  Done. Derived alignment is at tools\ru\alignment.tsv.gz (safe to commit;
echo  contains no audio). Rows listed above as missing need eyeballing.
pause
exit /b 0

:no_env
echo    [error] MFA not installed yet. Run setup-ru.bat (double-click) OR
echo    setup-ru-pixi.bat (GitHub route, works where conda-forge is blocked).
pause
exit /b 1

:bad_mfa
echo    [error] not a prepared corpus folder (expected sentences.mfa.tsv and wav16k inside): %DST%
echo    run ru-prepare.bat on it first.
pause
exit /b 1

:step_fail
echo.
echo    [error] a step failed - see the output above and send it to the developer.
echo    if it smells like non-ASCII path trouble (I:\chemera...), see tools/ru/README.md
echo    for the subst trick (pure-ASCII drive mapped to this folder).
pause
exit /b 1

:usage
echo  How to use:
echo    1. Run setup-ru.bat once (or setup-ru-pixi.bat if conda-forge is blocked),
echo       then drag your corpus folder (with sentences.mfa.tsv and wav16k\) ONTO this file, or
echo    2. Run from a terminal:  align-ru.bat "I:\chemera\corpus\ru"
pause
exit /b 0
