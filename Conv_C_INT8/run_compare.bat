@echo off
setlocal

cd /d "%~dp0"

set "NO_PAUSE=0"
if /I "%~1"=="--no-pause" set "NO_PAUSE=1"

set "RUNNER=conv_int8_reference_runner.exe"

for %%F in (conv_input.hex conv_kernel.hex conv_rtl_output.hex) do (
    if not exist "%%F" (
        echo ERROR: Missing %%F in %CD%
        echo Copy the three HEX files from Conv_RTL_INT8, then run again.
        set "RESULT=1"
        goto finish
    )
)

where gcc >nul 2>&1
if errorlevel 1 (
    echo ERROR: gcc was not found in PATH.
    set "RESULT=1"
    goto finish
)

echo Compiling INT8 C reference model...
gcc -std=c11 -Wall -Wextra -O2 -o "%RUNNER%" conv_int8_reference.c -lm
if errorlevel 1 (
    echo ERROR: Compilation failed.
    set "RESULT=1"
    goto cleanup
)

echo.
echo Running convolution and comparing with RTL...
echo.
"%RUNNER%"
set "RESULT=%ERRORLEVEL%"

:cleanup
if exist "%RUNNER%" del /q "%RUNNER%"

:finish
echo.
if "%NO_PAUSE%"=="0" pause
exit /b %RESULT%
