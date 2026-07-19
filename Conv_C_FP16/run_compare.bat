@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo   FP16 CONVOLUTION - C REFERENCE VS RTL OUTPUT
echo ============================================================
echo.

where gcc >nul 2>&1
if errorlevel 1 goto :gcc_missing

if not exist "conv_reference.c" goto :source_missing
if not exist "conv_input.hex" goto :input_missing
if not exist "conv_kernel.hex" goto :kernel_missing
if not exist "conv_output.hex" goto :output_missing

set "TEMP_EXE=%TEMP%\conv_reference_fp16_%RANDOM%_%RANDOM%.exe"

echo [1/2] Compiling conv_reference.c...
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -ffp-contract=off "conv_reference.c" -o "%TEMP_EXE%" -lm
if errorlevel 1 goto :compile_failed

echo [2/2] Running convolution and comparing with RTL...
echo.
"%TEMP_EXE%" "conv_input.hex" "conv_kernel.hex" "conv_output.hex" "conv_c_output.hex"
set "RUN_RESULT=%ERRORLEVEL%"

if exist "%TEMP_EXE%" del /q "%TEMP_EXE%" >nul 2>&1

echo.
if not "%RUN_RESULT%"=="0" goto :run_failed
echo Comparison completed.
echo C output was written to conv_c_output.hex
goto :finish_success

:run_failed
echo ERROR: Program execution failed with exit code %RUN_RESULT%.
goto :finish_failure

:gcc_missing
echo ERROR: GCC was not found in PATH.
echo Install GCC or add its bin directory to the PATH environment variable.
goto :finish_failure

:source_missing
echo ERROR: conv_reference.c was not found in this folder.
goto :finish_failure

:input_missing
echo ERROR: conv_input.hex was not found in this folder.
goto :finish_failure

:kernel_missing
echo ERROR: conv_kernel.hex was not found in this folder.
goto :finish_failure

:output_missing
echo ERROR: conv_output.hex was not found in this folder.
goto :finish_failure

:compile_failed
echo.
echo ERROR: Compilation failed.
if exist "%TEMP_EXE%" del /q "%TEMP_EXE%" >nul 2>&1
goto :finish_failure

:finish_success
echo.
if /i "%~1"=="--no-pause" exit /b 0
pause
exit /b 0

:finish_failure
echo.
if /i "%~1"=="--no-pause" exit /b 1
pause
exit /b 1
