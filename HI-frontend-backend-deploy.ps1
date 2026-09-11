<#
.SYNOPSIS
    Combined Backend + Frontend deployment script for Insight.

.DESCRIPTION
    Lets you choose Backend / Frontend / Both.
    By default, each component checks whether the remote repo actually has
    new commits before doing anything (git fetch + compare HEAD vs origin/main).
    If there are no new commits, that component's update is skipped.
    Answering "y" to the force prompt skips the change check entirely.

.EXAMPLE
    .\deploy.ps1
#>

$ErrorActionPreference = "Stop"

$BackendPath   = "C:\apps\insight\backend"
$FrontendPath  = "C:\apps\insight\frontend"
$NginxExe      = "D:\nginx-1.28.0\nginx.exe"
$NginxPrefix   = "D:\nginx-1.28.0"
$Pm2AppName    = "HI-api"
$Pm2StartEntry = "src/index.js"

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

function Test-UncommittedChanges {
    param([Parameter(Mandatory)][string]$Path)

    Push-Location $Path
    try {
        $status = git status --porcelain
        return -not [string]::IsNullOrWhiteSpace($status)
    }
    finally {
        Pop-Location
    }
}

function Invoke-SafePull {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Branch = "main"
    )

    if (Test-UncommittedChanges -Path $Path) {
        Write-Host "WARNING: Uncommitted local changes detected in $Path." -ForegroundColor Red
        $choice = Read-Host "Type STASH to stash them and continue, or anything else to abort"
        if ($choice -ne "STASH") {
            throw "Update aborted due to uncommitted changes in $Path."
        }
        git stash push -m "deploy.ps1 auto-stash $(Get-Date -Format o)"
        Write-Host "Local changes stashed. Run 'git stash pop' later to restore them." -ForegroundColor Yellow
    }

    git pull origin $Branch
}

function Restart-Pm2App {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$StartEntry
    )

    $running = $false
    try {
        $list = pm2 jlist 2>$null | ConvertFrom-Json
        $running = [bool]($list | Where-Object { $_.name -eq $Name })
    } catch {
        $running = $false
    }

    if ($running) {
        Write-Host "Restarting existing PM2 process '$Name'..." -ForegroundColor Yellow
        pm2 restart $Name
    }
    else {
        Write-Host "PM2 process '$Name' not found. Starting it fresh..." -ForegroundColor Yellow
        pm2 start $StartEntry --name $Name
    }
}

function Update-NginxServing {
    param(
        [Parameter(Mandatory)][string]$NginxExe,
        [Parameter(Mandatory)][string]$NginxPrefix
    )

    if (Get-Process nginx -ErrorAction SilentlyContinue) {
        Write-Host "Nginx already running. Reloading to pick up new build..." -ForegroundColor Yellow
        & $NginxExe -s reload -p $NginxPrefix
    }
    else {
        Write-Host "Nginx not running. Starting it..." -ForegroundColor Yellow
        Start-Process $NginxExe -ArgumentList "-p $NginxPrefix"
    }
}

function Invoke-HealthCheck {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Label,
        [int]$MaxAttempts = 5,
        [int]$DelaySeconds = 2
    )

    Write-Host "Request Check at $Url"

    $response  = $null
    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {

        try {
            $response = Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 5
            break
        }
        catch {
            $lastError = $_.Exception.Message
            $response  = $null
        }

        # spinner while waiting for the next attempt (skip after the last attempt)
        if ($attempt -lt $MaxAttempts) {
            $chars = "/-\|"
            $ticks = $DelaySeconds * 5   # 5 ticks/sec * DelaySeconds, 200ms each
            for ($i = 0; $i -lt $ticks; $i++) {
                $c = $chars[$i % $chars.Length]
                Write-Host "`b$c" -NoNewline
                Start-Sleep -Milliseconds 200
            }
            Write-Host "`b " -NoNewline
        }
    }
    Write-Host ""

    if ($response) {
        Write-Host "StatusCode: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "StatusDescription: $($response.StatusDescription)" -ForegroundColor Green
        Write-Host ">>> $Label deployed successfully.`n" -ForegroundColor Green
    }
    else {
        Write-Host "Error: $lastError" -ForegroundColor Red
        Write-Host ">>> $Label deployment failed (no response after $MaxAttempts attempts).`n" -ForegroundColor Red
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
        Write-Host "Force mode: skipping change check.`n" -ForegroundColor Yellow
    }

    Write-Host "[1/4] Updating Backend repo..." -ForegroundColor Yellow
    Get-Location
    Invoke-SafePull -Path $BackendPath -Branch "main"

    Write-Host "[2/4] Installing Backend dependencies...`n" -ForegroundColor Yellow
    npm ci

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
    Restart-Pm2App -Name $Pm2AppName -StartEntry $Pm2StartEntry

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
        Write-Host "Force mode: skipping change check.`n" -ForegroundColor Yellow
    }

    Write-Host "[1/3] Updating Frontend repo..." -ForegroundColor Yellow
    Get-Location
    Invoke-SafePull -Path $FrontendPath -Branch "main"

    Write-Host "[2/3] Installing Frontend dependencies...`n" -ForegroundColor Yellow
    npm ci

    Write-Host "[3/3] Building Frontend app...`n" -ForegroundColor Yellow
    npm run build

    Update-NginxServing -NginxExe $NginxExe -NginxPrefix $NginxPrefix

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