# Stop execution if any command fails
$ErrorActionPreference = "Stop"

$oldDir = Get-Location
# ---------- Frontend ----------

Write-Host "[1/3] Updating Frontend repo..." -ForegroundColor Yellow

# Go to frontend repo
Set-Location "C:\apps\insight\frontend"
Get-Location

# Pull latest code
git pull origin main

Write-Host "[2/3] Installing Frontend dependencies...`n" -ForegroundColor Yellow
# Install/update deps
npm ci

Write-Host "[3/3] Building Frontend app...`n" -ForegroundColor Yellow
# Build React app
npm run build

# nginx start if does not running
if (-not (Get-Process nginx -ErrorAction SilentlyContinue)) {
    Start-Process "D:\nginx-1.28.0\nginx.exe" -ArgumentList "-p D:\nginx-1.28.0"
}

# Optional Checking Response
$targetUrl = "http://localhost:3000"
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
    Write-Host ">>> Frontend deployed successfully.`n" -ForegroundColor Green
}
else {
    Write-Host "Error: $($error[0].Exception.Message)" -ForegroundColor Red
    Write-Host ">>> Frontend deployment failed.`n" -ForegroundColor Red
}

Set-Location $oldDir