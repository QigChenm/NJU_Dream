@echo off
chcp 65001 >nul
title AI 服务部署脚本
cd /d "%~dp0"

echo ============================================
echo     《最南幻想》AI 服务一键部署
echo ============================================
echo.

:: 检查 Ollama 是否已安装
where ollama >nul 2>&1
if %errorlevel% neq 0 (
    echo [1/3] 未检测到 Ollama，正在自动下载安装程序...
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
    echo [1/3] Ollama 已安装。
)

:: 启动 Ollama 服务（如果未运行）
echo [2/3] 正在启动 Ollama 服务...
ollama list >nul 2>&1
if %errorlevel% neq 0 (
    start "" ollama serve
    echo 等待服务启动...
    timeout /t 5 /nobreak >nul
) else (
    echo 服务已在运行。
)

:: 拉取千问模型
echo [3/3] 正在下载 AI 模型（qwen2.5:7b-instruct），可能需要几分钟，请稍候...
ollama pull qwen2.5:7b-instruct
if %errorlevel% neq 0 (
    echo 模型下载失败，请检查网络后重试。
    pause
    exit /b 1
)

echo.
echo ============================================
echo     部署成功！现在可以启动游戏并选择本地AI模式。
echo ============================================
timeout /t 3 >nul
exit /b 0