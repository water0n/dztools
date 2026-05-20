#requires -Version 5.0
#WindowsUtilities.psm1 - Módulo de utilidades para Windows
function Start-SystemUpdate {
  param([int]$DiskCleanupTimeoutMinutes = 3)
  $progressWindow = $null
  Write-DzDebug "`t[DEBUG]Start-SystemUpdate: INICIO (Timeout=$DiskCleanupTimeoutMinutes min)"
  try {
    $progressWindow = Show-WpfProgressBar -Title "Actualización del Sistema" -Message "Iniciando proceso..."
    $totalSteps = 5
    $currentStep = 0
    Write-Host "`nIniciando proceso de actualización..." -ForegroundColor Cyan
    Write-DzDebug "`t[DEBUG]Paso 1: Deteniendo servicio winmgmt..."
    Write-Host "`n[Paso 1/$totalSteps] Deteniendo servicio winmgmt..." -ForegroundColor Yellow
    $service = Get-Service -Name "winmgmt" -ErrorAction Stop
    Write-DzDebug "`t[DEBUG]Paso 1: Estado actual winmgmt=$($service.Status)"
    if ($service.Status -eq "Running") {
      Update-WpfProgressBar -Window $progressWindow -Percent 10 -Message "Deteniendo servicio WMI..."
      Stop-Service -Name "winmgmt" -Force -ErrorAction Stop
      Write-DzDebug "`t[DEBUG]Paso 1: winmgmt detenido OK"
      Write-Host "`n`tServicio detenido correctamente." -ForegroundColor Green
    }
    $currentStep++
    Update-WpfProgressBar -Window $progressWindow -Percent 20 -Message "Servicio WMI detenido"
    Start-Sleep -Milliseconds 500
    Write-DzDebug "`t[DEBUG]Paso 2: Renombrando carpeta Repository..."
    Write-Host "`n[Paso 2/$totalSteps] Renombrando carpeta Repository..." -ForegroundColor Yellow
    Update-WpfProgressBar -Window $progressWindow -Percent 30 -Message "Renombrando Repository..."
    try {
      $repoPath = Join-Path $env:windir "System32\Wbem\Repository"
      Write-DzDebug "`t[DEBUG]Paso 2: repoPath=$repoPath"
      if (Test-Path $repoPath) {
        $newName = "Repository_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Rename-Item -Path $repoPath -NewName $newName -Force -ErrorAction Stop
        Write-DzDebug "`t[DEBUG]Paso 2: Carpeta renombrada a $newName"
        Write-Host "`n`tCarpeta renombrada: $newName" -ForegroundColor Green
      }
    } catch {
      Write-DzDebug "`t[DEBUG]Paso 2: EXCEPCIÓN: $($_.Exception.Message)" Red
      Write-Host "`n`tAdvertencia: No se pudo renombrar Repository. Continuando..." -ForegroundColor Yellow
    }
    $currentStep++
    Update-WpfProgressBar -Window $progressWindow -Percent 40 -Message "Repository renovado"
    Start-Sleep -Milliseconds 500
    Write-DzDebug "`t[DEBUG]Paso 3: Reiniciando servicio winmgmt..."
    Write-Host "`n[Paso 3/$totalSteps] Reiniciando servicio winmgmt..." -ForegroundColor Yellow
    Update-WpfProgressBar -Window $progressWindow -Percent 50 -Message "Reiniciando servicio WMI..."
    net start winmgmt *>&1 | Write-Host
    Write-DzDebug "`t[DEBUG]Paso 3: winmgmt reiniciado"
    Write-Host "`n`tServicio WMI reiniciado." -ForegroundColor Green
    $currentStep++
    Update-WpfProgressBar -Window $progressWindow -Percent 60 -Message "Servicio WMI reiniciado"
    Start-Sleep -Milliseconds 500
    Write-DzDebug "`t[DEBUG]Paso 4: Limpiando archivos temporales..."
    Write-Host "`n[Paso 4/$totalSteps] Limpiando archivos temporales..." -ForegroundColor Cyan
    Update-WpfProgressBar -Window $progressWindow -Percent 70 -Message "Limpiando archivos temporales..."
    $cleanupResult = Clear-TemporaryFiles
    Write-DzDebug "`t[DEBUG]Paso 4: FilesDeleted=$($cleanupResult.FilesDeleted) SpaceFreedMB=$($cleanupResult.SpaceFreedMB)"
    Write-Host "`n`tTotal archivos eliminados: $($cleanupResult.FilesDeleted)" -ForegroundColor Green
    Write-Host "`n`tEspacio liberado: $($cleanupResult.SpaceFreedMB) MB" -ForegroundColor Green
    $currentStep++
    Update-WpfProgressBar -Window $progressWindow -Percent 80 -Message "Archivos temporales limpiados"
    Start-Sleep -Milliseconds 500
    Write-DzDebug "`t[DEBUG]Paso 5: Ejecutando Liberador de espacio..."
    Write-Host "`n[Paso 5/$totalSteps] Ejecutando Liberador de espacio..." -ForegroundColor Cyan
    Update-WpfProgressBar -Window $progressWindow -Percent 90 -Message "Preparando limpieza de disco..."
    Write-DzDebug "`t[DEBUG]Paso 5: Ejecutando Liberador de espacio..."
    Write-Host "`n[Paso 5/$totalSteps] Ejecutando Liberador de espacio..." -ForegroundColor Cyan
    Update-WpfProgressBar -Window $progressWindow -Percent 90 -Message "Preparando limpieza de disco..."

    # Agregar botón de cancelar a la ventana de progreso
    if ($progressWindow) {
      try {
        $progressWindow.Dispatcher.Invoke([action] {
            # Buscar el botón de cancelar (si ya existe)
            $cancelBtn = $progressWindow.FindName("btnCancel")
            if ($cancelBtn) {
              $cancelBtn.Visibility = "Visible"
              $cancelBtn.Content = "Finalizar ahora"
              $cancelBtn.ToolTip = "Saltar la limpieza de disco y finalizar"
            }
          }, [System.Windows.Threading.DispatcherPriority]::Normal)
      } catch {
        Write-DzDebug "`t[DEBUG]No se pudo mostrar botón cancelar: $_" Yellow
      }
    }
    $diskCleanupResult = Invoke-DiskCleanup -Wait -TimeoutMinutes $DiskCleanupTimeoutMinutes -ProgressWindow $progressWindow
    if ($progressWindow) {
      try {
        $progressWindow.Dispatcher.Invoke([action] {
            $cancelBtn = $progressWindow.FindName("btnCancel")
            if ($cancelBtn) {
              $cancelBtn.Visibility = "Collapsed"
            }
          }, [System.Windows.Threading.DispatcherPriority]::Normal)
      } catch {}
    }

    if ($diskCleanupResult -eq "Cancelled") {
      Write-DzDebug "`t[DEBUG]Paso 5: Usuario canceló la limpieza de disco"
      Write-Host "`n`tLimpieza de disco cancelada por el usuario." -ForegroundColor Yellow
    } elseif ($diskCleanupResult -eq "Timeout") {
      Write-DzDebug "`t[DEBUG]Paso 5: Timeout en limpieza de disco"
      Write-Host "`n`tLimpieza de disco finalizó por timeout." -ForegroundColor Yellow
    } else {
      Write-DzDebug "`t[DEBUG]Paso 5: Liberador completado"
    }
    Write-Host "`nSe recomienda REINICIAR el equipo" -ForegroundColor Yellow
    Write-DzDebug "`t[DEBUG]Start-SystemUpdate: Mostrando diálogo de reinicio"
    $result = [System.Windows.MessageBox]::Show("El proceso de actualización se completó exitosamente.`n`n" + "Se recomienda REINICIAR el equipo para completar la actualización del sistema WMI.`n`n" + "¿Desea reiniciar ahora?", "Actualización completada", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
      Write-Host "`n`tReiniciando equipo en 10 segundos..." -ForegroundColor Yellow
      Write-DzDebug "`t[DEBUG]Start-SystemUpdate: Usuario eligió reiniciar"
      Start-Sleep -Seconds 3
      shutdown /r /t 10 /c "Reinicio para completar actualización de sistema WMI"
    } else {
      Write-Host "`n`tRecuerde reiniciar el equipo más tarde." -ForegroundColor Yellow
      Write-DzDebug "`t[DEBUG]Start-SystemUpdate: Usuario canceló reinicio"
    }
    Write-DzDebug "`t[DEBUG]Start-SystemUpdate: FIN OK"
    return $true
  } catch {
    Write-DzDebug "`t[DEBUG]Start-SystemUpdate: EXCEPCIÓN: $($_.Exception.Message)" Red
    Write-DzDebug "`t[DEBUG]Start-SystemUpdate: ScriptStackTrace: $($_.ScriptStackTrace)" Red
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    [System.Windows.MessageBox]::Show("Error durante la actualización: $($_.Exception.Message)`n`n" + "Revise los logs y considere reiniciar manualmente el equipo.", "Error en actualización", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    return $false
  } finally {
    Write-DzDebug "`t[DEBUG]Start-SystemUpdate: FINALLY (cerrando progressWindow)"
    if ($progressWindow -ne $null -and $progressWindow.IsVisible) { Close-WpfProgressBar -Window $progressWindow }
  }
}
function Show-SystemComponents {
  param([switch]$SkipOnError)
  Write-Host "`n=== Componentes del sistema detectados ===" -ForegroundColor Cyan
  $os = $null
  $maxAttempts = 3
  $retryDelaySeconds = 2
  for ($attempt = 1; $attempt -le $maxAttempts -and -not $os; $attempt++) {
    try { $os = Get-CimInstance -ClassName CIM_OperatingSystem -ErrorAction Stop }catch {
      if ($attempt -lt $maxAttempts) {
        $msg = "Show-SystemComponents: ERROR intento {0}: {1}. Reintento en {2}s" -f $attempt, $_.Exception.Message, $retryDelaySeconds
        Write-Host $msg -ForegroundColor DarkYellow
        Start-Sleep -Seconds $retryDelaySeconds
      } else {
        Write-Host "`n[Windows]" -ForegroundColor Yellow
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if (-not $SkipOnError) { throw "No se pudo obtener información crítica del sistema" }else { Write-Host "Continuando sin información del sistema..." -ForegroundColor Yellow; return }
      }
    }
  }
  if (-not $os) {
    if (-not $SkipOnError) { throw "No se pudo obtener información crítica del sistema" }
    return
  }
  Write-Host "`n[Windows]" -ForegroundColor Yellow
  Write-Host "Versión: $($os.Caption) (Build $($os.Version))" -ForegroundColor White
  try {
    Write-DzDebug "`t[DEBUG]Show-SystemComponents: Obteniendo CIM_Processor..."
    $procesador = Get-CimInstance -ClassName CIM_Processor -ErrorAction Stop
    Write-Host "`n[Procesador]" -ForegroundColor Yellow
    Write-Host "Modelo: $($procesador.Name)" -ForegroundColor White
    Write-Host "Núcleos: $($procesador.NumberOfCores)" -ForegroundColor White
  } catch {
    Write-DzDebug "`t[DEBUG]Show-SystemComponents: Error leyendo procesador" Red
    Write-Host "`n[Procesador]" -ForegroundColor Yellow
    Write-Host "Error de lectura: $($_.Exception.Message)" -ForegroundColor Red
  }
  try {
    Write-DzDebug "`t[DEBUG]Show-SystemComponents: Obteniendo CIM_PhysicalMemory..."
    $memoria = Get-CimInstance -ClassName CIM_PhysicalMemory -ErrorAction Stop
    Write-Host "`n[Memoria RAM]" -ForegroundColor Yellow
    $memoria | ForEach-Object { Write-Host "Módulo: $([math]::Round($_.Capacity/1GB,2)) GB $($_.Manufacturer) ($($_.Speed) MHz)" -ForegroundColor White }
  } catch {
    Write-DzDebug "`t[DEBUG]Show-SystemComponents: Error leyendo memoria" Red
    Write-Host "`n[Memoria RAM]" -ForegroundColor Yellow
    Write-Host "Error de lectura: $($_.Exception.Message)" -ForegroundColor Red
  }
  try {
    Write-DzDebug "`t[DEBUG]Show-SystemComponents: Obteniendo CIM_DiskDrive..."
    $discos = Get-CimInstance -ClassName CIM_DiskDrive -ErrorAction Stop
    Write-Host "`n[Discos duros]" -ForegroundColor Yellow
    $discos | ForEach-Object { Write-Host "Disco: $($_.Model) ($([math]::Round($_.Size/1GB,2)) GB)" -ForegroundColor White }
  } catch {
    Write-DzDebug "`t[DEBUG]Show-SystemComponents: Error leyendo discos" Red
    Write-Host "`n[Discos duros]" -ForegroundColor Yellow
    Write-Host "Error de lectura: $($_.Exception.Message)" -ForegroundColor Red
  }
  Write-DzDebug "`t[DEBUG]Show-SystemComponents: FIN"
}
function Show-NSPrinters {
  [CmdletBinding()]param()
  Write-Host "`nImpresoras disponibles en el sistema:"
  $GetNSPrinters = {
    [CmdletBinding()]
    param()
    try {
      Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
          Name       = $_.Name
          PortName   = $_.PortName
          DriverName = $_.DriverName
          Shared     = [bool]$_.Shared
        }
      }
    } catch {
      Write-DzDebug "`t[DEBUG][Get-NSPrinters] ERROR: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
      @()
    }
  }.GetNewClosure()
  $printers = & $GetNSPrinters
  if (-not $printers -or $printers.Count -eq 0) { Write-Host "`nNo se encontraron impresoras."; return }
  $view = $printers | ForEach-Object {
    [PSCustomObject]@{
      Name       = ([string]$_.Name).Substring(0, [Math]::Min(24, ([string]$_.Name).Length))
      PortName   = ([string]$_.PortName).Substring(0, [Math]::Min(19, ([string]$_.PortName).Length))
      DriverName = ([string]$_.DriverName).Substring(0, [Math]::Min(19, ([string]$_.DriverName).Length))
      IsShared   = if ($_.Shared) { "Sí" } else { "No" }
    }
  }
  $uiItems = $printers | ForEach-Object {
    [PSCustomObject]@{
      Name       = [string]$_.Name
      PortName   = [string]$_.PortName
      DriverName = [string]$_.DriverName
      IsShared   = if ($_.Shared) { "Sí" } else { "No" }
    }
  }
  Write-Host ("{0,-25} {1,-20} {2,-20} {3,-10}" -f "Nombre", "Puerto", "Driver", "Compartida")
  Write-Host ("{0,-25} {1,-20} {2,-20} {3,-10}" -f "------", "------", "------", "---------")
  $view | ForEach-Object { Write-Host ("{0,-25} {1,-20} {2,-20} {3,-10}" -f $_.Name, $_.PortName, $_.DriverName, $_.IsShared) }
  $theme = Get-DzUiTheme
  $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Impresoras instaladas"
        Width="600" Height="300"
        MinWidth="600" MinHeight="300"
        MaxWidth="600" MaxHeight="300"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
    <Window.Resources>
        <Style TargetType="{x:Type Control}">
            <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
            <Setter Property="FontSize" Value="11"/>
        </Style>
        <Style x:Key="IconButtonStyle" TargetType="Button">
            <Setter Property="Width" Value="30"/>
            <Setter Property="Height" Value="26"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="{x:Type DataGrid}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="RowBackground" Value="{DynamicResource ControlBg}"/>
            <Setter Property="AlternatingRowBackground" Value="{DynamicResource PanelBg}"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="VerticalGridLinesBrush" Value="Transparent"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="AutoGenerateColumns" Value="False"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="CanUserDeleteRows" Value="False"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="SelectionUnit" Value="Cell"/>
            <Setter Property="CanUserResizeRows" Value="False"/>
            <Setter Property="CanUserSortColumns" Value="True"/>
            <Setter Property="RowHeaderWidth" Value="0"/>
            <Setter Property="Padding" Value="0"/>
        </Style>
        <Style TargetType="{x:Type DataGridColumnHeader}">
            <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource PanelFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
        </Style>
        <Style TargetType="{x:Type DataGridRow}">
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Style.Triggers>
                <Trigger Property="AlternationIndex" Value="1">
                    <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
                    <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
                    <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="{x:Type DataGridCell}">
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="Padding" Value="10,5"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
                    <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Border Background="{DynamicResource FormBg}"
            BorderBrush="{DynamicResource BorderBrushColor}"
            BorderThickness="1"
            CornerRadius="12"
            Margin="10"
            SnapsToDevicePixels="True">
        <Border.Effect>
            <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
        </Border.Effect>

        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="52"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Border Grid.Row="0"
                    Name="brdTitleBar"
                    Background="{DynamicResource FormBg}"
                    CornerRadius="12,12,0,0"
                    Padding="12,8">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0"
                            Width="6"
                            CornerRadius="3"
                            Background="{DynamicResource AccentPrimary}"
                            Margin="0,4,10,4"/>

                    <StackPanel Grid.Column="1" Orientation="Vertical">
                        <TextBlock Text="🖨️ Impresoras del Sistema"
                                   FontWeight="SemiBold"
                                   Foreground="{DynamicResource FormFg}"
                                   FontSize="12"/>
                        <TextBlock Text="Clic derecho en una celda para copiar"
                                   Foreground="{DynamicResource AccentMuted}"
                                   FontSize="10"
                                   Margin="0,2,0,0"/>
                    </StackPanel>

                    <Button Grid.Column="2"
                            Name="btnClose"
                            Style="{StaticResource IconButtonStyle}"
                            Content="✕"
                            ToolTip="Cerrar"/>
                </Grid>
            </Border>

            <Border Grid.Row="1"
                    Background="{DynamicResource PanelBg}"
                    BorderBrush="{DynamicResource BorderBrushColor}"
                    BorderThickness="1"
                    CornerRadius="10"
                    Padding="10,8"
                    Margin="12,0,12,10">
                <TextBlock Text="Tip: puedes dejar esta ventana a un lado como widget informativo."
                           Foreground="{DynamicResource PanelFg}"
                           FontSize="10"
                           Opacity="0.9"/>
            </Border>

            <Border Grid.Row="2"
                    Margin="12,0,12,12"
                    Background="{DynamicResource ControlBg}"
                    BorderBrush="{DynamicResource BorderBrushColor}"
                    BorderThickness="1"
                    CornerRadius="10">
                <DataGrid Name="dgPrinters" IsReadOnly="True">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Nombre" Binding="{Binding Name}" Width="200"/>
                        <DataGridTextColumn Header="Puerto" Binding="{Binding PortName}" Width="150"/>
                        <DataGridTextColumn Header="Driver" Binding="{Binding DriverName}" Width="150"/>
                        <DataGridTextColumn Header="Compartida" Binding="{Binding IsShared}" Width="*"/>
                    </DataGrid.Columns>
                </DataGrid>
            </Border>
        </Grid>
    </Border>
