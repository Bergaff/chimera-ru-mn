@echo off
rem  CHIMERA - local run on Windows. Double-click: installs everything that's missing,
rem  then builds the wasm and starts the app on http://127.0.0.1:5317.
rem  First run downloads: Rust (rustup), the wasm32 target, Bun.
rem  Windows needs the Visual Studio C++ Build Tools for ANY cargo build (host build
rem  scripts link against MSVC) - the batch installs them via winget if missing and
rem  sets the C++ environment (vcvars64) for this window.
rem  "dev.bat test" runs cargo test --workspace first and starts the app only if it is green.
rem  Leave the window open while developing; Ctrl+C to stop.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

rem Make freshly installed tools visible without reopening the window.
set "PATH=%USERPROFILE%\.cargo\bin;%USERPROFILE%\.bun\bin;%PATH%"

set HAS_LINK=0
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

echo.
echo  CHIMERA - local dev
echo  ==================

echo.
echo  [1/5] Rust...
where cargo >nul 2>nul
if not errorlevel 1 goto rust_ok
echo    cargo not found - installing stable Rust via rustup...
echo    source: static.rust-lang.org (official rustup-init.exe)
where curl.exe >nul 2>nul
if errorlevel 1 goto rust_dl_ps
curl.exe -sSf -o "%TEMP%\rustup-init.exe" https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe
if errorlevel 1 goto rust_fail
goto rust_run
:rust_dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' -OutFile '%TEMP%\rustup-init.exe'"
if errorlevel 1 goto rust_fail
:rust_run
"%TEMP%\rustup-init.exe" -y --default-toolchain stable
if errorlevel 1 goto rust_fail
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
where cargo >nul 2>nul
if errorlevel 1 goto rust_fail
goto rust_ok
:rust_fail
echo    [error] Rust installation failed. Install manually: https://rustup.rs
pause
exit /b 1
:rust_ok
echo    Rust: OK

echo.
echo  [2/5] wasm32 target...
call rustup target add wasm32-unknown-unknown
if errorlevel 1 goto wasm_fail
goto wasm_ok
:wasm_fail
echo    [error] could not add the wasm32-unknown-unknown target.
pause
exit /b 1
:wasm_ok

echo.
echo  [3/5] Bun...
where bun >nul 2>nul
if not errorlevel 1 goto bun_ok
echo    bun not found - installing via the official script at bun.sh ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm bun.sh/install.ps1 | iex"
if errorlevel 1 goto bun_fail
set "PATH=%USERPROFILE%\.bun\bin;%PATH%"
where bun >nul 2>nul
if errorlevel 1 goto bun_fail
goto bun_ok
:bun_fail
echo    [error] Bun installation failed. Install manually: https://bun.sh
pause
exit /b 1
:bun_ok
echo    Bun: OK

echo.
echo  [4/5] Visual Studio C++ toolchain (cargo needs it on Windows for host build scripts)...
call :try_msvc_env
if not errorlevel 1 goto link_ok
echo    MSVC C++ toolchain not usable yet.
where winget >nul 2>nul
if errorlevel 1 goto link_manual
choice /c YN /n /m "    Install or repair Visual Studio Build Tools (C++ workload) via winget now? [Y/N] "
if errorlevel 2 goto link_skip
winget install --force --accept-source-agreements --accept-package-agreements Microsoft.VisualStudio.2022.BuildTools --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --norestart"
call :try_msvc_env
if not errorlevel 1 goto link_ok
echo.
echo    [fail] The C++ workload still does not come online. Paste EVERYTHING from [4/5]
echo           onwards when asking for help - especially the [diag] lines above.
echo    Manual repair in an ELEVATED terminal, then rerun dev.bat:
echo      winget install --id Microsoft.VisualStudio.2022.BuildTools --force --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --norestart"
goto link_end
:link_manual
echo    winget not found. Install manually: https://aka.ms/vs/17/release/vs_BuildTools.exe
echo    (tick Desktop development with C++), then run dev.bat again.
goto link_end
:link_skip
echo    Skipped. cargo test, the CLI and even the wasm build fail without the C++ toolchain.
goto link_end
:link_ok
echo    MSVC toolchain: OK
:link_end

echo.
echo  [5/5] JS dependencies...
call bun install
if errorlevel 1 goto deps_fail
goto deps_ok
:deps_fail
echo    [error] bun install failed.
pause
exit /b 1
:deps_ok

if /i not "%~1"=="test" goto skip_tests
if "%HAS_LINK%"=="0" goto tests_skip
echo.
echo  [tests] cargo test --workspace...
call cargo test --workspace
if errorlevel 1 goto tests_fail
goto skip_tests
:tests_skip
echo.
echo  [tests] SKIPPED - Visual Studio C++ Build Tools are missing. Install them, then dev.bat test
goto skip_tests
:tests_fail
echo.
echo  [error] Tests failed - the app was NOT started.
echo          Suspects: hand-written test expectations; see docs/ru-mn-report.md
pause
exit /b 1
:skip_tests
if /i "%~1"=="test" goto tests_ran
echo.
echo  [tests] not run - use dev.bat test to gate the app on cargo test --workspace
:tests_ran

echo.
echo  Building the wasm and starting Vite...
echo  open http://127.0.0.1:5317   (leave this window open; Ctrl+C to stop)
echo.
echo  Useful checks without a browser:
echo    cargo run --release -p chimera-cli -- transcribe "Сайн байна уу?" --language mn
echo    cargo run --release -p chimera-cli -- render text out/mn-test "Сайн байна уу?" --language mn
echo    cargo run --release -p chimera-cli -- transcribe "Привет! Как твои дела?" --language ru
echo.
call bun run dev
pause
exit /b 0

rem Find VS Build Tools via vswhere and load its environment (link.exe, LIB, INCLUDE).
:try_msvc_env
set "VSINSTALL="
if exist "%VSWHERE%" goto tme_vswhere
echo    [diag] vswhere.exe NOT found at "%VSWHERE%" - the Build Tools installer did not register Visual Studio.
goto tme_glob
:tme_vswhere
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Workload.VCTools -property installationPath`) do set "VSINSTALL=%%i"
if defined VSINSTALL goto tme_have
echo    [diag] vswhere found no install with the VCTools workload. Installed Visual Studio products:
"%VSWHERE%" -products * -property installationPath
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%i"
if defined VSINSTALL goto tme_have
echo    [diag] the VC tools component is missing too - the C++ workload is probably NOT installed.
:tme_glob
for /d %%e in (2017 2019 2022) do for /d %%d in (BuildTools Community Professional Enterprise) do if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%e\%%d\VC\Auxiliary\Build\vcvars64.bat" set "VSINSTALL=%ProgramFiles(x86)%\Microsoft Visual Studio\%%e\%%d"
:tme_have
if not defined VSINSTALL exit /b 1
echo    [diag] using Visual Studio at: "%VSINSTALL%"
if not exist "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat" goto tme_novars
call "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat"
where link.exe
if errorlevel 1 exit /b 1
set HAS_LINK=1
exit /b 0
:tme_novars
echo    [diag] found Visual Studio at "%VSINSTALL%" but VC\Auxiliary\Build\vcvars64.bat is MISSING - the C++ workload is not installed there.
exit /b 1
