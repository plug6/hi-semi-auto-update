<#
.SYNOPSIS
    Combined Backend + Frontend deployment script for Insight.

.DESCRIPTION
    Lets you choose Backend / Frontend / Both.
    By default, each component checks whether the remote repo actually has
    new commits before doing anything (git fetch + compare HEAD vs origin/main).
    If there are no new commits, that component's update is skipped.
    Use -f to force the update regardless (old behavior, no check).

.EXAMPLE
    .\deploy.ps1
#>

$ErrorActionPreference = "Stop"

$BackendPath  = "C:\apps\insight\backend"
$FrontendPath = "C:\apps\insight\frontend"

# ============================================================
#  Helpers
# ============================================================

function Test-RemoteChanges {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Branch = "main"
    )

    Push-Location $Path
    try {
        git fetch origin $Branch --quiet | Out-Null
        $local  = git rev-parse HEAD
        $remote = git rev-parse "origin/$Branch"
        return ($local -ne $remote)
    }
    finally {
        Pop-Location
    }
}

function Invoke-HealthCheck {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Label
    )

    Write-Host "Request Check at $Url"
    $response = $null
    try {
        $response = Invoke-WebRequest $Url -UseBasicParsing -ErrorAction SilentlyContinue
    } catch { }

    $chars = "/-\|"
    for ($i = 0; $i -lt 10; $i++) {
        $c = $chars[$i % $chars.Length]
        Write-Host "`b$c" -NoNewline
        Start-Sleep -Milliseconds 200
    }
    Write-Host "`b "   # clear spinner

    if ($response) {
        Write-Host "StatusCode: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "StatusDescription: $($response.StatusDescription)" -ForegroundColor Green
        Write-Host ">>> $Label deployed successfully.`n" -ForegroundColor Green
    }
    else {
        Write-Host "Error: $($error[0].Exception.Message)" -ForegroundColor Red
        Write-Host ">>> $Label deployment failed.`n" -ForegroundColor Red
    }
}

# ============================================================
#  Backend
# ============================================================

function Update-Backend {
    param([switch]$Force)

    $oldDir = Get-Location
    Set-Location $BackendPath

    Write-Host "==================== BACKEND ====================" -ForegroundColor Cyan

    if (-not $Force) {
        Write-Host "Checking for remote changes..." -ForegroundColor Yellow
        $hasChanges = Test-RemoteChanges -Path $BackendPath -Branch "main"

        if (-not $hasChanges) {
            Write-Host ">>> Backend already up to date. Skipping update.`n" -ForegroundColor Green
            Set-Location $oldDir
            return
        }
        Write-Host "New commits found. Proceeding with update.`n" -ForegroundColor Yellow
    }
    else {
        Write-Host "Force mode (-f): skipping change check.`n" -ForegroundColor Yellow
    }

    Write-Host "[1/4] Updating Backend repo..." -ForegroundColor Yellow
    Get-Location
    git pull origin main

    Write-Host "[2/4] Installing Backend dependencies...`n" -ForegroundColor Yellow
    npm i

    # ---------- Database ----------
    Write-Host ""
    Write-Host "[3/4] Database setup options:" -ForegroundColor Cyan
    Write-Host "  1) Skip DB changes"
    Write-Host "  2) Run DB update (migrations + seed)"
    Write-Host "  3) Fresh DB install (baseline + seed)"
    Write-Host "  4) Restore DB from backup"
    $dbChoice = Read-Host "Select option [1/2/3/4] [default 1]"

    switch ($dbChoice) {

        "1" {
            Write-Host "Skipping database changes." -ForegroundColor Yellow
        }

        "2" {
            Write-Host "Running DB update..." -ForegroundColor Yellow
            node scripts/setup.js --update
        }

        "3" {
            Write-Host ""
            Write-Host "WARNING: Fresh DB install may DESTROY existing data." -ForegroundColor Red
            $confirm = Read-Host "Type YES to continue"

            if ($confirm -ne "YES") {
                throw "Fresh DB install cancelled by user."
            }

            $securePass = Read-Host "Enter postgres password" -AsSecureString
            $pgPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
            )

            if (-not $pgPassword) {
                throw "Postgres password cannot be empty."
            }

            node scripts/setup.js --fresh -p $pgPassword
        }

        "4" {
            Write-Host "Available backups:" -ForegroundColor Yellow
            Get-ChildItem "db/backups" -File | Sort-Object LastWriteTime -Descending |
                ForEach-Object { Write-Host "  $($_.Name)" }

            Write-Host ""
            $file = Read-Host "Enter backup filename (leave empty for latest)"

            $confirm = Read-Host "Type RESTORE to confirm"
            if ($confirm -ne "RESTORE") {
                throw "Restore cancelled."
            }

            if ([string]::IsNullOrWhiteSpace($file)) {
                Write-Host "Restoring latest backup..." -ForegroundColor Yellow
                node scripts/setup.js --restore
            }
            else {
                Write-Host "Restoring from $file ..." -ForegroundColor Yellow
                node scripts/setup.js --restore "db/backups/$file"
            }
        }

        default {
            Write-Host "Skipping database changes." -ForegroundColor Yellow
        }
    }

    # ---------- Restart Backend ----------
    Write-Host "[4/4] Restarting Backend with PM2...`n" -ForegroundColor Yellow
    pm2 restart "HI-api"

    # if (-not (pm2 restart "HI-api" -ErrorAction SilentlyContinue)) {
    #     pm2 start src/index.js --name "HI-api"
    # }

    Invoke-HealthCheck -Url "http://localhost:4000" -Label "Backend"

    Set-Location $oldDir
}