</Window>
"@
  try {
    $ui = New-WpfWindow -Xaml $stringXaml -PassThru
    $w = $ui.Window
    $c = $ui.Controls
    Set-DzWpfThemeResources -Window $w -Theme $theme
    Set-WpfDialogOwner -Dialog $w

    $w.WindowStartupLocation = "Manual"
    $w.Add_Loaded({
        try {
          $owner = $w.Owner
          if (-not $owner) { return }

          $ob = $owner.RestoreBounds
          $targetW = $w.ActualWidth
          $targetH = $w.ActualHeight
          if ($targetW -le 0) { $targetW = $w.Width }
          if ($targetH -le 0) { $targetH = $w.Height }

          $left = $ob.Left + (($ob.Width - $targetW) / 2)
          $top = $ob.Top + (($ob.Height - $targetH) / 2)

          $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
          $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
          $wa = $screen.WorkingArea

          if ($left -lt $wa.Left) { $left = $wa.Left }
          if ($top -lt $wa.Top) { $top = $wa.Top }
          if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
          if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }

          $w.Left = [double]$left
          $w.Top = [double]$top
        } catch {}
      }.GetNewClosure())
    try {
      Set-WpfDialogOwner -Dialog $w
      $brdTitleBar = $c['brdTitleBar']
      if ($brdTitleBar) {
        $brdTitleBar.Add_MouseLeftButtonDown({
            param($sender, $e)
            if ($e.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
              try { $w.DragMove() } catch {}
            }
          }.GetNewClosure())
      }
      $btnClose = $c['btnClose']
      if ($btnClose) {
        $btnClose.Add_Click({
            $w.Close()
          }.GetNewClosure())
      }
      $w.Add_PreviewKeyDown({
          param($sender, $e)
          if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $w.Close()
          }
        }.GetNewClosure())
    } catch {}
    $c['dgPrinters'].ItemsSource = $uiItems
    $grid = $c['dgPrinters']
    if ($grid) {
      $menu = New-Object System.Windows.Controls.ContextMenu
      $menuItem = New-Object System.Windows.Controls.MenuItem
      $menuItem.Header = "📋 Copiar celda"
      $menuItem.Add_Click({
          try {
            $selectedCells = $grid.SelectedCells
            if ($selectedCells.Count -eq 0) {
              Write-Host "`n⚠️ No hay celda seleccionada" -ForegroundColor Yellow
              return
            }
            $cell = $selectedCells[0]
            $item = $cell.Item
            $column = $cell.Column
            $value = ""
            if ($column -is [System.Windows.Controls.DataGridBoundColumn]) {
              $binding = $column.Binding -as [System.Windows.Data.Binding]
              if ($binding -and $binding.Path) {
                $propertyName = $binding.Path.Path
                if ($item.PSObject.Properties[$propertyName]) {
                  $value = [string]$item.PSObject.Properties[$propertyName].Value
                }
              }
            }
            if ([string]::IsNullOrEmpty($value)) { $value = [string]$item }
            Set-ClipboardTextSafe -Text $value -Owner $w | Out-Null
            Write-Host "`n✅ Valor copiado al portapapeles: '$value'" -ForegroundColor Green
          } catch {
            Write-Host "`n❌ Error copiando celda: $($_.Exception.Message)" -ForegroundColor Red
            Write-DzDebug "`t[DEBUG][Show-NSPrinters] Error copiando celda: $($_.Exception.Message)"
          }
        }.GetNewClosure())
      [void]$menu.Items.Add($menuItem)
      $grid.ContextMenu = $menu
    }
    $w.Show() | Out-Null
  } catch {
    Write-Host "`n❌ ERROR creando ventana: $($_.Exception.Message)" -ForegroundColor Red
    Write-DzDebug "`t[DEBUG][Show-NSPrinters] ERROR creando ventana: $($_.Exception.Message)" Red
  }
}
function Show-InstallPrinterDialog {
  [CmdletBinding()]
  param()

  Write-DzDebug "`t[DEBUG][Show-InstallPrinterDialog] INICIO"
  $theme = Get-DzUiTheme
  $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Instalar impresora"
        Width="560" Height="260"
        MinWidth="560" MinHeight="260"
        MaxWidth="560" MaxHeight="260"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style x:Key="TextInputStyle" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="30"/>
    </Style>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0"
              Name="brdTitleBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="Instalar impresora"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Usaremos el driver 'Generic / Text Only'."
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2"
                  Name="btnClose"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <TextBlock Text="Tip: el nombre es como quieres verla en Windows; la IP es la del equipo/impresora."
                   Foreground="{DynamicResource PanelFg}"
                   FontSize="10"
                   Opacity="0.9"/>
      </Border>
      <Grid Grid.Row="2" Margin="12,0,12,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="90"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="90"/>
          <ColumnDefinition Width="160"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Row="0" Grid.Column="0" Text="Nombre" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}"/>
        <TextBox  Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="3" Name="txtPrinterName" Style="{StaticResource TextInputStyle}"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Text="IP" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}" Margin="0,10,0,0"/>
        <Grid Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="3" Margin="0,10,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="60"/>
            <ColumnDefinition Width="12"/>
            <ColumnDefinition Width="60"/>
            <ColumnDefinition Width="12"/>
            <ColumnDefinition Width="60"/>
            <ColumnDefinition Width="12"/>
            <ColumnDefinition Width="60"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <TextBox Name="ip1" Grid.Column="0" Style="{StaticResource TextInputStyle}" Padding="10,6" HorizontalContentAlignment="Center"/>
          <TextBlock Grid.Column="1" Text="." VerticalAlignment="Center" HorizontalAlignment="Center" Foreground="{DynamicResource AccentMuted}" FontSize="16"/>
          <TextBox Name="ip2" Grid.Column="2" Style="{StaticResource TextInputStyle}" Padding="10,6" HorizontalContentAlignment="Center"/>
          <TextBlock Grid.Column="3" Text="." VerticalAlignment="Center" HorizontalAlignment="Center" Foreground="{DynamicResource AccentMuted}" FontSize="16"/>
          <TextBox Name="ip3" Grid.Column="4" Style="{StaticResource TextInputStyle}" Padding="10,6" HorizontalContentAlignment="Center"/>
          <TextBlock Grid.Column="5" Text="." VerticalAlignment="Center" HorizontalAlignment="Center" Foreground="{DynamicResource AccentMuted}" FontSize="16"/>
          <TextBox Name="ip4" Grid.Column="6" Style="{StaticResource TextInputStyle}" Padding="10,6" HorizontalContentAlignment="Center"/>
          <TextBlock Grid.Column="7"
                     Text="Ej: 192.168.1.50"
                     VerticalAlignment="Center"
                     Foreground="{DynamicResource AccentMuted}"
                     Margin="12,0,0,0"/>
        </Grid>
      </Grid>
      <StackPanel Grid.Row="3"
                  Orientation="Horizontal"
                  HorizontalAlignment="Right"
                  Margin="12,0,12,12">
        <Button Name="btnInstall"
                Content="Instalar"
                Style="{StaticResource PrimaryButtonStyle}"
                Margin="0,0,10,0"/>
        <Button Name="btnCancel"
                Content="Cancelar"
                Style="{StaticResource SecondaryButtonStyle}"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@
  try {
    $ui = New-WpfWindow -Xaml $stringXaml -PassThru
    $w = $ui.Window
    $c = $ui.Controls
    Set-DzWpfThemeResources -Window $w -Theme $theme
    try { Set-WpfDialogOwner -Dialog $w } catch {}
    try {
      if (-not $w.Owner -and $global:MainWindow -is [System.Windows.Window]) {
        $w.Owner = $global:MainWindow
      }
    } catch {}
    $w.WindowStartupLocation = "Manual"
    $w.Add_Loaded({
        try {
          $owner = $w.Owner
          if (-not $owner) { return }
          $ob = $owner.RestoreBounds
          $targetW = $w.ActualWidth
          $targetH = $w.ActualHeight
          if ($targetW -le 0) { $targetW = $w.Width }
          if ($targetH -le 0) { $targetH = $w.Height }
          $left = $ob.Left + (($ob.Width - $targetW) / 2)
          $top = $ob.Top + (($ob.Height - $targetH) / 2)
          $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
          $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
          $wa = $screen.WorkingArea
          if ($left -lt $wa.Left) { $left = $wa.Left }
          if ($top -lt $wa.Top) { $top = $wa.Top }
          if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
          if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
          $w.Left = [double]$left
          $w.Top = [double]$top
        } catch {}
      }.GetNewClosure())
    $ipBoxes = @($c['ip1'], $c['ip2'], $c['ip3'], $c['ip4']) | Where-Object { $_ -ne $null }
    $GetIpText = {
      $vals = @('ip1', 'ip2', 'ip3', 'ip4') | ForEach-Object {
        $t = [string]$c[$_].Text
        if ([string]::IsNullOrWhiteSpace($t)) { return "" }
        return $t.Trim()
      }
      ($vals -join ".")
    }.GetNewClosure()
    $SetIpFromString = {
      param([string]$ip)
      $parts = $ip -split '\.'
      if ($parts.Count -ne 4) { return $false }
      for ($i = 0; $i -lt 4; $i++) {
        if ($parts[$i] -notmatch '^\d{1,3}$') { return $false }
        $n = [int]$parts[$i]
        if ($n -lt 0 -or $n -gt 255) { return $false }
      }
      $c['ip1'].Text = ([int]$parts[0]).ToString()
      $c['ip2'].Text = ([int]$parts[1]).ToString()
      $c['ip3'].Text = ([int]$parts[2]).ToString()
      $c['ip4'].Text = ([int]$parts[3]).ToString()
      $c['ip4'].Focus() | Out-Null
      $c['ip4'].SelectAll()
      $true
    }.GetNewClosure()
    $IsDigitText = {
      param([string]$text)
      ($text -match '^\d+$')
    }.GetNewClosure()
    $ClampOctet = {
      param($tb)
      $t = [string]$tb.Text
      if ([string]::IsNullOrWhiteSpace($t)) { return }
      if ($t -notmatch '^\d{1,3}$') { $tb.Text = ""; return }
      $n = [int]$t
      if ($n -gt 255) { $n = 255 }
      if ($n -lt 0) { $n = 0 }
      $tb.Text = $n.ToString()
    }.GetNewClosure()
    for ($i = 0; $i -lt $ipBoxes.Count; $i++) {
      $tb = $ipBoxes[$i]
      $next = if ($i -lt 3) { $ipBoxes[$i + 1] } else { $null }
      $prev = if ($i -gt 0) { $ipBoxes[$i - 1] } else { $null }
      $tb.MaxLength = 3
      $tb.AddHandler([System.Windows.UIElement]::PreviewTextInputEvent,
        [System.Windows.Input.TextCompositionEventHandler] {
          param($sender, $e)
          if ($e.Text -eq ".") {
            $e.Handled = $true
            if ($next) { $next.Focus() | Out-Null; $next.SelectAll() }
            return
          }
          if ($e.Text -notmatch '^\d+$') { $e.Handled = $true; return }
          $start = $sender.SelectionStart
          $selLen = $sender.SelectionLength
          $before = if ($start -gt 0) { $sender.Text.Substring(0, $start) } else { "" }
          $after = if (($start + $selLen) -lt $sender.Text.Length) { $sender.Text.Substring($start + $selLen) } else { "" }
          $newText = $before + $e.Text + $after
          if ($newText.Length -gt 3) { $e.Handled = $true; return }
          if ($newText.Length -eq 3 -and $next) {
            $sender.Dispatcher.BeginInvoke([action] {
                try { $next.Focus() | Out-Null; $next.SelectAll() } catch {}
              }) | Out-Null
          }
        }, $true)
      [System.Windows.Input.CommandManager]::AddPreviewExecutedHandler($tb, {
          param($sender, $e)
          try {
            if ($e.Command -ne [System.Windows.Input.ApplicationCommands]::Paste) { return }
            $e.Handled = $true
            $text = [System.Windows.Clipboard]::GetText()
            if ([string]::IsNullOrWhiteSpace($text)) { return }
            $text = $text.Trim()
            if ($text -match '^\d{1,3}(\.\d{1,3}){3}$') {
              [void](& $SetIpFromString $text)
              return
            }
            if ($text -notmatch '^\d+$') { return }
            if ($text.Length -gt 3) { return }
            $start = $sender.SelectionStart
            $new = ($sender.Text.Remove($start, $sender.SelectionLength)).Insert($start, $text)
            if ($new.Length -gt 3) { return }
            $sender.Text = $new
            $sender.SelectionStart = [Math]::Min($new.Length, $start + $text.Length)
          } catch { }
        }.GetNewClosure())
      $tb.AddHandler([System.Windows.Controls.TextBox]::TextChangedEvent,
        [System.Windows.Controls.TextChangedEventHandler] {
          param($sender, $e)
          if (-not $next) { return }
          if ($sender.Text.Length -lt 3) { return }
          $caretAtEnd = ($sender.CaretIndex -ge $sender.Text.Length)
          $allSelected = ($sender.SelectionLength -eq $sender.Text.Length)
          if ($caretAtEnd -or $allSelected) {
            try { $next.Focus() | Out-Null; $next.SelectAll() } catch {}
          }
        }, $true)
      $tb.AddHandler([System.Windows.UIElement]::LostFocusEvent,
        [System.Windows.RoutedEventHandler] {
          param($sender, $e)
          & $ClampOctet $sender
        }, $true)
      $tb.AddHandler([System.Windows.UIElement]::PreviewKeyDownEvent,
        [System.Windows.Input.KeyEventHandler] {
          param($sender, $e)
          if ($e.Key -in @([System.Windows.Input.Key]::OemPeriod,
              [System.Windows.Input.Key]::Decimal,
              [System.Windows.Input.Key]::OemComma)) {
            $e.Handled = $true
            if ($next) { $next.Focus() | Out-Null; $next.SelectAll() }
            return
          }
          if ($e.Key -eq [System.Windows.Input.Key]::Back) {
            if ($sender.SelectionStart -eq 0 -and $sender.SelectionLength -eq 0 -and [string]::IsNullOrEmpty($sender.Text) -and $prev) {
              $prev.Focus() | Out-Null
              $prev.SelectAll()
              $e.Handled = $true
              return
            }
          }
          if ($e.Key -eq [System.Windows.Input.Key]::Left) {
            if ($sender.SelectionStart -eq 0 -and $prev) {
              $prev.Focus() | Out-Null
              $prev.SelectAll()
              $e.Handled = $true
              return
            }
          }
          if ($e.Key -eq [System.Windows.Input.Key]::Right) {
            if ($sender.SelectionStart -ge $sender.Text.Length -and $next) {
              $next.Focus() | Out-Null
              $next.SelectAll()
              $e.Handled = $true
              return
            }
          }
        }, $true)
    }
    try { $c['ip1'].Focus() | Out-Null } catch {}
    $ensureDriverSb = {
      param([string]$DriverName = "Generic / Text Only")
      if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
        return @{ Ok = $true; DriverName = $DriverName; InstalledNow = $false; Message = "Driver ya estaba instalado." }
      }
      try {
        $inf = Join-Path $env:WINDIR "INF\ntprint.inf"
        if (-not (Test-Path -LiteralPath $inf -PathType Leaf)) {
          return @{ Ok = $false; DriverName = $DriverName; InstalledNow = $false; Message = "No se encontró ntprint.inf en: $inf" }
        }
        $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
        $args = "printui.dll,PrintUIEntry /ia /m `"$DriverName`" /f `"$inf`" /h `"$arch`" /v `"Type 3 - User Mode`""
        Write-DzDebug "`t[DEBUG][Show-InstallPrinterDialog] Instalando driver via rundll32: $DriverName ($arch)"
        $p = Start-Process -FilePath "rundll32.exe" -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
        if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
          return @{ Ok = $true; DriverName = $DriverName; InstalledNow = $true; Message = "Driver instalado correctamente." }
        }
        return @{ Ok = $false; DriverName = $DriverName; InstalledNow = $false; Message = "Se ejecutó la instalación, pero el driver no apareció. ExitCode: $($p.ExitCode)" }
      } catch {
        return @{ Ok = $false; DriverName = $DriverName; InstalledNow = $false; Message = "Error instalando driver: $($_.Exception.Message)" }
      }
    }.GetNewClosure()
    $c['btnInstall'].Add_Click({
        Write-DzDebug "`t[DEBUG][Show-InstallPrinterDialog] Clic en Instalar"
        $name = [string]$c['txtPrinterName'].Text
        $ip = (& $GetIpText).Trim()
        if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
          Show-WpfMessageBox -Message "Completa los 4 segmentos de la IP." -Title "IP incompleta" -Buttons OK -Icon Warning | Out-Null
          return
        }
        $parts = $ip -split '\.'
        foreach ($p in $parts) {
          $n = [int]$p
          if ($n -lt 0 -or $n -gt 255) {
            Show-WpfMessageBox -Message "La IP no es válida. Cada segmento debe estar entre 0 y 255." -Title "IP inválida" -Buttons OK -Icon Warning | Out-Null
            return
          }
        }
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($ip)) {
          Show-WpfMessageBox -Message "Ingresa el nombre de la impresora y la IP." -Title "Datos requeridos" -Buttons OK -Icon Warning | Out-Null
          return
        }
        if (-not (Test-Administrator)) {
          Show-WpfMessageBox -Message "Esta acción requiere permisos de administrador." -Title "Permisos requeridos" -Buttons OK -Icon Warning | Out-Null
          return
        }
        if (Get-Printer -Name $name -ErrorAction SilentlyContinue) {
          Show-WpfMessageBox -Message "Ya existe una impresora con el nombre '$name'." -Title "Nombre duplicado" -Buttons OK -Icon Warning | Out-Null
          return
        }
        $driverCheck = & $ensureDriverSb "Generic / Text Only"
        $driverName = $driverCheck.DriverName
        if (-not $driverCheck.Ok) {
          Show-WpfMessageBox -Message "No se pudo asegurar el driver '$driverName'.`n`n$($driverCheck.Message)" -Title "Driver no disponible" -Buttons OK -Icon Error | Out-Null
          return
        }
        if ($driverCheck.InstalledNow) {
          Show-WpfMessageBox -Message "Se instaló automáticamente el driver '$driverName'.`nContinuaremos con la instalación de la impresora." -Title "Driver instalado" -Buttons OK -Icon Information | Out-Null
        }
        $basePortName = "IP_$ip"
        $portName = $basePortName
        $suffix = 0
        while (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue) {
          $suffix++
          $portName = "${basePortName}_$suffix"
        }
        try {
          Add-PrinterPort -Name $portName -PrinterHostAddress $ip -ErrorAction Stop | Out-Null
        } catch {
          Show-WpfMessageBox -Message "No se pudo crear el puerto '$portName':`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
          return
        }
        try {
          Add-Printer -Name $name -DriverName $driverName -PortName $portName -ErrorAction Stop | Out-Null
          Show-WpfMessageBox -Message "Impresora instalada correctamente.`nPuerto: $portName" -Title "Éxito" -Buttons OK -Icon Information | Out-Null
          $w.Close()
        } catch {
          Show-WpfMessageBox -Message "No se pudo instalar la impresora:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
        }
      })
    $c['btnClose'].Add_Click({ $w.Close() })
    $c['btnCancel'].Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
  } catch {
    Write-DzDebug "`t[DEBUG][Show-InstallPrinterDialog] ERROR creando ventana: $($_.Exception.Message)" Red
    Show-WpfMessageBox -Message "No se pudo crear la ventana de impresoras." -Title "Error" -Buttons OK -Icon Error | Out-Null
  }
  Write-DzDebug "`t[DEBUG][Show-InstallPrinterDialog] FIN"
}
function Invoke-ClearPrintJobs {
  [CmdletBinding()]param([System.Windows.Controls.TextBlock]$InfoTextBlock)
  try {
    if (-not (Test-Administrator)) {
      Show-WpfMessageBox -Message "Esta acción requiere permisos de administrador.`nPor favor, ejecuta Gerardo Zermeño Tools como administrador." -Title "Permisos insuficientes" -Buttons "OK" -Icon "Warning" | Out-Null
      return $false
    }
    $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if (-not $spooler) {
      Show-WpfMessageBox -Message "No se encontró el servicio 'Cola de impresión (Spooler)' en este equipo." -Title "Servicio no encontrado" -Buttons "OK" -Icon "Error" | Out-Null
      return $false
    }
    if ($InfoTextBlock) { $InfoTextBlock.Text = "Limpiando trabajos de impresión..." }
    try {
      Get-Printer -ErrorAction Stop | ForEach-Object {
        try { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue }catch { Write-Host "`tNo se pudieron limpiar trabajos de '$($_.Name)': $($_.Exception.Message)" -ForegroundColor Yellow }
      }
    } catch {
      Write-Host "`tNo se pudieron enumerar impresoras (Get-Printer). ¿Está instalado el módulo PrintManagement?" -ForegroundColor Yellow
    }
    if ($spooler.Status -eq 'Running') {
      Write-Host "`tDeteniendo servicio Spooler..." -ForegroundColor DarkYellow
      Stop-Service -Name Spooler -Force -ErrorAction Stop
    } else {
      Write-Host "`tSpooler no está en 'Running' (estado actual: $($spooler.Status))." -ForegroundColor DarkYellow
    }
    $spooler.Refresh()
    if ($spooler.StartType -eq 'Disabled') {
      Show-WpfMessageBox -Message "El servicio 'Cola de impresión (Spooler)' está DESHABILITADO.`nHabilítalo manualmente desde services.msc para poder iniciarlo." -Title "Spooler deshabilitado" -Buttons "OK" -Icon "Warning" | Out-Null
      if ($InfoTextBlock) { $InfoTextBlock.Text = "Spooler deshabilitado." }
      return $false
    }
    Write-Host "`tIniciando servicio Spooler..." -ForegroundColor DarkYellow
    Start-Service -Name Spooler -ErrorAction Stop
    if ($InfoTextBlock) { $InfoTextBlock.Text = "Listo: cola de impresión reiniciada." }
    Show-WpfMessageBox -Message "Los trabajos de impresión han sido eliminados y el servicio de cola de impresión se reinició correctamente." -Title "Operación exitosa" -Buttons "OK" -Icon "Information" | Out-Null
    return $true
  } catch {
    $err = $_.Exception.Message
    Write-Host "`n[ERROR Invoke-ClearPrintJobs] $err" -ForegroundColor Red
    if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: $err" }
    Show-WpfMessageBox -Message "Ocurrió un error al intentar limpiar impresoras o reiniciar el servicio:`n$err" -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
    return $false
  }
}
function Show-AddUserDialog {
  Write-DzDebug "`t[DEBUG][Show-AddUserDialog] INICIO"
  $theme = Get-DzUiTheme
  $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Crear Usuario de Windows"
        Width="640" Height="420"
        MinWidth="640" MinHeight="420"
        MaxWidth="640" MaxHeight="420"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">

  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>

    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="130"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>

    <Style x:Key="TextInputStyle" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <Style x:Key="PasswordInputStyle" TargetType="PasswordBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="30"/>
    </Style>

    <Style x:Key="ToggleEyeStyle" TargetType="ToggleButton">
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="RadioStyle" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="Margin" Value="0,0,12,0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>

  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>

    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header -->
      <Border Grid.Row="0"
              Name="HeaderBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>

          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="Crear Usuario de Windows"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Crea un usuario local y asígnalo al grupo correspondiente."
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>

          <Button Grid.Column="2"
                  Name="btnClose"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>

      <!-- Form -->
      <Grid Grid.Row="1" Margin="12,0,12,10">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="170"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Nombre de usuario" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}" Margin="0,0,10,8"/>
        <TextBox Grid.Row="0" Grid.Column="1" Name="txtUsername" Style="{StaticResource TextInputStyle}" Margin="0,0,0,8"/>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="Contraseña" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}" Margin="0,0,10,8"/>
        <Grid Grid.Row="1" Grid.Column="1" Margin="0,0,0,8">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <PasswordBox Grid.Column="0" Name="pwdPassword" Style="{StaticResource PasswordInputStyle}"/>
          <TextBox Grid.Column="0" Name="txtPasswordVisible" Style="{StaticResource TextInputStyle}" Visibility="Collapsed"/>

          <ToggleButton Grid.Column="1"
                        Name="tglShowPassword"
                        Style="{StaticResource ToggleEyeStyle}"
                        Content="👁"
                        ToolTip="Mostrar/Ocultar contraseña"/>
        </Grid>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Tipo de usuario" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}"/>
        <StackPanel Grid.Row="2" Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <RadioButton Name="rbStandard" Content="Usuario estándar" IsChecked="True" Style="{StaticResource RadioStyle}"/>
          <RadioButton Name="rbAdmin" Content="Administrador" Foreground="{DynamicResource FormFg}" VerticalAlignment="Center"/>
        </StackPanel>

        <Button Grid.Row="2" Grid.Column="2"
                Name="btnShowUsers"
                Content="Ver usuarios"
                Style="{StaticResource SecondaryButtonStyle}"
                MinWidth="120"
                Margin="12,0,0,0"/>
      </Grid>

      <!-- Requirements -->
      <Border Grid.Row="2"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="12"
              Margin="12,0,12,10">
        <StackPanel>
          <TextBlock Text="Requisitos"
                     FontWeight="SemiBold"
                     Foreground="{DynamicResource PanelFg}"
                     Margin="0,0,0,8"/>
          <TextBlock Text="• Nombre: sin espacios (ej. soporte01)" Foreground="{DynamicResource PanelFg}" Margin="0,0,0,2"/>
          <TextBlock Text="• Contraseña: mínimo 8 caracteres" Foreground="{DynamicResource PanelFg}" Margin="0,0,0,2"/>
          <TextBlock Text="• Administrador: úsalo solo si es necesario" Foreground="{DynamicResource PanelFg}"/>
        </StackPanel>
      </Border>

      <!-- Footer -->
      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0"
                Background="{DynamicResource PanelBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="10,8"
                Margin="0,0,10,0">
          <TextBlock Name="lblStatus"
                     Text="Listo."
                     Foreground="{DynamicResource PanelFg}"
                     VerticalAlignment="Center"
                     TextWrapping="Wrap"/>
        </Border>

        <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
          <Button Name="btnCancel"
                  Content="Cancelar"
                  Style="{StaticResource SecondaryButtonStyle}"
                  Margin="0,0,10,0"
                  IsCancel="True"/>

          <Button Name="btnCreate"
                  Content="Crear usuario"
                  Style="{StaticResource PrimaryButtonStyle}"
                  IsEnabled="False"
                  IsDefault="True"/>
        </StackPanel>
      </Grid>

    </Grid>
  </Border>
