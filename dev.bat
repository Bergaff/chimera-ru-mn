@echo off
rem  CHIMERA - local run on Windows. Double-click: installs everything that's missing,
rem  then builds the wasm and starts the app on http://127.0.0.1:5317.
rem  First run downloads: Rust (rustup), the wasm32 target, Bun.
rem  Also offered: Visual Studio C++ Build Tools via winget (needed for cargo test and the CLI).
rem  "dev.bat test" runs cargo test --workspace first and starts the app only if it is green.
rem  Leave the window open while developing; Ctrl+C to stop.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

rem Make freshly installed tools visible without reopening the window.
set "PATH=%USERPROFILE%\.cargo\bin;%USERPROFILE%\.bun\bin;%PATH%"

set HAS_LINK=1

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
echo  [4/5] MSVC Build Tools... the browser app builds without them, cargo test and the CLI need them.
where link.exe >nul 2>nul
if not errorlevel 1 goto link_ok
set HAS_LINK=0
echo    link.exe NOT found.
where winget >nul 2>nul
if errorlevel 1 goto link_manual
choice /c YN /n /m "    Install Visual Studio Build Tools (C++ workload) now via winget? Large download, needs admin. [Y/N] "
if errorlevel 2 goto link_skip
winget install --accept-source-agreements --accept-package-agreements Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --passive"
goto link_done
:link_manual
echo    winget not found. Install manually: https://aka.ms/vs/17/release/vs_BuildTools.exe
echo    and tick the "Desktop development with C++" workload.
goto link_done
:link_skip
echo    Skipped. Install later if cargo test fails with a linker error.
:link_done
goto link_end
:link_ok
echo    link.exe: OK
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
echo  [tests] SKIPPED - no MSVC linker. Install Build Tools first, then dev.bat test
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
