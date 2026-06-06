@echo off
chcp 65001 >nul
title AI 服务部署脚本
cd /d "%~dp0"

setlocal enabledelayedexpansion

:: 定义模型名称
set MODEL_QWEN2= qwen2.5:7b-instruct
set MODEL_QWEN3= qwen3:8b
set MODEL_LLAMA= llama3.1:8b
set MODEL_DEEPSEEK= deepseek-r1:7b

:: 检查 Ollama 是否已安装
where ollama >nul 2>&1
if %errorlevel% neq 0 (
    echo [安装] 未检测到 Ollama，正在自动下载安装程序...
    powershell -Command "Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile '%TEMP%\OllamaSetup.exe'"
    echo 安装程序下载完成，需要管理员权限进行安装，请在弹出的用户账户控制窗口中点击“是”。
    powershell -Command "Start-Process -FilePath '%TEMP%\OllamaSetup.exe' -ArgumentList '/S' -Verb RunAs -Wait"
    if %errorlevel% neq 0 (
        echo 安装失败，请手动从 https://ollama.com 下载安装。
        pause
        exit /b 1
    )
    echo Ollama 安装完成。
) else (
    echo [状态] Ollama 已安装。
)

:: 启动 Ollama 服务（如果未运行）
echo [启动] 正在启动 Ollama 服务...
ollama list >nul 2>&1
if %errorlevel% neq 0 (
    start "" ollama serve
    echo 等待服务启动...
    timeout /t 5 /nobreak >nul
) else (
    echo 服务已在运行。
)

echo.
echo ============================================
echo     请选择要下载的 AI 模型
echo ============================================
echo 1. 推荐模型：%MODEL_QWEN2% (约 4.4 GB)
echo 2. %MODEL_QWEN3% (约 4.7 GB)
echo 3. %MODEL_LLAMA% (约 4.7 GB)
echo 4. %MODEL_DEEPSEEK% (约 4.4 GB)
echo 5. 部署全部模型
echo 0. 退出
echo ============================================
set /p choice="请输入选项 (0-5): "

if "%choice%"=="0" exit /b 0
if "%choice%"=="1" call :PULL_MODEL %MODEL_QWEN2%
if "%choice%"=="2" call :PULL_MODEL %MODEL_QWEN3%
if "%choice%"=="3" call :PULL_MODEL %MODEL_LLAMA%
if "%choice%"=="4" call :PULL_MODEL %MODEL_DEEPSEEK%
if "%choice%"=="5" (
    call :PULL_MODEL %MODEL_QWEN2%
    call :PULL_MODEL %MODEL_QWEN3%
    call :PULL_MODEL %MODEL_LLAMA%
    call :PULL_MODEL %MODEL_DEEPSEEK%
)
if "%choice%" GTR "5" (
    echo 无效选择，请重新运行脚本。
    pause
    exit /b 1
)

echo.
echo ============================================
echo     部署成功！现在可以启动游戏并选择本地AI模式。
echo     请在游戏设置中将模型名称改为已下载的模型。
echo ============================================
timeout /t 3 >nul
exit /b 0

:PULL_MODEL
set model_name=%1
echo 正在检测模型 %model_name% 是否已安装...
ollama list | findstr /i "%model_name%" >nul
if %errorlevel% equ 0 (
    echo 模型 %model_name% 已存在，跳过下载。
) else (
    echo 正在下载 AI 模型 %model_name%，可能需要几分钟，请稍候...
    ollama pull %model_name%
    if %errorlevel% neq 0 (
        echo 模型 %model_name% 下载失败，请检查网络后重试。
        pause
        exit /b 1
    )
)
goto :eof