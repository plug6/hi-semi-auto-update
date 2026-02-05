# Stop execution if any command fails
$ErrorActionPreference = "Stop"

$oldDir = Get-Location
# ---------- Backend ----------

Write-Host "[1/4] Updating Backend repo..." -ForegroundColor Yellow

# Go to project folder
Set-Location "C:\apps\insight\backend"
Get-Location

# Pull latest code
git pull origin main

Write-Host "[2/4] Installing Backend dependencies...`n" -ForegroundColor Yellow
# Install/update deps
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
# Restart with PM2
if (-not (pm2 restart "HI-api" -ErrorAction SilentlyContinue)) {
    pm2 start src/index.js --name "HI-api"
}

# ---------- Health Check ----------
# Optional Checking Responce
$targetUrl = "http://localhost:4000"
$response = Invoke-WebRequest $targetUrl -UseBasicParsing -ErrorAction SilentlyContinue

Write-Host "Request Check at $targetUrl"
$chars = "/-\|"
for ($i = 0; $i -lt 10; $i++) {
    $c = $chars[$i % $chars.Length]
    Write-Host "`b$c" -NoNewline
    Start-Sleep -Milliseconds 200
}

Write-Host "`b "   # clear spinner

if ($?) {
    Write-Host "StatusCode: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "StatusDescription: $($response.StatusDescription)" -ForegroundColor Green
    Write-Host ">>> Backend deployed successfully.`n" -ForegroundColor Green
}
else {
    Write-Host "Error: $($error[0].Exception.Message)" -ForegroundColor Red
    Write-Host ">>> Backend deployment failed.`n" -ForegroundColor Red
}

Set-Location $oldDir