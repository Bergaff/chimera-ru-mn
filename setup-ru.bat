@echo off
rem  CHIMERA - one-time setup for the Russian forced alignment.
rem  micromamba (win-64) + montreal-forced-aligner 3.4.3 + Russian MFA acoustic
rem  model v3.1.0 (fallback v2.0.0) + Russian MFA dictionary v3.1.0 (fallback v2.0.0)
rem  + Russian MFA G2P v3.1.0 (optional, best effort).
rem  Everything lands in .tools\mfa inside the project folder - nothing on drive C:
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
set "MFA_DIR=%CD%\.tools\mfa"
set "BIN_DIR=%MFA_DIR%\bin"
set "ENV_DIR=%MFA_DIR%\env"
set "MAMBA_ROOT_PREFIX=%MFA_DIR%\root"
set "MAMBA_EXE=%BIN_DIR%\micromamba.exe"
set "MFA_ROOT_DIR=%MFA_DIR%\cache"

echo.
echo  CHIMERA - Russian MFA setup (one time, ~2 GB)
echo  ==============================================

rem --- 1) micromamba binary --------------------------------------------------
if exist "%MAMBA_EXE%" goto have_mamba
echo    downloading micromamba 2.10.0-0 (win-64, ~19 MB) ...
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
where curl.exe >nul 2>nul
if errorlevel 1 goto mamba_dl_ps
curl.exe -L --connect-timeout 10 --max-time 600 --progress-bar -o "%MAMBA_EXE%" https://github.com/mamba-org/micromamba-releases/releases/download/2.10.0-0/micromamba-win-64
if errorlevel 1 goto mamba_fail
goto have_mamba
:mamba_dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 600 -Uri 'https://github.com/mamba-org/micromamba-releases/releases/download/2.10.0-0/micromamba-win-64' -OutFile '%MAMBA_EXE%'"
if errorlevel 1 goto mamba_fail
:have_mamba
echo    micromamba: %MAMBA_EXE%

rem --- 2) conda env with MFA ---------------------------------------------------
if exist "%ENV_DIR%\Scripts\mfa.exe" goto mfa_env_ready
echo    creating env: montreal-forced-aligner 3.4.3 + python 3.11 (conda-forge) ...
echo    this takes a few minutes; progress below.
"%MAMBA_EXE%" create -y -q -p "%ENV_DIR%" -c conda-forge montreal-forced-aligner=3.4.3 python=3.11
if errorlevel 1 goto env_fail
:mfa_env_ready
call "%ENV_DIR%\Scripts\activate.bat" >nul
for /f "delims=" %%v in ('mfa version 2^>nul') do set "MFAV=%%v"
echo    MFA version: %MFAV%

rem --- 3) models ----------------------------------------------------------------
echo    downloading Russian acoustic model v3.1.0 (fallback v2.0.0) ...
mfa model download acoustic russian_mfa --version v3.1.0
if errorlevel 1 (
  echo    [warn] v3.1.0 failed, trying v2.0.0 ...
  mfa model download acoustic russian_mfa --version v2.0.0
  if errorlevel 1 goto model_fail
)
echo    downloading Russian dictionary v3.1.0 (fallback v2.0.0) ...
mfa model download dictionary russian_mfa --version v3.1.0
if errorlevel 1 (
  echo    [warn] v3.1.0 failed, trying v2.0.0 ...
  mfa model download dictionary russian_mfa --version v2.0.0
  if errorlevel 1 goto model_fail
)
echo    downloading Russian G2P v3.1.0 (optional, best effort) ...
mfa model download g2p russian_mfa --version v3.1.0
if errorlevel 1 echo    [warn] G2P unavailable; unseen words stay OOV - harmless.
echo.
echo    installed models:
mfa model list
echo.
echo  Done. Next: drag your corpus folder (the one with sentences.mfa.tsv and wav16k\)
echo  onto align-ru.bat.
pause
exit /b 0

:mamba_fail
echo    [error] could not download micromamba (network/proxy?). See the output above.
pause
exit /b 1
:env_fail
echo    [error] env creation failed (conda-forge unreachable?). See the output above.
pause
exit /b 1
:model_fail
echo    [error] model download failed. See the output above; re-run to retry.
pause
exit /b 1