</Window>
"@
  try { $ui = New-WpfWindow -Xaml $stringXaml -PassThru }catch { Write-DzDebug "`t[DEBUG][Show-AddUserDialog] ERROR creando ventana: $($_.Exception.Message)" Red; Show-WpfMessageBox -Message "No se pudo crear la ventana de usuario." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }
  $w = $ui.Window
  $c = $ui.Controls
  Set-DzWpfThemeResources -Window $w -Theme $theme
  try { Set-WpfDialogOwner -Dialog $w }catch {}
  try {
    if (-not $w.Owner -and $global:MainWindow -is [System.Windows.Window]) {
      $w.Owner = $global:MainWindow
    }
  } catch {}
  $w.WindowStartupLocation = "Manual"
  $w.Add_Loaded({
      try {
        $owner = $w.Owner
        if (-not $owner) { return }
        $ob = $owner.RestoreBounds
        $targetW = $w.ActualWidth
        $targetH = $w.ActualHeight
        if ($targetW -le 0) { $targetW = $w.Width }
        if ($targetH -le 0) { $targetH = $w.Height }
        $left = $ob.Left + (($ob.Width - $targetW) / 2)
        $top = $ob.Top + (($ob.Height - $targetH) / 2)
        $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
        $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
        $wa = $screen.WorkingArea
        if ($left -lt $wa.Left) { $left = $wa.Left }
        if ($top -lt $wa.Top) { $top = $wa.Top }
        if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
        if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
        $w.Left = [double]$left
        $w.Top = [double]$top
      } catch {}
    }.GetNewClosure())
  if (-not $w.Owner) { $w.WindowStartupLocation = "CenterScreen" }
  $script:__dlgResult = $false
  $c['btnClose'].Add_Click({ $w.DialogResult = $false; $w.Close() })
  $c['HeaderBar'].Add_MouseLeftButtonDown({ if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) { $w.DragMove() } })
  try { $adminGroup = (Get-LocalGroup | Where-Object SID -EQ 'S-1-5-32-544').Name; $userGroup = (Get-LocalGroup | Where-Object SID -EQ 'S-1-5-32-545').Name }catch { Show-WpfMessageBox -Message "No se pudieron obtener los grupos locales (requiere permisos).`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null; $w.Close(); return }
  $SetStatus = {
    param([string]$Text, [string]$Level = "Ok")
    switch ($Level) {
      "Ok" { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::ForestGreen }
      "Warn" { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::DarkGoldenrod }
      "Error" { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::Firebrick }
    }
    $c['lblStatus'].Text = $Text
  }.GetNewClosure()
  $GetPasswordText = {
    if ($c['txtPasswordVisible'].Visibility -eq 'Visible') {
      return [string]$c['txtPasswordVisible'].Text
    }
    return [string]$c['pwdPassword'].Password
  }.GetNewClosure()
  $WriteUsersTableConsoleSb = {
    param([Parameter(Mandatory)]$Rows)
    Write-Host ""
    Write-Host "Usuarios locales" -ForegroundColor Cyan
    $lines = @()
    $lines += ("{0,-28} {1,-14} {2,-14}" -f "Usuario", "Administrador", "Estado")
    $lines += ("{0,-28} {1,-14} {2,-14}" -f ("-" * 28), ("-" * 14), ("-" * 14))
    foreach ($r in $Rows) { $lines += ("{0,-28} {1,-14} {2,-14}" -f $r.Usuario, $r.Administrador, $r.Estado) }
    $lines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    Write-Host ""
  }.GetNewClosure()
  $getUsersRowsSb = {
    $adminGroupName = (Get-LocalGroup | Where-Object SID -eq 'S-1-5-32-544').Name
    $adminMembers = @{}
    try {
      Get-LocalGroupMember -Group $adminGroupName -ErrorAction Stop | ForEach-Object {
        $n = $_.Name
        if ($n -match '\\') { $n = ($n -split '\\')[-1] }
        $adminMembers[$n.ToLowerInvariant()] = $true
      }
    } catch {
      Write-DzDebug "`t[DEBUG][Show-UsersTableDialog] No se pudieron obtener miembros admin: $($_.Exception.Message)" Yellow
    }
    Get-LocalUser | Sort-Object Name | ForEach-Object {
      $uname = $_.Name
      $isAdmin = $false
      if ($adminMembers.Count -gt 0) { $isAdmin = $adminMembers.ContainsKey($uname.ToLowerInvariant()) }
      [pscustomobject]@{Usuario = $uname; Administrador = if ($isAdmin) { "Sí" }else { "No" }; Estado = if ($_.Enabled) { "Habilitado" }else { "Deshabilitado" } }
    }
  }.GetNewClosure()
  $ShowUsersTableDialogSb = {
    param([Parameter(Mandatory)][System.Windows.Window]$Owner, [Parameter(Mandatory)]$Rows, [Parameter(Mandatory)][scriptblock]$GetUsersRowsSb, [Parameter(Mandatory)][scriptblock]$WriteUsersTableConsoleSb)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Usuarios locales"
        Width="700" Height="500"
        MinWidth="650" MinHeight="430"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="CanResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">

  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>

    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>

    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header -->
      <Border Grid.Row="0"
              Name="HeaderBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>

          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="Usuarios locales"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Listado de usuarios del equipo (puedes copiar o eliminar)."
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>

          <Button Grid.Column="2"
                  Name="btnCloseX"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>

      <!-- Grid -->
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="8"
              Margin="12,0,12,10">
        <DataGrid Name="dgUsers"
                  AutoGenerateColumns="False"
                  CanUserAddRows="False"
                  CanUserDeleteRows="False"
                  IsReadOnly="True"
                  HeadersVisibility="Column"
                  GridLinesVisibility="None"
                  Background="{DynamicResource ControlBg}"
                  Foreground="{DynamicResource ControlFg}"
                  BorderBrush="{DynamicResource BorderBrushColor}"
                  BorderThickness="1"
                  RowHeight="28"
                  AlternationCount="2"
                  SelectionMode="Single">

          <DataGrid.ColumnHeaderStyle>
            <Style TargetType="{x:Type DataGridColumnHeader}">
              <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
              <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
              <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
              <Setter Property="BorderThickness" Value="0,0,0,1"/>
              <Setter Property="Padding" Value="10,6"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Style>
          </DataGrid.ColumnHeaderStyle>

          <DataGrid.RowStyle>
            <Style TargetType="{x:Type DataGridRow}">
              <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
              <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
              <Setter Property="BorderThickness" Value="0"/>
              <Style.Triggers>
                <Trigger Property="ItemsControl.AlternationIndex" Value="1">
                  <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                  <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
                  <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                </Trigger>
              </Style.Triggers>
            </Style>
          </DataGrid.RowStyle>

          <DataGrid.CellStyle>
            <Style TargetType="{x:Type DataGridCell}">
              <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
              <Setter Property="BorderThickness" Value="0,0,0,1"/>
              <Setter Property="Padding" Value="10,4"/>
            </Style>
          </DataGrid.CellStyle>

          <DataGrid.Columns>
            <DataGridTextColumn Header="Usuario" Binding="{Binding Usuario}" Width="*"/>
            <DataGridTextColumn Header="Administrador" Binding="{Binding Administrador}" Width="140"/>
            <DataGridTextColumn Header="Estado" Binding="{Binding Estado}" Width="150"/>
          </DataGrid.Columns>
        </DataGrid>
      </Border>

      <!-- Footer -->
      <Grid Grid.Row="2" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0"
                Background="{DynamicResource PanelBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="10,8"
                Margin="0,0,10,0">
          <TextBlock Name="lblFooter"
                     Text="Tip: selecciona un usuario para eliminar."
                     Foreground="{DynamicResource PanelFg}"
                     VerticalAlignment="Center"
                     TextWrapping="Wrap"/>
        </Border>

        <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
          <Button Name="btnDelete" Content="Eliminar" Style="{StaticResource SecondaryButtonStyle}" Margin="0,0,10,0"/>
          <Button Name="btnCopy" Content="Copiar" Style="{StaticResource SecondaryButtonStyle}" Margin="0,0,10,0"/>
          <Button Name="btnClose" Content="Cerrar" Style="{StaticResource PrimaryButtonStyle}"/>
        </StackPanel>
      </Grid>

    </Grid>
  </Border>
</Window>
"@
    $ui2 = New-WpfWindow -Xaml $xaml -PassThru
    $win = $ui2.Window
    $ctrl = $ui2.Controls
    $ctrl['btnCloseX'].Add_Click({ $win.Close() })
    $ctrl['btnClose'].Add_Click({ $win.Close() })
    $ctrl['HeaderBar'].Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) { $win.DragMove() }
      })
    $theme2 = Get-DzUiTheme
    Set-DzWpfThemeResources -Window $win -Theme $theme2
    if ($Owner) { $win.Owner = $Owner }
    $win.WindowStartupLocation = "Manual"
    $win.Add_Loaded({
        try {
          $owner = $win.Owner
          if (-not $owner) { return }
          $ob = $owner.RestoreBounds
          $targetW = $win.ActualWidth; if ($targetW -le 0) { $targetW = $win.Width }
          $targetH = $win.ActualHeight; if ($targetH -le 0) { $targetH = $win.Height }
          $left = $ob.Left + (($ob.Width - $targetW) / 2)
          $top = $ob.Top + (($ob.Height - $targetH) / 2)
          $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
          $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
          $wa = $screen.WorkingArea
          if ($left -lt $wa.Left) { $left = $wa.Left }
          if ($top -lt $wa.Top) { $top = $wa.Top }
          if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
          if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
          $win.Left = [double]$left
          $win.Top = [double]$top
        } catch {}
      }.GetNewClosure())
    if (-not $win.Owner) { $win.WindowStartupLocation = "CenterScreen" }
    $Rows = @($Rows)
    $ctrl['dgUsers'].ItemsSource = $Rows
    $refresh = {
      Write-DzDebug "`t[DEBUG][Show-UsersTableDialog] Refresh: obteniendo usuarios..."
      $newRows = @(& $GetUsersRowsSb)
      Write-DzDebug "`t[DEBUG][Show-UsersTableDialog] Refresh: rows=$($newRows.Count)"
      $Rows = $newRows
      $ctrl['dgUsers'].ItemsSource = $null
      $ctrl['dgUsers'].ItemsSource = $Rows
      & $WriteUsersTableConsoleSb -Rows $Rows
    }.GetNewClosure()
    $ctrl['btnCopy'].Add_Click({
        try {
          $tsv = ($Rows | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Usuario, $_.Administrador, $_.Estado }) -join "`r`n"
          [System.Windows.Clipboard]::SetText($tsv)
        } catch {}
      }.GetNewClosure())
    $ctrl['btnDelete'].Add_Click({
        try {
          $sel = $ctrl['dgUsers'].SelectedItem
          if (-not $sel -or [string]::IsNullOrWhiteSpace([string]$sel.Usuario)) { Show-WpfMessageBox -Message "Selecciona un usuario para eliminar." -Title "Aviso" -Buttons OK -Icon Warning -Owner $win | Out-Null; return }
          $u = [string]$sel.Usuario
          Write-DzDebug "`t[DEBUG][Show-UsersTableDialog] Solicitud eliminar usuario='$u'"
          if ($u.ToLowerInvariant() -in @("administrator", "administrador", "guest", "invitado", "defaultaccount", "wdagutilityaccount")) { Show-WpfMessageBox -Message "Este usuario está protegido y no se eliminará." -Title "Aviso" -Buttons OK -Icon Warning -Owner $win | Out-Null; return }
          $profile = $null
          try { $profile = (Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { $_.LocalPath -and ($_.LocalPath -match "\\Users\\$([regex]::Escape($u))$") } | Select-Object -First 1) }catch {}
          $profilePath = if ($profile -and $profile.LocalPath) { [string]$profile.LocalPath }else { "C:\Users\$u" }
          $warn = "Se eliminará el usuario:`n`n$u`n`nImportante:`nLa carpeta de perfil, si existe, normalmente está en:`n$profilePath`n`nLa eliminación del usuario no siempre borra esa carpeta."
          $c1 = Show-WpfMessageBoxSafe -Message $warn -Title "Confirmar eliminación" -Buttons YesNo -Icon Warning -Owner $win
          if ($c1 -ne [System.Windows.MessageBoxResult]::Yes) { return }
          $c2 = Show-WpfMessageBoxSafe -Message "¿Eliminar definitivamente el usuario '$u'?" -Title "Confirmación final" -Buttons YesNo -Icon Warning -Owner $win
          if ($c2 -ne [System.Windows.MessageBoxResult]::Yes) { return }
          Write-DzDebug "`t[DEBUG][Show-UsersTableDialog] Eliminando usuario='$u'..."
          try { Remove-LocalUser -Name $u -ErrorAction Stop }catch { Show-WpfMessageBox -Message "No se pudo eliminar el usuario:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error -Owner $win | Out-Null; return }
          Write-DzDebug "`t[DEBUG][Show-UsersTableDialog] Usuario eliminado OK usuario='$u'"
          Write-DzDebug "`t[DEBUG][Show-UsersTableDialog] Ejecutando refresh tras eliminar usuario='$u'..."
          & $refresh
          Write-DzDebug "`t[DEBUG][Show-UsersTableDialog] Refresh OK tras eliminar usuario='$u'"
        } catch {
          Show-WpfMessageBox -Message "Error al eliminar usuario:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error -Owner $win | Out-Null
        }
      }.GetNewClosure())
    $ctrl['btnClose'].Add_Click({ $win.Close() })
    $null = $win.ShowDialog()
  }.GetNewClosure()
  $ValidateForm = {
    $username = ([string]$c['txtUsername'].Text).Trim()
    $pass = (& $GetPasswordText).Trim()
    Write-DzDebug "`t[DEBUG][Show-AddUserDialog] Validate username='$username' passLen=$($pass.Length)"
    if ([string]::IsNullOrWhiteSpace($username)) { & $SetStatus "Escriba un nombre de usuario." "Warn"; $c['btnCreate'].IsEnabled = $false; return }
    if ($username -match "\s") { & $SetStatus "El nombre no debe contener espacios." "Warn"; $c['btnCreate'].IsEnabled = $false; return }
    if ([string]::IsNullOrWhiteSpace($pass)) { & $SetStatus "Escriba una contraseña." "Warn"; $c['btnCreate'].IsEnabled = $false; return }
    if ($pass.Length -lt 8) { & $SetStatus "La contraseña debe tener al menos 8 caracteres." "Warn"; $c['btnCreate'].IsEnabled = $false; return }
    try {
      $exists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
      if ($exists) { & $SetStatus "El usuario '$username' ya existe." "Error"; $c['btnCreate'].IsEnabled = $false; return }
    } catch {
      Write-DzDebug "`t[DEBUG][Show-AddUserDialog] Validate existencia falló: $($_.Exception.Message)" Yellow
      & $SetStatus "Aviso: no se pudo validar si el usuario ya existe (permisos)." "Warn"
    }
    & $SetStatus "Listo para crear usuario." "Ok"
    $c['btnCreate'].IsEnabled = $true
  }.GetNewClosure()
  $c['tglShowPassword'].Add_Checked({ Write-DzDebug "`t[DEBUG][Show-AddUserDialog] ShowPassword ON"; $c['txtPasswordVisible'].Text = [string]$c['pwdPassword'].Password; $c['pwdPassword'].Visibility = 'Collapsed'; $c['txtPasswordVisible'].Visibility = 'Visible'; & $ValidateForm }.GetNewClosure())
  $c['tglShowPassword'].Add_Unchecked({ Write-DzDebug "`t[DEBUG][Show-AddUserDialog] ShowPassword OFF"; $c['pwdPassword'].Password = [string]$c['txtPasswordVisible'].Text; $c['txtPasswordVisible'].Visibility = 'Collapsed'; $c['pwdPassword'].Visibility = 'Visible'; & $ValidateForm }.GetNewClosure())
  $c['txtUsername'].Add_TextChanged({ & $ValidateForm }.GetNewClosure())
  $c['pwdPassword'].Add_PasswordChanged({ & $ValidateForm }.GetNewClosure())
  $c['txtPasswordVisible'].Add_TextChanged({ Write-DzDebug "`t[DEBUG][Show-AddUserDialog] txtPasswordVisible changed"; & $ValidateForm }.GetNewClosure())
  $c['rbStandard'].Add_Checked({ Write-DzDebug "`t[DEBUG][Show-AddUserDialog] Tipo=Standard"; & $ValidateForm }.GetNewClosure())
  $c['rbAdmin'].Add_Checked({ Write-DzDebug "`t[DEBUG][Show-AddUserDialog] Tipo=Admin"; & $ValidateForm }.GetNewClosure())
  $c['btnShowUsers'].Add_Click({
      Write-DzDebug "`t[DEBUG][Show-AddUserDialog] btnShowUsers click (tabla)"
      try {
        Write-DzDebug "`t[DEBUG][Show-AddUserDialog] btnShowUsers: getUsersRowsSb=$([bool]$getUsersRowsSb)"
        $rows = @(& $getUsersRowsSb)
        Write-DzDebug "`t[DEBUG][Show-AddUserDialog] btnShowUsers: rows=$($rows.Count)"
        & $WriteUsersTableConsoleSb -Rows $rows
        & $ShowUsersTableDialogSb -Owner $w -Rows $rows -GetUsersRowsSb $getUsersRowsSb -WriteUsersTableConsoleSb $WriteUsersTableConsoleSb | Out-Null
        Write-DzDebug "`t[DEBUG][Show-AddUserDialog] Tabla de usuarios mostrada OK"
      } catch {
        Write-DzDebug "`t[DEBUG][Show-AddUserDialog] ERROR btnShowUsers: $($_.Exception.Message)" Red
        Show-WpfMessageBox -Message "No se pudieron listar usuarios:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
      }
    }.GetNewClosure())
  $c['btnCreate'].Add_Click({
      Write-DzDebug "`t[DEBUG][Show-AddUserDialog] btnCreate click"
      $username = ([string]$c['txtUsername'].Text).Trim()
      $password = & $GetPasswordText
      $isAdmin = $false; try { $isAdmin = [bool]$c['rbAdmin'].IsChecked }catch {}
      $tipo = if ($isAdmin) { "Administrador" }else { "Usuario estándar" }
      $group = if ($isAdmin) { $adminGroup }else { $userGroup }
      $confirmMsg = "Se creará el usuario:`n`n$username`n`nTipo: $tipo`nGrupo: $group"
      $conf = Show-WpfMessageBoxSafe -Message $confirmMsg -Title "Confirmar creación" -Buttons YesNo -Icon Warning -Owner $w
      if ($conf -ne [System.Windows.MessageBoxResult]::Yes) { Write-DzDebug "`t[DEBUG][Show-AddUserDialog] Creación cancelada"; return }
      try {
        if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) { & $SetStatus "El usuario '$username' ya existe." "Error"; Write-DzDebug "`t[DEBUG][Show-AddUserDialog] Ya existe: $username" Yellow; return }
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        New-LocalUser -Name $username -Password $securePassword -AccountNeverExpires -PasswordNeverExpires | Out-Null
        Add-LocalGroupMember -Group $group -Member $username
        Write-DzDebug "`t[DEBUG][Show-AddUserDialog] Usuario creado: $username Grupo: $group"
        Show-WpfMessageBox -Message "Usuario '$username' creado y agregado al grupo '$group'." -Title "Éxito" -Buttons OK -Icon Information | Out-Null
        $w.DialogResult = $true; $w.Close()
      } catch {
        Write-DzDebug "`t[DEBUG][Show-AddUserDialog] ERROR creando usuario: $($_.Exception.Message)" Red
        & $SetStatus "Error: $($_.Exception.Message)" "Error"
        Show-WpfMessageBox -Message "Error al crear usuario:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
      }
    }.GetNewClosure())
  $c['btnCancel'].Add_Click({ Write-DzDebug "`t[DEBUG][Show-AddUserDialog] btnCancel"; $w.DialogResult = $false; $w.Close() }.GetNewClosure())
  & $ValidateForm
  try { Write-DzDebug "`t[DEBUG][Show-AddUserDialog] ShowDialog()"; $w.ShowDialog() | Out-Null }catch { Write-DzDebug "`t[DEBUG][Show-AddUserDialog] ERROR ShowDialog: $($_.Exception.Message)" Red; throw }
  Write-DzDebug "`t[DEBUG][Show-AddUserDialog] FIN"
}
function Show-IPConfigDialog {
  Write-Host "`n- - - Comenzando el proceso - - -" -ForegroundColor Magenta
  $theme = Get-DzUiTheme

  function Test-IPv4 {
    param([string]$Ip)
    if ([string]::IsNullOrWhiteSpace($Ip)) { return $false }
    $Ip = $Ip.Trim()
    return [System.Net.IPAddress]::TryParse($Ip, [ref]([System.Net.IPAddress]$null)) -and ($Ip -match '^\d{1,3}(\.\d{1,3}){3}$')
  }

  function Get-AdapterIpsText {
    param([string]$Alias)
    try {
      $ips = Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress -and $_.IPAddress -notmatch '^169\.254\.' } |
      Select-Object -ExpandProperty IPAddress
      if ($ips) { return "IPs asignadas: " + ($ips -join ", ") }
    } catch {}
    return "IPs asignadas: -"
  }

  function Get-PrimaryIPv4 {
    param([string]$Alias)
    $all = @(Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress -and $_.IPAddress -notmatch '^169\.254\.' })
    if (-not $all -or $all.Count -eq 0) { return $null }

    $dhcp = $all | Where-Object { $_.PrefixOrigin -eq 'Dhcp' } | Select-Object -First 1
    if ($dhcp) { return $dhcp }

    $manual = $all | Where-Object { $_.PrefixOrigin -eq 'Manual' } | Select-Object -First 1
    if ($manual) { return $manual }

    return ($all | Select-Object -First 1)
  }

  function Get-Ipv4ConfigSnapshot {
    param([string]$Alias)
    $ip = Get-PrimaryIPv4 -Alias $Alias
    if (-not $ip) { return $null }

    $cfg = Get-NetIPConfiguration -InterfaceAlias $Alias -ErrorAction SilentlyContinue
    $gw = $null
    try { $gw = $cfg.IPv4DefaultGateway | Select-Object -ExpandProperty NextHop -ErrorAction SilentlyContinue } catch {}

    $dns = $null
    try { $dns = (Get-DnsClientServerAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses } catch {}

    [pscustomobject]@{
      IPAddress    = $ip.IPAddress
      PrefixLength = $ip.PrefixLength
      IsDhcp       = ($ip.PrefixOrigin -eq 'Dhcp')
      Gateway      = $gw
      DnsServers   = $dns
    }
  }

  function Convert-DhcpToStatic {
    param([string]$Alias)

    $snap = Get-Ipv4ConfigSnapshot -Alias $Alias
    if (-not $snap) { throw "No se pudo obtener configuración IPv4 del adaptador." }

    if (-not $snap.IsDhcp) { return $snap }

    Set-NetIPInterface -InterfaceAlias $Alias -Dhcp Disabled -ErrorAction Stop | Out-Null

    $existing = Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $snap.IPAddress -and $_.PrefixLength -eq $snap.PrefixLength }
    if (-not $existing) {
      New-NetIPAddress -InterfaceAlias $Alias -IPAddress $snap.IPAddress -PrefixLength $snap.PrefixLength -ErrorAction Stop | Out-Null
    }

    if ($snap.Gateway) {
      try {
        Remove-NetRoute -InterfaceAlias $Alias -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue -Confirm:$false | Out-Null
      } catch {}
      try {
        New-NetRoute -InterfaceAlias $Alias -AddressFamily IPv4 -NextHop $snap.Gateway -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Out-Null
      } catch {}
    }

    try {
      $dnsServers = @('8.8.8.8', '8.8.4.4') | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }
      Set-DnsClientServerAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ServerAddresses $dnsServers -ErrorAction Stop | Out-Null
    } catch {}

    return (Get-Ipv4ConfigSnapshot -Alias $Alias)
  }
  $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Asignación de IPs"
        Width="620" Height="280"
        MinWidth="620" MinHeight="280"
        MaxWidth="620" MaxHeight="280"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BaseButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="140"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
                <Setter Property="Cursor" Value="Arrow"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style x:Key="ComboStyle" TargetType="ComboBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,4"/>
      <Setter Property="Height" Value="30"/>
    </Style>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0"
              Name="HeaderBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="Asignación de IPs"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Selecciona un adaptador y aplica acciones (fija, adicional o DHCP)."
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2"
                  Name="btnClose"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <TextBlock Text="Tip: si el adaptador está en DHCP, al agregar IP adicional primero se convertirá a IP fija con la IP actual."
                   Foreground="{DynamicResource PanelFg}"
                   FontSize="10"
                   Opacity="0.9"
                   TextWrapping="Wrap"/>
      </Border>
      <Grid Grid.Row="2" Margin="12,0,12,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0"
                   Text="Adaptador de red"
                   Foreground="{DynamicResource FormFg}"
                   Margin="0,0,0,6"/>
        <ComboBox Grid.Row="1"
                  Name="cmbAdapters"
                  Style="{StaticResource ComboStyle}"
                  Margin="0,0,0,10"/>
        <Border Grid.Row="2"
                Background="{DynamicResource ControlBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="10">
          <TextBlock Name="lblIps"
                     Text="IPs asignadas: -"
                     Foreground="{DynamicResource AccentMuted}"
                     TextWrapping="Wrap"
                     VerticalAlignment="Top"/>
        </Border>
      </Grid>
      <StackPanel Grid.Row="3"
                  Orientation="Horizontal"
                  HorizontalAlignment="Right"
                  Margin="12,0,12,12">
        <Button Name="btnConvertStatic"
                Content="Convertir a IP fija"
                Style="{StaticResource SecondaryButtonStyle}"
                Margin="0,0,10,0"
                IsEnabled="False"/>
        <Button Name="btnAssignIp"
                Content="Agregar IP adicional"
                Style="{StaticResource PrimaryButtonStyle}"
                Margin="0,0,10,0"
                IsEnabled="False"/>
        <Button Name="btnDhcp"
                Content="Cambiar a DHCP"
                Style="{StaticResource SecondaryButtonStyle}"
                Margin="0,0,10,0"
                IsEnabled="False"/>
        <Button Name="btnCloseFooter"
                Content="Cerrar"
                Style="{StaticResource SecondaryButtonStyle}"
                IsCancel="True"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@


  $ui = New-WpfWindow -Xaml $stringXaml -PassThru
  $window = $ui.Window
  $c = $ui.Controls
  Set-DzWpfThemeResources -Window $window -Theme $theme
  Set-WpfDialogOwner -Dialog $window
  try {
    if (-not $window.Owner -and $global:MainWindow -is [System.Windows.Window]) {
      $window.Owner = $global:MainWindow
    }
  } catch {}

  $window.WindowStartupLocation = "Manual"
  $window.Add_Loaded({
      try {
        $owner = $window.Owner
        if (-not $owner) { return }

        $ob = $owner.RestoreBounds
        $targetW = $window.ActualWidth
        $targetH = $window.ActualHeight
        if ($targetW -le 0) { $targetW = $window.Width }
        if ($targetH -le 0) { $targetH = $window.Height }

        $left = $ob.Left + (($ob.Width - $targetW) / 2)
        $top = $ob.Top + (($ob.Height - $targetH) / 2)

        $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
        $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
        $wa = $screen.WorkingArea

        if ($left -lt $wa.Left) { $left = $wa.Left }
        if ($top -lt $wa.Top) { $top = $wa.Top }
        if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
        if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }

        $window.Left = [double]$left
        $window.Top = [double]$top
      } catch {}
    }.GetNewClosure())

  $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
  $c['cmbAdapters'].Items.Clear()
  $c['cmbAdapters'].Items.Add("Selecciona 1 adaptador de red") | Out-Null
  foreach ($a in $adapters) { $c['cmbAdapters'].Items.Add($a.Name) | Out-Null }
  $c['cmbAdapters'].SelectedIndex = 0

  $updateUi = {
    $sel = [string]$c['cmbAdapters'].SelectedItem
    $valid = ($sel -and $sel -ne "Selecciona 1 adaptador de red")
    $c['btnAssignIp'].IsEnabled = $valid
    $c['btnDhcp'].IsEnabled = $valid
    $c['btnConvertStatic'].IsEnabled = $valid
    if ($valid) { $c['lblIps'].Text = (Get-AdapterIpsText -Alias $sel) } else { $c['lblIps'].Text = "IPs asignadas: -" }
  }

  $c['cmbAdapters'].Add_SelectionChanged({ & $updateUi })
  & $updateUi

  $c['btnConvertStatic'].Add_Click({
      $alias = [string]$c['cmbAdapters'].SelectedItem
      if (-not $alias -or $alias -eq "Selecciona 1 adaptador de red") { Show-WpfMessageBox -Message "Por favor, selecciona un adaptador de red." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }

      $snap = Get-Ipv4ConfigSnapshot -Alias $alias
      if (-not $snap) { Show-WpfMessageBox -Message "No se pudo obtener la configuración IPv4 del adaptador." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }

      if (-not $snap.IsDhcp) { Show-WpfMessageBox -Message "El adaptador ya está en IP fija (Manual)." -Title "Información" -Buttons OK -Icon Information | Out-Null; return }

      $conf = Show-WpfMessageBox -Message "¿Desea convertir a IP fija usando la IP actual ($($snap.IPAddress))?" -Title "Confirmación" -Buttons YesNo -Icon Question
      if ($conf -ne [System.Windows.MessageBoxResult]::Yes) { return }

      try {
        Convert-DhcpToStatic -Alias $alias | Out-Null
        Show-WpfMessageBox -Message "Listo. Se convirtió a IP fija usando $($snap.IPAddress)." -Title "Éxito" -Buttons OK -Icon Information | Out-Null
        $c['lblIps'].Text = (Get-AdapterIpsText -Alias $alias)
      } catch {
        Show-WpfMessageBox -Message "Error al convertir a IP fija:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
      }
    })

  $c['btnAssignIp'].Add_Click({
      $alias = [string]$c['cmbAdapters'].SelectedItem
      if (-not $alias -or $alias -eq "Selecciona 1 adaptador de red") { Show-WpfMessageBox -Message "Por favor, selecciona un adaptador de red." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }

      $snap = Get-Ipv4ConfigSnapshot -Alias $alias
      if (-not $snap) { Show-WpfMessageBox -Message "No se pudo obtener la configuración IPv4 del adaptador." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }

      if ($snap.IsDhcp) {
        $conf = Show-WpfMessageBox -Message "El adaptador está en DHCP. Para agregar IP adicional se convertirá primero a IP fija usando la IP actual ($($snap.IPAddress)). ¿Continuar?" -Title "Confirmación" -Buttons YesNo -Icon Question
        if ($conf -ne [System.Windows.MessageBoxResult]::Yes) { return }
        try { $snap = Convert-DhcpToStatic -Alias $alias } catch {
          Show-WpfMessageBox -Message "Error al convertir a fija:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
          return
        }
      }

      $newIp = New-WpfInputDialog -Title "IP adicional" -Prompt "Ingrese la IP IPv4 adicional:" -DefaultValue ""
      if ([string]::IsNullOrWhiteSpace($newIp)) { return }
      if (-not (Test-IPv4 -Ip $newIp)) { Show-WpfMessageBox -Message "La IP '$newIp' no es válida." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }

      $newIp = $newIp.Trim()
      $exists = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $newIp }
      if ($exists) { Show-WpfMessageBox -Message "La IP $newIp ya está asignada a $alias." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }

      try {
        New-NetIPAddress -InterfaceAlias $alias -IPAddress $newIp -PrefixLength $snap.PrefixLength -ErrorAction Stop | Out-Null
        Show-WpfMessageBox -Message "Se agregó la IP adicional $newIp al adaptador $alias." -Title "Éxito" -Buttons OK -Icon Information | Out-Null
        $c['lblIps'].Text = (Get-AdapterIpsText -Alias $alias)
      } catch {
        Show-WpfMessageBox -Message "Error al agregar IP:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
      }
    })

  $c['btnDhcp'].Add_Click({
      $alias = [string]$c['cmbAdapters'].SelectedItem
      if (-not $alias -or $alias -eq "Selecciona 1 adaptador de red") { Show-WpfMessageBox -Message "Por favor, selecciona un adaptador de red." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }

      $conf = Show-WpfMessageBox -Message "¿Está seguro de que desea cambiar a DHCP? (Se eliminarán IPs Manual adicionales y se limpiará la puerta de enlace)" -Title "Confirmación" -Buttons YesNo -Icon Question
      if ($conf -ne [System.Windows.MessageBoxResult]::Yes) { return }

      try {
        $adapter = Get-NetAdapter -Name $alias -ErrorAction Stop
        $ifIndex = $adapter.ifIndex

        $manualIps = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -eq "Manual" }
        foreach ($ip in $manualIps) {
          Remove-NetIPAddress -InterfaceAlias $alias -IPAddress $ip.IPAddress -PrefixLength $ip.PrefixLength -Confirm:$false -ErrorAction SilentlyContinue
        }

        $routes = Get-NetRoute -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" -or $_.RouteMetric -ge 0 }
        foreach ($r in $routes) {
          Remove-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix $r.DestinationPrefix -NextHop $r.NextHop -Confirm:$false -ErrorAction SilentlyContinue
        }

        Set-NetIPInterface -InterfaceAlias $alias -Dhcp Enabled -ErrorAction Stop | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction SilentlyContinue | Out-Null

        ipconfig /renew $alias | Out-Null

        Show-WpfMessageBox -Message "Se cambió a DHCP y se limpió la puerta de enlace/rutas del adaptador $alias." -Title "Éxito" -Buttons OK -Icon Information | Out-Null
        $c['lblIps'].Text = "Generando IP por DHCP. Seleccione de nuevo."
      } catch {
        Show-WpfMessageBox -Message "Error al cambiar a DHCP:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
      }

    })

  $c['btnClose'].Add_Click({ $window.Close() })
  $c['btnCloseFooter'].Add_Click({ $window.Close() })
  $c['HeaderBar'].Add_MouseLeftButtonDown({
      if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) { $window.DragMove() }
    })

  $window.ShowDialog() | Out-Null
}
function Show-LZMADialog {
  param([array]$Instaladores)
  Write-DzDebug "`t[DEBUG][Show-LZMADialog] INICIO"
  $theme = Get-DzUiTheme
  $UiConfirm = { param([string]$m, [string]$t = "Confirmar")(Show-WpfMessageBoxSafe -Message $m -Title $t -Buttons "YesNo" -Icon "Question" -Owner $w) -eq [System.Windows.MessageBoxResult]::Yes }.GetNewClosure()
  function Convert-RegProviderPathToDisplay {
    param([Parameter(Mandatory)][string]$ProviderPath)
    $p = $ProviderPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    if ($p -like 'HKEY_LOCAL_MACHINE\*') { return ('HKLM:\' + $p.Substring('HKEY_LOCAL_MACHINE\'.Length)) }
    if ($p -like 'HKEY_CURRENT_USER\*') { return ('HKCU:\' + $p.Substring('HKEY_CURRENT_USER\'.Length)) }
    return $p
  }
  function Get-LzmaInstallerItems {
    $LZMAregistryPath = "HKLM:\SOFTWARE\WOW6432Node\Caphyon\Advanced Installer\LZMA"
    if (-not (Test-Path $LZMAregistryPath)) { return @() }
    $carpetasPrincipales = Get-ChildItem -Path $LZMAregistryPath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
    $tmp = @()
    foreach ($carpeta in $carpetasPrincipales) {
      $subdirs = Get-ChildItem -Path $carpeta.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
      foreach ($sd in $subdirs) {
        $tmp += [PSCustomObject]@{Name = [string]$sd.PSChildName; ProviderPath = [string]$sd.PSPath; DisplayPath = (Convert-RegProviderPathToDisplay -ProviderPath ([string]$sd.PSPath)) }
      }
    }
    $tmp | Sort-Object Name -Descending
  }
  if (-not $Instaladores -or $Instaladores.Count -eq 0) {
    $LZMAregistryPath = "HKLM:\SOFTWARE\WOW6432Node\Caphyon\Advanced Installer\LZMA"
    if (-not (Test-Path $LZMAregistryPath)) {
      Write-DzDebug "`t[DEBUG][Show-LZMADialog] No existe la clave LZMA: $LZMAregistryPath" Yellow
      Show-WpfMessageBox -Message "No se encontró Advanced Installer (LZMA) en este equipo.`n`nRuta no existe:`n$LZMAregistryPath" -Title "Sin instaladores" -Buttons OK -Icon Information | Out-Null
      Write-DzDebug "`t[DEBUG][Show-LZMADialog] Fin - sin clave LZMA"
      return
    }
    try {
      $carpetasPrincipales = Get-ChildItem -Path $LZMAregistryPath -ErrorAction Stop | Where-Object { $_.PSIsContainer }
      if (-not $carpetasPrincipales -or $carpetasPrincipales.Count -lt 1) {
        Write-DzDebug "`t[DEBUG][Show-LZMADialog] No se encontraron carpetas principales." Yellow
        Show-WpfMessageBox -Message "No se encontraron carpetas principales en la ruta del registro." -Title "Sin resultados" -Buttons OK -Icon Information | Out-Null
        return
      }
      $tmp = @()
      foreach ($carpeta in $carpetasPrincipales) {
        $subdirs = Get-ChildItem -Path $carpeta.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
        foreach ($sd in $subdirs) { $tmp += [PSCustomObject]@{Name = $sd.PSChildName; Path = $sd.PSPath } }
      }
      if (-not $tmp -or $tmp.Count -lt 1) {
        Write-DzDebug "`t[DEBUG][Show-LZMADialog] No se encontraron subcarpetas." Yellow
        Show-WpfMessageBox -Message "No se encontraron instaladores (subcarpetas) en la ruta del registro." -Title "Sin resultados" -Buttons OK -Icon Information | Out-Null
        return
      }
      $Instaladores = $tmp | Sort-Object Name -Descending
    } catch {
      Write-DzDebug "`t[DEBUG][Show-LZMADialog] Error accediendo al registro: $($_.Exception.Message)" Red
      Show-WpfMessageBox -Message "Error accediendo al registro:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error | Out-Null
      return
    }
  }
  $items = foreach ($i in $Instaladores) {
    if (-not $i) { continue }
    $provider = if ($null -ne $i.PSObject.Properties['ProviderPath']) { [string]$i.ProviderPath } else { [string]$i.Path }
    $displayPath = if ($null -ne $i.PSObject.Properties['DisplayPath'] -and -not [string]::IsNullOrWhiteSpace([string]$i.DisplayPath)) { [string]$i.DisplayPath } else { Convert-RegProviderPathToDisplay -ProviderPath $provider }
    [PSCustomObject]@{Name = [string]$i.Name; ProviderPath = $provider; DisplayPath = $displayPath; Display = ("{0}  |  {1}" -f [string]$i.Name, $displayPath) }
  }
  $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Carpetas LZMA"
        Width="760" Height="290"
        MinWidth="760" MinHeight="290"
        MaxWidth="760" MaxHeight="290"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style x:Key="ComboStyle" TargetType="ComboBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,4"/>
      <Setter Property="Height" Value="30"/>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Style.Triggers>
        <Trigger Property="IsHighlighted" Value="True">
          <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
          <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Opacity" Value="0.55"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>

    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0"
              Name="HeaderBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>

          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="Carpetas LZMA"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Seleccione el instalador (registro) que desea renombrar."
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>

          <Button Grid.Column="2"
                  Name="btnClose"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>

      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <TextBlock Text="Tip: si algo falla, puedes renombrar el registro para forzar que el instalador se regenere."
                   Foreground="{DynamicResource PanelFg}"
                   FontSize="10"
                   Opacity="0.9"/>
      </Border>

      <Grid Grid.Row="2" Margin="12,0,12,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <ComboBox Name="cmbInstallers"
                  Grid.Row="0"
                  Style="{StaticResource ComboStyle}"
                  Margin="0,0,0,10"
                  DisplayMemberPath="Display"
                  SelectedValuePath="ProviderPath"/>

        <Border Grid.Row="1"
                Background="{DynamicResource ControlBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="10">
          <StackPanel>
            <TextBlock Text="AI_ExePath:" Foreground="{DynamicResource FormFg}" Margin="0,0,0,4"/>
            <TextBlock Name="lblExePath"
                       Text="-"
                       Foreground="{DynamicResource AccentMuted}"
                       TextWrapping="Wrap"
                       TextTrimming="None"/>
          </StackPanel>
        </Border>
      </Grid>

      <StackPanel Grid.Row="3"
                  Orientation="Horizontal"
                  HorizontalAlignment="Right"
                  Margin="12,0,12,12">
        <Button Name="btnRename" Content="Renombrar" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,10,0" IsEnabled="False"/>
        <Button Name="btnExit" Content="Salir" Style="{StaticResource SecondaryButtonStyle}" IsCancel="True"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@
  try { $ui = New-WpfWindow -Xaml $stringXaml -PassThru } catch { Write-DzDebug "`t[DEBUG][Show-LZMADialog] ERROR creando ventana: $($_.Exception.Message)" Red; Show-WpfMessageBox -Message "No se pudo crear la ventana LZMA." -Title "Error" -Buttons OK -Icon Error | Out-Null; return }
  $w = $ui.Window
  $c = $ui.Controls
  Set-DzWpfThemeResources -Window $w -Theme $theme
  try { Set-WpfDialogOwner -Dialog $w } catch {}
  try { if (-not $w.Owner -and $global:MainWindow -is [System.Windows.Window]) { $w.Owner = $global:MainWindow } } catch {}
  $w.WindowStartupLocation = "Manual"
  $w.Add_Loaded({
      try {
        $owner = $w.Owner
        if (-not $owner) { $w.WindowStartupLocation = "CenterScreen"; return }
        $ob = $owner.RestoreBounds
        $targetW = $w.ActualWidth
        $targetH = $w.ActualHeight
        if ($targetW -le 0) { $targetW = $w.Width }
        if ($targetH -le 0) { $targetH = $w.Height }
        $left = $ob.Left + (($ob.Width - $targetW) / 2)
        $top = $ob.Top + (($ob.Height - $targetH) / 2)
        $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
        $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
        $wa = $screen.WorkingArea
        if ($left -lt $wa.Left) { $left = $wa.Left }
        if ($top -lt $wa.Top) { $top = $wa.Top }
        if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
        if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
        $w.Left = [double]$left
        $w.Top = [double]$top
      } catch {}
    }.GetNewClosure())
  $script:__dlgResult = $false
  $script:__allowClose = $false
  $w.Add_Closing({ param($sender, $e)if (-not $script:__allowClose) { $e.Cancel = $true } })
  $c['btnClose'].Add_Click({ $script:__dlgResult = $false; $script:__allowClose = $true; $w.Close() })
  $c['HeaderBar'].Add_MouseLeftButtonDown({ if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) { $w.DragMove() } })
  $placeholder = [PSCustomObject]@{Name = ""; ProviderPath = ""; Display = "Selecciona instalador a renombrar" }
  $c['cmbInstallers'].ItemsSource = @($placeholder) + @($items)
  $c['cmbInstallers'].SelectedIndex = 0
  $updateUi = {
    $idx = $c['cmbInstallers'].SelectedIndex
    $c['btnRename'].IsEnabled = ($idx -gt 0)
    if ($idx -le 0) { $c['lblExePath'].Text = "-"; return }
    $it = $c['cmbInstallers'].SelectedItem
    if (-not $it -or [string]::IsNullOrWhiteSpace($it.ProviderPath)) { $c['lblExePath'].Text = "No encontrado"; return }
    try {
      $prop = Get-ItemProperty -Path $it.ProviderPath -Name "AI_ExePath" -ErrorAction SilentlyContinue
      if ($prop -and $prop.AI_ExePath) { $c['lblExePath'].Text = [string]$prop.AI_ExePath } else { $c['lblExePath'].Text = "No encontrado" }
    } catch { $c['lblExePath'].Text = "Error leyendo AI_ExePath" }
  }
  $c['cmbInstallers'].Add_SelectionChanged({ & $updateUi })
  & $updateUi
  $c['btnRename'].Add_Click({
      $idx = $c['cmbInstallers'].SelectedIndex
      if ($idx -le 0) { return }
      $it = $c['cmbInstallers'].SelectedItem
      if (-not $it -or [string]::IsNullOrWhiteSpace($it.ProviderPath)) { return }
      $rutaVieja = [string]$it.ProviderPath
      $nombreViejo = [string]$it.Name
      $nuevoNombre = "$nombreViejo.backup"
      $msg = "¿Está seguro de renombrar el registro?`n`n$rutaVieja`n`nA:`n$nuevoNombre"
      $ok = & $UiConfirm $msg "Confirmar renombrado"
      if (-not $ok) { return }
      try {
        Rename-Item -Path $rutaVieja -NewName $nuevoNombre -ErrorAction Stop
        Show-WpfMessageBox -Message "Registro renombrado correctamente." -Title "Éxito" -Buttons OK -Icon Information -Owner $w | Out-Null
        $fresh = Get-LzmaInstallerItems
        $freshItems = foreach ($i in $fresh) { [PSCustomObject]@{Name = [string]$i.Name; ProviderPath = [string]$i.ProviderPath; DisplayPath = [string]$i.DisplayPath; Display = ("{0}  |  {1}" -f [string]$i.Name, [string]$i.DisplayPath) } }
        $placeholder2 = [PSCustomObject]@{Name = ""; ProviderPath = ""; Display = "Selecciona instalador a renombrar" }
        $c['cmbInstallers'].ItemsSource = @($placeholder2) + @($freshItems)
        $c['cmbInstallers'].SelectedIndex = 0
        & $updateUi
      } catch {
        Show-WpfMessageBox -Message "Error al renombrar:`n$($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error -Owner $w | Out-Null
      }
    })
  $c['btnExit'].Add_Click({ $script:__dlgResult = $false; $script:__allowClose = $true; $w.Close() })
  $null = $w.ShowDialog()
  Write-DzDebug "`t[DEBUG][Show-LZMADialog] FIN"
  return $script:__dlgResult
}
function Show-FirewallConfigDialog {
  Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] INICIO"
  if (-not (Test-Administrator)) {
    Show-WpfMessageBox -Message "Esta acción requiere permisos de administrador.`n`nPor favor, ejecuta Gerardo Zermeño Tools como administrador." -Title "Permisos requeridos" -Buttons OK -Icon Warning | Out-Null
    return
  }
  $theme = Get-DzUiTheme
  $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Configuraciones de Firewall"
        Width="760" Height="350"
        MinWidth="760" MinHeight="350"
        MaxWidth="760" MaxHeight="350"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="130"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style x:Key="TextInputStyle" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style x:Key="CheckStyle" TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="ListBoxStyle" TargetType="ListBox">
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="Padding" Value="6"/>
    </Style>
  </Window.Resources>

  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>

    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0"
              Name="HeaderBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>

          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="Configuraciones de Firewall"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Busca y agrega puertos al Firewall de Windows (reglas de entrada/salida)."
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>

          <Button Grid.Column="2"
                  Name="btnClose"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>

      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <TextBlock Text="Tip: escribe un puerto (1-65535) para buscar reglas existentes o crear nuevas reglas de Entrada/Salida."
                   Foreground="{DynamicResource PanelFg}"
                   FontSize="10"
                   Opacity="0.9"/>
      </Border>

      <Grid Grid.Row="2" Margin="12,0,12,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="12"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Row="0" Grid.Column="0"
                Background="{DynamicResource ControlBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="12">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <TextBlock Text="Buscar puerto"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       Margin="0,0,0,8"/>

            <Grid Grid.Row="1" Margin="0,0,0,8">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="90"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>

              <TextBlock Grid.Column="0" Text="Puerto" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}"/>
              <TextBox Grid.Column="1" Name="txtSearchPort" Style="{StaticResource TextInputStyle}" IsEnabled="False" Margin="0,0,10,0"/>
              <Button Grid.Column="2" Name="btnSearch" IsEnabled="False" Content="Buscar" Style="{StaticResource SecondaryButtonStyle}" MinWidth="110"/>
            </Grid>

            <ListBox Grid.Row="2" Name="lbResults" Style="{StaticResource ListBoxStyle}"/>
          </Grid>
        </Border>

        <Border Grid.Row="0" Grid.Column="2"
                Background="{DynamicResource ControlBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="12">
          <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <TextBlock Text="Agregar regla de puerto"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       Margin="0,0,0,8"/>

            <Grid Grid.Row="1" Margin="0,0,0,8">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="90"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>

              <TextBlock Grid.Column="0" Text="Puerto" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}"/>
              <TextBox Grid.Column="1" Name="txtAddPort" Style="{StaticResource TextInputStyle}"/>
            </Grid>

            <Grid Grid.Row="2" Margin="0,0,0,8">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="90"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>

              <TextBlock Grid.Column="0" Text="Nombre" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}"/>
              <TextBox Grid.Column="1" Name="txtRuleName" Style="{StaticResource TextInputStyle}" Text="Regla de puerto"/>
            </Grid>

            <Border Grid.Row="3"
                    Background="{DynamicResource PanelBg}"
                    BorderBrush="{DynamicResource BorderBrushColor}"
                    BorderThickness="1"
                    CornerRadius="10"
                    Padding="10">
              <StackPanel>
                <TextBlock Text="Dirección"
                           FontWeight="SemiBold"
                           Foreground="{DynamicResource PanelFg}"
                           Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal">
                  <CheckBox Name="chkInbound" Content="Entrada" Style="{StaticResource CheckStyle}" IsChecked="True"/>
                  <CheckBox Name="chkOutbound" Content="Salida" Style="{StaticResource CheckStyle}" IsChecked="True" Margin="0,0,0,0"/>
                </StackPanel>
              </StackPanel>
            </Border>
          </Grid>
        </Border>
      </Grid>

      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0"
                Background="{DynamicResource PanelBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="10,8"
                Margin="0,0,10,0">
          <TextBlock Name="lblStatus"
                     Text="Listo."
                     Foreground="{DynamicResource PanelFg}"
                     VerticalAlignment="Center"
                     TextWrapping="Wrap"/>
        </Border>

        <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
          <Button Name="btnAdd" Content="Agregar reglas" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,10,0"/>
          <Button Name="btnCloseFooter" Content="Cerrar" Style="{StaticResource SecondaryButtonStyle}"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
  try {
    $ui = New-WpfWindow -Xaml $stringXaml -PassThru
  } catch {
    Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] ERROR creando ventana: $($_.Exception.Message)" Red
    Show-WpfMessageBox -Message "No se pudo crear la ventana de firewall." -Title "Error" -Buttons OK -Icon Error | Out-Null
    return
  }
  $w = $ui.Window
  $c = $ui.Controls
  Set-DzWpfThemeResources -Window $w -Theme $theme
  try { Set-WpfDialogOwner -Dialog $w } catch {}
  try {
    if (-not $w.Owner -and $global:MainWindow -is [System.Windows.Window]) {
      $w.Owner = $global:MainWindow
    }
  } catch {}
  $w.WindowStartupLocation = "Manual"
  $w.Add_Loaded({
      try {
        $owner = $w.Owner
        if (-not $owner) { return }
        $ob = $owner.RestoreBounds
        $targetW = $w.ActualWidth
        $targetH = $w.ActualHeight
        if ($targetW -le 0) { $targetW = $w.Width }
        if ($targetH -le 0) { $targetH = $w.Height }
        $left = $ob.Left + (($ob.Width - $targetW) / 2)
        $top = $ob.Top + (($ob.Height - $targetH) / 2)
        $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
        $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
        $wa = $screen.WorkingArea
        if ($left -lt $wa.Left) { $left = $wa.Left }
        if ($top -lt $wa.Top) { $top = $wa.Top }
        if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
        if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
        $w.Left = [double]$left
        $w.Top = [double]$top
      } catch {}
    }.GetNewClosure())
  $SetStatus = {
    param([string]$Text, [string]$Level = "Ok")
    switch ($Level) {
      "Ok" { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::ForestGreen }
      "Warn" { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::DarkGoldenrod }
      "Error" { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::Firebrick }
    }
    $c['lblStatus'].Text = $Text
  }.GetNewClosure()
  $GetPortValue = {
    param([string]$Text)
    $trim = ([string]$Text).Trim()
    $val = 0
    if (-not [int]::TryParse($trim, [ref]$val)) { return $null }
    if ($val -lt 1 -or $val -gt 65535) { return $null }
    return $val
  }.GetNewClosure()
  $TestPortMatch = {
    param([string]$LocalPort, [int]$Port)
    if ([string]::IsNullOrWhiteSpace($LocalPort)) { return $false }
    if ($LocalPort -eq "Any") { return $true }
    foreach ($segment in ($LocalPort -split ',')) {
      $s = $segment.Trim()
      if ([string]::IsNullOrWhiteSpace($s)) { continue }
      if ($s -match '^\d+$') {
        if ([int]$s -eq $Port) { return $true }
      } elseif ($s -match '^(?<start>\d+)\s*-\s*(?<end>\d+)$') {
        $start = [int]$Matches.start
        $end = [int]$Matches.end
        if ($Port -ge $start -and $Port -le $end) { return $true }
      }
    }
    return $false
  }.GetNewClosure()
  $GetFirewallPortMatchesAsync = {
    param([int]$Port, [System.Windows.Window]$ProgressWindow, [scriptblock]$OnComplete)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions = "ReuseThread"
    $rs.Open()
    $rs.SessionStateProxy.SetVariable("Port", $Port)
    $rs.SessionStateProxy.SetVariable("ProgressWindow", $ProgressWindow)
    $rs.SessionStateProxy.SetVariable("OnComplete", $OnComplete)
    $rs.SessionStateProxy.SetVariable("TestPortMatchCode", $TestPortMatch)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        function Update-ProgressSafe {
          param($Window, $Percent, $Message)
          if (-not $Window -or $Window.IsClosed) { return }
          try {
            $Window.Dispatcher.Invoke([action] {
                if (-not $Window.IsClosed) {
                  if ($Window.ProgressBar) {
                    $Window.ProgressBar.IsIndeterminate = $false
                    $Window.ProgressBar.Value = $Percent
                  }
                  if ($Window.PercentLabel) { $Window.PercentLabel.Text = "$Percent%" }
                  if ($Window.MessageLabel -and $Message) { $Window.MessageLabel.Text = $Message }
                  $Window.UpdateLayout()
                }
              }, [System.Windows.Threading.DispatcherPriority]::Normal)
          } catch {}
        }
        try {
          Update-ProgressSafe -Window $ProgressWindow -Percent 5 -Message "Obteniendo reglas de Firewall..."
          Start-Sleep -Milliseconds 100
          $rules = Get-NetFirewallRule -ErrorAction Stop
          Update-ProgressSafe -Window $ProgressWindow -Percent 30 -Message "Filtrando puertos..."
          Start-Sleep -Milliseconds 100
          $filters = $rules | Get-NetFirewallPortFilter -ErrorAction Stop
          Update-ProgressSafe -Window $ProgressWindow -Percent 70 -Message "Procesando coincidencias..."
          Start-Sleep -Milliseconds 100
          $matches = @()
          $total = $filters.Count
          $current = 0
          $lastUpdate = [DateTime]::Now
          foreach ($f in $filters) {
            $current++
            $now = [DateTime]::Now
            if (($now - $lastUpdate).TotalMilliseconds -gt 200 -or $current -eq $total) {
              $percent = [Math]::Min(70 + [int](($current / $total) * 25), 95)
              Update-ProgressSafe -Window $ProgressWindow -Percent $percent -Message "Procesando $current de $total reglas..."
              $lastUpdate = $now
            }
            if ($f.Protocol -notin @('TCP', 'UDP')) { continue }
            $testResult = & $TestPortMatchCode -LocalPort $f.LocalPort -Port $Port
            if (-not $testResult) { continue }
            $r = $f.AssociatedNetFirewallRule
            if (-not $r) { continue }
            $matches += [pscustomobject]@{Direction = [string]$r.Direction; Name = [string]$r.DisplayName; Enabled = [string]$r.Enabled; Action = [string]$r.Action; Profile = [string]$r.Profile; Protocol = [string]$f.Protocol; LocalPort = [string]$f.LocalPort }
          }
          Update-ProgressSafe -Window $ProgressWindow -Percent 100 -Message "Listo."
          if ($OnComplete) { $ProgressWindow.Dispatcher.Invoke([action] { & $OnComplete $matches }, [System.Windows.Threading.DispatcherPriority]::Normal) }
        } catch {
          $errMsg = $_.Exception.Message
          if ($OnComplete) { $ProgressWindow.Dispatcher.Invoke([action] { & $OnComplete @{Error = $errMsg } }, [System.Windows.Threading.DispatcherPriority]::Normal) }
        }
      })
    $handle = $ps.BeginInvoke()
    return @{PowerShell = $ps; Runspace = $rs; Handle = $handle }
  }.GetNewClosure()
  $GetFirewallPortMatchesSync = {
    param([int]$Port)
    $oldPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
      $rules = Get-NetFirewallRule -ErrorAction Stop
      $filters = $rules | Get-NetFirewallPortFilter -ErrorAction Stop
    } finally { $ProgressPreference = $oldPref }
    $matches = @()
    foreach ($f in $filters) {
      if ($f.Protocol -notin @('TCP', 'UDP')) { continue }
      if (-not (& $TestPortMatch -LocalPort $f.LocalPort -Port $Port)) { continue }
      $r = $f.AssociatedNetFirewallRule
      if (-not $r) { continue }
      $matches += [pscustomobject]@{Direction = [string]$r.Direction; Name = [string]$r.DisplayName; Enabled = [string]$r.Enabled; Action = [string]$r.Action; Profile = [string]$r.Profile; Protocol = [string]$f.Protocol; LocalPort = [string]$f.LocalPort }
    }
    return $matches
  }.GetNewClosure()
  $RenderResults = {
    param([array]$Matches, [int]$Port)
    $c['lbResults'].Items.Clear()
    if (-not $Matches -or $Matches.Count -eq 0) {
      $c['lbResults'].Items.Add("No se encontraron reglas para el puerto $Port.") | Out-Null
      & $SetStatus "Sin coincidencias para el puerto $Port." "Warn"
      return
    }
    foreach ($m in $Matches) {
      $label = "{0} | {1} | {2} | {3} | {4} | Puertos: {5}" -f $m.Direction, $m.Action, $m.Profile, $m.Protocol, $m.Name, $m.LocalPort
      $c['lbResults'].Items.Add($label) | Out-Null
    }
    & $SetStatus "Se encontraron $($Matches.Count) regla(s) para el puerto $Port." "Ok"
  }.GetNewClosure()
  $c['btnClose'].Add_Click({ $w.Close() })
  $c['btnCloseFooter'].Add_Click({ $w.Close() })
  $c['HeaderBar'].Add_MouseLeftButtonDown({ if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) { $w.DragMove() } })
  $c['btnSearch'].Add_Click({
      Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] btnSearch click a las $([DateTime]::Now.ToString("o"))"
      $port = & $GetPortValue $c['txtSearchPort'].Text
      Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] Buscar puerto='$($c['txtSearchPort'].Text)' port=$port"
      if ($null -eq $port) { & $SetStatus "Ingresa un puerto válido (1-65535)." "Warn"; return }
      $pb = Show-WpfProgressBar -Title "Buscando reglas de Firewall" -Message "Iniciando..."
      if (-not $pb) { & $SetStatus "Error creando barra de progreso." "Error"; return }
      $c['btnSearch'].IsEnabled = $false
      $c['btnAdd'].IsEnabled = $false
      $onComplete = {
        param($result)
        try {
          if ($result -is [hashtable] -and $result.ContainsKey('Error')) {
            Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] Error buscando reglas: $($result.Error)" Red
            & $SetStatus "Error al buscar reglas: $($result.Error)" "Error"
          } else {
            $matches = $result
            Write-DzDebug "`t[DEBUG] Encontradas $($matches.Count) coincidencias para puerto $port"
            & $RenderResults $matches $port
          }
        } catch {
          Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] Error procesando resultados: $($_.Exception.Message)" Red
          & $SetStatus "Error procesando resultados: $($_.Exception.Message)" "Error"
        } finally {
          if ($pb) { Close-WpfProgressBar -Window $pb }
          $c['btnSearch'].IsEnabled = $true
          $c['btnAdd'].IsEnabled = $true
        }
      }.GetNewClosure()
      try { $job = & $GetFirewallPortMatchesAsync $port $pb $onComplete } catch {
        Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] Error iniciando búsqueda async: $($_.Exception.Message)" Red
        & $SetStatus "Error al iniciar búsqueda: $($_.Exception.Message)" "Error"
        if ($pb) { Close-WpfProgressBar -Window $pb }
        $c['btnSearch'].IsEnabled = $true
        $c['btnAdd'].IsEnabled = $true
      }
    }.GetNewClosure())
  $c['btnAdd'].Add_Click({
      Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] btnAdd click a las $([DateTime]::Now.ToString("o"))"
      $port = & $GetPortValue $c['txtAddPort'].Text
      if ($null -eq $port) { & $SetStatus "Ingresa un puerto válido (1-65535)." "Warn"; return }
      $directions = @()
      if ($c['chkInbound'].IsChecked) { $directions += "Inbound" }
      if ($c['chkOutbound'].IsChecked) { $directions += "Outbound" }
      if ($directions.Count -eq 0) { & $SetStatus "Selecciona al menos una dirección (Entrada/Salida)." "Warn"; return }
      $ruleName = $c['txtRuleName'].Text.Trim()
      if ([string]::IsNullOrWhiteSpace($ruleName)) { $ruleName = "Puerto $port" }
      try {
        $created = 0
        $createdRules = @()
        $errors = @()
        foreach ($dir in $directions) {
          $dirLabel = if ($dir -eq "Inbound") { "Entrada" } else { "Salida" }
          $finalRuleName = "$ruleName ($dirLabel)"
          $desc = "Regla creada para puerto $port ($dirLabel)."
          try {
            New-NetFirewallRule -DisplayName $finalRuleName -Direction $dir -Action Allow -Protocol TCP -LocalPort $port -Profile Any -Description $desc -ErrorAction Stop | Out-Null
            $created++
            $createdRules += $finalRuleName
            Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] Regla creada: $finalRuleName"
          } catch {
            if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*ya existe*") {
              Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] Ya existe regla $dir para puerto $port"
            } else {
              $errors += "Error en $dirLabel`: $($_.Exception.Message)"
              Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] Error creando regla $dir`: $($_.Exception.Message)" Red
            }
          }
        }
        if ($errors.Count -gt 0) {
          & $SetStatus "Errores al crear reglas: $($errors -join '; ')" "Error"
        } elseif ($created -gt 0) {
          & $SetStatus "Se agregaron $created regla(s) para el puerto $port." "Ok"
          $dirText = ($directions | ForEach-Object { if ($_ -eq "Inbound") { "Entrada" } else { "Salida" } }) -join " y "
          $msg = "Regla(s) agregada(s) exitosamente:`n`nNombre: $($createdRules -join ', ')`nPuerto: $port`nDirección: $dirText"
          $result = Show-WpfMessageBox -Message $msg -Title "Regla agregada" -Buttons "OK" -Icon "Information" -Owner $w
          if ($result -eq [System.Windows.MessageBoxResult]::OK) { $w.Close() }
        } else {
          & $SetStatus "No se crearon reglas nuevas: ya existen reglas con ese nombre." "Warn"
        }
      } catch {
        Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] Error agregando reglas: $($_.Exception.Message)" Red
        & $SetStatus "Error al agregar reglas: $($_.Exception.Message)" "Error"
      }
    }.GetNewClosure())
  try {
    Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] ShowDialog()"
    $w.ShowDialog() | Out-Null
  } catch {
    Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] ERROR ShowDialog: $($_.Exception.Message)" Red
    throw
  }
  Write-DzDebug "`t[DEBUG][Show-FirewallConfigDialog] FIN"
}
Export-ModuleMember -Function @('Show-SystemComponents', 'Start-SystemUpdate', 'show-NSPrinters', 'Invoke-ClearPrintJobs',
  'Show-AddUserDialog', 'Show-IPConfigDialog', 'Show-LZMADialog', 'Show-FirewallConfigDialog',
  'Show-InstallPrinterDialog')