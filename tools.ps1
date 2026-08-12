param(
    [string]$Branch = "release",
    [switch]$ForceUpdate
)

Write-Host "`n==============================================" -ForegroundColor Red
Write-Host "           ADVERTENCIA DE VERSIÓN BETA " -ForegroundColor Red
Write-Host "==============================================" -ForegroundColor Red
Write-Host "Esta aplicación se encuentra en fase de desarrollo BETA.`n" -ForegroundColor Yellow
Write-Host "Algunas funciones pueden realizar cambios irreversibles en: `n"
Write-Host " - Su equipo" -ForegroundColor Red
Write-Host " - Bases de datos" -ForegroundColor Red
Write-Host " - Configuraciones del sistema`n" -ForegroundColor Red
Write-Host "¿Acepta ejecutar esta aplicación bajo su propia responsabilidad? (Y/N)" -ForegroundColor Yellow
$response = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
$answer = $response.Character.ToString().ToUpper()
while ($answer -notin 'Y', 'N') {
    $response = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    $answer = $response.Character.ToString().ToUpper()
}
if ($answer -ne 'Y') {
    Write-Host "`nEjecución cancelada por el usuario.`n" -ForegroundColor Red
    return
}

Clear-Host

$baseRuntimePath = "C:\temp\dztools"
$releasePath = Join-Path $baseRuntimePath "release"
$versionFile = Join-Path $releasePath "version.json"
$mainPath = Join-Path $releasePath "main.ps1"
$Owner = "water0n"
$Repo = "dztools"

function Get-LocalVersion {
    if (-not (Test-Path $versionFile)) {
        return $null
    }
    try {
        $versionData = Get-Content $versionFile -Raw | ConvertFrom-Json
        return $versionData.Version
    } catch {
        return $null
    }
}

function Get-LatestGitHubVersion {
    try {
        $apiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        return $release.tag_name
    } catch {
        Write-Host "  ⚠ No se pudo obtener la versión remota" -ForegroundColor Yellow
        return $null
    }
}

function Compare-Versions {
    param([string]$Local, [string]$Remote)

    $localClean = $Local -replace '^v', ''
    $remoteClean = $Remote -replace '^v', ''

    if ($remoteClean -gt $localClean) {
        return "Newer"
    } elseif ($remoteClean -eq $localClean) {
        return "Same"
    } else {
        return "Older"
    }
}

function Get-UserChoice {
    param([string]$Prompt, [string[]]$ValidChoices)

    Write-Host $Prompt -ForegroundColor Yellow -NoNewline
    $response = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    $answer = $response.Character.ToString().ToUpper()
    Write-Host " $answer"

    while ($answer -notin $ValidChoices) {
        Write-Host $Prompt -ForegroundColor Yellow -NoNewline
        $response = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $answer = $response.Character.ToString().ToUpper()
        Write-Host " $answer"
    }

    return $answer
}

$localVersion = Get-LocalVersion
$hasLocalInstall = (Test-Path $mainPath) -and ($null -ne $localVersion)

