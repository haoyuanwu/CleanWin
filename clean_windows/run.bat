@echo off
rem CleanWin - 启动开发运行（自动补环境变量、关闭占用进程）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