# ============================================================
#  Frontend
# ============================================================

function Update-Frontend {
    param([switch]$Force)

    $oldDir = Get-Location
    Set-Location $FrontendPath

    Write-Host "==================== FRONTEND ====================" -ForegroundColor Cyan

    if (-not $Force) {
        Write-Host "Checking for remote changes..." -ForegroundColor Yellow
        $hasChanges = Test-RemoteChanges -Path $FrontendPath -Branch "main"

        if (-not $hasChanges) {
            Write-Host ">>> Frontend already up to date. Skipping update.`n" -ForegroundColor Green
            Set-Location $oldDir
            return
        }
        Write-Host "New commits found. Proceeding with update.`n" -ForegroundColor Yellow
    }
    else {
        Write-Host "Force mode (-f): skipping change check.`n" -ForegroundColor Yellow
    }

    Write-Host "[1/3] Updating Frontend repo..." -ForegroundColor Yellow
    Get-Location
    git pull origin main

    Write-Host "[2/3] Installing Frontend dependencies...`n" -ForegroundColor Yellow
    npm ci

    Write-Host "[3/3] Building Frontend app...`n" -ForegroundColor Yellow
    npm run build

    if (-not (Get-Process nginx -ErrorAction SilentlyContinue)) {
        Start-Process "D:\nginx-1.28.0\nginx.exe" -ArgumentList "-p D:\nginx-1.28.0"
    }

    Invoke-HealthCheck -Url "http://localhost:3000" -Label "Frontend"

    Set-Location $oldDir
}

# ============================================================
#  Main menu
# ============================================================

Write-Host "What do you want to update?" -ForegroundColor Cyan
Write-Host "  1) Backend"
Write-Host "  2) Frontend"
Write-Host "  3) Both"
$target = Read-Host "Select option [1/2/3] [default 3]"
if ([string]::IsNullOrWhiteSpace($target)) { $target = "3" }

$forceInput = Read-Host "Force update, skip change check? [y/N]"
$f = ($forceInput -eq "y" -or $forceInput -eq "Y")

switch ($target) {
    "1" { Update-Backend  -Force:$f }
    "2" { Update-Frontend -Force:$f }
    "3" {
        Update-Backend  -Force:$f
        Update-Frontend -Force:$f
    }
    default {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
    }
}