#requires -Version 5.0
#main.ps1 - Punto de entrada principal para la aplicación DzTools
chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [Console]::OutputEncoding
$global:version = "beta.25.12.03.1046"
try {
    Write-Host "PSVersion: $($PSVersionTable.PSVersion) | STA: $([Threading.Thread]::CurrentThread.ApartmentState)" -ForegroundColor Cyan
    Write-Host "Cargando ensamblados de WPF..." -ForegroundColor Yellow
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
    Write-Host "  ✓ WPF cargado" -ForegroundColor Green
} catch {
    Write-Host "✗ Error cargando WPF: $_" -ForegroundColor Red
    pause
    exit 1
}
if (Get-Command Set-ExecutionPolicy -ErrorAction SilentlyContinue) {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
}
function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Stop-GlobalProgress
    Write-Host $Message -ForegroundColor $Color
}
Write-Host "`nImportando módulos..." -ForegroundColor Yellow
$modulesPath = Join-Path $PSScriptRoot "modules"
$modules = @("GUI.psm1", "Database.psm1", "Utilities.psm1", "SqlTreeView.psm1", "Installers.psm1", "WindowsUtilities.psm1", "NationalUtilities.psm1", "SqlOps.psm1", "QueriesPad.psm1")
foreach ($module in $modules) {
    $modulePath = Join-Path $modulesPath $module
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -Force -ErrorAction Stop -DisableNameChecking
            Write-Host "  ✓ $module" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Error importando módulo: $module" -ForegroundColor Red
            Write-Host "    Ruta    : $modulePath" -ForegroundColor DarkYellow
            Write-Host "    Mensaje : $($_.Exception.Message)" -ForegroundColor Yellow
            throw
        }
    } else {
        Write-Host "  ✗ $module no encontrado" -ForegroundColor Red
    }
}
$global:defaultInstructions = @"
----- CAMBIOS -----
- Nuevo botón para Innstaladores NS
- Monitor de servicios y logs
- Historial de queries
- SSMS Portable
    * TreeView nuevo!
    * Crear y eliminar bases de datos
    * Attach / detach de base de datos
    * Backup de bases de datos con compresión
    * Restaurar permite seleccionar ruta de archivos logicos
    * Funciones para ver tamaño y reparar base de datos
    * Ejecución de queries
    * Exportar resultados a CSV/Excel
    * Queries predefinidas
    * Mejoras en seguridad y manejo de errores
    * Carga de INIS en la conexión a BDD.
    * Multiples Queries (MultiQuery)
- Instalador de impresoras Generic Text por IP
- Registro y deregistro de Dlls
- Configuraciones de Firewall
    * Buscar reglas existentes "deshabilitada termporalmente"
    * Agregar reglas nuevas
- Nueva interfaz WPF
    * Fuentes y colores actualizados.
    * Modo oscuro
    * Modo debug
- Instalador de herramientas (Choco)
    * Nuevo form para buscar paquetes choco.
    * Permite instalar paquetes.
    * Permite desinstalar paquetes.
    * Ver estado de paquetes instalados.
- Restructura del proceso de Backups (choco).
    * Progressbar animada
    * Se agregó compresión con contraseña de respaldos
