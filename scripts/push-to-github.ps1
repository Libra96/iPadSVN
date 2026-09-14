# 创建 GitHub 私有仓库并推送（Windows PowerShell）
# 用法：在 D:\MY\Code\IPAD 目录运行 .\scripts\push-to-github.ps1

$ErrorActionPreference = "Stop"
$RepoName = "iPadSVN"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

Write-Host "==> 1/4 检查 GitHub 登录..." -ForegroundColor Cyan
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Write-Host "未找到 gh，正在安装 GitHub CLI..."
    winget install GitHub.cli --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

$loggedIn = $false
cmd /c "gh auth status >nul 2>nul"
if ($LASTEXITCODE -eq 0) { $loggedIn = $true }

if (-not $loggedIn) {
    Write-Host "请在浏览器中完成 GitHub 登录授权..." -ForegroundColor Yellow
    gh auth login -h github.com -p https -w -s repo
    if ($LASTEXITCODE -ne 0) { throw "GitHub 登录失败，请重试" }
}

$user = (gh api user -q .login)
Write-Host "已登录: $user"

Write-Host "==> 2/4 创建私有仓库 $RepoName ..." -ForegroundColor Cyan
$exists = gh repo view "$user/$RepoName" 2>$null
if ($LASTEXITCODE -ne 0) {
    gh repo create $RepoName --private --description "iPad native SVN client" --confirm
} else {
    Write-Host "仓库已存在，跳过创建"
}

Write-Host "==> 3/4 配置 remote ..." -ForegroundColor Cyan
git branch -M main
git remote remove origin 2>$null
git remote add origin "https://github.com/$user/$RepoName.git"

Write-Host "==> 4/4 推送代码 ..." -ForegroundColor Cyan
git push -u origin main

Write-Host ""
Write-Host "完成! 仓库地址: https://github.com/$user/$RepoName" -ForegroundColor Green
Write-Host "下一步: GitHub -> Actions -> Build iPadSVN App -> Run workflow"
