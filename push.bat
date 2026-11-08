@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title MoshaverTahsili - Force Push to GitHub
color 0B

set "REPO_URL=https://github.com/Tahmoures54/MoshaverTahsili.git"
set "BRANCH=main"
set "COMMIT_MSG=Full project upload"

cd /d "%~dp0"

echo ============================================
echo   MoshaverTahsili - Force Push
echo   Repo:   %REPO_URL%
echo   Branch: %BRANCH%
echo ============================================
echo.

REM --- 1) Check git ---
where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Git not installed!
    echo Download: https://git-scm.com/download/win
    pause
    exit /b 1
)

REM --- 2) Init repo if needed ---
if not exist ".git" (
    echo [INFO] Initializing git repo ...
    git init
    git branch -M %BRANCH%
)

REM --- 3) User config (only if missing) ---
git config user.name >nul 2>nul
if errorlevel 1 (
    set /p "GIT_NAME=Enter your Git name: "
    git config user.name "!GIT_NAME!"
)
git config user.email >nul 2>nul
if errorlevel 1 (
    set /p "GIT_EMAIL=Enter your Git email: "
    git config user.email "!GIT_EMAIL!"
)

REM --- 4) Set remote ---
git remote remove origin >nul 2>nul
git remote add origin %REPO_URL%

REM --- 5) Stage everything ---
echo [INFO] Staging files ...
git add -A

REM --- 6) Commit (never fails) ---
echo [INFO] Committing ...
git commit -m "%COMMIT_MSG%" --allow-empty

REM --- 7) Ensure branch name ---
git branch -M %BRANCH%

REM --- 8) Force push ---
echo.
echo [INFO] Force pushing to origin/%BRANCH% ...
echo.
git push -u origin %BRANCH% --force

if errorlevel 1 (
    echo.
    echo ============================================
    echo   [ERROR] Push failed!
    echo ============================================
    echo.
    echo Common fixes:
    echo   1. GitHub password = Personal Access Token, NOT your account password
    echo      Get one: https://github.com/settings/tokens
    echo   2. Check internet connection / firewall
    echo   3. Try running CMD as Administrator
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   SUCCESS - Project pushed to GitHub
echo   %REPO_URL%
echo ============================================
pause