@echo off
rem  CHIMERA - local run on Windows. Double-click: installs what's missing,
rem  then builds the wasm and starts the app on http://127.0.0.1:5317.
rem
rem  Everything this batch downloads goes into <repo>\.tools\ - nothing installs to drive C:
rem    .tools\rustup\        RUSTUP_HOME   (Rust toolchain + wasm32 target)
rem    .tools\cargo\         CARGO_HOME    (cargo, registry caches)
rem    .tools\bun\           BUN_INSTALL   (Bun runtime)
rem    .tools\vsbuildtools\  Visual Studio Build Tools, only if offered and accepted
rem  (installations are found via vswhere, so vcvars64 keeps working with a custom path)
rem
rem  Arguments (combine freely, e.g. "dev.bat test local"):
rem    test   - run cargo test --workspace first; the app starts only if it is green
rem    local  - ignore tools installed system-wide, use/install the project-local ones
rem  Without "local", tools already installed system-wide are used as-is.
rem  Leave the window open while developing; Ctrl+C to stop.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "TOOLS_DIR=%CD%\.tools"
set "PATH=%TOOLS_DIR%\cargo\bin;%TOOLS_DIR%\bun\bin;%PATH%"
rem NOTE: RUSTUP_HOME/CARGO_HOME are set only on the project-local path, never for system tools.
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"

set HAS_LINK=0
set FORCE_LOCAL=0
set WANT_TEST=0
for %%a in (%*) do call :arg "%%a"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

echo.
echo  CHIMERA - local dev
echo  ==================
echo  downloads go to: %TOOLS_DIR%

echo.
echo  [1/5] Rust...
if exist "%TOOLS_DIR%\cargo\bin\cargo.exe" goto rust_local
if "%FORCE_LOCAL%"=="1" goto rust_install
where cargo >nul 2>nul
if not errorlevel 1 goto rust_sys
goto rust_install
:rust_local
set "RUSTUP_HOME=%TOOLS_DIR%\rustup"
set "CARGO_HOME=%TOOLS_DIR%\cargo"
goto rust_done
:rust_sys
echo    Using the Rust you already have system-wide. "dev.bat local" forces project-local.
goto rust_done
:rust_install
set "RUSTUP_HOME=%TOOLS_DIR%\rustup"
set "CARGO_HOME=%TOOLS_DIR%\cargo"
echo    Installing stable Rust into %TOOLS_DIR% (drive C: is NOT used)...
echo    source: https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe
where curl.exe >nul 2>nul
if errorlevel 1 goto rust_dl_ps
curl.exe -sSfL -o "%TOOLS_DIR%\rustup-init.exe" https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe
if errorlevel 1 goto rust_fail
goto rust_run
:rust_dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' -OutFile '%TOOLS_DIR%\rustup-init.exe'"
if errorlevel 1 goto rust_fail
:rust_run
"%TOOLS_DIR%\rustup-init.exe" -y --default-toolchain stable --no-modify-path
if errorlevel 1 goto rust_fail
set "PATH=%TOOLS_DIR%\cargo\bin;%PATH%"
if not exist "%TOOLS_DIR%\cargo\bin\cargo.exe" goto rust_fail
goto rust_done
:rust_fail
echo    [error] Rust installation failed. See https://rustup.rs
pause
exit /b 1
:rust_done
echo    Rust: OK
where cargo

echo.
echo  [2/5] wasm32 target...
call rustup target add wasm32-unknown-unknown
if errorlevel 1 goto wasm_fail
goto wasm_done
:wasm_fail
echo    [error] could not add the wasm32-unknown-unknown target.
pause
exit /b 1
:wasm_done

echo.
echo  [3/5] Bun...
if exist "%TOOLS_DIR%\bun\bin\bun.exe" goto bun_done
if "%FORCE_LOCAL%"=="1" goto bun_install
where bun >nul 2>nul
if not errorlevel 1 goto bun_sys
goto bun_install
:bun_sys
echo    Using the Bun you already have system-wide. "dev.bat local" forces project-local.
goto bun_done
:bun_install
echo    Installing Bun into %TOOLS_DIR% (drive C: is NOT used)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $env:BUN_INSTALL = '%TOOLS_DIR%\bun'; irm bun.sh/install.ps1 | iex"
if errorlevel 1 goto bun_fail
if not exist "%TOOLS_DIR%\bun\bin\bun.exe" goto bun_fail
goto bun_done
:bun_fail
echo    [error] Bun installation failed. Install manually: https://bun.sh
pause
exit /b 1
:bun_done
echo    Bun: OK

