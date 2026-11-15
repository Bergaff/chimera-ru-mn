@echo off
rem  CHIMERA - Russian MFA setup via PIXI (fallback route when conda-forge hosts
rem  are stubbed by the network filter). Uses the conda-forge OCI mirror on
rem  ghcr.io (GitHub Container Registry, maintained by the conda-forge team).
rem  Everything lands in .tools\pixi (binary+envs) and .tools\mfa\cache (models).
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
set "TOOLS_DIR=%CD%\.tools"
set "PIXI_HOME=%TOOLS_DIR%\pixi"
set "MFA_ROOT_DIR=%TOOLS_DIR%\mfa\cache"

echo.
echo  CHIMERA - Russian MFA setup via pixi (GitHub/OCI route)
echo  =====================================================

rem --- 1) pixi binary from GitHub releases ------------------------------------
if exist "%PIXI_HOME%\bin\pixi.exe" goto have_pixi
echo    downloading pixi v0.84.2 (x86_64-pc-windows-msvc, ~60 MB, from GitHub releases) ...
if not exist "%PIXI_HOME%\bin" mkdir "%PIXI_HOME%\bin"
where curl.exe >nul 2>nul
if errorlevel 1 goto pixi_dl_ps
curl.exe -L --connect-timeout 10 --max-time 900 --progress-bar -o "%PIXI_HOME%\pixi.zip" https://github.com/prefix-dev/pixi/releases/download/v0.84.2/pixi-x86_64-pc-windows-msvc.zip
if errorlevel 1 goto pixi_fail
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force -Path '%PIXI_HOME%\pixi.zip' -DestinationPath '%PIXI_HOME%\bin'"
del "%PIXI_HOME%\pixi.zip" >nul
goto have_pixi
:pixi_dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 900 -Uri 'https://github.com/prefix-dev/pixi/releases/download/v0.84.2/pixi-x86_64-pc-windows-msvc.zip' -OutFile '%PIXI_HOME%\pixi.zip'; Expand-Archive -Force -Path '%PIXI_HOME%\pixi.zip' -DestinationPath '%PIXI_HOME%\bin'; Remove-Item '%PIXI_HOME%\pixi.zip'"
if errorlevel 1 goto pixi_fail
:have_pixi
echo    pixi: %PIXI_HOME%\bin\pixi.exe
"%PIXI_HOME%\bin\pixi.exe" --version

rem --- 2) config: conda-forge -> OCI mirror on ghcr.io --------------------------
if not exist "%PIXI_HOME%" mkdir "%PIXI_HOME%"
> "%PIXI_HOME%\config.toml" echo [mirrors]
>> "%PIXI_HOME%\config.toml" echo "https://conda.anaconda.org/conda-forge" = ["oci://ghcr.io/channel-mirrors/conda-forge"]
echo    config: %PIXI_HOME%\config.toml

rem --- 3) global install of MFA from the OCI mirror ------------------------------
if exist "%PIXI_HOME%\known-good.txt" goto mfa_ready
echo    installing montreal-forced-aligner 3.4.3 (this downloads ~1-2 GB) ...
"%PIXI_HOME%\bin\pixi.exe" global install "montreal-forced-aligner =3.4.3" "python =3.11"
if errorlevel 1 (
  echo    [warn] pinned spec failed, trying unpinned montreal-forced-aligner ...
  "%PIXI_HOME%\bin\pixi.exe" global install montreal-forced-aligner
  if errorlevel 1 goto gx_fail
)
echo ok> "%PIXI_HOME%\known-good.txt"
:mfa_ready
echo    mfa: %PIXI_HOME%\bin\mfa.exe
"%PIXI_HOME%\bin\pixi.exe" global list
echo.

rem --- 4) models ------------------------------------------------------------------
echo    downloading Russian acoustic model v3.1.0 (fallback v2.0.0) ...
"%PIXI_HOME%\bin\mfa.exe" model download acoustic russian_mfa --version v3.1.0
if errorlevel 1 (
  echo    [warn] v3.1.0 failed, trying v2.0.0 ...
  "%PIXI_HOME%\bin\mfa.exe" model download acoustic russian_mfa --version v2.0.0
  if errorlevel 1 goto model_fail
)
echo    downloading Russian dictionary v3.1.0 (fallback v2.0.0) ...
"%PIXI_HOME%\bin\mfa.exe" model download dictionary russian_mfa --version v3.1.0
if errorlevel 1 (
  echo    [warn] v3.1.0 failed, trying v2.0.0 ...
  "%PIXI_HOME%\bin\mfa.exe" model download dictionary russian_mfa --version v2.0.0
  if errorlevel 1 goto model_fail
)
echo    downloading Russian G2P v3.1.0 (optional, best effort) ...
"%PIXI_HOME%\bin\mfa.exe" model download g2p russian_mfa --version v3.1.0
if errorlevel 1 echo    [warn] G2P unavailable; unseen words stay OOV - harmless.
echo.
echo    installed models:
"%PIXI_HOME%\bin\mfa.exe" model list
echo.
echo  Done. Now drag I:\chemera\corpus\ru onto align-ru.bat.
pause
exit /b 0

:pixi_fail
echo    [error] could not download pixi from GitHub (network/proxy?). See the output above.
pause
exit /b 1
:gx_fail
echo    [error] pixi could not install MFA from the OCI mirror (see output above).
echo    ghcr.io may be blocked on your network too - send the output to the developer.
pause
exit /b 1
:model_fail
echo    [error] model download failed. See the output above; re-run to retry.
pause
exit /b 1
