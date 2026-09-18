<#
.SYNOPSIS
    Fibex EDMS Local Development Manager (Podman)

.DESCRIPTION
    Helper script to run and manage Fibex EDMS in local development with live reload.

.EXAMPLE
    .\dev.ps1 start       # Starts dev server with live reload
    .\dev.ps1 stop        # Stops the running dev container
    .\dev.ps1 logs        # Follows container logs
    .\dev.ps1 shell       # Opens a bash prompt in the dev container
    .\dev.ps1 manage ...  # Runs manage.py commands (e.g. .\dev.ps1 manage check)
#>

param (
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "restart", "logs", "shell", "manage", "status")]
    [string]$Action = "start",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = "Stop"
$ContainerName = "fibex-dev"
$ComposeFile = "docker-compose.dev.yml"

function Start-DevServer {
    Write-Host ">>> Checking if $ContainerName is already running..." -ForegroundColor Cyan
    $running = podman ps --filter "name=$ContainerName" --format "{{.Names}}"
    if ($running -eq $ContainerName) {
        Write-Host ">>> $ContainerName is already running at http://localhost:8000" -ForegroundColor Green
        return
    }

    # Clean up any stopped container with same name
    podman rm -f $ContainerName 2>$null | Out-Null

    Write-Host ">>> Starting Fibex EDMS Dev Server with Live Reload..." -ForegroundColor Cyan
    Write-Host ">>> Using network_mode: host (accessible at http://localhost:8000)" -ForegroundColor DarkGray

    # Use podman run directly for maximum reliability across Windows/WSL
    podman run -d `
        --name $ContainerName `
        --network host `
        -v ".:/app:z" `
        -w /app `
        -e DJANGO_SETTINGS_MODULE=mayan.settings.development `
        -e MAYAN_MEDIA_ROOT=/app/mayan/media `
        -e PYTHONUNBUFFERED=1 `
        fibex-edms-app:latest `
        python manage.py runserver 0.0.0.0:8000 --settings=mayan.settings.development

    Write-Host ">>> Container launched. Waiting for server to initialize..." -ForegroundColor Cyan
    
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:8000" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($resp.StatusCode -in 200, 302) {
                $ready = $true
                break
            }
        } catch {
            # Still booting
        }
        Write-Host -NoNewline "."
    }
    Write-Host ""

    if ($ready) {
        Write-Host ">>> Fibex EDMS is READY at: http://localhost:8000" -ForegroundColor Green
        Write-Host ">>> Live reload is active! Edit any code in your IDE to trigger reload." -ForegroundColor Green
    } else {
        Write-Host ">>> Server is still booting. Follow logs with: .\dev.ps1 logs" -ForegroundColor Yellow
    }
}

function Stop-DevServer {
    Write-Host ">>> Stopping $ContainerName..." -ForegroundColor Cyan
    podman stop $ContainerName 2>$null | Out-Null
    podman rm $ContainerName 2>$null | Out-Null
    Write-Host ">>> Stopped." -ForegroundColor Green
}

function Show-Logs {
    podman logs -f $ContainerName
}

function Enter-Shell {
    podman exec -it $ContainerName /bin/bash
}

function Run-Manage {
    if (-not $ExtraArgs) {
        Write-Host "Usage: .\dev.ps1 manage <command> (e.g. .\dev.ps1 manage check)" -ForegroundColor Yellow
        return
    }
    podman exec -it $ContainerName python manage.py $ExtraArgs
}

function Show-Status {
    podman ps --filter "name=$ContainerName"
}

switch ($Action) {
    "start"   { Start-DevServer }
    "stop"    { Stop-DevServer }
    "restart" { Stop-DevServer; Start-DevServer }
    "logs"    { Show-Logs }
    "shell"   { Enter-Shell }
    "manage"  { Run-Manage }
    "status"  { Show-Status }
}
