# ============================================================
# deploy_update.ps1 — CrystalApp OTA Update Publisher
# Uso: .\scripts\deploy_update.ps1 -Version "1.0.3" -Notes "Correcciones y mejoras"
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$Notes = "Nueva version disponible"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# ---- 1. Bump version in pubspec.yaml ----
Write-Host "`n[1/5] Actualizando version en pubspec.yaml..." -ForegroundColor Cyan
$pubspec = Get-Content "$ProjectRoot\pubspec.yaml" -Raw
# Extract current build number and increment
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
Write-Host "`n[2/5] Compilando APK..." -ForegroundColor Cyan
Set-Location $ProjectRoot
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Write-Host "Build fallido" -ForegroundColor Red; exit 1 }
Write-Host "   APK compilado correctamente" -ForegroundColor Green

$apkSource = "$ProjectRoot\build\app\outputs\flutter-apk\app-release.apk"

# ---- 3. Upload APK to Supabase Storage ----
Write-Host "`n[3/5] Subiendo APK a Supabase Storage..." -ForegroundColor Cyan

# Read Supabase config from supabase_config.dart
$configFile = Get-Content "$ProjectRoot\lib\services\supabase_config.dart" -Raw
$supabaseUrl = if ($configFile -match "url\s*=\s*'([^']+)'") { $Matches[1] } else { "" }
$supabaseKey = if ($configFile -match "anonKey\s*=\s*'([^']+)'") { $Matches[1] } else { "" }

if (-not $supabaseUrl -or -not $supabaseKey) {
    Write-Host "   Error: No se pudo leer la config de Supabase" -ForegroundColor Red
    exit 1
}

$apkBytes = [System.IO.File]::ReadAllBytes($apkSource)
$headers = @{
    "apikey"        = $supabaseKey
    "Authorization" = "Bearer $supabaseKey"
    "Content-Type"  = "application/octet-stream"
    "x-upsert"      = "true"
}

$uploadUrl = "$supabaseUrl/storage/v1/object/app-updates/crystalapp-latest.apk"
Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -Body $apkBytes
Write-Host "   APK subido correctamente" -ForegroundColor Green

$apkPublicUrl = "$supabaseUrl/storage/v1/object/public/app-updates/crystalapp-latest.apk"

# ---- 4. Upload latest.json ----
Write-Host "`n[4/5] Actualizando latest.json en Supabase..." -ForegroundColor Cyan

$latestJson = @"
{
  "version_name": "$Version",
  "build_number": "$newBuild",
  "apk_url": "$apkPublicUrl",
  "release_notes": "$Notes"
}
"@

$jsonHeaders = @{
    "apikey"        = $supabaseKey
    "Authorization" = "Bearer $supabaseKey"
    "Content-Type"  = "application/json"
    "x-upsert"      = "true"
}

$jsonUrl = "$supabaseUrl/storage/v1/object/app-updates/latest.json"
Invoke-RestMethod -Uri $jsonUrl -Method Post -Headers $jsonHeaders -Body ([System.Text.Encoding]::UTF8.GetBytes($latestJson))
Write-Host "   latest.json actualizado" -ForegroundColor Green

# ---- 5. Summary ----
Write-Host "`n[5/5] Publicacion completada!" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Magenta
Write-Host "  Version:       $Version+$newBuild" -ForegroundColor White
Write-Host "  APK URL:       $apkPublicUrl" -ForegroundColor White
Write-Host "  Notas:         $Notes" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor Magenta
Write-Host "`nLos dispositivos recibiran la notificacion de actualizacion al abrir la app.`n" -ForegroundColor Cyan
