# Stop execution if any command fails
$ErrorActionPreference = "Stop"

$oldDir = Get-Location
# ---------- Backend ----------

Write-Host "[1/3] Updating Backend repo..." -ForegroundColor Yellow

# Go to project folder
Set-Location "C:\apps\insight\backend"
Get-Location

# Pull latest code
git pull origin main

Write-Host "[2/3] Installing Backend dependencies...`n" -ForegroundColor Yellow
# Install/update deps
npm ci

Write-Host "[3/3] Restarting Backend with PM2...`n" -ForegroundColor Yellow
# Restart with PM2
if (-not (pm2 restart "HI-api" -ErrorAction SilentlyContinue)) {
    pm2 start src/index.js --name "HI-api"
}

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