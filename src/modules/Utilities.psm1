#requires -Version 5.0
#Utilities.psm1 - Módulo de utilidades para DzTools

$script:DzToolsConfigPath = "C:\Temp\dztools\dztools.ini"
$script:DzDebugEnabled = $null

function Get-DzToolsConfigPath {
    return $script:DzToolsConfigPath
}
function Get-DzDebugPreference {
    $configPath = Get-DzToolsConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $false
    }
    $content = Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue
    $inDevSection = $false

    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*;') { continue }
        if ($trimmed -match '^\[desarrollo\]\s*$') {
            $inDevSection = $true
            continue
        }
        if ($inDevSection -and $trimmed -match '^\[') {
            break
        }
        if ($inDevSection -and $trimmed -match '^\s*debug\s*=\s*(.+)\s*$') {
            return ($matches[1].ToLower() -eq 'true')
        }
    }
    return $false
}
function Ensure-DzUiConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return
    }

    $content = Get-Content -LiteralPath $ConfigPath -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = @() }

    $lines = New-Object System.Collections.Generic.List[string]
    $uiFound = $false
    $modeFound = $false
    $inUiSection = $false

    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*;') {
            $lines.Add($line)
            continue
        }
        if ($trimmed -match '^\[UI\]\s*$') {
            $uiFound = $true
            $inUiSection = $true
            $lines.Add($line)
            continue
        }
        if ($inUiSection -and $trimmed -match '^\[') {
            if (-not $modeFound) {
                $lines.Add("mode=light")
                $modeFound = $true
            }
            $inUiSection = $false
        }
        if ($inUiSection -and $trimmed -match '^\s*mode\s*=\s*(.+)\s*$') {
            $modeFound = $true
        }
        $lines.Add($line)
    }

    if ($uiFound -and -not $modeFound) {
        $lines.Add("mode=light")
    }
    if (-not $uiFound) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne "") {
            $lines.Add("")
        }
        $lines.Add("[UI]")
        $lines.Add("mode=light")
    }

    Set-Content -LiteralPath $ConfigPath -Value $lines -Encoding UTF8
}
function Update-DzIniSetting {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $configPath = Get-DzToolsConfigPath

    if (-not (Test-Path -LiteralPath $configPath)) {
        Initialize-DzToolsConfig | Out-Null
    }

    $content = Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = @() }

    $lines = New-Object System.Collections.Generic.List[string]
    $sectionFound = $false
    $keyUpdated = $false
    $inTargetSection = $false
    $escapedKey = [regex]::Escape($Key)

    foreach ($line in $content) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^\s*;') {
            $lines.Add($line)
            continue
        }

        if ($trimmed -match '^\[(.+)\]\s*$') {
            if ($inTargetSection -and -not $keyUpdated) {
                $lines.Add("$Key=$Value")
                $keyUpdated = $true
            }

            $currentSection = $matches[1].Trim()
            $inTargetSection = ($currentSection.ToLower() -eq $Section.ToLower())
            if ($inTargetSection) { $sectionFound = $true }

            $lines.Add($line)
            continue
        }

        if ($inTargetSection -and $trimmed -match "^\s*${escapedKey}\s*=") {
            $lines.Add("$Key=$Value")
            $keyUpdated = $true
            continue
        }

        $lines.Add($line)
    }

    if ($sectionFound) {
        if (-not $keyUpdated) {
            $lines.Add("$Key=$Value")
        }
    } else {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne "") {
            $lines.Add("")
        }
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
    }

    Set-Content -LiteralPath $configPath -Value $lines -Encoding UTF8
}
function Get-DzUiMode {
    $configPath = Get-DzToolsConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) {
        return "light"
    }
    $content = Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue
    $inUiSection = $false
    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*;') {
            continue
        }
        if ($trimmed -match '^\[UI\]\s*$') {
            $inUiSection = $true
            continue
        }
        if ($inUiSection -and $trimmed -match '^\[') {
            break
        }
        if ($inUiSection -and $trimmed -match '^\s*mode\s*=\s*(.+)\s*$') {
            return $matches[1].ToLower()
        }
    }
    return "light"
}
function Set-DzUiMode {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('dark', 'light')]
        [string]$Mode
    )
    Update-DzIniSetting -Section "UI" -Key "mode" -Value $Mode
}
function Set-DzDebugPreference {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )
    $value = if ($Enabled) {
        'true'
    } else {
        'false'
    }
    Update-DzIniSetting -Section "desarrollo" -Key "debug" -Value $value
    $script:DzDebugEnabled = $Enabled
}
function Initialize-DzToolsConfig {
    $configPath = Get-DzToolsConfigPath
    $configDir = Split-Path -Path $configPath -Parent
    if (-not (Test-Path -LiteralPath $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $configPath)) {
        "[desarrollo]`ndebug=false`n`n[UI]`nmode=light`n`n[sql]`n; server=user|password" | Out-File -FilePath $configPath -Encoding UTF8 -Force
    }
    Ensure-DzUiConfig -ConfigPath $configPath
    $script:DzDebugEnabled = Get-DzDebugPreference
    return $script:DzDebugEnabled
}
function Get-DzIniSectionMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Section
    )

    $configPath = Get-DzToolsConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) { return @{} }

    $content = Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue
    if ($null -eq $content) { return @{} }

    $map = @{}
    $inSection = $false
    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*;') { continue }
        if ($trimmed -match '^\[(.+)\]\s*$') {
            $current = $matches[1].Trim()
            $inSection = ($current.ToLower() -eq $Section.ToLower())
            continue
        }
        if (-not $inSection) { continue }
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $parts = $trimmed -split '=', 2
        if ($parts.Count -lt 2) { continue }
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $map[$key] = $value
        }
    }
    return $map
}
function Get-DzSavedSqlConnections {
    [CmdletBinding()]
    param()

    $entries = Get-DzIniSectionMap -Section "sql"
    $connections = @()
    foreach ($server in $entries.Keys) {
        $value = [string]$entries[$server]
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $parts = $value -split '\|', 2
        if ($parts.Count -lt 2) { continue }
        $user = $parts[0]
        $password = ""
        try {
            $bytes = [Convert]::FromBase64String($parts[1])
            $password = [System.Text.Encoding]::UTF8.GetString($bytes)
        } catch {
            $password = ""
        }
        $connections += [pscustomobject]@{
            Server   = $server
            User     = $user
            Password = $password
        }
    }
    return $connections
}
function Get-DzSavedSqlConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server
    )

    $serverText = $Server.Trim()
    if ([string]::IsNullOrWhiteSpace($serverText)) { return $null }

    $entries = Get-DzSavedSqlConnections
    foreach ($entry in $entries) {
        if ($entry.Server -and $entry.Server.Trim().ToLower() -eq $serverText.ToLower()) {
            return $entry
        }
    }
    return $null
}
function Save-DzSqlConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,
        [Parameter(Mandatory = $true)]
        [string]$User,
        [Parameter(Mandatory = $true)]
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($Server) -or [string]::IsNullOrWhiteSpace($User)) { return }
    if ([string]::IsNullOrWhiteSpace($Password)) { return }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    $encoded = [Convert]::ToBase64String($bytes)
    $value = "$User|$encoded"
    Update-DzIniSetting -Section "sql" -Key $Server -Value $value
}
function Write-DzDebug {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    if ($null -eq $script:DzDebugEnabled) {
        $script:DzDebugEnabled = Get-DzDebugPreference
    }

    if ($script:DzDebugEnabled) {
        if (Get-Command Stop-GlobalProgress -ErrorAction SilentlyContinue) {
            Stop-GlobalProgress
        } else {
            #Write-Host ""
        }

        Write-Host $Message -ForegroundColor $Color
    }
}
function Test-Administrator {
    [CmdletBinding()]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-SystemInfo {
    [CmdletBinding()]
    param()
    $info = @{
        ComputerName      = [System.Net.Dns]::GetHostName()
        OS                = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        NetAdapters       = @()
    }
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $adapters) {
        $adapterInfo = @{
            Name        = $adapter.Name
            Status      = $adapter.Status
            MacAddress  = $adapter.MacAddress
            IPAddresses = @()
        }
        $ipAddresses = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' }
        foreach ($ip in $ipAddresses) {
            $adapterInfo.IPAddresses += $ip.IPAddress
        }
        $info.NetAdapters += $adapterInfo
    }
    return $info
}
function Clear-TemporaryFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Paths = @("$env:TEMP", "C:\Windows\Temp")
    )
    $totalDeleted = 0
    $totalSize = 0
    foreach ($path in $Paths) {
        if (Test-Path $path) {
            try {
                $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    try {
                        if ($item.PSIsContainer) {
                            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        } else {
                            $totalSize += $item.Length
                            Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
                        }
                        $totalDeleted++
                    } catch {
                        Write-Verbose "No se pudo eliminar: $($item.FullName)"
                    }
                }
            } catch {
                Write-Warning "Error accediendo a $path : $_"
            }
        }
    }
    return @{
        FilesDeleted = $totalDeleted
        SpaceFreedMB = [math]::Round($totalSize / 1MB, 2)
    }
}
function Test-ChocolateyInstalled {
    [CmdletBinding()]
    param()
    return [bool](Get-Command choco -ErrorAction SilentlyContinue)
}
function Install-Chocolatey {
    [CmdletBinding()]
    param()

    if (Test-ChocolateyInstalled) {
        Write-Verbose "Chocolatey ya está instalado"
        return $true
    }

    try {
        Write-Host "Instalando Chocolatey..." -ForegroundColor Yellow
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        choco config set cacheLocation C:\Choco\cache
        Write-Host "Chocolatey instalado correctamente" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Error instalando Chocolatey: $_"
        return $false
    }
}
function Get-AdminGroupName {
    $groups = net localgroup | Where-Object { $_ -match "Administrador|Administrators" }

    if ($groups -match "\bAdministradores\b") {
        return "Administradores"
    } elseif ($groups -match "\bAdministrators\b") {
        return "Administrators"
    }

    try {
        $adminGroup = Get-LocalGroup | Where-Object { $_.SID -like "S-1-5-32-544" }
        return $adminGroup.Name
    } catch {
        return "Administrators"
    }
}
function Invoke-DiskCleanup {
    [CmdletBinding()]
    param(
        [switch]$Configure,
        [switch]$Wait,
        [int]$TimeoutMinutes = 3,
        $ProgressWindow = $null
    )

    try {
        $cleanmgr = Join-Path $env:SystemRoot "System32\cleanmgr.exe"
        $profileId = 9999

        Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: INICIO Configure=$Configure, Wait=$Wait, TimeoutMinutes=$TimeoutMinutes"

        if ($Configure) {
            Write-Host "`n`tAbriendo configuración del Liberador de espacio..." -ForegroundColor Cyan
            Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: lanzando /sageset:$profileId"
            Start-Process $cleanmgr -ArgumentList "/sageset:$profileId" -Verb RunAs
            return
        }

        Write-Host "`n`tEjecutando Liberador de espacio en disco..." -ForegroundColor Cyan

        if ($Wait) {
            Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: lanzando /sagerun:$profileId (BLOQUEANTE con timeout)"
            Write-Host "`n`tEsperando a que termine la limpieza de disco..." -ForegroundColor Yellow
            Write-Host "`t(Timeout: $TimeoutMinutes minutos)" -ForegroundColor Yellow

            $proc = Start-Process $cleanmgr -ArgumentList "/sagerun:$profileId" -WindowStyle Hidden -PassThru
            if ($null -eq $proc) {
                throw "Invoke-DiskCleanup: Start-Process devolvió NULL (no se pudo iniciar cleanmgr)."
            }

            Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Proceso iniciado. PID=$($proc.Id)"

            $timeoutSeconds = $TimeoutMinutes * 60
            $script:remainingSeconds = $timeoutSeconds
            $script:cleanupCancelled = $false
            $script:cleanupCompleted = $false
            $timer = $null

            # Configurar botón de cancelar
            if ($ProgressWindow -ne $null -and $ProgressWindow.IsVisible) {
                try {
                    $ProgressWindow.Dispatcher.Invoke([action] {
                            $cancelBtn = $ProgressWindow.FindName("btnCancel")
                            if ($cancelBtn) {
                                $cancelBtn.Visibility = "Visible"
                                $cancelBtn.Content = "Finalizar ahora"
                                $cancelBtn.ToolTip = "Saltar la limpieza de disco y continuar"

                                # Remover handlers previos
                                $cancelBtn.RemoveHandler(
                                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
                                    [System.Windows.RoutedEventHandler] {}
                                )

                                # Agregar handler de cancelación
                                $cancelBtn.Add_Click({
                                        Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Botón cancelar presionado"
                                        $script:cleanupCancelled = $true
                                    }.GetNewClosure())
                            }
                        }, [System.Windows.Threading.DispatcherPriority]::Normal)
                    Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Botón cancelar configurado"
                } catch {
                    Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Error configurando botón cancelar: $_" Yellow
                }

                # Configurar timer de actualización
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromSeconds(1)

                $timer.Add_Tick({
                        param($sender, $e)
                        try {
                            if ($script:remainingSeconds -gt 0) {
                                $script:remainingSeconds--

                                $mins = [math]::Floor($script:remainingSeconds / 60)
                                $secs = $script:remainingSeconds % 60

                                if ($ProgressWindow -and $ProgressWindow.PSObject.Properties.Name -contains 'MessageLabel') {
                                    $ProgressWindow.MessageLabel.Text = "Liberando espacio en disco...`nTiempo restante: $mins min $secs seg"
                                }
                            } else {
                                $sender.Stop()
                            }
                        } catch {
                            Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Tick EXCEPCIÓN: $($_.Exception.Message)" Red
                            $sender.Stop()
                        }
                    }.GetNewClosure())

                $timer.Start()
                Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Timer iniciado"
            }

            $checkInterval = 500
            $elapsed = 0

            # Loop principal con verificación de cancelación
            while (-not $proc.HasExited -and $elapsed -lt ($timeoutSeconds * 1000) -and -not $script:cleanupCancelled) {
                Start-Sleep -Milliseconds $checkInterval
                $elapsed += $checkInterval

                if ($ProgressWindow -ne $null -and $ProgressWindow.IsVisible) {
                    $ProgressWindow.Dispatcher.Invoke(
                        [System.Windows.Threading.DispatcherPriority]::Background,
                        [action] {}
                    )
                }
            }

            # Detener timer
            if ($timer) {
                $timer.Stop()
            }

            # Ocultar botón de cancelar
            if ($ProgressWindow -ne $null -and $ProgressWindow.IsVisible) {
                try {
                    $ProgressWindow.Dispatcher.Invoke([action] {
                            $cancelBtn = $ProgressWindow.FindName("btnCancel")
                            if ($cancelBtn) {
                                $cancelBtn.Visibility = "Collapsed"
                            }
                        }, [System.Windows.Threading.DispatcherPriority]::Normal)
                } catch {}
            }

            # Evaluar resultado
            if ($script:cleanupCancelled) {
                Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: CANCELADO por usuario" Yellow
                Write-Host "`n`tLimpieza de disco cancelada por el usuario." -ForegroundColor Yellow

                try {
                    $proc.Kill()
                    $proc.WaitForExit(3000)
                    Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Proceso terminado por cancelación"
                } catch {
                    Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Error al terminar proceso cancelado" Yellow
                }

                if ($ProgressWindow -ne $null -and $ProgressWindow.IsVisible) {
                    if ($ProgressWindow.PSObject.Properties.Name -contains 'MessageLabel') {
                        $ProgressWindow.MessageLabel.Text = "Limpieza de disco cancelada"
                    }
                }

                return "Cancelled"
            } elseif ($proc.HasExited) {
                Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Proceso completado. ExitCode=$($proc.ExitCode)"
                Write-Host "`n`tLiberador de espacio completado." -ForegroundColor Green

                if ($ProgressWindow -ne $null -and $ProgressWindow.IsVisible) {
                    if ($ProgressWindow.PSObject.Properties.Name -contains 'MessageLabel') {
                        $ProgressWindow.MessageLabel.Text = "Limpieza completada exitosamente"
                    }
                }

                return "Completed"
            } else {
                Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: TIMEOUT alcanzado" Yellow
                Write-Host "`n`tAdvertencia: El proceso excedió el tiempo límite." -ForegroundColor Yellow

                try {
                    $proc.Kill()
                    $proc.WaitForExit(5000)
                    Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Proceso terminado forzosamente por timeout"
                } catch {
                    Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: Error al terminar proceso por timeout" Red
                }

                if ($ProgressWindow -ne $null -and $ProgressWindow.IsVisible) {
                    if ($ProgressWindow.PSObject.Properties.Name -contains 'MessageLabel') {
                        $ProgressWindow.MessageLabel.Text = "Limpieza de disco: tiempo agotado"
                    }
                }

                return "Timeout"
            }
        } else {
            Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: lanzando /sagerun:$profileId (NO bloqueante)"
            $proc = Start-Process $cleanmgr `
                -ArgumentList "/sagerun:$profileId" `
                -WindowStyle Hidden `
                -PassThru
            Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: lanzado. PID=$($proc.Id)"
            Write-Host "`n`tLiberador de espacio iniciado." -ForegroundColor Green
            return "Started"
        }

        Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: FIN OK"
    } catch {
        Write-DzDebug "`t[DEBUG]Invoke-DiskCleanup: EXCEPCIÓN: $($_.Exception.Message)" Red
        Write-Host "`n`tError en limpieza de disco: $($_.Exception.Message)" -ForegroundColor Red
        return "Error"
    } finally {
        # Limpiar variables de script
        $script:cleanupCancelled = $false
        $script:cleanupCompleted = $false
    }
}
function Stop-CleanmgrProcesses {
    [CmdletBinding()]
    param()

    try {
        $cleanmgrProcesses = Get-Process -Name "cleanmgr" -ErrorAction SilentlyContinue

        if ($cleanmgrProcesses) {
            Write-Host "`n`tEncontrando procesos cleanmgr activos..." -ForegroundColor Yellow
            Write-DzDebug "`t[DEBUG]Stop-CleanmgrProcesses: Encontrados $($cleanmgrProcesses.Count) procesos"

            foreach ($proc in $cleanmgrProcesses) {
                Write-Host "`t  Terminando proceso cleanmgr (PID: $($proc.Id))..." -ForegroundColor Yellow
                $proc.Kill()
                Start-Sleep -Milliseconds 500
            }

            Write-Host "`tProcesos cleanmgr terminados." -ForegroundColor Green
            Write-DzDebug "`t[DEBUG]Stop-CleanmgrProcesses: Procesos terminados"
        } else {
            Write-DzDebug "`t[DEBUG]Stop-CleanmgrProcesses: No hay procesos cleanmgr activos"
        }
    } catch {
        Write-DzDebug "`t[DEBUG]Stop-CleanmgrProcesses: Error: $($_.Exception.Message)" Red
        Write-Host "`tError al terminar procesos: $($_.Exception.Message)" -ForegroundColor Red
    }
}
function Test-SameHost {
    param(
        [string]$serverName
    )
    $machinePart = $serverName.Split('\')[0]
    $machineName = $machinePart.Split(',')[0]
    if ($machineName -eq '.') {
        $machineName = $env:COMPUTERNAME
    }
    return ($env:COMPUTERNAME -eq $machineName)
}
function Test-7ZipInstalled {
    return (Test-Path "C:\Program Files\7-Zip\7z.exe")
}
function Test-MegaToolsInstalled {
    return ([bool](Get-Command megatools -ErrorAction SilentlyContinue))
}
function Show-WarnDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [string]$Title
    )
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Warning
    ) | Out-Null
}
function Test-7ZipInstalled {
    [CmdletBinding()]
    param()
    $paths = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    return [bool](Get-Command 7z -ErrorAction SilentlyContinue)
}
function Get-7ZipPath {
    [CmdletBinding()]
    param()
    $paths = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command 7z -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}
