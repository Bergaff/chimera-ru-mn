@echo off
rem  CHIMERA - local run on Windows. Double-click to start (wasm build + Vite dev server).
rem  "dev.bat test" also runs the Rust test suite first (it must be green before any deploy).
rem  Leave the window open while developing; Ctrl+C to stop.
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

echo.
echo  CHIMERA - local dev
echo  ==================

where cargo >nul 2>nul
if errorlevel 1 (
  echo [error] cargo not found. Install Rust first: https://rustup.rs
  echo         Then close and reopen this window and run again.
  pause
  exit /b 1
)
where bun >nul 2>nul
if errorlevel 1 (
  echo [error] bun not found. Install Bun first: https://bun.sh
  echo         Then close and reopen this window and run again.
  pause
  exit /b 1
)

echo  [1/4] wasm32 target (idempotent)...
rustup target add wasm32-unknown-unknown
if errorlevel 1 (
  echo [error] rustup failed to add the wasm32 target.
  pause
  exit /b 1
)

echo  [2/4] JS dependencies...
call bun install
if errorlevel 1 (
  echo [error] bun install failed.
  pause
  exit /b 1
)

if /i "%~1"=="test" (
  echo  [3/4] cargo test --workspace...
  call cargo test --workspace
  if errorlevel 1 (
    echo.
    echo [error] Tests failed - the app was NOT started. Read the output above;
    echo         hand-checked test expectations are the first suspects; see docs/ru-mn-report.md.
    pause
    exit /b 1
  )
) else (
  echo  [3/4] tests skipped - run "dev.bat test" to run cargo test --workspace first
)

echo  [4/4] building the wasm and starting Vite...
echo        open http://127.0.0.1:5317   ^(leave this window open; Ctrl+C to stop^)
echo.
echo  Useful checks without a browser:
echo    cargo run --release -p chimera-cli -- transcribe "Сайн байна уу?" --language mn
echo    cargo run --release -p chimera-cli -- render text out/mn-test "Сайн байна уу?" --language mn
echo    cargo run --release -p chimera-cli -- transcribe "Привет! Как твои дела?" --language ru
echo.
call bun run dev
pause
