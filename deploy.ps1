# ========================================
# Auto-Deploy Script for Flutter Web App
# ========================================
# This script automatically:
# 1. Increments build number in pubspec.yaml
# 2. Builds the Flutter web app
# 3. Deploys to Firebase Hosting
# ========================================

Write-Host "🚀 Starting Auto-Deploy Process..." -ForegroundColor Cyan
Write-Host ""

# Step 1: Read current version from pubspec.yaml
Write-Host "📖 Reading current version from pubspec.yaml..." -ForegroundColor Yellow
$pubspecPath = "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw

# Extract version line (format: "version: 1.0.0+1")
$versionMatch = $pubspecContent | Select-String -Pattern "version:\s*(.+)"
if (-not $versionMatch) {
    Write-Host "❌ ERROR: Could not find version in pubspec.yaml" -ForegroundColor Red
    exit 1
}

$currentVersion = $versionMatch.Matches.Groups[1].Value.Trim()
Write-Host "   Current version: $currentVersion" -ForegroundColor White

# Step 2: Parse and increment build number
$parts = $currentVersion -split '\+'
if ($parts.Count -ne 2) {
    Write-Host "❌ ERROR: Invalid version format. Expected 'X.Y.Z+N'" -ForegroundColor Red
    exit 1
}

$versionName = $parts[0]  # e.g., "1.0.0"
$buildNumber = [int]$parts[1]  # e.g., 1

$newBuildNumber = $buildNumber + 1
$newVersion = "$versionName+$newBuildNumber"

Write-Host "   New version: $newVersion" -ForegroundColor Green
Write-Host ""

# Step 3: Update pubspec.yaml
Write-Host "✏️  Updating pubspec.yaml..." -ForegroundColor Yellow
$newPubspecContent = $pubspecContent -replace "version:\s*.+", "version: $newVersion"
Set-Content $pubspecPath -Value $newPubspecContent -Encoding UTF8

Write-Host "   ✅ pubspec.yaml updated successfully" -ForegroundColor Green
Write-Host ""

# Step 4: Clean build artifacts
Write-Host "🧹 Cleaning build artifacts..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: flutter clean failed" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Clean completed" -ForegroundColor Green
Write-Host ""

# Step 5: Build Flutter web app
Write-Host "🔨 Building Flutter web app..." -ForegroundColor Yellow
flutter build web
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: flutter build web failed" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Build completed successfully" -ForegroundColor Green
Write-Host ""

# Step 6: Deploy to Firebase Hosting
Write-Host "🚀 Deploying to Firebase Hosting..." -ForegroundColor Yellow
firebase deploy
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ERROR: firebase deploy failed" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Deploy completed successfully" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
Write-Host "   Version: $currentVersion → $newVersion" -ForegroundColor White
Write-Host "   Build number incremented: $buildNumber → $newBuildNumber" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 The app is now live with version $newVersion" -ForegroundColor Cyan
