param(
    [Parameter(Mandatory=$false)]
    [string]$Version = "1.2.1",

    [Parameter(Mandatory=$false)]
    [string]$Notes = "Fotos de perfil en contactos y seleccion de miembros para grupos",

    [Parameter(Mandatory=$false)]
    [string]$GitHubRepo = "Yuk1Katsume/crystalapp",

    [Parameter(Mandatory=$false)]
    [string]$GitHubToken = $env:GITHUB_TOKEN,

    [Parameter(Mandatory=$false)]
    [string]$SupabaseKey = "sb_publishable_mUZuacNconoEDYTYg6DEDA_dkL_ZknI"
)

if (-not $GitHubToken) {
    # Extract token from git remote if present
    $remoteUrl = git remote get-url origin
    if ($remoteUrl -match 'ghp_[a-zA-Z0-9]+') {
        $GitHubToken = $Matches[0]
    }
}

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
    Write-Host "   Nueva Version: $Version+$newBuild" -ForegroundColor Green
} else {
    Write-Host "   Error: No se pudo parsear la version en pubspec.yaml" -ForegroundColor Red
    exit 1
}

# ---- 2. Build release APK ----
Write-Host "`n[2/5] Compilando APK release (arm64-v8a)..." -ForegroundColor Cyan
Set-Location $ProjectRoot
flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub
if ($LASTEXITCODE -ne 0) {
    Write-Host "Reintentando build generico..." -ForegroundColor Yellow
    flutter build apk --release --no-pub
    if ($LASTEXITCODE -ne 0) { Write-Host "Build fallido" -ForegroundColor Red; exit 1 }
}

$apkPath = "$ProjectRoot\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
if (-not (Test-Path $apkPath)) {
    $apkPath = "$ProjectRoot\build\app\outputs\flutter-apk\app-release.apk"
}
$sizeMB = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
Write-Host "   APK compilado correctamente ($sizeMB MB)" -ForegroundColor Green

# ---- 3. Create Release on GitHub & Upload APK ----
Write-Host "`n[3/5] Creando Release en GitHub y subiendo APK..." -ForegroundColor Cyan

$ghHeaders = @{
    "Authorization" = "token $GitHubToken"
    "Accept"        = "application/vnd.github.v3+json"
    "User-Agent"    = "CrystalApp-DeployScript"
}

$releaseBody = @{
    "tag_name"         = "v$Version-$newBuild"
    "name"             = "CrystalApp v$Version ($newBuild)"
    "body"             = $Notes
    "draft"            = $false
    "prerelease"       = $false
} | ConvertTo-Json

$createReleaseUrl = "https://api.github.com/repos/$GitHubRepo/releases"
$releaseRes = Invoke-RestMethod -Uri $createReleaseUrl -Method Post -Headers $ghHeaders -Body ([System.Text.Encoding]::UTF8.GetBytes($releaseBody)) -ContentType "application/json; charset=utf-8"

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
Write-Host "`n[4/5] Actualizando latest.json en Supabase para activar popup OTA..." -ForegroundColor Cyan

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
    "apikey"        = $SupabaseKey
    "Authorization" = "Bearer $SupabaseKey"
    "Content-Type"  = "application/json"
    "x-upsert"      = "true"
}

$jsonUrl = "$supabaseUrl/storage/v1/object/app-updates/latest.json"
Invoke-RestMethod -Uri $jsonUrl -Method Post -Headers $sbHeaders -Body ([System.Text.Encoding]::UTF8.GetBytes($latestJson))
Write-Host "   latest.json actualizado en Supabase" -ForegroundColor Green

# ---- 5. Commit and Push to Git ----
Write-Host "`n[5/5] Subiendo cambios y tag a Git..." -ForegroundColor Cyan
git add -A
git commit -m "release: v$Version+$newBuild - $Notes"
git push origin main

Write-Host "`n=======================================" -ForegroundColor Magenta
Write-Host "  DESPLIEGUE OTA COMPLETADO CON ÉXITO!" -ForegroundColor Green
Write-Host "  Version:       $Version+$newBuild" -ForegroundColor White
Write-Host "  APK GitHub:    $apkDownloadUrl" -ForegroundColor White
Write-Host "  Notas:         $Notes" -ForegroundColor White
Write-Host "=======================================`n" -ForegroundColor Magenta