echo.
echo  [4/5] Visual Studio C++ toolchain (cargo needs it on Windows for host build scripts)...
call :try_msvc_env
if not errorlevel 1 goto link_ok
echo    MSVC C++ toolchain not usable yet.
echo    If installed now, it goes to %TOOLS_DIR%\vsbuildtools (several GB), not drive C:.
choice /c YN /n /m "    Install Visual Studio Build Tools (C++ workload) now? [Y/N] "
if errorlevel 2 goto link_skip
where curl.exe >nul 2>nul
if errorlevel 1 goto vs_dl_ps
curl.exe -sSfL -o "%TOOLS_DIR%\vs_buildtools.exe" https://aka.ms/vs/17/release/vs_buildtools.exe
if errorlevel 1 goto vs_dl_fail
goto vs_run
:vs_dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' -OutFile '%TOOLS_DIR%\vs_buildtools.exe'"
if errorlevel 1 goto vs_dl_fail
goto vs_run
:vs_dl_fail
echo    [error] could not download vs_buildtools.exe. Install manually: https://aka.ms/vs/17/release/vs_BuildTools.exe
goto link_end
:vs_run
echo    Installing into %TOOLS_DIR%\vsbuildtools - this takes a while and needs admin (UAC).
echo    Command: "%TOOLS_DIR%\vs_buildtools.exe" --passive --norestart --installPath "%TOOLS_DIR%\vsbuildtools" --add Microsoft.VisualStudio.Workload.VCTools
"%TOOLS_DIR%\vs_buildtools.exe" --passive --norestart --installPath "%TOOLS_DIR%\vsbuildtools" --add Microsoft.VisualStudio.Workload.VCTools
set "VS_RC=%errorlevel%"
if "%VS_RC%"=="0" goto vs_after
if "%VS_RC%"=="3010" goto vs_after
echo    [fail] installer exited with code %VS_RC%. See https://aka.ms/vs/17/release/vs_BuildTools.exe for a manual install (tick Desktop development with C++).
goto link_end
:vs_after
call :try_msvc_env
if not errorlevel 1 goto link_ok
echo    [fail] installed, but the C++ environment still does not come online. Paste everything from [4/5] above when asking for help.
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
goto deps_done
:deps_fail
echo    [error] bun install failed.
pause
exit /b 1
:deps_done

if "%WANT_TEST%"=="0" goto skip_tests
if "%HAS_LINK%"=="0" goto tests_skip
echo.
echo  [tests] cargo test --workspace...
call cargo test --workspace
if errorlevel 1 goto tests_fail
goto skip_tests
:tests_skip
echo.
echo  [tests] SKIPPED - Visual Studio C++ Build Tools are missing. Install them, then dev.bat test local
goto skip_tests
:tests_fail
echo.
echo  [error] Tests failed - the app was NOT started.
echo          Suspects: hand-written test expectations; see docs/ru-mn-report.md
pause
exit /b 1
:skip_tests
if "%WANT_TEST%"=="1" goto tests_ran
echo.
echo  [tests] not run - use dev.bat test to gate the app on cargo test --workspace
:tests_ran

echo.
echo  Building the wasm and starting Vite...
echo  open http://127.0.0.1:5317   (leave this window open; Ctrl+C to stop)
echo.
echo  Tools live in: %TOOLS_DIR%   (gitignored; delete it to free space, reruns reinstall)
echo  Useful checks without a browser:
echo    cargo run --release -p chimera-cli -- transcribe "Сайн байна уу?" --language mn
echo    cargo run --release -p chimera-cli -- transcribe "Привет! Как твои дела?" --language ru
echo.
call bun run dev
pause
exit /b 0

rem  Parse arguments: "test" and "local", combinable in any order.
:arg
if /i "%~1"=="test" set WANT_TEST=1
if /i "%~1"=="local" set FORCE_LOCAL=1
exit /b 0

rem Find VS Build Tools via vswhere (any drive, any path, including inside this repo), load its environment.
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
