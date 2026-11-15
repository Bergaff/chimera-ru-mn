@echo off
rem  CHIMERA - one-time setup for the Russian forced alignment.
rem  micromamba (win-64) + montreal-forced-aligner 3.4.3 + Russian MFA acoustic
rem  model v3.1.0 (fallback v2.0.0) + Russian MFA dictionary (v3.1.0, fallback v2.0.0)
rem  + Russian MFA G2P v3.1.0 (optional). Everything lands in .tools\mfa - nothing on C:.
rem  conda-forge mirrors are tried in order: upstream -> prefix.dev -> TUNA.
rem  The micromamba repodata cache is wiped before EVERY attempt: a poisoned
rem  cache (e.g. from a broken first run) makes every channel look empty.
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
echo.
echo    micromamba info (platform - root prefix - config):
"%MAMBA_EXE%" info

rem --- 1b) reachability + content sniff (diagnostics only) --------------------
echo.
echo    channel probes (what does the network ACTUALLY return?) ...
where curl.exe >nul 2>nul
if errorlevel 1 goto probes_done
call :sniff https://conda.anaconda.org/conda-forge/win-64/repodata.json conda.anaconda.org
call :sniff https://prefix.dev/conda-forge/win-64/repodata.json prefix.dev
call :sniff https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/win-64/repodata.json tuna
del "%MFA_DIR%\probe-*.bin" >nul 2>nul
:probes_done
goto probes_ok

:sniff
echo    --- %2 ---
curl.exe -s -r 0-400 -o "%MFA_DIR%\probe-%2.bin" -w "      http_code=%%{http_code} type=%%{content_type} bytes_downloaded=%%{size_download}\n" "%1"
if exist "%MFA_DIR%\probe-%2.bin" powershell -NoProfile -Command "$b=[IO.File]::ReadAllBytes('%MFA_DIR%\probe-%2.bin'); $t=[Text.Encoding]::UTF8.GetString($b); $t=($t -replace '[^ -~]','.'); Write-Host ('      first bytes: ' + $t.Substring(0, [Math]::Min(100, $t.Length)))"
exit /b 0

:probes_ok
rem --- 2) conda env with MFA (mirror cascade, fresh cache every time) ---------
if exist "%ENV_DIR%\Scripts\mfa.exe" goto mfa_env_ready
echo.
echo    creating env: montreal-forced-aligner 3.4.3 + python 3.11 ...
if exist "%ENV_DIR%" rmdir /s /q "%ENV_DIR%"
call :try_channel conda-forge
if not errorlevel 1 goto mfa_env_ready
echo    [warn] upstream conda-forge failed, trying https://prefix.dev/conda-forge ...
if exist "%ENV_DIR%" rmdir /s /q "%ENV_DIR%"
call :try_channel https://prefix.dev/conda-forge
if not errorlevel 1 goto mfa_env_ready
echo    [warn] prefix.dev failed, trying the tuna tsinghua mirror ...
if exist "%ENV_DIR%" rmdir /s /q "%ENV_DIR%"
call :try_channel https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge
if not errorlevel 1 goto mfa_env_ready
goto env_fail
:try_channel
echo    channel: %1
if exist "%MAMBA_ROOT_PREFIX%\pkgs\cache" rmdir /s /q "%MAMBA_ROOT_PREFIX%\pkgs\cache"
"%MAMBA_EXE%" create -y -p "%ENV_DIR%" -c "%1" montreal-forced-aligner=3.4.3 python=3.11
exit /b %errorlevel%
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
echo    [error] env creation failed on ALL mirrors (see the output above).
echo    paste everything in this window to the developer, especially:
echo    - the 'micromamba info' platform line,
echo    - the three 'first bytes' probe lines.
pause
exit /b 1
:model_fail
echo    [error] model download failed. See the output above; re-run to retry.
pause
exit /b 1
