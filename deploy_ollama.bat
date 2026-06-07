@echo off
@chcp 65001 >nul 2>&1
@title AI Service Deploy Script
@cd /d "%~dp0"
@setlocal enabledelayedexpansion

:: Model definitions
@set MODEL_QWEN2=qwen2.5:7b-instruct
@set MODEL_QWEN3=qwen3:8b
@set MODEL_LLAMA=llama3.1:8b
@set MODEL_DEEPSEEK=deepseek-r1:7b

@echo.
@echo ============================================
@echo     AI Service One-Click Deployment
@echo ============================================
@echo.

:: Check if Ollama is installed
@where ollama >nul 2>&1
@if %errorlevel% neq 0 (
    @echo [1/3] Ollama not found. Downloading installer.
    @curl -L -o "%TEMP%\OllamaSetup.exe" "https://ollama.com/download/OllamaSetup.exe"
    @if not exist "%TEMP%\OllamaSetup.exe" (
        @echo Download failed. Please install Ollama manually from https://ollama.com
        @pause
        @exit /b 1
    )
    @echo Starting installer. Administrator privileges required. Please allow UAC prompt.
    @"%TEMP%\OllamaSetup.exe" /S
    @if %errorlevel% neq 0 (
        @echo Installation failed. Please install manually.
        @pause
        @exit /b 1
    )
    @echo Ollama installed successfully.
) else (
    @echo [1/3] Ollama is already installed.
)

:: Start Ollama service if not running
@echo [2/3] Starting Ollama service.
@ollama list >nul 2>&1
@if %errorlevel% neq 0 (
    @start "" ollama serve
    @echo Waiting for service to start.
    @timeout /t 5 /nobreak >nul
) else (
    @echo Service is already running.
)

@echo.
@echo ============================================
@echo     Select AI Model to Download
@echo ============================================
@echo 1. %MODEL_QWEN2% (about 4.4 GB)
@echo 2. %MODEL_QWEN3% (about 4.7 GB)
@echo 3. %MODEL_LLAMA% (about 4.7 GB)
@echo 4. %MODEL_DEEPSEEK% (about 4.4 GB)
@echo 5. Download all models
@echo 0. Exit
@echo ============================================
@set /p choice="Enter your choice (0-5): "

@if "%choice%"=="0" goto :end
@if "%choice%"=="1" call :PULL_MODEL %MODEL_QWEN2%
@if "%choice%"=="2" call :PULL_MODEL %MODEL_QWEN3%
@if "%choice%"=="3" call :PULL_MODEL %MODEL_LLAMA%
@if "%choice%"=="4" call :PULL_MODEL %MODEL_DEEPSEEK%
@if "%choice%"=="5" (
    @call :PULL_MODEL %MODEL_QWEN2%
    @call :PULL_MODEL %MODEL_QWEN3%
    @call :PULL_MODEL %MODEL_LLAMA%
    @call :PULL_MODEL %MODEL_DEEPSEEK%
)
@if "%choice%" GTR "5" (
    @echo Invalid choice. Please rerun the script.
    @pause
    @exit /b 1
)

@echo.
@echo ============================================
@echo     Deployment successful. You can now start the game and select local AI mode.
@echo     In the game settings, change the model name to the one you just downloaded.
@echo ============================================

:end
@echo Script finished. Window will close in 10 seconds.
@timeout /t 10
@exit /b 0

:PULL_MODEL
@set model_name=%1
@echo Checking if model %model_name% is already installed.
@ollama list | findstr /i "%model_name%" >nul
@if %errorlevel% equ 0 (
    @echo Model %model_name% already exists. Skipping download.
) else (
    @echo Downloading model %model_name%. This may take several minutes. Please wait.
    @ollama pull %model_name%
    @if %errorlevel% neq 0 (
        @echo Model %model_name% download failed. Please check your network connection and retry.
        @pause
        @exit /b 1
    )
)
@goto :eof