Write-Host "Iniciando Antigravity IDE con Remote Debugging en puerto 9000..." -ForegroundColor Cyan
Start-Process "antigravity" -ArgumentList "--remote-debugging-port=9000"