- Se agregó consola de cambios y tool tip para botones
- Busqueda avanzada de puertos SQL
- Query Browser para SQL en pestaña: Base de datos
- - Ahora se pueden agregar comentarios con "-" y entre "/* */"
- - Tabla en consola
- - Obtener columnas en consola
- Se agregó botón para limpiar AnyDesk
- Se agregó botón para mostrar impresoras instaladas
- Se agregó botón para limpiar y reiniciar cola de impresión
- Se agregó botón para agregar usuario de Windows
- Se agregó botón para forzar actualización de datos del sistema
- Se agregó botón para buscar instalador LZMA
- Se agregó botón para agregar IPs a adaptadores de red
- Se agregó botón para cambiar OTM a SQL/DBF
- Se agregó botón para permisos en C:\NationalSoft
- Se agregó botón para creación de SRM APK
- Se agregó botón para extractor de instalador
- Se agregó botón para ejecutar SQL Server Management Studio
- Se agregó botón para ejecutar Database4
- Se agregó botón para ejecutar SQL Server Manager
- Se agregó botón para ejecutar ExpressProfiler
"@
function Initialize-Environment {
    if (!(Test-Path -Path "C:\Temp")) {
        try {
            New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
            Write-Host "Carpeta 'C:\Temp' creada." -ForegroundColor Green
        } catch {
            Write-Host "Error creando C:\Temp: $_" -ForegroundColor Yellow
        }
    }
    try {
        $debugEnabled = Initialize-DzToolsConfig
    } catch {
        Write-Host "Advertencia: No se pudo inicializar la configuración de debug. $_" -ForegroundColor Yellow
    }
    try {
        Initialize-QueriesConfig | Out-Null
        Write-Host "  ✓ Sistema de queries inicializado" -ForegroundColor Green
    } catch {
        Write-Host "Advertencia: No se pudo inicializar el sistema de queries. $_" -ForegroundColor Yellow
    }
    return $true
}
$global:isHighlightingQuery = $false
function New-MainForm {
    $mainForm = New-MainWindow
    $window = $mainForm.Window
    $controls = $mainForm.Controls
    $global:MainWindow = $window
    $lblHostname = $window.FindName("lblHostname")
    $lblPort = $window.FindName("lblPort")
    $txt_IpAdress = $window.FindName("txt_IpAdress")
    $txt_AdapterStatus = $window.FindName("txt_AdapterStatus")
    $txt_InfoInstrucciones = $window.FindName("txt_InfoInstrucciones")
    $btnInstalarHerramientas = $window.FindName("btnInstalarHerramientas")
    $btnProfiler = $window.FindName("btnProfiler")
    $btnDatabase = $window.FindName("btnDatabase")
    $btnSQLManager = $window.FindName("btnSQLManager")
    $btnSQLManagement = $window.FindName("btnSQLManagement")
    $btnPrinterTool = $window.FindName("btnPrinterTool")
    $btnLectorDPicacls = $window.FindName("btnLectorDPicacls")
    $LZMAbtnBuscarCarpeta = $window.FindName("LZMAbtnBuscarCarpeta")
    $btnConfigurarIPs = $window.FindName("btnConfigurarIPs")
    $btnAddUser = $window.FindName("btnAddUser")
    $btnFirewallConfig = $window.FindName("btnFirewallConfig")
    $btnForzarActualizacion = $window.FindName("btnForzarActualizacion")
    $btnClearAnyDesk = $window.FindName("btnClearAnyDesk")
    $btnShowPrinters = $window.FindName("btnShowPrinters")
    $btnInstallPrinter = $window.FindName("btnInstallPrinter")
    $btnClearPrintJobs = $window.FindName("btnClearPrintJobs")
    $btnAplicacionesNS = $window.FindName("btnAplicacionesNS")
    $btnCambiarOTM = $window.FindName("btnCambiarOTM")
    $btnCheckPermissions = $window.FindName("btnCheckPermissions")
    $btnCreateAPK = $window.FindName("btnCreateAPK")
    $btnExtractInstaller = $window.FindName("btnExtractInstaller")
    $btnInstaladoresNS = $window.FindName("btnInstaladoresNS")
    $btnRegisterDlls = $window.FindName("btnRegisterDlls")
    $btnMonitorServiciosLog = $window.FindName("btnMonitorServiciosLog")
    $txtServer = $window.FindName("txtServer")
    $txtUser = $window.FindName("txtUser")
    $txtPassword = $window.FindName("txtPassword")
    $cmbDatabases = $window.FindName("cmbDatabases")
    $btnConnectDb = $window.FindName("btnConnectDb")
    $btnDisconnectDb = $window.FindName("btnDisconnectDb")
    $btnSsmsPanelToggle = $window.FindName("btnSsmsPanelToggle")
    $lblConnectionStatus = $window.FindName("lblConnectionStatus")
    $btnExecute = $window.FindName("btnExecute")
    $btnClearQuery = $window.FindName("btnClearQuery")
    $btnExport = $window.FindName("btnExport")
    $btnHistorial = $window.FindName("btnHistorial")
    $cmbQueries = $window.FindName("cmbQueries")
    $tcQueries = $window.FindName("tcQueries")
    $tcResults = $window.FindName("tcResults")
    $tvDatabases = $window.FindName("tvDatabases")
    $tabAddQuery = $window.FindName("tabAddQuery")
    $panelSsmsContent = $window.FindName("panelSsmsContent")
    $tglDarkMode = $window.FindName("tglDarkMode")
    $tglDebugMode = $window.FindName("tglDebugMode")
    $script:predefinedQueries = Get-PredefinedQueries
    #Sirveaun?
    $script:sqlKeywords = 'ADD|ALL|ALTER|AND|ANY|AS|ASC|AUTHORIZATION|BACKUP|BETWEEN|BIGINT|BINARY|BIT|BY|CASE|CHECK|COLUMN|CONSTRAINT|CREATE|CROSS|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|DATABASE|DEFAULT|DELETE|DESC|DISTINCT|DROP|EXEC|EXECUTE|EXISTS|FOREIGN|FROM|FULL|FUNCTION|GROUP|HAVING|IN|INDEX|INNER|INSERT|INT|INTO|IS|JOIN|KEY|LEFT|LIKE|LIMIT|NOT|NULL|ON|OR|ORDER|OUTER|PRIMARY|PROCEDURE|REFERENCES|RETURN|RIGHT|ROWNUM|SELECT|SET|SMALLINT|TABLE|TOP|TRUNCATE|UNION|UNIQUE|UPDATE|VALUES|VIEW|WHERE|WITH|RESTORE'
    if ($cmbQueries) {
        $cmbQueries.Items.Clear()
        $cmbQueries.Items.Add("Selecciona una consulta predefinida") | Out-Null
        foreach ($key in ($script:predefinedQueries.Keys | Sort-Object)) {
            $cmbQueries.Items.Add($key) | Out-Null
        }
        $cmbQueries.SelectedIndex = 0
        $cmbQueries.Add_SelectionChanged({
                $selectedQuery = $cmbQueries.SelectedItem
                if (-not $selectedQuery -or $selectedQuery -eq "Selecciona una consulta predefinida") { return }
                if (-not $script:predefinedQueries.ContainsKey($selectedQuery)) { return }
                $editor = Get-ActiveQueryRichTextBox -TabControl $global:tcQueries
                Write-DzDebug "`t[DEBUG]Insertando consulta predefinida '$selectedQuery' en la pestaña consulta"
                if (-not $editor) { return }
                $queryText = $script:predefinedQueries[$selectedQuery]
                Set-SqlEditorText -Editor $editor -Text $queryText
                $editor.Focus() | Out-Null
            })
    }
    if ($tabAddQuery) {
        $tabAddQuery.Add_PreviewMouseLeftButtonDown({
                New-QueryTab -TabControl $tcQueries | Out-Null
                $_.Handled = $true
            })
    }
    Write-Host "`nRestaurando pestañas de queries..." -ForegroundColor Yellow
    try {
        $restoredCount = Restore-OpenQueryTabs -TabControl $tcQueries
        if ($restoredCount -gt 0) {
            Write-Host "  ✓ Restauradas $restoredCount pestaña(s)" -ForegroundColor Green
            $emptyTabs = @($tcQueries.Items | Where-Object {
                    $_ -is [System.Windows.Controls.TabItem] -and
                    $_.Tag -and
                    $_.Tag.Type -eq 'QueryTab' -and
                    $_.Tag.Editor -and
                    [string]::IsNullOrWhiteSpace((Get-SqlEditorText -Editor $_.Tag.Editor))
                })
            if ($restoredCount -gt 0 -and $emptyTabs.Count -gt 0) {
                foreach ($emptyTab in $emptyTabs) {
                    try {
                        $tcQueries.Items.Remove($emptyTab)
                        Write-DzDebug "`t[DEBUG] Pestaña vacía eliminada"
                    } catch {}
                }
            }
        } else {
            Write-Host "  No hay pestañas guardadas, creando una nueva" -ForegroundColor Gray
            $existingQueryTabs = @($tcQueries.Items | Where-Object {
                    $_ -is [System.Windows.Controls.TabItem] -and
                    $_.Tag -and
                    $_.Tag.Type -eq 'QueryTab'
                })
        }
    } catch {
        Write-Host "  Advertencia: No se pudieron restaurar las pestañas: $_" -ForegroundColor Yellow
        $existingQueryTabs = @($tcQueries.Items | Where-Object {
                $_ -is [System.Windows.Controls.TabItem] -and
                $_.Tag -and
                $_.Tag.Type -eq 'QueryTab'
            })
        if ($existingQueryTabs.Count -eq 0) {
            New-QueryTab -TabControl $tcQueries | Out-Null
        }
    }
    if ($btnExecute -and -not $btnExecute.IsEnabled) {
        if ($tcQueries) { $tcQueries.IsEnabled = $false }
        if ($tcResults) { $tcResults.IsEnabled = $false }
    }
    $script:execStopwatch = [System.Diagnostics.Stopwatch]::new()
    $script:execUiTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:execUiTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $script:execUiTimer.Add_Tick({
            if ($global:lblExecutionTimer) {
                $t = $script:execStopwatch.Elapsed
                $global:lblExecutionTimer.Text = ("Timer: {0:mm\:ss\.f}" -f $t)
            }
        })
    function Start-ExecutionTimer {
        $script:execStopwatch.Restart()
        if (-not $script:execUiTimer.IsEnabled) { $script:execUiTimer.Start() }
    }
    function Stop-ExecutionTimer {
        $script:execStopwatch.Stop()
        if ($script:execUiTimer.IsEnabled) { $script:execUiTimer.Stop() }
        if ($global:lblExecutionTime) {
            $t = $script:execStopwatch.Elapsed
            $global:lblExecutionTime.Text = ("Tiempo: {0:mm\:ss\.fff}" -f $t)
        }
    }
    $global:txtServer = $txtServer
    $global:txtUser = $txtUser
    $global:txtPassword = $txtPassword
    $global:cmbDatabases = $cmbDatabases
    $global:btnConnectDb = $btnConnectDb
    $global:btnDisconnectDb = $btnDisconnectDb
    $global:btnExecute = $btnExecute
    $global:btnClearQuery = $btnClearQuery
    $global:btnExport = $btnExport
    $global:btnHistorial = $btnHistorial
    $global:cmbQueries = $cmbQueries
    $global:tcQueries = $tcQueries
    $global:tcResults = $tcResults
    $global:tvDatabases = $tvDatabases
    $global:tabAddQuery = $tabAddQuery
    $global:txtMessages = $window.FindName("txtMessages")
    if ($global:txtMessages -and $global:txtMessages.PSObject.Properties['IsReadOnly']) {
        $global:txtMessages.IsReadOnly = $true
    }
    $global:lblExecutionTimer = $window.FindName("lblExecutionTimer")
    $global:lblRowCount = $window.FindName("lblRowCount")
    $global:lblConnectionStatus = $lblConnectionStatus
    if ($tvDatabases) {
        try {
            Write-Host "`nAplicando estilo al TreeView..." -ForegroundColor Yellow
            $style = New-Object System.Windows.Style([System.Windows.Controls.TreeViewItem])
            $triggerSelected = New-Object System.Windows.Trigger
            $triggerSelected.Property = [System.Windows.Controls.TreeViewItem]::IsSelectedProperty
            $triggerSelected.Value = $true
            $triggerSelected.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TreeViewItem]::BackgroundProperty, $window.FindResource("AccentPrimary"))))
            $triggerSelected.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TreeViewItem]::ForegroundProperty, $window.FindResource("FormFg"))))
            $triggerFocused = New-Object System.Windows.Trigger
            $triggerFocused.Property = [System.Windows.Controls.TreeViewItem]::IsFocusedProperty
            $triggerFocused.Value = $true
            $triggerFocused.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TreeViewItem]::BackgroundProperty, $window.FindResource("AccentPrimary"))))
            $style.Triggers.Add($triggerSelected)
            $style.Triggers.Add($triggerFocused)
            $tvDatabases.ItemContainerStyle = $style
            Write-Host "  ✓ Estilo de TreeView aplicado correctamente" -ForegroundColor Green
        } catch {
            Write-Host "✗ Error aplicando estilo al TreeView: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if ($btnSsmsPanelToggle) {
        $panelContent = $window.FindName("panelSsmsContent")
        if (-not $panelContent) {
            Write-DzDebug "`t[DEBUG] ERROR: No se encontró panelSsmsContent" -Color Red
            return
        }
        $panelContent.Visibility = "Visible"
        $btnSsmsPanelToggle.Content = "▼"
        $btnSsmsPanelToggle.IsChecked = $true
        $btnSsmsPanelToggle.Add_Click({
                try {
                    $panel = $window.FindName("panelSsmsContent")
                    if (-not $panel) {
                        Write-DzDebug "`t[DEBUG] ERROR: Panel no encontrado en el evento" -Color Red
                        return
                    }
                    $isExpanded = $btnSsmsPanelToggle.IsChecked -eq $true
                    Write-DzDebug "`t[DEBUG] Toggle Click - IsChecked: $isExpanded"
                    if ($isExpanded) {
                        $panel.Visibility = "Visible"
                        $btnSsmsPanelToggle.Content = "▼"
                        Write-DzDebug "`t[DEBUG] Panel expandido" -Color Green
                    } else {
                        $panel.Visibility = "Collapsed"
                        $btnSsmsPanelToggle.Content = "▲"
                        Write-DzDebug "`t[DEBUG] Panel colapsado" -Color Yellow
                    }
                } catch {
                    Write-DzDebug "`t[DEBUG] Error en toggle: $($_.Exception.Message)" -Color Red
                    Write-Host "Error detallado: $($_ | Format-List * -Force | Out-String)" -ForegroundColor Red
                }
            }.GetNewClosure())
    }
    $lblHostname.text = [System.Net.Dns]::GetHostName()
    $txt_InfoInstrucciones.Text = $global:defaultInstructions
    $script:initializingToggles = $true
    if ($tglDarkMode) { $tglDarkMode.IsChecked = ((Get-DzUiMode) -eq 'dark') }
    if ($tglDebugMode) { $tglDebugMode.IsChecked = (Get-DzDebugPreference) }
    $script:initializingToggles = $false
    $script:setInstructionText = {
        param([string]$Message)
        if ($null -ne $txt_InfoInstrucciones) {
            $txt_InfoInstrucciones.Dispatcher.Invoke([action] { $txt_InfoInstrucciones.Text = $Message })
        }
    }.GetNewClosure()
    $script:showRestartNotice = {
        param([string]$settingLabel)
        Show-WpfMessageBoxSafe -Message "Se guardó $settingLabel en dztools.ini.`nReinicia la aplicación para aplicar los cambios." -Title "Reinicio requerido" -Buttons "OK" -Icon "Information" -Owner $window | Out-Null
    }.GetNewClosure()
    if ($tglDarkMode) {
        $tglDarkMode.Add_Checked({
                Write-DzDebug "`t[DEBUG]Toggle Dark Mode activado"
                if ($script:initializingToggles) { return }
                Set-DzUiMode -Mode "dark"
                if ($script:showRestartNotice -is [scriptblock]) { $script:showRestartNotice.Invoke("el modo Dark") }
            })
        $tglDarkMode.Add_Unchecked({
                Write-DzDebug "`t[DEBUG]Toggle Dark Mode desactivado"
                if ($script:initializingToggles) { return }
                Set-DzUiMode -Mode "light"
                if ($script:showRestartNotice -is [scriptblock]) { $script:showRestartNotice.Invoke("el modo Light") }
            })
    }
    if ($tglDebugMode) {
        $tglDebugMode.Add_Checked({
                if ($script:initializingToggles) { return }
                Set-DzDebugPreference -Enabled $true
                Write-Host "[DEBUG] Activado" -ForegroundColor Yellow
            })
        $tglDebugMode.Add_Unchecked({
                Write-DzDebug "`t[DEBUG]Toggle DEBUG desactivado"
                if ($script:initializingToggles) { return }
                Set-DzDebugPreference -Enabled $false
                Write-Host "[DEBUG] Desactivado" -ForegroundColor DarkGray
            })
    }
    $global:txt_AdapterStatus = $txt_AdapterStatus

    @($lblHostname, $lblPort, $txt_IpAdress, $txt_AdapterStatus, $txt_InfoInstrucciones) | ForEach-Object {
        if ($_ -and $_.PSObject.Properties['IsReadOnly']) {
            $_.IsReadOnly = $true
        }
    }
    Initialize-SystemInfo -LblPort $lblPort -LblIpAddress $txt_IpAdress -LblAdapterStatus $txt_AdapterStatus -ModulesPath $modulesPath
    Load-IniConnectionsToComboBox -Combo $txtServer
    if ($txtServer.Items.Count -eq 1) {
        try {
            $serverText = $txtServer.Items[0]
            if (-not [string]::IsNullOrWhiteSpace($serverText)) {
                $txtServer.SelectedIndex = 0
                Start-Sleep -Milliseconds 200
                Apply-SavedSqlCredentials -ServerText $serverText
                Write-DzDebug "`t[DEBUG] Credenciales aplicadas para conexión única: $serverText" -Color Green
            }
        } catch {
            Write-DzDebug "`t[DEBUG] Error aplicando credenciales iniciales: $_" -Color Yellow
        }
    }
    $buttonsToUpdate = @($LZMAbtnBuscarCarpeta, $btnInstalarHerramientas, $btnFirewallConfig, $btnProfiler, $btnDatabase, $btnSQLManager, $btnSQLManagement, $btnPrinterTool, $btnLectorDPicacls, $btnConfigurarIPs, $btnAddUser, $btnForzarActualizacion, $btnClearAnyDesk, $btnShowPrinters, $btnInstallPrinter, $btnClearPrintJobs, $btnAplicacionesNS, $btnCheckPermissions, $btnCambiarOTM, $btnCreateAPK, $btnExtractInstaller, $btnInstaladoresNS, $btnRegisterDlls, $btnMonitorServiciosLog)
    foreach ($button in $buttonsToUpdate) {
        $button.Add_MouseLeave({ if ($script:setInstructionText) { $script:setInstructionText.Invoke($global:defaultInstructions) } })
    }
    $lblHostname.Add_PreviewMouseLeftButtonDown({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG] Click en lblHostname - Evento iniciado" -Color DarkGray
            try {
                $hostname = [System.Net.Dns]::GetHostName()
                if ([string]::IsNullOrWhiteSpace($hostname)) { Write-Host "`n[AVISO] No se pudo obtener el hostname." -ForegroundColor Yellow; return }
                $ok = Set-ClipboardTextSafe -Text $hostname -Owner $global:MainWindow
                if ($ok) { Write-Host "`nNombre del equipo copiado: $hostname" -ForegroundColor Green }else { Ui-Error "No se pudo copiar el hostname al portapapeles." $global:MainWindow }
            } catch {
                Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
                Ui-Error "Error: $($_.Exception.Message)" $global:MainWindow
            } finally {
                $e.Handled = $true
            }
        }.GetNewClosure())
    $lblPort.Add_PreviewMouseLeftButtonDown({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG] Click en lblPort - Evento iniciado" -Color DarkGray
            try {
                $textToCopy = [string]$sender.Text

                if ([string]::IsNullOrWhiteSpace($textToCopy) -or $textToCopy -like "🔍*") {
                    Write-Host "`n⚠ No hay puertos listos para copiar" -ForegroundColor Yellow
                    return
                }

                if (Get-Command Set-ClipboardTextSafe -ErrorAction SilentlyContinue) {
                    Set-ClipboardTextSafe -Text $textToCopy -Owner $global:MainWindow
                    Write-Host "`n✓ Puertos SQL copiados al portapapeles" -ForegroundColor Green
                } else {
                    Set-Clipboard -Value $textToCopy
                    Write-Host "`n✓ Puertos SQL copiados al portapapeles (Set-Clipboard)" -ForegroundColor Green
                }

            } catch {
                Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
            } finally {
                $e.Handled = $true
            }
        }.GetNewClosure())
    $txt_IpAdress.Add_PreviewMouseLeftButtonDown({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG] Click en txt_IpAdress - Evento iniciado" -Color DarkGray
            try {
                $textToCopy = [string]$sender.Text

                if ([string]::IsNullOrWhiteSpace($textToCopy) -or $textToCopy -like "🔍*") {
                    Write-Host "`n⚠ No hay IPs listas para copiar" -ForegroundColor Yellow
                    return
                }

                if (Get-Command Set-ClipboardTextSafe -ErrorAction SilentlyContinue) {
                    Set-ClipboardTextSafe -Text $textToCopy -Owner $global:MainWindow
                    Write-Host "`n✓ Direcciones IP copiadas al portapapeles" -ForegroundColor Green
                    Write-Host " IPs: $textToCopy" -ForegroundColor Green
                } else {
                    Set-Clipboard -Value $textToCopy
                    Write-Host "`n✓ Direcciones IP copiadas al portapapeles (Set-Clipboard)" -ForegroundColor Green
                }

            } catch {
                Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
            } finally {
                $e.Handled = $true
            }
        }.GetNewClosure())

    $txt_AdapterStatus.Add_PreviewMouseLeftButtonDown({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG] Click en txt_AdapterStatus - Evento iniciado" -Color DarkGray
            try {
                $adapters = $txt_AdapterStatus.Tag
                if (-not $adapters -or $adapters.Count -eq 0) { Write-Host "`n⚠ No hay adaptadores para configurar" -ForegroundColor Yellow; return }
                if (Get-Command Set-AdaptersToPrivate -ErrorAction SilentlyContinue) {
                    Set-AdaptersToPrivate -AdapterDetails $adapters -Owner $global:MainWindow
                }
            } catch {
                Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
            } finally {
                $e.Handled = $true
            }
        }.GetNewClosure())
    $btnInstalarHerramientas.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Instalar Herramientas' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Instalar Herramientas' - - -" -ForegroundColor Magenta
            if (-not (Check-Chocolatey)) {
                Write-Host "Chocolatey no está instalado. No se puede abrir el menú de instaladores." -ForegroundColor Red
                return
            }
            Show-ChocolateyInstallerMenu
        })
    $btnProfiler.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Profiler' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Profiler' - - -" -ForegroundColor Magenta
            Invoke-PortableTool -ToolName "ExpressProfiler" -Url "https://github.com/ststeiger/ExpressProfiler/releases/download/1.0/ExpressProfiler20.zip" -ZipPath "C:\Temp\ExpressProfiler22wAddinSigned.zip" -ExtractPath "C:\Temp\ExpressProfiler2" -ExeName "ExpressProfiler.exe" -InfoTextBlock $txt_InfoInstrucciones
        })
    $btnDatabase.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Database' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Database' - - -" -ForegroundColor Magenta
            Invoke-PortableTool -ToolName "Database4" -Url "https://fishcodelib.com/files/DatabaseNet4.zip" -ZipPath "C:\Temp\DatabaseNet4.zip" -ExtractPath "C:\Temp\Database4" -ExeName "Database4.exe" -InfoTextBlock $txt_InfoInstrucciones
        })
    $btnPrinterTool.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Printer Tool' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Printer Tool' - - -" -ForegroundColor Magenta
            Invoke-PortableTool -ToolName "POS Printer Test" -Url "https://3nstar.com/wp-content/uploads/2023/07/RPT-RPI-Printer-Tool-1.zip" -ZipPath "C:\Temp\RPT-RPI-Printer-Tool-1.zip" -ExtractPath "C:\Temp\RPT-RPI-Printer-Tool-1" -ExeName "POS Printer Test.exe" -InfoTextBlock $txt_InfoInstrucciones
        })
    $btnLectorDPicacls.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Lector DP + icacls' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Lector DP + icacls' - - -" -ForegroundColor Magenta
            Invoke-LectorDP -InfoTextBlock $txt_InfoInstrucciones -OwnerWindow $window
        })
    $btnSQLManager.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'SQL Manager' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'SQL Manager' - - -" -ForegroundColor Magenta
            function Get-SQLServerManagers {
                $possiblePaths = @("${env:SystemRoot}\System32\SQLServerManager*.msc", "${env:SystemRoot}\SysWOW64\SQLServerManager*.msc")
                $managers = foreach ($pattern in $possiblePaths) { Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object FullName }
                @($managers) | Where-Object { $_ } | Select-Object -Unique
            }
            $managers = Get-SQLServerManagers
            if (-not $managers -or $managers.Count -eq 0) { Ui-Error "No se encontró ninguna versión de SQL Server Configuration Manager." $global:MainWindow; return }
            Show-SQLselector -Managers $managers
        })
    $btnSQLManagement.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'SQL Management' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'SQL Management' - - -" -ForegroundColor Magenta
            function Get-SSMSVersions {
                $ssmsPaths = @()
                $fixedPaths = @(
                    "${env:ProgramFiles(x86)}\Microsoft SQL Server\*\Tools\Binn\ManagementStudio\Ssms.exe",
                    "${env:ProgramFiles(x86)}\Microsoft SQL Server Management Studio *\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles(x86)}\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles(x86)}\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles(x86)}\Microsoft SQL Server Management Studio 21\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles(x86)}\Microsoft SQL Server Management Studio 22\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio 21\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio 22\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio 21\Release\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio 20\Release\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio 19\Release\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio *\Common7\IDE\Ssms.exe",
                    "${env:ProgramFiles}\Microsoft SQL Server Management Studio *\Release\Common7\IDE\Ssms.exe"
                )
                foreach ($pattern in $fixedPaths) {
                    $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue
                    foreach ($f in $found) {
                        if ($ssmsPaths -notcontains $f.FullName) {
                            $ssmsPaths += $f.FullName
                            Write-DzDebug "`t[DEBUG] ✓ Encontrado: $($f.FullName)" -Color Green
                        }
                    }
                }
                if ($ssmsPaths.Count -eq 0) {
                    Write-DzDebug "`t[DEBUG] No se encontró en rutas fijas. Buscando en registro..." -Color DarkGray
                    $registryPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
                    foreach ($regPath in $registryPaths) {
                        $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*SQL Server Management Studio*" -and $_.InstallLocation -and $_.InstallLocation.Trim() -ne "" }
                        foreach ($entry in $entries) {
                            $installPath = $entry.InstallLocation.Trim()
                            if (-not $installPath.EndsWith('\')) { $installPath += '\' }
                            foreach ($sub in @("Common7\IDE\Ssms.exe", "Release\Common7\IDE\Ssms.exe")) {
                                $full = Join-Path $installPath $sub
                                if (Test-Path $full) {
                                    $resolved = (Resolve-Path $full).Path
                                    if ($ssmsPaths -notcontains $resolved) {
                                        $ssmsPaths += $resolved
                                        Write-DzDebug "`t[DEBUG] ✓ Encontrado (registro): $resolved" -Color Green
                                    }
                                }
                            }
                        }
                    }
                }
                $ssmsPaths | Sort-Object -Descending
            }
            $ssmsVersions = Get-SSMSVersions
            $filteredVersions = foreach ($p in $ssmsVersions) { if ((Split-Path $p -Leaf) -eq "Ssms.exe" -and (Test-Path $p -PathType Leaf)) { $p } }
            if (-not $filteredVersions -or $filteredVersions.Count -eq 0) {
                Write-Host "`tNo se encontró ninguna versión de SSMS instalada." -ForegroundColor Red
                $wantManual = Ui-Confirm "No se encontró SQL Server Management Studio. ¿Desea buscar manualmente?" "SSMS no encontrado"
                if ($wantManual) {
                    $openFileDialog = New-Object Microsoft.Win32.OpenFileDialog
                    $openFileDialog.Filter = "SSMS Executable (Ssms.exe)|Ssms.exe"
                    $openFileDialog.Title = "Seleccione Ssms.exe"
                    if ($openFileDialog.ShowDialog() -eq $true) {
                        try {
                            Start-Process -FilePath $openFileDialog.FileName
                            Write-Host "`tEjecutando: $($openFileDialog.FileName)" -ForegroundColor Green
                        } catch { Ui-Error "Error al ejecutar SSMS: $($_.Exception.Message)" $global:MainWindow }
                    }
                } else {
                    $wantDownload = Ui-Confirm "¿Desea descargar la última versión de SSMS?" "Descargar SSMS"
                    if ($wantDownload) { Start-Process "https://aka.ms/ssmsfullsetup" }
                }
                return
            }
            Write-Host "`t✓ Se encontraron $($filteredVersions.Count) instalación(es) de SSMS" -ForegroundColor Green
            Show-SQLselector -SSMSVersions $filteredVersions
        })
    $btnForzarActualizacion.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Forzar Actualización' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Forzar Actualización' - - -" -ForegroundColor Magenta
            Show-SystemComponents
            $ok = Ui-Confirm "¿Desea forzar la actualización de datos?" "Confirmación" $global:MainWindow
            if ($ok) { Start-SystemUpdate; Ui-Info "Actualización completada" "Éxito" $global:MainWindow } else { Write-Host "`tEl usuario canceló la operación." -ForegroundColor Red }
        })
    $btnClearAnyDesk.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Clear AnyDesk' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Clear AnyDesk' - - -" -ForegroundColor Magenta
            $ok = Ui-Confirm "¿Estás seguro de renovar AnyDesk?" "Confirmar renovación" $global:MainWindow
            if ($ok) {
                $filesToDelete = @("C:\ProgramData\AnyDesk\system.conf", "C:\ProgramData\AnyDesk\service.conf", "$env:APPDATA\AnyDesk\system.conf", "$env:APPDATA\AnyDesk\service.conf")
                $deletedFilesCount = 0
                $errors = @()
                try {
                    Write-Host "`tCerrando el proceso AnyDesk..." -ForegroundColor Yellow
                    Stop-Process -Name "AnyDesk" -Force -ErrorAction Stop
                    Write-Host "`tAnyDesk ha sido cerrado correctamente." -ForegroundColor Green
                } catch {
                    Write-Host "`tError al cerrar el proceso AnyDesk: $_" -ForegroundColor Red
                    $errors += "No se pudo cerrar el proceso AnyDesk."
                }
                foreach ($file in $filesToDelete) {
                    try {
                        if (Test-Path $file) {
                            Remove-Item -Path $file -Force -ErrorAction Stop
                            Write-Host "`tArchivo eliminado: $file" -ForegroundColor Green
                            $deletedFilesCount++
                        } else {
                            Write-Host "`tArchivo no encontrado: $file" -ForegroundColor Red
                        }
                    } catch { Write-Host "`nError al eliminar el archivo." -ForegroundColor Red }
                }
                if ($errors.Count -eq 0) { Ui-Info "$deletedFilesCount archivo(s) eliminado(s) correctamente." "Éxito" $global:MainWindow } else { Ui-Error "Se encontraron errores. Revisa la consola para más detalles." $global:MainWindow }
            } else { Write-Host "`tEl usuario canceló la operación." -ForegroundColor Red }
        })
    $btnShowPrinters.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Show Printers' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Show Printers' - - -" -ForegroundColor Magenta
            Show-NSPrinters
        })
    $btnInstallPrinter.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Instalar impresora' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Instalar impresora' - - -" -ForegroundColor Magenta
            Show-InstallPrinterDialog
        })
    $btnClearPrintJobs.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Clear Print Jobs' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Clear Print Jobs' - - -" -ForegroundColor Magenta
            Invoke-ClearPrintJobs -InfoTextBlock $txt_InfoInstrucciones
        })
    $btnCheckPermissions.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Revisar Permisos' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Revisar Permisos' - - -" -ForegroundColor Magenta
            if (-not (Test-Administrator)) {
                Ui-Error "Esta acción requiere permisos de administrador.`r`nPor favor, ejecuta Gerardo Zermeño Tools como administrador." $global:MainWindow
                return
            }
            Check-Permissions
        })
    $btnAplicacionesNS.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Aplicaciones NS' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Aplicaciones NS' - - -" -ForegroundColor Magenta
            $res = Get-NSApplicationsIniReport
            Show-NSApplicationsIniReport -Resultados $res
        })
    $btnRegisterDlls.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Registro registro de dlls' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Registro registro de dlls' - - -" -ForegroundColor Magenta
            Show-DllRegistrationDialog
        })
    $btnMonitorServiciosLog.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Log Monitor Servicios' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Log Monitor Servicios' - - -" -ForegroundColor Magenta
            Invoke-NSMonitorServicesLogSetup -Owner $window
        })
    $btnCambiarOTM.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Cambiar OTM' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Cambiar OTM' - - -" -ForegroundColor Magenta
            Invoke-CambiarOTMConfig -InfoTextBlock $txt_InfoInstrucciones
        })
    $LZMAbtnBuscarCarpeta.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Buscar Instaladores LZMA' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Buscar Instaladores LZMA' - - -" -ForegroundColor Magenta
            Show-LZMADialog
        })
    $btnConfigurarIPs.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Configurar IPs' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Configurar IPs' - - -" -ForegroundColor Magenta
            Show-IPConfigDialog
        })
    $btnAddUser.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Agregar Usuario' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Agregar Usuario' - - -" -ForegroundColor Magenta
            Show-AddUserDialog
        })
    $btnFirewallConfig.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Configuraciones de Firewall' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Configuraciones de Firewall' - - -" -ForegroundColor Magenta
            Show-FirewallConfigDialog
        })
    $btnCreateAPK.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Crear APK' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Crear APK' - - -" -ForegroundColor Magenta
            Invoke-CreateApk -InfoTextBlock $txt_InfoInstrucciones
        })
    $btnExtractInstaller.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Extraer Instalador' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Extraer Instalador' - - -" -ForegroundColor Magenta
            Show-InstallerExtractorDialog
        })
    $btnInstaladoresNS.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Instaladores NS' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`t- - - Abriendo 'Instaladores NS' - - -" -ForegroundColor Gray
            Start-Process "https://nationalsoft-my.sharepoint.com/:f:/g/personal/gerardo_zermeno_softrestaurant_com/IgC3tKgxlNw9S7JmBk935kCrAVq9jkz06CJek9ljNOrr_Hw?e=xf2dFh"
        })
    $btnDisconnectDb.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Desconectar Base de Datos' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Desconectando de la Base de Datos - - -" -ForegroundColor Cyan
            Disconnect-DbUiSafe
        })
    $btnConnectDb.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Conectar Base de Datos' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Comenzando el proceso de 'Conectar Base de Datos' - - -" -ForegroundColor Magenta
            Connect-DbUiSafe
        })
    if ($txtServer) {
        $getServerText = {
            $text = $null
            if ($global:txtServer.SelectedItem -is [string]) {
                $text = $global:txtServer.SelectedItem
            } elseif (-not [string]::IsNullOrWhiteSpace($global:txtServer.Text)) {
                $text = $global:txtServer.Text
            }
            if ($text) { return $text.Trim() } else { return "" }
        }
        $txtServer.Add_SelectionChanged({
                try {
                    $serverText = & $getServerText
                    Write-DzDebug "`t[DEBUG] Servidor seleccionado: '$serverText'"
                    if (-not [string]::IsNullOrWhiteSpace($serverText)) {
                        Start-Sleep -Milliseconds 100
                        Apply-SavedSqlCredentials -ServerText $serverText
                    }
                } catch {
                    Write-DzDebug "`t[DEBUG] Error aplicando credenciales: $_" -Color Red
                }
            }.GetNewClosure())
    }
    $btnExecute.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Ejecutar Consulta' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n`t- - - Ejecutando consulta - - -" -ForegroundColor Gray
            Execute-QueryUiSafe
        })
    $cmbDatabases.Add_SelectionChanged({
            if ($global:cmbDatabases.SelectedItem) {
                $dbName = Get-DbNameFromComboSelection -ComboBox $global:cmbDatabases
                if ($dbName) {
                    $global:database = $dbName
                    if ($global:lblConnectionStatus) {
                        $global:lblConnectionStatus.Text = "✓ Conectado a: $($global:server) | DB: $dbName"
                    }
                    if (Get-Command Set-QueryTabsDatabase -ErrorAction SilentlyContinue) {
                        Set-QueryTabsDatabase -TabControl $global:tcQueries -Database $dbName
                    }
                }
                if ($dbName -and $global:tvDatabases) {
                    Select-SqlTreeDatabase -TreeView $global:tvDatabases -DatabaseName $dbName
                }
            }
        })
    #en main.ps1
    $global:dgResults = $window.FindName("dgResults")
    $btnClearQuery.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Limpiar Query' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            try {
                $editor = Get-ActiveQueryRichTextBox -TabControl $global:tcQueries
                if (-not $editor) { throw "No hay una pestaña de consulta activa." }
                Clear-SqlEditorText -Editor $editor
                if ($global:dgResults) { $global:dgResults.ItemsSource = $null }
                if ($global:txtMessages) { $global:txtMessages.Text = "" }
                if ($global:lblRowCount) { $global:lblRowCount.Text = "Filas: --" }
                $tab = Get-ActiveQueryTab -TabControl $global:tcQueries
                $tabName = if ($tab -and $tab.Tag -and $tab.Tag.Title) { $tab.Tag.Title } else { "Desconocida" }
                Write-DzDebug "`t[DEBUG] Se limpió la consulta en la pestaña: $tabName"
                Write-Host "Consulta limpiada" -ForegroundColor Cyan
            } catch {
                $msg = $_.Exception.Message
                if ($global:txtMessages) { $global:txtMessages.Text = $msg }
                Write-Host "`n=============== ERROR ==============" -ForegroundColor Red
                Write-Host "Mensaje: $msg" -ForegroundColor Yellow
                Write-Host "====================================" -ForegroundColor Red
            }
        })
    $btnExport.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Exportar resultados' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Export-ResultsUiSafe
        })
    $btnHistorial.Add_Click({
            Write-DzDebug ("`t[DEBUG] Click en 'Historial' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
            Write-Host "`n- - - Abriendo historial de queries - - -" -ForegroundColor Magenta
            Show-QueryHistoryWindow -Owner $window
        })
    $window.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq 'F5' -and $btnExecute.IsEnabled) {
                $btnExecute.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
                $e.Handled = $true
            }
        })
    $closeWindowScript = {
        Write-Host "Cerrando aplicación..." -ForegroundColor Yellow
        Write-DzDebug "`t[DEBUG] Botón Salir presionado" -Color DarkGray
        try {
            $btn = $args[0]
            $win = [System.Windows.Window]::GetWindow($btn)
            if ($null -ne $win) {
                $win.Close()
                Write-DzDebug "`t[DEBUG] Ventana cerrada (método 1)" -Color DarkGray
            } else {
                $window.Close()
                Write-DzDebug "`t[DEBUG] Ventana cerrada (método 2)" -Color DarkGray
            }
        } catch {
            Write-Host "Error al cerrar: $_" -ForegroundColor Yellow
            Write-DzDebug "`t[DEBUG] Error: $_" -Color Red
        }
    }.GetNewClosure()
    $window.Dispatcher.Add_UnhandledException({
            param($sender, $e)
            $ex = $e.Exception
            Write-Host "`n[WPF Dispatcher ERROR]" -ForegroundColor Red
            Write-Host "Mensaje: $($ex.Message)" -ForegroundColor Yellow
            Write-Host "Tipo   : $($ex.GetType().FullName)" -ForegroundColor Yellow
            Write-Host "Stack  : $($ex.StackTrace)" -ForegroundColor DarkYellow
            if ($ex -is [System.Management.Automation.RuntimeException] -and $ex.ErrorRecord) {
                $er = $ex.ErrorRecord
                if ($er.InvocationInfo) {
                    Write-Host "Archivo : $($er.InvocationInfo.ScriptName)" -ForegroundColor Cyan
                    Write-Host "Línea   : $($er.InvocationInfo.ScriptLineNumber)" -ForegroundColor Cyan
                    Write-Host "Código  : $($er.InvocationInfo.Line)" -ForegroundColor Cyan
                    Write-Host "Pos     : $($er.InvocationInfo.PositionMessage)" -ForegroundColor DarkCyan
                }
                Write-Host "PSScriptStackTrace:" -ForegroundColor Magenta
                Write-Host $er.ScriptStackTrace -ForegroundColor Magenta
            }
            $e.Handled = $true
        })
    $window.Add_Closing({
            param($sender, $e)
            Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
            Write-Host "  Cerrando aplicación..." -ForegroundColor Yellow
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
            try {
                Write-Host "`n  📝 Guardando estado de pestañas..." -ForegroundColor Yellow
                if ($global:tcQueries) {
                    $saved = Save-OpenQueryTabs -TabControl $global:tcQueries
                    if ($saved) { Write-Host "  ✓ Estado guardado exitosamente" -ForegroundColor Green } else { Write-Host "  ⚠ No se pudo guardar el estado" -ForegroundColor Yellow }
                }
            } catch {
                Write-Host "  ✗ Error guardando pestañas: $_" -ForegroundColor Red
            }
            try {
                if ($global:connection -and $global:connection.State -eq [System.Data.ConnectionState]::Open) {
                    Write-Host "`n  🔌 Cerrando conexión a base de datos..." -ForegroundColor Yellow
                    Disconnect-DbUiSafe
                    Write-Host "  ✓ Conexión cerrada" -ForegroundColor Green
                }
            } catch {}
            Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
            Write-Host "  ¡Hasta pronto!" -ForegroundColor Green
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
        })
    Write-Host "  ✓ Formulario WPF creado exitosamente" -ForegroundColor Green
    return $window
}
function Start-Application {
    Write-Host "`nInicializando entorno..." -ForegroundColor Yellow
    if (-not (Initialize-Environment)) {
        Write-Host "  ✗ Error inicializando entorno" -ForegroundColor Red
        return
    }
    Write-Host "  ✓ Entorno listo" -ForegroundColor Green
    Write-Host "`nCargando módulos..." -ForegroundColor Yellow
    $modulesPath = Join-Path $PSScriptRoot "modules"
    $modules = @("GUI.psm1", "Database.psm1", "Utilities.psm1", "SqlTreeView.psm1", "Installers.psm1", "WindowsUtilities.psm1", "NationalUtilities.psm1", "SqlOps.psm1", "QueriesPad.psm1")
    foreach ($module in $modules) {
        $modulePath = Join-Path $modulesPath $module
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
        }
    }
    Write-Host "  ✓ Módulos cargados" -ForegroundColor Green
    Write-Host "`nCreando interfaz gráfica..." -ForegroundColor Yellow
    $mainForm = New-MainForm
    Write-Host "  ✓ Interfaz lista`n" -ForegroundColor Green
    Write-Host "`n==================================================" -ForegroundColor DarkCyan
    Write-Host "       Gerardo Zermeño Tools - Suite de Utilidades       " -ForegroundColor Green
    Write-Host "              Versión: $($global:version)               " -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor DarkCyan
    Write-Host "`nTodos los derechos reservados para Gerardo Zermeño Tools." -ForegroundColor Cyan
    Write-Host "Para reportar errores o sugerencias, contacte vía Teams." -ForegroundColor Cyan
    Write-Host "O crea un issue en GitHub en:" -ForegroundColor Cyan
    Write-Host "https://github.com/water0ff/dztools/issues/new" -ForegroundColor Cyan
    $null = $mainForm.ShowDialog()
}
try {
    Start-Application
} catch {
    Write-Host "Error fatal: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo) {
        Write-Host "Archivo : $($_.InvocationInfo.ScriptName)" -ForegroundColor Yellow
        Write-Host "Línea   : $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
        Write-Host "Col     : $($_.InvocationInfo.OffsetInLine)" -ForegroundColor Yellow
        Write-Host "Código  : $($_.InvocationInfo.Line)" -ForegroundColor Yellow
        Write-Host "Pos     : $($_.InvocationInfo.PositionMessage)" -ForegroundColor DarkYellow
    }
    Write-Host "ScriptStackTrace:" -ForegroundColor Magenta
    Write-Host $_.ScriptStackTrace -ForegroundColor Magenta
    Write-Host "Stack Trace .NET:" -ForegroundColor DarkRed
    Write-Host $_.Exception.StackTrace -ForegroundColor DarkRed
    pause
    exit 1
}