function Install-7ZipWithChoco {
    [CmdletBinding()]
    param()
    if (-not (Test-ChocolateyInstalled)) {
        Write-DzDebug "`t[DEBUG] [Install-7ZipWithChoco] Chocolatey no está instalado"
        return $false
    }
    try {
        Write-Host "Instalando 7zip con Chocolatey..." -ForegroundColor Yellow
        choco install 7zip -y --no-progress | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Start-Sleep -Seconds 2
        return (Test-7ZipInstalled)
    } catch {
        Write-Host "Error instalando 7zip: $_" -ForegroundColor Red
        return $false
    }
}
function Download-FileWithProgressWpfStream {
    param(
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [string]$OutFile,
        [Parameter(Mandatory)] $Window,
        [Parameter()] [ScriptBlock]$OnStatus
    )
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    $dir = Split-Path $OutFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $total = $null
    try {
        $head = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -ErrorAction Stop
        $cl = $head.Headers["Content-Length"]
        if ($cl) { $total = [int64]$cl }
    } catch {
        $total = $null
    }
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = "GET"
    $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    $req.Accept = "*/*"
    $req.AllowAutoRedirect = $true
    $resp = $null
    $inStream = $null
    $outStream = $null
    try {
        $resp = $req.GetResponse()
        if (-not $total) {
            try { $total = [int64]$resp.ContentLength } catch { $total = $null }
        }
        $inStream = $resp.GetResponseStream()
        $outStream = New-Object System.IO.FileStream($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $buffer = New-Object byte[] (1024 * 128)
        [int64]$readTotal = 0
        [int64]$lastUi = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        if ($Window -and $Window.ProgressBar) {
            try {
                $Window.Dispatcher.Invoke([Action] {
                        $Window.ProgressBar.IsIndeterminate = $false
                        $Window.ProgressBar.Value = 0
                    }, [System.Windows.Threading.DispatcherPriority]::Render) | Out-Null
            } catch {}
        }
        while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $read)
            $readTotal += $read
            if (($readTotal - $lastUi) -ge (512KB) -or $sw.ElapsedMilliseconds -ge 200) {
                $lastUi = $readTotal
                $sw.Restart()
                $percent = 0
                if ($total -and $total -gt 0) {
                    $percent = [int][Math]::Min(100, [Math]::Floor(($readTotal * 100.0) / $total))
                }
                $mb = [Math]::Round($readTotal / 1MB, 2)
                $totalMb = if ($total) { [Math]::Round($total / 1MB, 2) } else { $null }
                $msg = if ($totalMb) { "Descargando... $mb / $totalMb MB ($percent%)" } else { "Descargando... $mb MB" }
                if ($Window) {
                    try {
                        Update-WpfProgressBar -Window $Window -Percent $percent -Message $msg
                        $Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render) | Out-Null
                    } catch {}
                }
                if ($OnStatus) { try { & $OnStatus $percent $msg } catch {} }
            }
        }
        if ($Window) {
            try {
                Update-WpfProgressBar -Window $Window -Percent 100 -Message "Descarga completada."
                $Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render) | Out-Null
            } catch {}
        }
        return $true
    } finally {
        try { if ($outStream) { $outStream.Flush(); $outStream.Close() } } catch {}
        try { if ($inStream) { $inStream.Close() } } catch {}
        try { if ($resp) { $resp.Close() } } catch {}
    }
}
function Get-NSIniConnectionInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath
    )
    if (-not (Test-Path -LiteralPath $FilePath)) { return $null }
    try {
        $content = Get-Content -LiteralPath $FilePath -ErrorAction Stop
        $dataSource = ($content | Select-String -Pattern '^DataSource=(.*)' -ErrorAction SilentlyContinue | Select-Object -First 1).Matches.Groups[1].Value
        $catalog = ($content | Select-String -Pattern '^Catalog=(.*)' -ErrorAction SilentlyContinue | Select-Object -First 1).Matches.Groups[1].Value
        $authType = ($content | Select-String -Pattern '^autenticacion=(\d+)' -ErrorAction SilentlyContinue | Select-Object -First 1).Matches.Groups[1].Value
        $authUser = if ($authType -eq "2") { "sa" } elseif ($authType -eq "1") { "Windows" } else { "Desconocido" }
        return [pscustomobject]@{
            DataSource = $dataSource
            Catalog    = $catalog
            Usuario    = $authUser
        }
    } catch {
        Write-DzDebug "`t[DEBUG][Get-NSIniConnectionInfo] ERROR: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
        return $null
    }
}
function Get-NSApplicationsIniReport {
    [CmdletBinding()]
    param(
        [hashtable[]]$PathsToCheck = @(
            @{ Path = "C:\NationalSoft\Softrestaurant9.5.0Pro"; INI = "restaurant.ini"; Nombre = "SR9.5" },
            @{ Path = "C:\NationalSoft\Softrestaurant12.0"; INI = "restaurant.ini"; Nombre = "SR12" },
            @{ Path = "C:\NationalSoft\Softrestaurant11.0"; INI = "restaurant.ini"; Nombre = "SR11" },
            @{ Path = "C:\NationalSoft\Softrestaurant10.0"; INI = "restaurant.ini"; Nombre = "SR10" },
            @{ Path = "C:\NationalSoft\NationalSoftHoteles3.0"; INI = "nshoteles.ini"; Nombre = "Hoteles" },
            @{ Path = "C:\NationalSoft\OnTheMinute4.5"; INI = "checadorsql.ini"; Nombre = "OnTheMinute" }
        ),
        [string]$RestCardPath = "C:\NationalSoft\Restcard\RestCard.ini"
    )
    $resultados = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $PathsToCheck) {
        $basePath = $entry.Path
        $mainIni = Join-Path $basePath $entry.INI
        $appName = $entry.Nombre
        if (Test-Path -LiteralPath $mainIni) {
            $iniData = Get-NSIniConnectionInfo -FilePath $mainIni
            if ($iniData) {
                $resultados.Add([pscustomobject]@{
                        Aplicacion = $appName
                        INI        = $entry.INI
                        DataSource = $iniData.DataSource
                        Catalog    = $iniData.Catalog
                        Usuario    = $iniData.Usuario
                    })
            } else {
                $resultados.Add([pscustomobject]@{
                        Aplicacion = $appName
                        INI        = $entry.INI
                        DataSource = "NA"
                        Catalog    = "NA"
                        Usuario    = "NA"
                    })
            }
        } else {
            $resultados.Add([pscustomobject]@{
                    Aplicacion = $appName
                    INI        = "No encontrado"
                    DataSource = "NA"
                    Catalog    = "NA"
                    Usuario    = "NA"
                })
        }
        $inisFolder = Join-Path $basePath "INIS"
        if (Test-Path -LiteralPath $inisFolder) {
            $iniFiles = Get-ChildItem -LiteralPath $inisFolder -Filter "*.ini" -ErrorAction SilentlyContinue
            if ($appName -eq "OnTheMinute") {
                if ($iniFiles -and $iniFiles.Count -gt 1) {
                    foreach ($iniFile in $iniFiles) {
                        $iniData = Get-NSIniConnectionInfo -FilePath $iniFile.FullName
                        if ($iniData) {
                            $resultados.Add([pscustomobject]@{
                                    Aplicacion = $appName
                                    INI        = $iniFile.Name
                                    DataSource = $iniData.DataSource
                                    Catalog    = $iniData.Catalog
                                    Usuario    = $iniData.Usuario
                                })
                        }
                    }
                }
            } else {
                foreach ($iniFile in $iniFiles) {
                    $iniData = Get-NSIniConnectionInfo -FilePath $iniFile.FullName
                    if ($iniData) {
                        $resultados.Add([pscustomobject]@{
                                Aplicacion = $appName
                                INI        = $iniFile.Name
                                DataSource = $iniData.DataSource
                                Catalog    = $iniData.Catalog
                                Usuario    = $iniData.Usuario
                            })
                    }
                }
            }
        }
    }
    if (Test-Path -LiteralPath $RestCardPath) {
        $resultados.Add([pscustomobject]@{
                Aplicacion = "Restcard"
                INI        = "RestCard.ini"
                DataSource = "existe"
                Catalog    = "existe"
                Usuario    = "existe"
            })
    } else {
        $resultados.Add([pscustomobject]@{
                Aplicacion = "Restcard"
                INI        = "No encontrado"
                DataSource = "NA"
                Catalog    = "NA"
                Usuario    = "NA"
            })
    }
    return $resultados
}
function Show-WpfPathSelectionDialog {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][array] $Items,
        [string]$ExecuteButtonText = "Ejecutar"
    )
    $theme = Get-DzUiTheme
    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
        Height="420" Width="780"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="$($theme.FormForeground)"/>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="$($theme.ControlForeground)"/>
            <Setter Property="BorderBrush" Value="$($theme.BorderColor)"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="ListBoxItem">
            <Setter Property="Foreground" Value="$($theme.ControlForeground)"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="$($theme.AccentPrimary)"/>
                    <Setter Property="Foreground" Value="$($theme.FormForeground)"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="SystemButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="$($theme.ButtonSystemBackground)"/>
            <Setter Property="Foreground" Value="$($theme.ButtonSystemForeground)"/>
        </Style>
    </Window.Resources>
    <Border Background="{DynamicResource FormBg}"
            CornerRadius="10"
            BorderBrush="{DynamicResource AccentPrimary}"
            BorderThickness="2"
            Padding="0">
        <Border.Effect>
            <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="12" Opacity="0.25"/>
        </Border.Effect>
        <Grid Margin="16">
            <Grid.RowDefinitions>
                <RowDefinition Height="36"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="250"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Grid Grid.Row="0" Name="HeaderBar" Background="Transparent">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Name="txtHeader"
                           Text="$Title"
                           VerticalAlignment="Center"
                           FontWeight="SemiBold"/>
                <Button Name="btnClose"
                        Grid.Column="1"
                        Content="✕"
                        Width="34" Height="26"
                        Margin="8,0,0,0"
                        ToolTip="Cerrar"
                        Background="Transparent"
                        BorderBrush="Transparent"/>
            </Grid>
            <TextBlock Grid.Row="1"
                       Name="lblPrompt"
                       Text="$Prompt"
                       FontWeight="SemiBold"
                       Margin="0,0,0,10"/>
            <ListBox Grid.Row="2"
                     Name="lstItems"
                     DisplayMemberPath="Display"
                     SelectedValuePath="Path" />
            <Grid Grid.Row="3" Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="Versión seleccionada:" Margin="0,0,0,2"/>
                    <TextBlock Name="lblSelectedDisplay"
                            Text=""
                            FontFamily="{DynamicResource CodeFontFamily}"
                            TextWrapping="NoWrap"
                            TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Bottom">
                    <Button Name="btnCancel" Content="Cancelar" Width="110" Height="30" Margin="0,0,10,0" IsCancel="True" Style="{StaticResource SystemButtonStyle}"/>
                    <Button Name="btnExecute" Content="$ExecuteButtonText" Width="110" Height="30" Style="{StaticResource SystemButtonStyle}" IsDefault="True"/>
                </StackPanel>
            </Grid>
        </Grid>
    </Border>
