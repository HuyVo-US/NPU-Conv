@echo off
setlocal

cd /d "%~dp0"

echo Running FP16 convolution C model...
echo.

if not exist "input.hex" (
    echo ERROR: input.hex not found in %cd%
    echo Copy input.hex from Conv_RTL_FP16 into this folder first.
    echo.
    pause
    exit /b 1
)

if not exist "kernel.hex" (
    echo ERROR: kernel.hex not found in %cd%
    echo Copy kernel.hex from Conv_RTL_FP16 into this folder first.
    echo.
    pause
    exit /b 1
)

if not exist "output.hex" (
    echo ERROR: output.hex not found in %cd%
    echo Copy output.hex from Conv_RTL_FP16 into this folder first.
    echo.
    pause
    exit /b 1
)

if not exist "conv_fp16_model.exe" (
    echo conv_fp16_model.exe not found. Compiling conv_fp16_model.c...
    gcc conv_fp16_model.c -o conv_fp16_model.exe
    if errorlevel 1 (
        echo.
        echo ERROR: compile failed. Check that gcc is installed and available in PATH.
        echo.
        pause
        exit /b 1
    )
    echo.
)

conv_fp16_model.exe input.hex kernel.hex output.hex output_c_model.hex

echo.
pause