if ($hasLocalInstall -and -not $ForceUpdate) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  📦 Instalación local detectada" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Versión local:  " -NoNewline -ForegroundColor Gray
    Write-Host "$localVersion" -ForegroundColor Green
    Write-Host "  Ruta:           " -NoNewline -ForegroundColor Gray
    Write-Host "$releasePath" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Verificando actualizaciones..." -ForegroundColor Yellow
    $remoteVersion = Get-LatestGitHubVersion

    if ($null -ne $remoteVersion) {
        Write-Host "  Versión remota: " -NoNewline -ForegroundColor Gray

        $comparison = Compare-Versions -Local $localVersion -Remote $remoteVersion

        switch ($comparison) {
            "Same" {
                Write-Host "$remoteVersion " -NoNewline -ForegroundColor Green
                Write-Host "✓ Actualizado" -ForegroundColor Green
                Write-Host ""
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  ✅ Ya tienes la última versión. Iniciando versión local..." -ForegroundColor Green
                Write-Host ""

                $exe = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh" } else { "powershell" }
                & $exe -NoProfile -ExecutionPolicy Bypass -File $mainPath
                return
            }
            "Newer" {
                Write-Host "$remoteVersion " -NoNewline -ForegroundColor Yellow
                Write-Host "⚠ Actualización disponible" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
                Write-Host ""

                $choice = Get-UserChoice "¿Descargar nueva versión? (S/N): " @('S', 'N')

                if ($choice -eq 'N') {
                    Write-Host ""
                    Write-Host "Iniciando versión local..." -ForegroundColor Green
                    Write-Host ""
                    $exe = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh" } else { "powershell" }
                    & $exe -NoProfile -ExecutionPolicy Bypass -File $mainPath
                    return
                }
            }
            "Older" {
                Write-Host "$remoteVersion " -NoNewline -ForegroundColor DarkGray
                Write-Host "ℹ Versión local más reciente" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
                Write-Host ""

                $choice = Get-UserChoice "¿Ejecutar versión local? (S/N): " @('S', 'N')

                if ($choice -eq 'S') {
                    Write-Host ""
                    Write-Host "Iniciando versión local..." -ForegroundColor Green
                    Write-Host ""
                    $exe = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh" } else { "powershell" }
                    & $exe -NoProfile -ExecutionPolicy Bypass -File $mainPath
                    return
                } else {
                    Write-Host "`nEjecución cancelada.`n" -ForegroundColor Yellow
                    return
                }
            }
        }
    } else {
        Write-Host "  ⚠ No se pudo verificar versión remota" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host ""

        $choice = Get-UserChoice "¿Ejecutar versión local? (S/N): " @('S', 'N')

        if ($choice -eq 'S') {
            Write-Host ""
            Write-Host "Iniciando versión local..." -ForegroundColor Green
            Write-Host ""
            $exe = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh" } else { "powershell" }
            & $exe -NoProfile -ExecutionPolicy Bypass -File $mainPath
            return
        } else {
            Write-Host "`nEjecución cancelada.`n" -ForegroundColor Yellow
            return
        }
    }
}

Write-Host ""
if ($ForceUpdate) {
    Write-Host "Forzando actualización..." -ForegroundColor Yellow
} else {
    Write-Host "Descargando nueva instalación..." -ForegroundColor Yellow
}
Write-Host ""

if (-not (Test-Path $baseRuntimePath)) {
    New-Item -ItemType Directory -Path $baseRuntimePath | Out-Null
}

Write-Host "Preparando entorno..." -ForegroundColor Yellow

$zipPath = Join-Path $baseRuntimePath "dztools.zip"

Write-Host "Limpiando versión anterior..." -ForegroundColor Yellow
try {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path $releasePath) { Remove-Item $releasePath -Recurse -Force -ErrorAction SilentlyContinue }
} catch {}

$zipUrl = "https://github.com/$Owner/$Repo/releases/latest/download/dztools-release.zip"

Write-Host "Descargando última versión..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Write-Host "  ✓ Descarga completada" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Error al descargar: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host "Extrayendo archivos..." -ForegroundColor Yellow
try {
    if (-not (Test-Path $releasePath)) {
        New-Item -ItemType Directory -Path $releasePath | Out-Null
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $releasePath)
    Write-Host "  ✓ Extracción completada" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Error al extraer: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host "Preparando aplicación..." -ForegroundColor Yellow
if (-not (Test-Path $mainPath)) {
    Write-Host "  ✗ No se encontró main.ps1 en la carpeta release." -ForegroundColor Red
    Write-Host "  Ruta esperada: $mainPath" -ForegroundColor DarkYellow
    return
}

$newVersion = Get-LocalVersion
if ($newVersion) {
    Write-Host "  ✓ Versión instalada: $newVersion" -ForegroundColor Green
} else {
    Write-Host "  ✓ Instalación completada" -ForegroundColor Green
}

Write-Host ""
Write-Host "=================================================" -ForegroundColor Gray
Write-Host "   Iniciando Gerardo Zermeño Tools" -ForegroundColor Green
if ($newVersion) {
    Write-Host "   Versión: $newVersion" -ForegroundColor DarkGray
}
Write-Host "   Canal: $Branch" -ForegroundColor DarkGray
Write-Host "   Carpeta: $releasePath" -ForegroundColor DarkGray
Write-Host "=================================================" -ForegroundColor Gray
Write-Host ""

$exe = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh" } else { "powershell" }
& $exe -NoProfile -ExecutionPolicy Bypass -File $mainPath
