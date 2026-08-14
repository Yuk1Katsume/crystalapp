# ============================================================
# deploy_update_github.ps1 — CrystalApp OTA Update via GitHub Releases
# Uso: .\scripts\deploy_update_github.ps1 -Version "1.0.5" -Notes "Nuevas mejoras" -GitHubRepo "TuUsuario/crystalapp" -GitHubToken "ghp_xxx" -ServiceRoleKey "eyJ..."
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$Notes = "Nueva version disponible",

    [Parameter(Mandatory=$true)]
    [string]$GitHubRepo, # formato: propietario/repositorio (ej: usuario/crystalapp)

    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,

    [Parameter(Mandatory=$true)]
    [string]$ServiceRoleKey
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# ---- 1. Bump version in pubspec.yaml ----
Write-Host "`n[1/5] Actualizando version en pubspec.yaml..." -ForegroundColor Cyan
$pubspec = Get-Content "$ProjectRoot\pubspec.yaml" -Raw
if ($pubspec -match 'version:\s*([\d.]+)\+(\d+)') {
    $currentBuild = [int]$Matches[2]
    $newBuild = $currentBuild + 1
    $newVersionLine = "version: $Version+$newBuild"
    $pubspec = $pubspec -replace 'version:\s*[\d.]+\+\d+', $newVersionLine
    Set-Content "$ProjectRoot\pubspec.yaml" $pubspec -NoNewline
    Write-Host "   Version: $Version+$newBuild" -ForegroundColor Green
} else {
    Write-Host "   Error: No se pudo encontrar la version en pubspec.yaml" -ForegroundColor Red
    exit 1
}

# ---- 2. Build release APK ----
Write-Host "`n[2/5] Compilando APK release (arm64-v8a)..." -ForegroundColor Cyan
Set-Location $ProjectRoot
flutter build apk --release --target-platform android-arm64 --split-per-abi
if ($LASTEXITCODE -ne 0) { Write-Host "Build fallido" -ForegroundColor Red; exit 1 }
Write-Host "   APK compilado correctamente" -ForegroundColor Green

$apkPath = "$ProjectRoot\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
if (-not (Test-Path $apkPath)) {
    $apkPath = "$ProjectRoot\build\app\outputs\flutter-apk\app-release.apk"
}

# ---- 3. Create Release on GitHub & Upload APK ----
Write-Host "`n[3/5] Creando Release en GitHub y subiendo APK..." -ForegroundColor Cyan

$ghHeaders = @{
    "Authorization" = "token $GitHubToken"
    "Accept"        = "application/vnd.github.v3+json"
    "User-Agent"    = "CrystalApp-DeployScript"
}

# 3.1 Create GitHub Release
$releaseBody = @{
    "tag_name"         = "v$Version-$newBuild"
    "name"             = "CrystalApp v$Version ($newBuild)"
    "body"             = $Notes
    "draft"            = $false
    "prerelease"       = $false
} | ConvertTo-Json

$createReleaseUrl = "https://api.github.com/repos/$GitHubRepo/releases"
$releaseRes = Invoke-RestMethod -Uri $createReleaseUrl -Method Post -Headers $ghHeaders -Body $releaseBody

# 3.2 Upload Asset to GitHub Release
# upload_url comes back as e.g. "https://uploads.github.com/repos/user/repo/releases/12345/assets{?name,label}"
$uploadBase = $releaseRes.upload_url.Split('{')[0]
$apkBytes = [System.IO.File]::ReadAllBytes($apkPath)
$assetName = "crystalapp-v$Version.apk"
$uploadAssetUrl = "$uploadBase`?name=$assetName"

$assetHeaders = @{
    "Authorization" = "token $GitHubToken"
    "Content-Type"  = "application/vnd.android.package-archive"
    "User-Agent"    = "CrystalApp-DeployScript"
}

$assetRes = Invoke-RestMethod -Uri $uploadAssetUrl -Method Post -Headers $assetHeaders -Body $apkBytes
$apkDownloadUrl = $assetRes.browser_download_url
Write-Host "   APK subido a GitHub Releases: $apkDownloadUrl" -ForegroundColor Green

# ---- 4. Update latest.json in Supabase ----
Write-Host "`n[4/5] Actualizando latest.json en Supabase..." -ForegroundColor Cyan

$supabaseUrl = "https://qxnsdjykzkkikilxaqnv.supabase.co"
$latestJson = @"
{
  "version_name": "$Version",
  "build_number": "$newBuild",
  "apk_url": "$apkDownloadUrl",
  "release_notes": "$Notes"
}
"@

$sbHeaders = @{
    "apikey"        = $ServiceRoleKey
    "Authorization" = "Bearer $ServiceRoleKey"
    "Content-Type"  = "application/json"
    "x-upsert"      = "true"
}

$jsonUrl = "$supabaseUrl/storage/v1/object/app-updates/latest.json"
Invoke-RestMethod -Uri $jsonUrl -Method Post -Headers $sbHeaders -Body ([System.Text.Encoding]::UTF8.GetBytes($latestJson))
Write-Host "   latest.json actualizado en Supabase" -ForegroundColor Green

# ---- 5. Summary ----
Write-Host "`n[5/5] Publicacion completada con GitHub Releases!" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Magenta
Write-Host "  Version:       $Version+$newBuild" -ForegroundColor White
Write-Host "  APK GitHub:    $apkDownloadUrl" -ForegroundColor White
Write-Host "  Notas:         $Notes" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor Magenta
Write-Host "`nLos dispositivos descargaran el APK directamente desde GitHub Releases sin limites de espacio.`n" -ForegroundColor Cyan
