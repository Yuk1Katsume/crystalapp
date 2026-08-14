$supabaseUrl = 'https://qxnsdjykzkkikilxaqnv.supabase.co'
# IMPORTANTE: Usa el SERVICE ROLE KEY (no el anon key) para bypasear RLS
# Encuéntralo en: Supabase Dashboard → Settings → API → service_role key
$serviceRoleKey = $args[0]

if (-not $serviceRoleKey) {
    Write-Host 'USO: .\upload_only.ps1 <service_role_key>' -ForegroundColor Red
    Write-Host 'Obtén el key en: https://supabase.com/dashboard/project/qxnsdjykzkkikilxaqnv/settings/api' -ForegroundColor Yellow
    exit 1
}

$apkPublicUrl = $supabaseUrl + '/storage/v1/object/public/app-updates/crystalapp-latest.apk'

$jsonHeaders = @{
    'apikey'        = $serviceRoleKey
    'Authorization' = 'Bearer ' + $serviceRoleKey
    'Content-Type'  = 'application/json'
    'x-upsert'      = 'true'
}

# Step 1: Create bucket with service role key
Write-Host '[1/3] Asegurando bucket app-updates...' -ForegroundColor Cyan
$bucketBody = '{"id":"app-updates","name":"app-updates","public":true}'
try {
    Invoke-RestMethod -Uri ($supabaseUrl + '/storage/v1/bucket') -Method Post -Headers $jsonHeaders -Body $bucketBody
    Write-Host '   Bucket creado' -ForegroundColor Green
} catch {
    Write-Host '   Bucket ya existe' -ForegroundColor Yellow
}

# Step 2: Upload APK (arm64 only, much smaller)
$apkSource = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-release.apk'
$arm64Apk  = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'

$apkToUpload = if (Test-Path $arm64Apk) { $arm64Apk } elseif (Test-Path $apkSource) { $apkSource } else { $null }

if ($apkToUpload) {
    $sizeMB = [math]::Round((Get-Item $apkToUpload).Length / 1MB, 1)
    Write-Host "[2/3] Subiendo APK ($sizeMB MB)..." -ForegroundColor Cyan
    $apkBytes = [System.IO.File]::ReadAllBytes($apkToUpload)
    $apkHeaders = @{
        'apikey'        = $serviceRoleKey
        'Authorization' = 'Bearer ' + $serviceRoleKey
        'Content-Type'  = 'application/octet-stream'
        'x-upsert'      = 'true'
    }
    try {
        Invoke-RestMethod -Uri ($supabaseUrl + '/storage/v1/object/app-updates/crystalapp-latest.apk') -Method Post -Headers $apkHeaders -Body $apkBytes
        Write-Host '   APK subido correctamente' -ForegroundColor Green
    } catch {
        Write-Host "   Error: $_" -ForegroundColor Red
        $apkPublicUrl = ''
    }
} else {
    Write-Host '[2/3] No se encontro APK, omitiendo...' -ForegroundColor Yellow
    $apkPublicUrl = ''
}

# Step 3: Upload latest.json
Write-Host '[3/3] Subiendo latest.json...' -ForegroundColor Cyan
$version = if ($args[1]) { $args[1] } else { '1.0.4' }
$build   = if ($args[2]) { $args[2] } else { '5' }
$notes   = if ($args[3]) { $args[3] } else { 'Mejoras de rendimiento y nuevas funciones' }
$latestJson = '{"version_name":"' + $version + '","build_number":"' + $build + '","apk_url":"' + $apkPublicUrl + '","release_notes":"' + $notes + '"}'
try {
    Invoke-RestMethod -Uri ($supabaseUrl + '/storage/v1/object/app-updates/latest.json') -Method Post -Headers $jsonHeaders -Body ([System.Text.Encoding]::UTF8.GetBytes($latestJson))
    Write-Host '   latest.json subido' -ForegroundColor Green
} catch {
    Write-Host "   Error: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host "=== Publicado: v$version+$build ===" -ForegroundColor Magenta