</Window>
"@
    $ui = New-WpfWindow -Xaml $stringXaml -PassThru
    $w = $ui.Window
    $c = $ui.Controls
    Set-DzWpfThemeResources -Window $w -Theme $theme
    try { if (Get-Command Set-WpfDialogOwner -ErrorAction SilentlyContinue) { Set-WpfDialogOwner -Dialog $w } } catch {}
    if (-not $w.Owner) { $w.WindowStartupLocation = "CenterScreen" }
    $c['btnClose'].Add_Click({ $w.Close() })
    $c['HeaderBar'].Add_MouseLeftButtonDown({
            if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) { $w.DragMove() }
        })
    $c['lstItems'].ItemsSource = $Items
    if ($Items.Count -gt 0) { $c['lstItems'].SelectedIndex = 0 }
    $updateSelected = {
        $it = $c['lstItems'].SelectedItem
        if ($it) {
            $short = $null
            if ($it.PSObject.Properties.Match('DisplayShort').Count -gt 0) {
                $short = [string]$it.DisplayShort
            }
            $c['lblSelectedDisplay'].Text = if (-not [string]::IsNullOrWhiteSpace($short)) { $short } else { [string]$it.Display }
        } else {
            $c['lblSelectedDisplay'].Text = ""
        }
    }
    & $updateSelected
    $c['lstItems'].Add_SelectionChanged({ & $updateSelected })
    $script:_selectedItem = $null
    $c['btnExecute'].Add_Click({
            $it = $c['lstItems'].SelectedItem
            if (-not $it) { return }
            $script:_selectedItem = $it
            $w.DialogResult = $true
            $w.Close()
        })
    $c['btnCancel'].Add_Click({
            $w.DialogResult = $false
            $w.Close()
        })
    $ok = $w.ShowDialog()
    if ($ok) { return $script:_selectedItem }
    return $null
}
function Show-SQLselector {
    param(
        [array]$Managers,
        [array]$SSMSVersions
    )
    function Get-ManagerBits {
        param([string]$Path)
        if ($Path -match "\\SysWOW64\\") { return "32 bits" }
        return "64 bits"
    }
    function Get-ManagerVersion {
        param([string]$Path)
        if ($Path -match "SQLServerManager(\d+)\.msc") { return $matches[1] }
        return "?"
    }
    function New-SelectorItem {
        param(
            [string]$Path,
            [string]$Display,
            [string]$DisplayShort
        )
        [PSCustomObject]@{
            Path         = $Path
            Display      = $Display
            DisplayShort = $DisplayShort
        }
    }
    if ($Managers -and $Managers.Count -gt 0) {
        $items = @()
        $unique = $Managers | Where-Object { $_ } | Select-Object -Unique
        foreach ($m in $unique) {
            $ver = Get-ManagerVersion -Path $m
            $bits = Get-ManagerBits -Path $m
            $display = "SQLServerManager$ver  |  $bits  |  $m"
            $displayShort = "SQLServerManager$ver  |  $bits"
            $items += (New-SelectorItem -Path $m -Display $display -DisplayShort $displayShort)
        }
        $selected = Show-WpfPathSelectionDialog `
            -Title "Seleccionar Configuration Manager" `
            -Prompt "Seleccione la versión de SQL Server Configuration Manager a ejecutar:" `
            -Items $items `
            -ExecuteButtonText "Abrir"
        if ($selected) {
            Write-DzDebug "`t[DEBUG][Show-SQLselector] Seleccionado: $($selected.Display)"
            Start-Process -FilePath $selected.Path
        }
        return
    }
    if ($SSMSVersions -and $SSMSVersions.Count -gt 0) {
        $items = @()
        $unique = $SSMSVersions | Where-Object { $_ } | Select-Object -Unique
        foreach ($p in $unique) {
            try {
                $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($p)
                $prod = if ($vi.ProductName) { $vi.ProductName } else { "SSMS" }
                $ver = if ($vi.FileVersion) { $vi.FileVersion } else { "" }
                $display = "$prod  |  $ver  |  $p"
                $displayShort = "$prod  |  $ver"
                $items += (New-SelectorItem -Path $p -Display $display -DisplayShort $displayShort)
            } catch {
                $items += (New-SelectorItem -Path $p -Display "SSMS  |  $p" -DisplayShort "SSMS")
            }
        }
        $selected = Show-WpfPathSelectionDialog `
            -Title "Seleccionar SSMS" `
            -Prompt "Seleccione la versión de SQL Server Management Studio a ejecutar:" `
            -Items $items `
            -ExecuteButtonText "Ejecutar"
        if ($selected) {
            Write-DzDebug "`t[DEBUG][Show-SQLselector] Seleccionado: $($selected.DisplayShort)"
            Start-Process -FilePath $selected.Path
        }
        return
    }
    Write-DzDebug "`t[DEBUG][Show-SQLselector] No se recibieron rutas para Managers ni para SSMS." Yellow
}
function Get-SqlPortWithDebug {
    Write-DzDebug "`n`t[DEBUG][Update-PortsUI] === INICIANDO BÚSQUEDA DE PUERTOS SQL ==="
    Write-DzDebug "`t[DEBUG] Fecha/Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    $ports = @()

    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server"
    )

    Write-DzDebug "`t[DEBUG][Update-PortsUI] 1. Buscando instancias SQL instaladas..."

    foreach ($basePath in $registryPaths) {
        try {
            Write-DzDebug "`t[DEBUG][Update-PortsUI]   Examinando ruta: $basePath"

            if (-not (Test-Path $basePath)) {
                Write-DzDebug "`t[DEBUG][Update-PortsUI]   ✗ La ruta no existe"
                continue
            }

            Write-DzDebug "`t[DEBUG][Update-PortsUI]   Método 1: Buscando en 'InstalledInstances'..."
            $installedInstances = Get-ItemProperty -Path $basePath -Name "InstalledInstances" -ErrorAction SilentlyContinue

            if ($installedInstances -and $installedInstances.InstalledInstances) {
                Write-DzDebug "`t[DEBUG][Update-PortsUI]   ✓ Instancias encontradas: $($installedInstances.InstalledInstances -join ', ')"
                foreach ($instance in $installedInstances.InstalledInstances) {
                    if ($ports.Instance -contains $instance) {
                        Write-DzDebug "`t[DEBUG][Update-PortsUI]     Instancia '$instance' ya procesada, saltando..."
                        continue
                    }

                    Write-DzDebug "`t[DEBUG][Update-PortsUI]     Procesando instancia: '$instance'"

                    $possiblePaths = @(
                        "$basePath\$instance\MSSQLServer\SuperSocketNetLib\Tcp",
                        "$basePath\$instance\MSSQLServer\SuperSocketNetLib\Tcp\IPAll",
                        "$basePath\MSSQLServer\$instance\SuperSocketNetLib\Tcp"
                    )

                    $portFound = $false
                    foreach ($tcpPath in $possiblePaths) {
                        Write-DzDebug "`t[DEBUG][Update-PortsUI]       Probando ruta: $tcpPath"

                        if (Test-Path $tcpPath) {
                            Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✓ Ruta existe"

                            $tcpPort = Get-ItemProperty -Path $tcpPath -Name "TcpPort" -ErrorAction SilentlyContinue
                            $tcpDynamicPorts = Get-ItemProperty -Path $tcpPath -Name "TcpDynamicPorts" -ErrorAction SilentlyContinue

                            if ($tcpPort -and $tcpPort.TcpPort) {
                                $portInfo = [PSCustomObject]@{
                                    Instance = $instance
                                    Port     = $tcpPort.TcpPort
                                    Path     = $tcpPath
                                    Type     = "Static"
                                }
                                $ports += $portInfo
                                Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✓ Puerto estático encontrado: $($tcpPort.TcpPort)"
                                $portFound = $true
                                break
                            } elseif ($tcpDynamicPorts -and $tcpDynamicPorts.TcpDynamicPorts) {
                                $portInfo = [PSCustomObject]@{
                                    Instance = $instance
                                    Port     = $tcpDynamicPorts.TcpDynamicPorts
                                    Path     = $tcpPath
                                    Type     = "Dynamic"
                                }
                                $ports += $portInfo
                                Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✓ Puerto dinámico encontrado: $($tcpDynamicPorts.TcpDynamicPorts)"
                                $portFound = $true
                                break
                            } else {
                                Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✗ No se encontró puerto en esta ruta"
                            }
                        } else {
                            Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✗ Ruta no existe"
                        }
                    }

                    if (-not $portFound) {
                        Write-DzDebug "`t[DEBUG][Update-PortsUI]     ✗ No se encontró puerto para la instancia '$instance'"
                    }
                }
            } else {
                Write-DzDebug "`t[DEBUG][Update-PortsUI]   ✗ No se encontró la clave 'InstalledInstances' en esta ruta"
            }

            Write-DzDebug "`t[DEBUG][Update-PortsUI]   Método 2: Explorando todas las carpetas..."

            $allSqlEntries = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer } |
            Select-Object -ExpandProperty PSChildName

            if ($allSqlEntries) {
                Write-DzDebug "`t[DEBUG][Update-PortsUI]   Carpetas encontradas: $($allSqlEntries -join ', ')"

                foreach ($entry in $allSqlEntries) {
                    if ($entry -match "^MSSQL\d+" -or $entry -match "^SQL" -or $entry -match "NATIONALSOFT") {
                        if ($ports.Instance -contains $entry) {
                            Write-DzDebug "`t[DEBUG][Update-PortsUI]     Instancia '$entry' ya procesada, saltando..."
                            continue
                        }

                        Write-DzDebug "`t[DEBUG][Update-PortsUI]     Analizando posible instancia: '$entry'"
                        $tcpPath = "$basePath\$entry\MSSQLServer\SuperSocketNetLib\Tcp"

                        if (Test-Path $tcpPath) {
                            Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✓ Ruta TCP encontrada: $tcpPath"

                            $tcpPort = Get-ItemProperty -Path $tcpPath -Name "TcpPort" -ErrorAction SilentlyContinue
                            $tcpDynamicPorts = Get-ItemProperty -Path $tcpPath -Name "TcpDynamicPorts" -ErrorAction SilentlyContinue

                            if ($tcpPort -and $tcpPort.TcpPort) {
                                $portInfo = [PSCustomObject]@{
                                    Instance = $entry
                                    Port     = $tcpPort.TcpPort
                                    Path     = $tcpPath
                                    Type     = "Static"
                                }
                                $ports += $portInfo
                                Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✓ Puerto estático encontrado: $($tcpPort.TcpPort)"
                            } elseif ($tcpDynamicPorts -and $tcpDynamicPorts.TcpDynamicPorts) {
                                $portInfo = [PSCustomObject]@{
                                    Instance = $entry
                                    Port     = $tcpDynamicPorts.TcpDynamicPorts
                                    Path     = $tcpPath
                                    Type     = "Dynamic"
                                }
                                $ports += $portInfo
                                Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✓ Puerto dinámico encontrado: $($tcpDynamicPorts.TcpDynamicPorts)"
                            } else {
                                Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✗ No se encontró puerto en esta ruta"
                            }
                        }
                    }
                }
            }
        } catch {
            Write-DzDebug "`t[DEBUG][Update-PortsUI]   ERROR en búsqueda: $($_.Exception.Message)"
            Write-DzDebug "`t[DEBUG][Update-PortsUI]   StackTrace: $($_.ScriptStackTrace)"
        }
    }

    Write-DzDebug "`t[DEBUG][Update-PortsUI]   Método 3: Buscando servicios SQL Server..."

    $sqlServices = Get-Service -Name "*SQL*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*SQL Server (*" }

    foreach ($service in $sqlServices) {
        Write-DzDebug "`t[DEBUG][Update-PortsUI]     Servicio: $($service.DisplayName)"

        if ($service.DisplayName -match "SQL Server \((.+)\)") {
            $instanceName = $matches[1]

            if ($ports.Instance -contains $instanceName) {
                Write-DzDebug "`t[DEBUG][Update-PortsUI]       Instancia '$instanceName' ya procesada, saltando..."
                continue
            }

            Write-DzDebug "`t[DEBUG][Update-PortsUI]       Posible instancia: '$instanceName'"

            foreach ($basePath in $registryPaths) {
                $tcpPath = "$basePath\MSSQLServer\$instanceName\SuperSocketNetLib\Tcp"

                if (Test-Path $tcpPath) {
                    $tcpPort = Get-ItemProperty -Path $tcpPath -Name "TcpPort" -ErrorAction SilentlyContinue
                    $tcpDynamicPorts = Get-ItemProperty -Path $tcpPath -Name "TcpDynamicPorts" -ErrorAction SilentlyContinue

                    if ($tcpPort -and $tcpPort.TcpPort) {
                        $portInfo = [PSCustomObject]@{
                            Instance = $instanceName
                            Port     = $tcpPort.TcpPort
                            Path     = $tcpPath
                            Type     = "Static"
                        }
                        $ports += $portInfo
                        Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✓ Puerto estático encontrado: $($tcpPort.TcpPort)"
                        break
                    } elseif ($tcpDynamicPorts -and $tcpDynamicPorts.TcpDynamicPorts) {
                        $portInfo = [PSCustomObject]@{
                            Instance = $instanceName
                            Port     = $tcpDynamicPorts.TcpDynamicPorts
                            Path     = $tcpPath
                            Type     = "Dynamic"
                        }
                        $ports += $portInfo
                        Write-DzDebug "`t[DEBUG][Update-PortsUI]       ✓ Puerto dinámico encontrado: $($tcpDynamicPorts.TcpDynamicPorts)"
                        break
                    }
                }
            }
        }
    }

    Write-DzDebug "`t[DEBUG][Update-PortsUI]   Método 4: Buscando puertos en uso por sqlservr.exe..."

    $sqlProcesses = Get-Process -Name "sqlservr" -ErrorAction SilentlyContinue
    if ($sqlProcesses) {
        foreach ($process in $sqlProcesses) {
            Write-DzDebug "`t[DEBUG][Update-PortsUI]     Proceso sqlservr.exe encontrado (PID: $($process.Id))"

            $netstatOutput = netstat -ano | Select-String ":$($process.Id)\s"

            foreach ($line in $netstatOutput) {
                if ($line -match ":(\d+)\s.*$($process.Id)$") {
                    $port = $matches[1]
                    Write-DzDebug "`t[DEBUG][Update-PortsUI]       Puerto en uso: $port"

                    if (-not ($ports.Port -contains $port)) {
                        $processInfo = Get-WmiObject Win32_Process -Filter "ProcessId = $($process.Id)" | Select-Object CommandLine
                        if ($processInfo.CommandLine -match "-s(.+?)\s") {
                            $instanceFromCmd = $matches[1]
                        } else {
                            $instanceFromCmd = "Unknown"
                        }

                        $portInfo = [PSCustomObject]@{
                            Instance = $instanceFromCmd
                            Port     = $port
                            Path     = "From Process"
                            Type     = "In Use"
                        }
                        $ports += $portInfo
                    }
                }
            }
        }
    } else {
        Write-DzDebug "`t[DEBUG][Update-PortsUI]    ✗ No se encontraron procesos sqlservr.exe"
    }

    Write-DzDebug "`t[DEBUG][Update-PortsUI] `n=== RESUMEN DE BÚSQUEDA ==="
    Write-DzDebug "`t[DEBUG][Update-PortsUI] Total de instancias con puerto encontradas: $($ports.Count)"
    if ($ports.Count -gt 0) {
        foreach ($port in $ports) {
            Write-DzDebug "`t[DEBUG][Update-PortsUI]   - Instancia: $($port.Instance) | Puerto: $($port.Port) | Tipo: $($port.Type)"
            Write-DzDebug "`t[DEBUG][Update-PortsUI]     Ruta: $($port.Path)"
        }
    } else {
        Write-DzDebug "`t[DEBUG][Update-PortsUI]   ✗ No se encontraron puertos SQL configurados"
        Write-DzDebug "`t[DEBUG][Update-PortsUI] === SUGERENCIAS ==="
        Write-DzDebug "`t[DEBUG][Update-PortsUI] 1. Verifica si SQL Server está instalado"
        Write-DzDebug "`t[DEBUG][Update-PortsUI] 2. Revisa el Configuration Manager de SQL Server"
        Write-DzDebug "`t[DEBUG][Update-PortsUI] 3. Verifica si el servicio SQL Server está ejecutándose"
        Write-DzDebug "`t[DEBUG][Update-PortsUI] 4. Consulta el log de errores de SQL Server"
    }

    Write-DzDebug "`t[DEBUG][Update-PortsUI] === FIN DE BÚSQUEDA ===`n"

    if ($ports.Count -gt 0) {
        $ports = $ports | Sort-Object -Property Instance
        $formattedPorts = @()

        foreach ($port in $ports) {
            $instanceName = if ($port.Instance -eq "MSSQLSERVER") { "Default" } else { $port.Instance }
            $formattedPort = [PSCustomObject]@{
                Instance       = $port.Instance
                Port           = $port.Port
                Path           = $port.Path
                Type           = $port.Type
                FormattedText  = "$instanceName`: $($port.Port)"
                SingleLineText = "$instanceName`: $($port.Port) - $($port.Type)"
            }
            $formattedPorts += $formattedPort
        }

        $ports = $formattedPorts
    }

    return $ports
}
function Show-SqlPortsInfo {
    param([array]$sqlPorts)
    if ($sqlPorts.Count -eq 0) {
        Write-Host "=== RESUMEN DE BÚSQUEDA SQL ===" -ForegroundColor Yellow
        Write-Host "No se encontraron puertos SQL ni instalaciones de SQL Server" -ForegroundColor Red
        Write-Host "=== FIN DE BÚSQUEDA ===" -ForegroundColor Yellow
        return
    }
    Write-Host "`n=== RESUMEN DE BÚSQUEDA SQL ===" -ForegroundColor Cyan
    Write-Host "Total de instancias con puerto encontradas: $($sqlPorts.Count)" -ForegroundColor White
    Write-Host ""
    $sqlPorts | ForEach-Object {
        Write-Host "  - Instancia: $($_.Instance) | Puerto: $($_.Port) | Tipo: $($_.Type)" -ForegroundColor Green
        if ($_.Method -and $global:debugEnabled) {
            Write-Host "    Método de detección: $($_.Method)" -ForegroundColor DarkGray
        }
    }
    Write-Host "`n=== FIN DE BÚSQUEDA ===" -ForegroundColor Cyan
}
function Set-ClipboardTextSafe {
    param(
        [Parameter(Mandatory)][string]$Text,
        [int]$MaxRetries = 8,
        [int]$DelayMs = 60,
        [System.Windows.Window]$Owner = $null
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $doCopy = {
        param($t, $max, $delay)
        for ($i = 0; $i -lt $max; $i++) {
            try {
                [System.Windows.Clipboard]::Clear()
                [System.Windows.Clipboard]::SetText($t)
                return $true
            } catch {
                Start-Sleep -Milliseconds $delay
            }
        }
        return $false
    }
    try {
        if ($global:MainWindow -and $global:MainWindow.Dispatcher) {
            return [bool]$global:MainWindow.Dispatcher.Invoke([Func[bool]] {
                    & $doCopy $Text $MaxRetries $DelayMs
                })
        }
    } catch {}
    try {
        return [bool](& $doCopy $Text $MaxRetries $DelayMs)
    } catch {}
    if ($Owner) { Ui-Error "No se pudo copiar al portapapeles (posiblemente está en uso). Intenta de nuevo." $Owner }
    return $false
}
function Apply-SavedSqlCredentials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerText
    )

    if ([string]::IsNullOrWhiteSpace($ServerText)) {
        Write-DzDebug "`t[DEBUG] ServerText está vacío"
        return
    }

    Write-DzDebug "`t[DEBUG] Aplicando credenciales guardadas para: '$ServerText'"

    $saved = Get-DzSavedSqlConnection -Server $ServerText

    if (-not $saved) {
        Write-DzDebug "`t[DEBUG] No hay credenciales guardadas para: '$ServerText'"

        # LIMPIAR los campos cuando no hay credenciales
        try {
            if ($global:txtUser) {
                $global:txtUser.Text = ""
                Write-DzDebug "`t[DEBUG] ✓ Campo de usuario limpiado"
            }

            if ($global:txtPassword) {
                $global:txtPassword.Password = ""
                Write-DzDebug "`t[DEBUG] ✓ Campo de contraseña limpiado"
            }
        } catch {
            Write-DzDebug "`t[DEBUG] ✗ Error limpiando campos: $_" -Color Red
        }

        return
    }

    Write-DzDebug "`t[DEBUG] ✓ Credenciales encontradas para: '$ServerText' (User: $($saved.User))"

    try {
        if ($global:txtUser) {
            $global:txtUser.Text = $saved.User
            Write-DzDebug "`t[DEBUG] ✓ Usuario aplicado: '$($saved.User)'"
        }

        if ($global:txtPassword) {
            $global:txtPassword.Password = $saved.Password
            Write-DzDebug "`t[DEBUG] ✓ Contraseña aplicada"
        }
    } catch {
        Write-DzDebug "`t[DEBUG] ✗ Error aplicando credenciales: $_" -Color Red
    }
}
function Initialize-SystemInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$LblPort,
        [Parameter(Mandatory = $true)]$LblIpAddress,
        [Parameter(Mandatory = $true)]$LblAdapterStatus,
        [Parameter(Mandatory = $false)][string]$ModulesPath = $PSScriptRoot
    )
    $portsJob = Start-Job -ScriptBlock {
        param($modulePath)
        Import-Module $modulePath -Force -DisableNameChecking
        Get-SqlPortWithDebug
    } -ArgumentList (Join-Path $ModulesPath "Utilities.psm1")
    $networkJob = Start-Job -ScriptBlock {
        try {
            $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
            $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
            $ipsWithAdapters = @()
            $adapterDetails = @()
            foreach ($adapter in $adapters) {
                $adapterIPs = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' }
                $profile = $profiles | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex }
                $networkType = if ($profile) {
                    switch ($profile.NetworkCategory) {
                        'Private' { "Privada" }
                        'Public' { "Pública" }
                        'DomainAuthenticated' { "Dominio" }
                        default { "Desconocida" }
                    }
                } else {
                    "Sin perfil"
                }
                foreach ($ip in $adapterIPs) {
                    $ipsWithAdapters += @{
                        AdapterName = $adapter.Name
                        IPAddress   = $ip.IPAddress
                    }
                }
                $adapterDetails += [PSCustomObject]@{
                    AdapterName    = $adapter.Name
                    NetworkType    = $networkType
                    InterfaceIndex = $adapter.ifIndex
                }
            }
            $privateCount = ($profiles | Where-Object { $_.NetworkCategory -eq 'Private' }).Count
            $totalCount = $profiles.Count
            @{
                IPs            = $ipsWithAdapters
                AdapterDetails = $adapterDetails
                AdapterStatus  = "Redes: $privateCount/$totalCount privadas"
            }
        } catch {
            @{
                IPs            = @()
                AdapterDetails = @()
                AdapterStatus  = "Error: $_"
            }
        }
    }
    $LblPort.Dispatcher.Invoke([action] {
            $LblPort.Text = "🔍 Buscando puertos SQL..."
            $LblPort.UpdateLayout()
        })
    $LblIpAddress.Dispatcher.Invoke([action] {
            $LblIpAddress.Text = "🔍 Obteniendo IPs..."
            $LblIpAddress.UpdateLayout()
        })
    $LblAdapterStatus.Dispatcher.Invoke([action] {
            $LblAdapterStatus.Text = "🔍 Verificando adaptadores..."
            $LblAdapterStatus.UpdateLayout()
        })
    $script:portsApplied = $false
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Add_Tick({
            if (-not $script:portsApplied -and $portsJob -and $portsJob.State -in @("Completed", "Failed", "Stopped")) {
                $script:portsApplied = $true

                try {
                    $portsResult = Receive-Job $portsJob -ErrorAction SilentlyContinue | ForEach-Object { $_ }
                    Remove-Job $portsJob -Force -ErrorAction SilentlyContinue
                    $portsJob = $null

                    Update-PortsUI -LblPort $LblPort -PortsResult $portsResult
                } catch {
                    Write-DzDebug "`t[DEBUG][SystemInfo] Error procesando puertos: $_"
                    $portsJob = $null
                }
            }
            if ($networkJob.State -in @("Completed", "Failed", "Stopped")) {
                try {
                    $networkResult = Receive-Job $networkJob -ErrorAction SilentlyContinue
                    Remove-Job $networkJob -Force -ErrorAction SilentlyContinue
                    if ($networkResult) {
                        Update-NetworkUI -LblIpAddress $LblIpAddress -LblAdapterStatus $LblAdapterStatus -NetworkResult $networkResult
                    }
                } catch {
                    Write-DzDebug "`t[DEBUG][SystemInfo] Error procesando red: $_"
                }
                $networkJob = $null
            }
            if ($null -eq $portsJob -and $null -eq $networkJob) {
                $timer.Stop()
                Write-DzDebug "`t[DEBUG][SystemInfo] Carga de información del sistema completada"
            }
        }.GetNewClosure())
    $timer.Start()
    Write-Host "`nIniciada carga asíncrona de información del sistema" -ForegroundColor Yellow
}
function Update-PortsUI {
    param($LblPort, $PortsResult)
    Write-DzDebug "`t[DEBUG][Update-PortsUI] Iniciando actualización de UI de puertos" -Color Cyan
    $portsArray = @($PortsResult | Where-Object {
            $_ -ne $null -and
            $_.PSObject.Properties.Match('Port').Count -gt 0 -and
            $_.PSObject.Properties.Match('Instance').Count -gt 0 -and
            ![string]::IsNullOrWhiteSpace([string]$_.Port)
        })
    Write-DzDebug "`t[DEBUG][Update-PortsUI] Puertos filtrados: $($portsArray.Count)" -Color Cyan
    $LblPort.Dispatcher.Invoke([action] {
            if ($portsArray.Count -gt 0) {
                $sortedPorts = $portsArray | Sort-Object -Property Instance
                $displayLines = @()
                foreach ($port in $sortedPorts) {
                    $instanceName = if ($port.Instance -eq "MSSQLSERVER") { "Default" } else { $port.Instance }
                    $displayLines += "$instanceName : $($port.Port)"
                }
                $displayText = $displayLines -join "`n"
                if ($LblPort.Text -ne $displayText) {
                    $LblPort.Text = $displayText
                    $LblPort.Tag = $sortedPorts
                    $LblPort.ToolTip = "$($sortedPorts.Count) instancia(s) encontrada(s). Clic para copiar"
                    Write-DzDebug "`t[DEBUG][Update-PortsUI] UI actualizada con $($sortedPorts.Count) líneas" -Color Green
                } else {
                    Write-DzDebug "`t[DEBUG][Update-PortsUI] UI ya tiene el mismo texto, omitiendo actualización" -Color Yellow
                }
            } else {
                if ($LblPort.Text -and $LblPort.Text -notlike "🔍*" -and $LblPort.Text -ne "No se encontraron puertos SQL") {
                    Write-DzDebug "`t[DEBUG][Update-PortsUI] Resultado vacío, pero ya había datos. No se pisa la UI." -Color Yellow
                    return
                }
                if ($LblPort.Text -ne "No se encontraron puertos SQL") {
                    $LblPort.Text = "No se encontraron puertos SQL"
                    $LblPort.Tag = $null
                    $LblPort.ToolTip = "No se encontraron instalaciones de SQL Server"
                    Write-DzDebug "`t[DEBUG][Update-PortsUI] UI actualizada: No se encontraron puertos SQL" -Color Yellow
                }
            }
            $LblPort.UpdateLayout()
        })
}

