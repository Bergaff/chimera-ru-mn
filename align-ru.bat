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
set "MFA_ROOT_DIR=%MFA_DIR%\cache"

echo.
echo  CHIMERA - Russian corpus alignment (MFA)
echo  =======================================

if "%~1"=="" goto usage
set "DST=%~1"
if not exist "%DST%\sentences.mfa.tsv" goto bad_mfa
if not exist "%DST%\wav16k" goto bad_mfa
if not exist "%ENV_DIR%\Scripts\mfa.exe" goto no_env

echo    [1/3] building the MFA corpus (one folder per utterance) ...
"%ENV_DIR%\Scripts\python.exe" tools\ru\align.py prepare "%DST%" "%DST%\mfa\corpus"
if errorlevel 1 goto step_fail
echo.
echo    [2/3] mfa align (Russian acoustic model + dictionary; dither 0) ...
call "%ENV_DIR%\Scripts\activate.bat" >nul
mfa align -q --clean -c "tools\ru\mfa.yaml" -j "%NUMBER_OF_PROCESSORS%" --output_format json "%DST%\mfa\corpus" russian_mfa russian_mfa "%DST%\mfa\aligned"
if errorlevel 1 goto step_fail
echo.
echo    [3/3] collecting word/phone tiers into tools\ru\alignment.tsv.gz ...
"%ENV_DIR%\Scripts\python.exe" tools\ru\align.py collect "%DST%\mfa\aligned" "%DST%"
if errorlevel 1 goto step_fail
echo.
echo  Done. Derived alignment is at tools\ru\alignment.tsv.gz (safe to commit;
echo  contains no audio). Rows listed above as missing need eyeballing.
pause
exit /b 0

:no_env
echo    [error] MFA env not found in .tools\mfa - run setup-ru.bat first (double-click it).
pause
exit /b 1

:bad_mfa
echo    [error] not a prepared corpus folder (expected sentences.mfa.tsv and wav16k\
 inside): %DST%
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
echo    1. Run setup-ru.bat once (double-click) to install MFA into .tools\mfa, then
echo    2. Drag your corpus folder (with sentences.mfa.tsv and wav16k\) ONTO this file, or
echo    3. Run from a terminal:  align-ru.bat "I:\chemera\corpus\ru"
pause
exit /b 0
