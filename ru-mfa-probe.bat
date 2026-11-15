@echo off
rem  CHIMERA - decisive network probe for the conda question (paste the output).
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
set "MFA_DIR=%CD%\.tools\mfa"
set "MAMBA_ROOT_PREFIX=%MFA_DIR%\root"
set "MAMBA_EXE=%MFA_DIR%\bin\micromamba.exe"

echo CHIMERA - conda/MFA network probe
echo ================================
echo  1) deep byte-range probes into conda-forge/win-64/repodata.json
curl.exe -s -r 0-200 -o NUL -w "   offset head     http_code=%%{http_code} bytes=%%{size_download}\n" https://conda.anaconda.org/conda-forge/win-64/repodata.json
curl.exe -s -r 90000000-90000299 -o NUL -w "   offset 90 MB    http_code=%%{http_code} bytes=%%{size_download}\n" https://conda.anaconda.org/conda-forge/win-64/repodata.json
curl.exe -s -r 199000000-199000299 -o NUL -w "   offset 199 MB   http_code=%%{http_code} bytes=%%{size_download}\n" https://conda.anaconda.org/conda-forge/win-64/repodata.json
echo     (not 206 with exactly 300 bytes -^> the proxy is rewriting conda downloads)
echo.
echo  2) micromamba verbose dry-run (what IT actually sees)
if exist "%MAMBA_ROOT_PREFIX%\pkgs\cache" (
  echo    repodata cache files:
  dir /a "%MAMBA_ROOT_PREFIX%\pkgs\cache"
)
if not exist "%MAMBA_EXE%" goto no_mamba
"%MAMBA_EXE%" create --dry-run -v -p "%MFA_DIR%\probe-env" -c conda-forge python=3.11 > "%MFA_DIR%\probe.log" 2>&1
findstr /i /c:"repodata" /c:"found" /c:"solving" /c:"packages" "%MFA_DIR%\probe.log"
echo.
echo    full log: %MFA_DIR%\probe.log
goto done

:no_mamba
echo    micromamba not found at %MAMBA_EXE% (was setup-ru.bat run?)

:done
pause
exit /b 0
