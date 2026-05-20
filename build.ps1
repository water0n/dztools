#requires -Version 5.0
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("patch", "minor", "major")]
    [string]$Bump = "patch",
    [Parameter(Mandatory = $false)]
    [switch]$Test,
    [Parameter(Mandatory = $false)]
    [switch]$Release,
    [Parameter(Mandatory = $false)]
    [string]$Version
)
Write-Host "=== Gerardo Zermeño Tools Build Script ===" -ForegroundColor Cyan
Write-Host "Directorio: $PSScriptRoot" -ForegroundColor Yellow
Write-Host "PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$SrcPath = Join-Path $ProjectRoot "src"
$ReleasePath = Join-Path $ProjectRoot "release"
$VersionFile = Join-Path $SrcPath "version.json"
function Get-CurrentVersion {
    if (Test-Path $VersionFile) {
        try {
            $content = Get-Content $VersionFile -Raw
            $data = $content | ConvertFrom-Json
            return [version]$data.Version
        } catch {
            Write-Host "Error leyendo version.json: $_" -ForegroundColor Yellow
            return [version]"0.1.0"
        }
    }
    return [version]"0.1.0"
}
if ($Test) {
    Write-Host "`nEJECUTANDO PRUEBAS..." -ForegroundColor Green

    if (-not (Get-Module -Name Pester -ListAvailable)) {
        Write-Host "Instalando Pester..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -Scope CurrentUser -AllowClobber
    }

    if (-not (Test-Path ".\tests")) {
        Write-Host "Creando carpeta tests básica..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path ".\tests" -Force | Out-Null

        @'
# Pruebas básicas
Describe "Pruebas iniciales" {
    It "Debe existir el archivo main.ps1" {
        Test-Path ".\src\main.ps1" | Should -Be $true
    }

    It "Deben existir los módulos" {
        $modules = @("GUI.psm1", "Database.psm1", "Utilities.psm1", "SqlTreeView.psm1", "Installers.psm1", "WindowsUtilities.psm1", "NationalUtilities.psm1", "SqlOps.psm1", "QueriesPad.psm1")
        foreach ($module in $modules) {
            Test-Path ".\src\modules\$module" | Should -Be $true
        }
    }
}
'@ | Out-File -FilePath ".\tests\Basic.Tests.ps1" -Encoding UTF8
    }
    try {
        $result = Invoke-Pester -Path ".\tests" -PassThru
        if ($result.FailedCount -gt 0) {
            Write-Host "Pruebas fallidas: $($result.FailedCount)" -ForegroundColor Red
            exit 1
        }
        Write-Host "✓ Todas las pruebas pasaron ($($result.PassedCount) pruebas)" -ForegroundColor Green
    } catch {
        Write-Host "Error ejecutando pruebas: $_" -ForegroundColor Red
        exit 1
    }
}
if ($Release) {
    Write-Host "`nCREANDO RELEASE..." -ForegroundColor Green
    if ($Version) {
        $versionString = $Version
        Write-Host "Usando versión proporcionada: $versionString" -ForegroundColor Cyan
    } else {
        $currentVersion = Get-CurrentVersion
        Write-Host "Versión actual: $currentVersion" -ForegroundColor Yellow
        $major = $currentVersion.Major
        $minor = $currentVersion.Minor
        $build = $currentVersion.Build
        switch ($Bump) {
            "major" {
                $major++
                $minor = 0
                $build = 0
            }
            "minor" {
                $minor++
                $build = 0
            }
            "patch" {
                if ($build -lt 0) { $build = 0 } else { $build++ }
            }
        }
        $newVersion = [version]::new($major, $minor, $build)
        $versionString = $newVersion.ToString()
        Write-Host "Nueva versión: $versionString" -ForegroundColor Cyan
    }
    $versionInfo = [ordered]@{
        Version     = $versionString
        LastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    }
    $versionInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $VersionFile -Encoding UTF8
    Write-Host "version.json actualizado en: $VersionFile" -ForegroundColor Green
    if (Test-Path $ReleasePath) {
        Remove-Item $ReleasePath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ReleasePath -Force | Out-Null
    Write-Host "Copiando archivos..." -ForegroundColor Yellow
    $mustHave = @(
        (Join-Path $SrcPath "lib\AvalonEdit.dll"),
        (Join-Path $SrcPath "resources\SQL.xshd")
    )

    foreach ($f in $mustHave) {
        if (-not (Test-Path $f)) { throw "Falta archivo requerido: $f" }
    }
    Copy-Item -Path "$SrcPath\*" -Destination $ReleasePath -Recurse -Force
    $mainFile = Join-Path $ReleasePath "main.ps1"
    if (Test-Path $mainFile) {
        (Get-Content $mainFile) -replace '\$global:version = ".*?"', "`$global:version = `"$versionString`"" |
        Out-File $mainFile -Encoding UTF8
    }
    @'
@echo off
cls
echo ===================================================
echo   ...Local RUN \ GDZT Tools - Suite de Utilidades
echo ===================================================
echo.

if not exist "C:\Temp" (
    mkdir C:\Temp
    echo Carpeta C:\Temp creada
)

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0main.ps1"

if %errorlevel% neq 0 (
    echo.
    echo Error al ejecutar la herramienta
    pause
)
'@ | Out-File -FilePath "$ReleasePath\run.bat" -Encoding ASCII
    Write-Host "✓ Release creado en: $ReleasePath" -ForegroundColor Green
    $zipPath = Join-Path $ProjectRoot "dztools-release.zip"
    Write-Host "Creando zip: $zipPath" -ForegroundColor Yellow

    $tempZipRoot = Join-Path $env:TEMP ("dztools_zip_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempZipRoot -Force | Out-Null

    try {
        # Copiamos el release a temporal para evitar locks
        Copy-Item -Path (Join-Path $ReleasePath '*') -Destination $tempZipRoot -Recurse -Force

        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

        Compress-Archive -Path (Join-Path $tempZipRoot '*') -DestinationPath $zipPath -Force
        Write-Host "✓ ZIP generado correctamente: $zipPath" -ForegroundColor Green
    } catch {
        Write-Host "❌ Error creando el ZIP: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        # Limpieza
        Remove-Item $tempZipRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "`n✅ Proceso completado" -ForegroundColor Green