function Update-NetworkUI {
    param($LblIpAddress, $LblAdapterStatus, $NetworkResult)

    $LblIpAddress.Dispatcher.Invoke([action] {
            if ($NetworkResult.IPs -and $NetworkResult.IPs.Count -gt 0) {
                $ipsLines = @()
                foreach ($ip in $NetworkResult.IPs) {
                    $ipsLines += "$($ip.AdapterName): $($ip.IPAddress)"
                }
                $ipsText = $ipsLines -join "`n"

                $LblIpAddress.Text = $ipsText
                $LblIpAddress.Tag = $NetworkResult.IPs
                $LblIpAddress.ToolTip = "$($NetworkResult.IPs.Count) dirección(es) IP. Clic para copiar"
                Write-DzDebug "`t[DEBUG][Update-NetworkUI] ✓ IPs encontradas: $($NetworkResult.IPs.Count)"
            } else {
                $LblIpAddress.Text = "No se encontraron direcciones IP"
                $LblIpAddress.Tag = $null
                $LblIpAddress.ToolTip = "No hay IPs disponibles"
                Write-DzDebug "`t[DEBUG][Update-NetworkUI] ⚠ No se encontraron direcciones IP"
            }
            $LblIpAddress.UpdateLayout()
        })

    $LblAdapterStatus.Dispatcher.Invoke([action] {
            if ($NetworkResult.AdapterDetails -and $NetworkResult.AdapterDetails.Count -gt 0) {
                $adapterLines = @()
                foreach ($adapter in $NetworkResult.AdapterDetails) {
                    $adapterLines += "$($adapter.AdapterName): $($adapter.NetworkType)"
                }
                $adapterText = $adapterLines -join "`n"

                $LblAdapterStatus.Text = $adapterText
                $LblAdapterStatus.Tag = $NetworkResult.AdapterDetails
                $LblAdapterStatus.ToolTip = "$($NetworkResult.AdapterDetails.Count) adaptador(es). Clic para convertir a red privada"
                Write-DzDebug "`t[DEBUG][Update-NetworkUI] ✓ Detalles de adaptadores actualizados"
            } else {
                $LblAdapterStatus.Text = "Sin adaptadores activos"
                $LblAdapterStatus.Tag = $null
                $LblAdapterStatus.ToolTip = "No hay adaptadores activos"
                Write-DzDebug "`t[DEBUG][Update-NetworkUI] ⚠ No se encontraron adaptadores activos"
            }
            $LblAdapterStatus.UpdateLayout()
        })
}
function Refresh-AdapterStatus {
    try {
        if ($null -eq $global:txt_AdapterStatus) {
            Write-Host "ADVERTENCIA: El control de estado de adaptadores no está disponible." -ForegroundColor Yellow
            return
        }
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $adapterInfo = @()
        foreach ($adapter in $adapters) {
            $profile = Get-NetConnectionProfile -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue
            $networkType = if ($profile) {
                switch ($profile.NetworkCategory) {
                    'Private' { "Privada" }
                    'Public' { "Pública" }
                    'DomainAuthenticated' { "Dominio" }
                    default { "Desconocida" }
                }
            } else {
                "Sin perfil"
            }
            $adapterInfo += "$($adapter.Name): $networkType"
        }
        if ($adapterInfo.Count -gt 0) {
            $global:txt_AdapterStatus.Dispatcher.Invoke([action] {
                    $global:txt_AdapterStatus.Text = $adapterInfo -join "`n"
                })
        } else {
            $global:txt_AdapterStatus.Dispatcher.Invoke([action] {
                    $global:txt_AdapterStatus.Text = "Sin adaptadores activos"
                })
        }
    } catch {
        Write-Host "Error al actualizar estado de adaptadores: $_"
    }
}
function Get-NetworkAdapterStatus {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    $profiles = Get-NetConnectionProfile
    $adapterStatus = @()
    foreach ($adapter in $adapters) {
        $profile = $profiles | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex }
        $networkCategory = if ($profile) { $profile.NetworkCategory } else { "Desconocido" }
        $adapterStatus += [PSCustomObject]@{
            AdapterName     = $adapter.Name
            NetworkCategory = $networkCategory
            InterfaceIndex  = $adapter.ifIndex
        }
    }
    return $adapterStatus
}
function Set-AdaptersToPrivate {
    [CmdletBinding()]
    param(
        [Parameter()][array]$AdapterDetails = @(),
        [Parameter()][System.Windows.Window]$Owner
    )
    try {
        if (-not (Test-Administrator)) {
            if ($Owner) {
                Ui-Error "Se requieren permisos de administrador para cambiar el tipo de red.`n`nEjecuta la aplicación como administrador." $Owner
            } else {
                Write-Host "`n✗ Se requieren permisos de administrador" -ForegroundColor Red
            }
            return $false
        }
        if (-not $AdapterDetails -or $AdapterDetails.Count -eq 0) {
            Write-Host "`n⚠ No hay adaptadores para configurar" -ForegroundColor Yellow
            return $false
        }
        $toConvert = @($AdapterDetails | Where-Object { $_.NetworkType -ne "Privada" })
        if ($toConvert.Count -eq 0) {
            if ($Owner) {
                Ui-Info "Todos los adaptadores ya están configurados como red privada." $Owner
            } else {
                Write-Host "`n✓ Todos los adaptadores ya son privados" -ForegroundColor Green
            }
            return $true
        }
        $adapterList = ($toConvert | ForEach-Object { "  • $($_.AdapterName) ($($_.NetworkType))" }) -join "`n"
        $message = "Se cambiarán los siguientes adaptadores a red PRIVADA:`n`n$adapterList`n`n¿Continuar?"
        $confirm = if ($Owner) {
            Ui-Confirm $message "Cambiar a red privada" $Owner
        } else {
            $response = Read-Host "¿Continuar? (S/N)"
            $response -eq 'S'
        }
        if (-not $confirm) {
            Write-Host "`n⚠ Operación cancelada por el usuario" -ForegroundColor Yellow
            return $false
        }
        $changed = 0
        $errors = @()
        foreach ($adapter in $toConvert) {
            try {
                Write-Host "`nCambiando adaptador: $($adapter.AdapterName)..." -ForegroundColor Yellow
                Set-NetConnectionProfile -InterfaceIndex $adapter.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
                Write-Host "  ✓ $($adapter.AdapterName) configurado como red privada" -ForegroundColor Green
                $changed++
            } catch {
                $errMsg = "Error en $($adapter.AdapterName): $($_.Exception.Message)"
                $errors += $errMsg
                Write-Host "  ✗ $errMsg" -ForegroundColor Red
            }
        }
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host "  Adaptadores cambiados: $changed/$($toConvert.Count)" -ForegroundColor $(if ($changed -eq $toConvert.Count) { "Green" } else { "Yellow" })
        if ($errors.Count -gt 0) {
            Write-Host "  Errores: $($errors.Count)" -ForegroundColor Red
        }
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        if ($Owner) {
            if ($changed -gt 0 -and $errors.Count -eq 0) {
                Ui-Info "$changed adaptador(es) configurado(s) como red privada exitosamente.`n`nSe recomienda verificar la conectividad de red." $Owner
            } elseif ($changed -gt 0 -and $errors.Count -gt 0) {
                Ui-Warn "$changed adaptador(es) configurado(s), pero con $($errors.Count) error(es).`n`nRevisa la consola para más detalles." $Owner
            } else {
                Ui-Error "No se pudo cambiar ningún adaptador.`n`n$($errors -join "`n")" $Owner
            }
        }
        if (Get-Command Refresh-AdapterStatus -ErrorAction SilentlyContinue) {
            Start-Sleep -Milliseconds 500
            Refresh-AdapterStatus
        }
        return ($changed -gt 0)
    } catch {
        Write-Host "`n✗ Error general: $($_.Exception.Message)" -ForegroundColor Red
        if ($Owner) {
            Ui-Error "Error cambiando adaptadores:`n$($_.Exception.Message)" $Owner
        }
        return $false
    }
}
Export-ModuleMember -Function @(
    'Get-DzToolsConfigPath', 'Get-DzDebugPreference', 'Get-DzUiMode', 'Set-DzUiMode',
    'Set-DzDebugPreference', 'Initialize-DzToolsConfig', 'Get-DzIniSectionMap', 'Get-DzSavedSqlConnections',
    'Get-DzSavedSqlConnection', 'Save-DzSqlConnection', 'Write-DzDebug', 'Test-Administrator',
    'Get-SystemInfo', 'Clear-TemporaryFiles', 'Test-ChocolateyInstalled', 'Install-Chocolatey',
    'Get-AdminGroupName', 'Invoke-DiskCleanup', 'Stop-CleanmgrProcesses', 'Test-SameHost',
    'Test-7ZipInstalled', 'Test-MegaToolsInstalled', 'Download-FileWithProgressWpfStream', 'Refresh-AdapterStatus',
    'Get-NetworkAdapterStatus', 'Get-SqlPortWithDebug', 'Show-SqlPortsInfo', 'Show-WarnDialog',
    'Get-7ZipPath', 'Install-7ZipWithChoco', 'Show-SQLselector', 'get-NSApplicationsIniReport',
    'Set-ClipboardTextSafe', 'Initialize-SystemInfo', 'Update-PortsUI', 'Update-NetworkUI',
    'Apply-SavedSqlCredentials', 'Apply-SavedSqlCredentials', 'Set-AdaptersToPrivate')