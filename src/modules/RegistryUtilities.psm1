#requires -Version 5.0
#RegistryUtilities.psm1 - Utilidades basadas en el Registro de Windows (LZMA y corrección NVMe 4KB para SQL Server)

$script:RegistryUtilitiesModulePath = $PSCommandPath
$script:NvmeDefaultRegistryRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme'
$script:NvmeDefaultBackupRoot = 'C:\Temp\dztools\backups\nvme'
$script:NvmeValueName = 'ForcedPhysicalSectorSizeInBytes'

function Write-NvmeDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    if (Get-Command Write-DzDebug -ErrorAction SilentlyContinue) {
        Write-DzDebug -Message $Message -Color $Color
    }
}

function Test-NvmeAdminPrivilege {
    [CmdletBinding()]
    param()

    if (Get-Command Test-Administrator -ErrorAction SilentlyContinue) {
        return [bool](Test-Administrator)
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-RegExePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )

    $normalized = $RegistryPath.Trim()
    if ($normalized -match '^Microsoft\.PowerShell\.Core\\Registry::(.+)$') {
        $normalized = $Matches[1]
    }

    if ($normalized -match '^HKLM:\\(.*)$') { return ('HKLM\' + $Matches[1]) }
    if ($normalized -match '^HKCU:\\(.*)$') { return ('HKCU\' + $Matches[1]) }
    if ($normalized -match '^HKEY_LOCAL_MACHINE\\(.*)$') { return ('HKLM\' + $Matches[1]) }
    if ($normalized -match '^HKEY_CURRENT_USER\\(.*)$') { return ('HKCU\' + $Matches[1]) }
    if ($normalized -match '^HKLM\\(.*)$' -or $normalized -match '^HKCU\\(.*)$') { return $normalized }

    if ($normalized -match '^([^:]+):\\(.*)$') {
        $driveName = $Matches[1]
        $subPath = $Matches[2]
        $drive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
        if ($drive -and $drive.Provider.Name -eq 'Registry' -and -not [string]::IsNullOrWhiteSpace($drive.Root)) {
            $fullRoot = if ([string]::IsNullOrWhiteSpace($subPath)) { $drive.Root.TrimEnd('\') } else { "$($drive.Root.TrimEnd('\'))\$subPath" }
            if ($fullRoot -match '^HKEY_LOCAL_MACHINE\\(.*)$') { return ('HKLM\' + $Matches[1]) }
            if ($fullRoot -match '^HKEY_CURRENT_USER\\(.*)$') { return ('HKCU\' + $Matches[1]) }
            return $fullRoot
        }
    }

    return $normalized
}

function Invoke-Fsutil {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    try {
        $raw = & fsutil.exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $text = ($raw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        return [PSCustomObject]@{
            ExitCode = [int]$exitCode
            Output   = [string]$text
        }
    } catch {
        return [PSCustomObject]@{
            ExitCode = 1
            Output   = [string]$_.Exception.Message
        }
    }
}

function Invoke-RegExe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    try {
        $raw = & reg.exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $text = ($raw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        return [PSCustomObject]@{
            ExitCode = [int]$exitCode
            Output   = [string]$text
        }
    } catch {
        return [PSCustomObject]@{
            ExitCode = 1
            Output   = [string]$_.Exception.Message
        }
    }
}

function Write-NvmeAuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,
        [Parameter(Mandatory = $true)]
        [string]$BackupId,
        [string]$Result = 'Success',
        [string]$Details = '',
        [string]$BackupRoot = $script:NvmeDefaultBackupRoot
    )

    try {
        if (-not (Test-Path -LiteralPath $BackupRoot)) {
            New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null
        }
        $logPath = Join-Path $BackupRoot 'nvme_audit.log'
        $stamp = (Get-Date).ToString('o')
        $line = "{0} | Action={1} | BackupId={2} | User={3} | Computer={4} | Result={5} | Details={6}" -f `
            $stamp, $Action, $BackupId, $env:USERNAME, $env:COMPUTERNAME, $Result, $Details
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, $utf8NoBom)
        Write-NvmeDebug -Message "`t[DEBUG][NVMe Audit] $line" -Color DarkCyan
        if (Get-Command Write-DzAuditEvent -ErrorAction SilentlyContinue) {
            $evType = if ($Action -eq 'Restore') { 'REGISTRY_NVME_RESTORE' } else { 'REGISTRY_NVME_APPLY' }
            $st = if ($Result -eq 'Success') { 'OK' } else { 'ERROR' }
            Write-DzAuditEvent -EventType $evType -Target $BackupId -Status $st -Details @{
                action    = $Action
                backup_id = $BackupId
                result    = $Result
                details   = $Details
            }
        }
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][NVMe Audit] Error escribiendo log: $($_.Exception.Message)" -Color Yellow
    }
}

#region Sección A - Migración Carpetas LZMA

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
  try { Set-WpfDialogOwner -Dialog $w } catch { Write-Verbose $_.Exception.Message }
  try { if (-not $w.Owner -and $global:MainWindow -is [System.Windows.Window]) { $w.Owner = $global:MainWindow } } catch { Write-Verbose $_.Exception.Message }
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
      } catch { Write-Verbose $_.Exception.Message }
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

#endregion

#region Sección B - Motor de Análisis NVMe, fsutil, Registro y SQL ERRORLOG

<#
.SYNOPSIS
Obtiene versión, build y tipo de sistema operativo Windows (datos informativos).
#>
function Get-NvmeOsInfo {
    [CmdletBinding()]
    param()

    $caption = ''
    $version = ''
    $buildStr = ''
    $productType = 1
    $arch = ''

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
        if ($os) {
            $caption = [string]$os.Caption
            $version = [string]$os.Version
            $buildStr = [string]$os.BuildNumber
            if ($null -ne $os.ProductType) { $productType = [int]$os.ProductType }
            $arch = [string]$os.OSArchitecture
        }
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeOsInfo] Error CIM Win32_OperatingSystem: $($_.Exception.Message)" -Color Yellow
    }

    $displayVersion = ''
    $ubr = $null
    $productName = $caption
    try {
        $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        if ($cv) {
            if ([string]::IsNullOrWhiteSpace($buildStr) -and $cv.CurrentBuildNumber) {
                $buildStr = [string]$cv.CurrentBuildNumber
            }
            if ($cv.DisplayVersion) { $displayVersion = [string]$cv.DisplayVersion }
            elseif ($cv.ReleaseId) { $displayVersion = [string]$cv.ReleaseId }
            if ($null -ne $cv.UBR) { $ubr = [int]$cv.UBR }
            if ([string]::IsNullOrWhiteSpace($productName) -and $cv.ProductName) { $productName = [string]$cv.ProductName }
        }
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeOsInfo] Error leyendo CurrentVersion: $($_.Exception.Message)" -Color Yellow
    }

    $buildInt = 0
    [void][int]::TryParse($buildStr, [ref]$buildInt)

    return [PSCustomObject]@{
        Caption        = $caption
        ProductName    = $productName
        Version        = $version
        BuildNumber    = $buildInt
        DisplayVersion = $displayVersion
        UBR            = $ubr
        Architecture   = $arch
        ProductType    = $productType
        IsWindows11    = ($buildInt -ge 22000)
        IsServer       = ($productType -ne 1)
    }
}

function Resolve-NvmeDiskDriverService {
    [CmdletBinding()]
    param(
        [string]$DiskPnpDeviceId,
        [array]$Controllers
    )

    if (-not [string]::IsNullOrWhiteSpace($DiskPnpDeviceId) -and (Get-Command Get-PnpDeviceProperty -ErrorAction SilentlyContinue)) {
        try {
            $currentId = $DiskPnpDeviceId
            for ($depth = 0; $depth -lt 3; $depth++) {
                $parentProp = Get-PnpDeviceProperty -InstanceId $currentId -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue
                if (-not $parentProp -or [string]::IsNullOrWhiteSpace([string]$parentProp.Data)) {
                    break
                }
                $parentId = [string]$parentProp.Data
                $svcProp = Get-PnpDeviceProperty -InstanceId $parentId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue
                $svc = if ($svcProp -and $svcProp.Data) { ([string]$svcProp.Data).Trim() } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($svc) -and $svc -ine 'disk' -and $svc -ine 'partmgr') {
                    return [PSCustomObject]@{
                        DriverService   = $svc
                        ControllerId    = $parentId
                        DetectionSource = 'DEVPKEY_Device_Parent'
                    }
                }
                $currentId = $parentId
            }
        } catch {
            Write-NvmeDebug -Message "`t[DEBUG][Resolve-NvmeDiskDriverService] Error PnP property: $($_.Exception.Message)" -Color Yellow
        }
    }

    if ($Controllers -and $Controllers.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$Controllers[0].Service)) {
        return [PSCustomObject]@{
            DriverService   = [string]$Controllers[0].Service
            ControllerId    = [string]$Controllers[0].PNPDeviceID
            DetectionSource = 'SingleControllerFallback'
        }
    }

    return [PSCustomObject]@{
        DriverService   = ''
        ControllerId    = ''
        DetectionSource = 'Unknown'
    }
}

<#
.SYNOPSIS
Detecta discos NVMe, el controlador/servicio que los maneja y el estado del servicio stornvme.
#>
function Get-NvmeDiskInfo {
    [CmdletBinding()]
    param(
        [string]$ServiceRegistryPath = $script:NvmeDefaultRegistryRoot
    )

    $stornvmeKeyExists = Test-Path -LiteralPath $ServiceRegistryPath
    $stornvmeStart = $null
    if ($stornvmeKeyExists) {
        try {
            $svcProps = Get-ItemProperty -LiteralPath $ServiceRegistryPath -ErrorAction SilentlyContinue
            if ($null -ne $svcProps -and $null -ne $svcProps.PSObject.Properties['Start']) {
                $stornvmeStart = [int]$svcProps.Start
            }
        } catch {
            Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeDiskInfo] Error leyendo servicio stornvme: $($_.Exception.Message)" -Color Yellow
        }
    }

    $driverState = ''
    $driverStatus = ''
    $driverStartMode = ''
    try {
        $sysDrv = Get-CimInstance -ClassName Win32_SystemDriver -Filter "Name='stornvme'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sysDrv) {
            $driverState = [string]$sysDrv.State
            $driverStatus = [string]$sysDrv.Status
            $driverStartMode = [string]$sysDrv.StartMode
        }
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeDiskInfo] Error leyendo Win32_SystemDriver: $($_.Exception.Message)" -Color Yellow
    }

    $controllers = @()
    try {
        $scsiAdapters = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass='SCSIAdapter'" -ErrorAction SilentlyContinue)
        foreach ($adapter in $scsiAdapters) {
            $compat = @($adapter.CompatibleID) -join ' '
            $hw = @($adapter.HardwareID) -join ' '
            $svc = [string]$adapter.Service
            $name = [string]$adapter.Name
            $isNvmeCtrl = ($compat -match 'CC_0108') -or
                          ($hw -match 'CC_0108') -or
                          ($svc -match '^(stornvme|iaStor|secnvme|nvme)') -or
                          ($name -match 'NVM\s*Express|NVMe')
            if ($isNvmeCtrl) {
                $controllers += [PSCustomObject]@{
                    Name        = $name
                    Service     = $svc
                    PNPDeviceID = [string]$adapter.PNPDeviceID
                    IsStornvme  = ($svc -ieq 'stornvme')
                }
            }
        }
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeDiskInfo] Error listando controladores SCSIAdapter: $($_.Exception.Message)" -Color Yellow
    }

    $cimDrives = @()
    try {
        $cimDrives = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue)
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeDiskInfo] Error leyendo Win32_DiskDrive: $($_.Exception.Message)" -Color Yellow
    }

    $physicalDisks = @()
    if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        try {
            $physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        } catch {
            Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeDiskInfo] Error en Get-PhysicalDisk: $($_.Exception.Message)" -Color Yellow
        }
    }

    $nvmeDisks = @()
    $seenDeviceIds = @{}

    foreach ($pd in $physicalDisks) {
        $busTypeStr = [string]$pd.BusType
        $devId = [string]$pd.DeviceId
        $cimMatch = $cimDrives | Where-Object { [string]$_.Index -eq $devId } | Select-Object -First 1
        $pnpId = if ($cimMatch) { [string]$cimMatch.PNPDeviceID } else { '' }

        $isNvme = ($busTypeStr -ieq 'NVMe') -or ($pnpId -match 'NVME')
        if (-not $isNvme) { continue }

        $seenDeviceIds[$devId] = $true
        $drvInfo = Resolve-NvmeDiskDriverService -DiskPnpDeviceId $pnpId -Controllers $controllers
        $drvService = [string]$drvInfo.DriverService
        if ([string]::IsNullOrWhiteSpace($drvService) -and $busTypeStr -ieq 'NVMe' -and $driverState -ieq 'Running' -and (@($controllers | Where-Object { -not $_.IsStornvme }).Count -eq 0)) {
            $drvService = 'stornvme'
            $drvInfo.DetectionSource = 'SystemDriverFallback'
        }

        $isStornvme = ($drvService -ieq 'stornvme')
        $nvmeDisks += [PSCustomObject]@{
            DeviceId              = $devId
            FriendlyName          = [string]$pd.FriendlyName
            BusType               = $busTypeStr
            MediaType             = [string]$pd.MediaType
            PhysicalSectorSize    = if ($null -ne $pd.PhysicalSectorSize) { [long]$pd.PhysicalSectorSize } else { $null }
            LogicalSectorSize     = if ($null -ne $pd.LogicalSectorSize) { [long]$pd.LogicalSectorSize } else { $null }
            PNPDeviceID           = $pnpId
            DriverService         = $drvService
            DriverDetectionSource = [string]$drvInfo.DetectionSource
            ControllerId          = [string]$drvInfo.ControllerId
            IsStornvme            = $isStornvme
        }
    }

    foreach ($cd in $cimDrives) {
        $idxStr = [string]$cd.Index
        if ($seenDeviceIds.ContainsKey($idxStr)) { continue }
        $pnpId = [string]$cd.PNPDeviceID
        if ($pnpId -notmatch 'NVME') { continue }

        $drvInfo = Resolve-NvmeDiskDriverService -DiskPnpDeviceId $pnpId -Controllers $controllers
        $drvService = [string]$drvInfo.DriverService
        $isStornvme = ($drvService -ieq 'stornvme')

        $nvmeDisks += [PSCustomObject]@{
            DeviceId              = $idxStr
            FriendlyName          = [string]$cd.Model
            BusType               = 'NVMe'
            MediaType             = 'SSD'
            PhysicalSectorSize    = $null
            LogicalSectorSize     = if ($null -ne $cd.BytesPerSector) { [long]$cd.BytesPerSector } else { $null }
            PNPDeviceID           = $pnpId
            DriverService         = $drvService
            DriverDetectionSource = [string]$drvInfo.DetectionSource
            ControllerId          = [string]$drvInfo.ControllerId
            IsStornvme            = $isStornvme
        }
    }

    $hasNvme = ($nvmeDisks.Count -gt 0)
    $hasStornvme = (@($nvmeDisks | Where-Object { $_.IsStornvme }).Count -gt 0)
    $hasUnsupported = (@($nvmeDisks | Where-Object { -not [string]::IsNullOrWhiteSpace($_.DriverService) -and -not $_.IsStornvme }).Count -gt 0)
    $allUnsupported = ($hasNvme -and (-not $hasStornvme) -and $hasUnsupported)

    return [PSCustomObject]@{
        HasNvmeDisks               = $hasNvme
        HasStornvmeDisk            = $hasStornvme
        HasUnsupportedDriverDisk   = $hasUnsupported
        AllDisksUnsupportedDriver  = $allUnsupported
        Disks                      = @($nvmeDisks)
        Controllers                = @($controllers)
        StornvmeServiceExists      = $stornvmeKeyExists
        StornvmeStart              = $stornvmeStart
        StornvmeDriverState        = $driverState
        StornvmeDriverStatus       = $driverStatus
        StornvmeDriverStartMode    = $driverStartMode
    }
}

<#
.SYNOPSIS
Parser puro e independiente del idioma para la salida de fsutil fsinfo sectorinfo.
#>
function ConvertFrom-FsutilSectorInfo {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Output = '',
        [string]$DriveLetter = ''
    )

    $text = if ($null -eq $Output) { '' } else { [string]$Output }
    $requiresElevation = $false
    if ($text -match '(?i)(acceso denegado|access is denied|requires elevation|elevated|error\s*5\b)') {
        $requiresElevation = $true
    }

    $fields = [ordered]@{
        LogicalBytesPerSector                                = $null
        PhysicalBytesPerSectorForAtomicity                   = $null
        PhysicalBytesPerSectorForPerformance                 = $null
        FileSystemEffectivePhysicalBytesPerSectorForAtomicity = $null
    }

    foreach ($fieldName in @($fields.Keys)) {
        $pattern = "(?mi)^\s*$([regex]::Escape($fieldName))\s*:\s*([0-9][0-9 \t\u00A0.,]*)"
        $m = [regex]::Match($text, $pattern)
        if ($m.Success) {
            $digits = ($m.Groups[1].Value -replace '[^\d]', '')
            if (-not [string]::IsNullOrWhiteSpace($digits)) {
                $parsed = [long]0
                if ([long]::TryParse($digits, [ref]$parsed)) {
                    $fields[$fieldName] = $parsed
                }
            }
        }
    }

    $physicalValues = @()
    foreach ($pKey in @(
            'PhysicalBytesPerSectorForAtomicity',
            'PhysicalBytesPerSectorForPerformance',
            'FileSystemEffectivePhysicalBytesPerSectorForAtomicity'
        )) {
        if ($null -ne $fields[$pKey]) {
            $physicalValues += [long]$fields[$pKey]
        }
    }

    $maxPhysical = $null
    if ($physicalValues.Count -gt 0) {
        $maxPhysical = ($physicalValues | Measure-Object -Maximum).Maximum
    }

    $hasAnyParsed = ($null -ne $fields['LogicalBytesPerSector']) -or ($physicalValues.Count -gt 0)

    return [PSCustomObject]@{
        DriveLetter                                          = $DriveLetter
        Success                                              = ($hasAnyParsed -and (-not $requiresElevation))
        RequiresElevation                                    = $requiresElevation
        LogicalBytesPerSector                                = $fields['LogicalBytesPerSector']
        PhysicalBytesPerSectorForAtomicity                   = $fields['PhysicalBytesPerSectorForAtomicity']
        PhysicalBytesPerSectorForPerformance                 = $fields['PhysicalBytesPerSectorForPerformance']
        FileSystemEffectivePhysicalBytesPerSectorForAtomicity = $fields['FileSystemEffectivePhysicalBytesPerSectorForAtomicity']
        MaxPhysicalSectorSize                                = $maxPhysical
        RawOutput                                            = $text
    }
}

function Get-DriveToDiskMap {
    [CmdletBinding()]
    param()

    $map = @{}
    if ((Get-Command Get-Partition -ErrorAction SilentlyContinue) -and (Get-Command Get-Disk -ErrorAction SilentlyContinue)) {
        try {
            $allDisks = @{}
            foreach ($d in @(Get-Disk -ErrorAction SilentlyContinue)) {
                $allDisks[[string]$d.Number] = $d
            }
            foreach ($part in @(Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })) {
                $letter = ([string]$part.DriveLetter).TrimEnd(':').ToUpperInvariant()
                if ([string]::IsNullOrWhiteSpace($letter)) { continue }
                $disk = $allDisks[[string]$part.DiskNumber]
                if (-not $map.ContainsKey($letter)) {
                    $map[$letter] = @()
                }
                if ($disk) {
                    $map[$letter] += [PSCustomObject]@{
                        DiskNumber         = [string]$disk.Number
                        BusType            = [string]$disk.BusType
                        FriendlyName       = [string]$disk.FriendlyName
                        PhysicalSectorSize = if ($null -ne $disk.PhysicalSectorSize) { [long]$disk.PhysicalSectorSize } else { $null }
                        LogicalSectorSize  = if ($null -ne $disk.LogicalSectorSize) { [long]$disk.LogicalSectorSize } else { $null }
                    }
                }
            }
            if ($map.Count -gt 0) {
                return $map
            }
        } catch {
            Write-NvmeDebug -Message "`t[DEBUG][Get-DriveToDiskMap] Error Get-Partition/Get-Disk: $($_.Exception.Message)" -Color Yellow
        }
    }

    try {
        $ldToPart = @(Get-CimInstance -ClassName Win32_LogicalDiskToPartition -ErrorAction SilentlyContinue)
        $partToDisk = @(Get-CimInstance -ClassName Win32_DiskDriveToDiskPartition -ErrorAction SilentlyContinue)
        $drives = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue)
        foreach ($rel in $ldToPart) {
            $letter = ''
            if ($rel.Dependent -and $rel.Dependent.DeviceID) {
                $letter = ([string]$rel.Dependent.DeviceID).TrimEnd(':').ToUpperInvariant()
            }
            if ([string]::IsNullOrWhiteSpace($letter)) { continue }
            $partId = if ($rel.Antecedent) { [string]$rel.Antecedent.DeviceID } else { '' }
            $diskRel = $partToDisk | Where-Object { $_.Dependent -and ([string]$_.Dependent.DeviceID -eq $partId) } | Select-Object -First 1
            if ($diskRel -and $diskRel.Antecedent) {
                $diskDevId = [string]$diskRel.Antecedent.DeviceID
                $dd = $drives | Where-Object { [string]$_.DeviceID -eq $diskDevId } | Select-Object -First 1
                if ($dd) {
                    $isNvme = ([string]$dd.PNPDeviceID -match 'NVME')
                    if (-not $map.ContainsKey($letter)) { $map[$letter] = @() }
                    $map[$letter] += [PSCustomObject]@{
                        DiskNumber         = [string]$dd.Index
                        BusType            = if ($isNvme) { 'NVMe' } else { [string]$dd.InterfaceType }
                        FriendlyName       = [string]$dd.Model
                        PhysicalSectorSize = $null
                        LogicalSectorSize  = if ($null -ne $dd.BytesPerSector) { [long]$dd.BytesPerSector } else { $null }
                    }
                }
            }
        }
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][Get-DriveToDiskMap] Error fallback CIM: $($_.Exception.Message)" -Color Yellow
    }

    return $map
}

<#
.SYNOPSIS
Ejecuta fsutil fsinfo sectorinfo únicamente sobre volúmenes respaldados por discos NVMe.
#>
function Get-NvmeSectorDiagnostics {
    [CmdletBinding()]
    param(
        $DiskInfo
    )

    $fixedDrives = @()
    try {
        $fixedDrives = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction SilentlyContinue | Sort-Object DeviceID)
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeSectorDiagnostics] Error leyendo Win32_LogicalDisk: $($_.Exception.Message)" -Color Yellow
    }

    $driveToDisk = Get-DriveToDiskMap
    $diskById = @{}
    if ($DiskInfo -and $DiskInfo.Disks) {
        foreach ($nd in $DiskInfo.Disks) {
            $diskById[[string]$nd.DeviceId] = $nd
        }
    }

    $volumes = @()
    $skippedNonNvme = @()
    $requiresElevation = $false

    foreach ($ld in $fixedDrives) {
        $devId = [string]$ld.DeviceID
        if ([string]::IsNullOrWhiteSpace($devId)) { continue }
        $letter = $devId.TrimEnd(':').ToUpperInvariant()

        $underlying = if ($driveToDisk.ContainsKey($letter)) { @($driveToDisk[$letter]) } else { @() }
        $isNvmeVol = $false
        $matchedDiskNums = @()
        $driverService = ''
        $isStornvme = $false
        $fallbackPhysical = $null

        foreach ($ud in $underlying) {
            $dNum = [string]$ud.DiskNumber
            if ($ud.BusType -ieq 'NVMe' -or $diskById.ContainsKey($dNum)) {
                $isNvmeVol = $true
                $matchedDiskNums += $dNum
                if ($diskById.ContainsKey($dNum)) {
                    $nd = $diskById[$dNum]
                    if ([string]::IsNullOrWhiteSpace($driverService) -and -not [string]::IsNullOrWhiteSpace([string]$nd.DriverService)) {
                        $driverService = [string]$nd.DriverService
                    }
                    if ($nd.IsStornvme) { $isStornvme = $true }
                    if ($null -ne $nd.PhysicalSectorSize) {
                        $candSize = [long]$nd.PhysicalSectorSize
                        if ($null -eq $fallbackPhysical -or $candSize -gt $fallbackPhysical) {
                            $fallbackPhysical = $candSize
                        }
                    }
                } elseif ($null -ne $ud.PhysicalSectorSize) {
                    $candSize = [long]$ud.PhysicalSectorSize
                    if ($null -eq $fallbackPhysical -or $candSize -gt $fallbackPhysical) {
                        $fallbackPhysical = $candSize
                    }
                }
            }
        }

        if (-not $isNvmeVol) {
            $busLabel = if ($underlying.Count -gt 0) { ($underlying | ForEach-Object { $_.BusType }) -join ',' } else { 'Desconocido' }
            $skippedNonNvme += [PSCustomObject]@{
                DriveLetter = $letter
                DeviceID    = $devId
                BusType     = $busLabel
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($driverService) -and $DiskInfo -and $DiskInfo.HasStornvmeDisk -and (-not $DiskInfo.HasUnsupportedDriverDisk)) {
            $driverService = 'stornvme'
            $isStornvme = $true
        }

        $fsRes = Invoke-Fsutil -Arguments @('fsinfo', 'sectorinfo', "${letter}:")
        $parsed = ConvertFrom-FsutilSectorInfo -Output $fsRes.Output -DriveLetter $letter
        if ($parsed.RequiresElevation) {
            $requiresElevation = $true
        }

        $dataSource = if ($parsed.Success) { 'fsutil' } elseif ($null -ne $fallbackPhysical) { 'PhysicalDisk' } else { 'Unavailable' }
        $effectiveMax = if ($parsed.Success -and $null -ne $parsed.MaxPhysicalSectorSize) {
            [long]$parsed.MaxPhysicalSectorSize
        } elseif ($null -ne $fallbackPhysical) {
            [long]$fallbackPhysical
        } else {
            $null
        }

        $volumes += [PSCustomObject]@{
            DriveLetter                = $letter
            DeviceID                   = $devId
            VolumeName                 = [string]$ld.VolumeName
            IsNvmeVolume               = $true
            DiskNumbers                = @($matchedDiskNums)
            DriverService              = $driverService
            IsStornvme                 = $isStornvme
            Fsutil                     = $parsed
            FallbackPhysicalSectorSize = $fallbackPhysical
            EffectiveMaxPhysicalSector = $effectiveMax
            DataSource                 = $dataSource
            RequiresElevation          = [bool]$parsed.RequiresElevation
        }
    }

    return [PSCustomObject]@{
        Volumes               = @($volumes)
        SkippedNonNvmeDrives  = @($skippedNonNvme)
        RequiresElevation     = $requiresElevation
    }
}

<#
.SYNOPSIS
Inspecciona la clave HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device y su valor ForcedPhysicalSectorSizeInBytes.
#>
function Get-NvmeRegistryState {
    [CmdletBinding()]
    param(
        [string]$RootPath = $script:NvmeDefaultRegistryRoot
    )

    $parametersPath = Join-Path $RootPath 'Parameters'
    $devicePath = Join-Path $parametersPath 'Device'
    $valueName = $script:NvmeValueName

    $rootExists = Test-Path -LiteralPath $RootPath
    $parametersExists = Test-Path -LiteralPath $parametersPath
    $deviceExists = Test-Path -LiteralPath $devicePath

    $valueExists = $false
    $valueKind = $null
    $valueData = @()
    $has4095Rule = $false

    if ($deviceExists) {
        try {
            $regKey = Get-Item -LiteralPath $devicePath -ErrorAction Stop
            $names = @($regKey.GetValueNames())
            if ($names -contains $valueName) {
                $valueExists = $true
                $valueKind = $regKey.GetValueKind($valueName).ToString()
                $rawVal = $regKey.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($null -ne $rawVal) {
                    if ($rawVal -is [System.Array]) {
                        $valueData = @($rawVal | ForEach-Object { [string]$_ })
                    } else {
                        $valueData = @([string]$rawVal)
                    }
                }
                if ($valueKind -eq 'MultiString') {
                    $has4095Rule = (@($valueData | Where-Object { ([string]$_).Trim() -match '^\*\s*4095$' }).Count -gt 0)
                }
            }
        } catch {
            Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeRegistryState] Error leyendo clave '$devicePath': $($_.Exception.Message)" -Color Yellow
        }
    }

    $regExeDevicePath = ConvertTo-RegExePath -RegistryPath $devicePath
    $regQuery = Invoke-RegExe -Arguments @('query', $regExeDevicePath, '/v', $valueName)

    return [PSCustomObject]@{
        RootPath             = $RootPath
        ParametersPath       = $parametersPath
        DevicePath           = $devicePath
        TargetRegExePath     = $regExeDevicePath
        ValueName            = $valueName
        RootKeyExists        = $rootExists
        ParametersKeyExists  = $parametersExists
        DeviceKeyExists      = $deviceExists
        ValueExists          = $valueExists
        ValueKind            = $valueKind
        ValueData            = @($valueData)
        IsValueTypeValid     = ((-not $valueExists) -or ($valueKind -eq 'MultiString'))
        Has4095Rule          = $has4095Rule
        RegQueryExitCode     = [int]$regQuery.ExitCode
        RawRegQueryOutput    = [string]$regQuery.Output
    }
}

function Get-SqlErrorLogDirectories {
    [CmdletBinding()]
    param()

    $dirs = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    $addDir = {
        param([string]$Candidate)
        if ([string]::IsNullOrWhiteSpace($Candidate)) { return }
        $clean = $Candidate.Trim().Trim('"').TrimEnd('\')
        if ([string]::IsNullOrWhiteSpace($clean)) { return }
        $key = $clean.ToLowerInvariant()
        if (-not $seen.ContainsKey($key) -and (Test-Path -LiteralPath $clean -PathType Container)) {
            $seen[$key] = $true
            $dirs.Add($clean)
        }
    }

    $sqlRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server'
    )

    foreach ($sqlRoot in $sqlRoots) {
        $instKeyPath = Join-Path $sqlRoot 'Instance Names\SQL'
        if (-not (Test-Path -LiteralPath $instKeyPath)) { continue }
        try {
            $instKey = Get-Item -LiteralPath $instKeyPath -ErrorAction Stop
            foreach ($instName in @($instKey.GetValueNames())) {
                $instId = [string]$instKey.GetValue($instName)
                if ([string]::IsNullOrWhiteSpace($instId)) { continue }

                $paramsPath = Join-Path (Join-Path $sqlRoot $instId) 'MSSQLServer\Parameters'
                if (Test-Path -LiteralPath $paramsPath) {
                    try {
                        $paramKey = Get-Item -LiteralPath $paramsPath -ErrorAction Stop
                        foreach ($pName in @($paramKey.GetValueNames() | Where-Object { $_ -match '^SQLArg\d+$' })) {
                            $pVal = [string]$paramKey.GetValue($pName)
                            if ($pVal -cmatch '^-e(.+)$') {
                                $errFile = $Matches[1].Trim().Trim('"')
                                $parentDir = Split-Path -Path $errFile -Parent
                                & $addDir $parentDir
                            }
                        }
                    } catch {
                        Write-NvmeDebug -Message "`t[DEBUG][Get-SqlErrorLogDirectories] Error leyendo Parameters: $($_.Exception.Message)" -Color Yellow
                    }
                }

                $setupPath = Join-Path (Join-Path $sqlRoot $instId) 'Setup'
                if (Test-Path -LiteralPath $setupPath) {
                    $setupProps = Get-ItemProperty -LiteralPath $setupPath -ErrorAction SilentlyContinue
                    if ($setupProps) {
                        if ($setupProps.SQLDataRoot) { & $addDir (Join-Path ([string]$setupProps.SQLDataRoot) 'Log') }
                        if ($setupProps.SQLPath) { & $addDir (Join-Path ([string]$setupProps.SQLPath) 'Log') }
                    }
                }
            }
        } catch {
            Write-NvmeDebug -Message "`t[DEBUG][Get-SqlErrorLogDirectories] Error leyendo Instance Names: $($_.Exception.Message)" -Color Yellow
        }
    }

    foreach ($pfRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($pfRoot)) { continue }
        $sqlBase = Join-Path $pfRoot 'Microsoft SQL Server'
        if (-not (Test-Path -LiteralPath $sqlBase)) { continue }
        try {
            Get-ChildItem -LiteralPath $sqlBase -Directory -Filter 'MSSQL*' -ErrorAction SilentlyContinue | ForEach-Object {
                & $addDir (Join-Path $_.FullName 'MSSQL\Log')
            }
        } catch {
            Write-NvmeDebug -Message "`t[DEBUG][Get-SqlErrorLogDirectories] Error explorando '$sqlBase': $($_.Exception.Message)" -Color Yellow
        }
    }

    return @($dirs.ToArray())
}

function Read-SqlLogTailLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [int]$TailLines = 2000,
        [long]$MaxTailBytes = 2097152
    )

    $fs = $null
    $sr = $null
    try {
        $fs = [System.IO.FileStream]::new(
            $FilePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        if ($fs.Length -eq 0) {
            return @()
        }

        $bom = New-Object byte[] 4
        $readCount = $fs.Read($bom, 0, [Math]::Min(4, [int]$fs.Length))

        $encoding = [System.Text.Encoding]::UTF8
        $skipPartialLine = $false
        $startOffset = 0L

        if ($readCount -ge 2 -and $bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) {
            $encoding = [System.Text.Encoding]::Unicode
            $startOffset = 2L
        } elseif ($readCount -ge 2 -and $bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) {
            $encoding = [System.Text.Encoding]::BigEndianUnicode
            $startOffset = 2L
        } elseif ($readCount -ge 3 -and $bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) {
            $encoding = [System.Text.Encoding]::UTF8
            $startOffset = 3L
        } elseif ($readCount -ge 4 -and $bom[1] -eq 0 -and $bom[3] -eq 0) {
            $encoding = [System.Text.Encoding]::Unicode
            $startOffset = 0L
        }

        if ($fs.Length -gt ($MaxTailBytes + $startOffset)) {
            $seekPos = $fs.Length - $MaxTailBytes
            if ($encoding -eq [System.Text.Encoding]::Unicode -or $encoding -eq [System.Text.Encoding]::BigEndianUnicode) {
                if (($seekPos % 2) -ne 0) { $seekPos++ }
            }
            if ($seekPos -lt $startOffset) { $seekPos = $startOffset }
            $fs.Position = $seekPos
            $skipPartialLine = $true
        } else {
            $fs.Position = $startOffset
        }

        $sr = [System.IO.StreamReader]::new($fs, $encoding, $false, 4096, $true)
        if ($skipPartialLine) {
            $null = $sr.ReadLine()
        }

        $queue = New-Object System.Collections.Generic.Queue[string]
        while (-not $sr.EndOfStream) {
            $line = $sr.ReadLine()
            if ($null -eq $line) { break }
            $queue.Enqueue($line)
            if ($queue.Count -gt $TailLines) {
                $null = $queue.Dequeue()
            }
        }

        return @($queue.ToArray())
    } finally {
        if ($sr) { $sr.Dispose() }
        if ($fs) { $fs.Dispose() }
    }
}

<#
.SYNOPSIS
Busca en las últimas líneas de ERRORLOG y ERRORLOG.1 de SQL Server indicios de sectores > 4KB.
#>
function Find-SqlMisalignedIoErrors {
    [CmdletBinding()]
    param(
        [string[]]$LogDirectories,
        [int]$TailLines = 2000
    )

    $dirs = if ($PSBoundParameters.ContainsKey('LogDirectories')) {
        @($LogDirectories | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) })
    } else {
        Get-SqlErrorLogDirectories
    }

    $scannedFiles = @()
    $findings = @()

    foreach ($dir in $dirs) {
        foreach ($fileName in @('ERRORLOG', 'ERRORLOG.1')) {
            $fullPath = Join-Path $dir $fileName
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }

            $scannedFiles += $fullPath
            try {
                $lines = Read-SqlLogTailLines -FilePath $fullPath -TailLines $TailLines
                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }

                    $matchedType = $null
                    if ($line -match '(?i)misaligned\s+log\s+IO') {
                        $matchedType = 'MisalignedLogIO'
                    } elseif ($line -match '(?i)(Error:\s*(5178|5179)\b|\b(5178|5179)\b.*(sector|bytes|misaligned|synchronous|master\.mdf|IO))') {
                        $matchedType = 'SectorError5178_5179'
                    } elseif ($line -match '(?i)(EXCEPTION_STACK_OVERFLOW|c00000fd)') {
                        $matchedType = 'ExceptionStackOverflow'
                    }

                    if ($matchedType) {
                        $findings += [PSCustomObject]@{
                            FilePath  = $fullPath
                            MatchType = $matchedType
                            Line      = $line.Trim()
                        }
                    }
                }
            } catch {
                Write-NvmeDebug -Message "`t[DEBUG][Find-SqlMisalignedIoErrors] Error leyendo '$fullPath': $($_.Exception.Message)" -Color Yellow
            }
        }
    }

    $hasFindings = ($findings.Count -gt 0)
    $summary = if ($scannedFiles.Count -eq 0) {
        'No se encontraron archivos ERRORLOG de SQL Server.'
    } elseif ($hasFindings) {
        "Se encontraron $($findings.Count) coincidencia(s) en $($scannedFiles.Count) archivo(s)."
    } else {
        "Sin incidencias NVMe en $($scannedFiles.Count) archivo(s) ERRORLOG revisado(s)."
    }

    return [PSCustomObject]@{
        Scanned             = $true
        SearchedDirectories = @($dirs)
        ScannedFiles        = @($scannedFiles)
        Findings            = @($findings)
        HasFindings         = $hasFindings
        Summary             = $summary
    }
}

<#
.SYNOPSIS
Función pura de evaluación y dictamen de elegibilidad NVMe (independiente del número de build).
#>
function Test-NvmeSqlFixCandidate {
    [CmdletBinding()]
    param(
        $OsInfo,
        $DiskInfo,
        $SectorDiagnostics,
        $RegistryState,
        $SqlLogResult
    )

    $reasons = New-Object System.Collections.Generic.List[string]

    $has4095 = [bool]($RegistryState -and $RegistryState.Has4095Rule)
    $valueExists = [bool]($RegistryState -and $RegistryState.ValueExists)
    $valueTypeValid = if ($RegistryState) { [bool]$RegistryState.IsValueTypeValid } else { $true }

    $hasNvme = [bool]($DiskInfo -and $DiskInfo.HasNvmeDisks)
    $hasStornvme = [bool]($DiskInfo -and $DiskInfo.HasStornvmeDisk)
    $allUnsupportedDriver = [bool]($DiskInfo -and $DiskInfo.AllDisksUnsupportedDriver)
    $hasMixedDrivers = [bool]($DiskInfo -and $DiskInfo.HasStornvmeDisk -and $DiskInfo.HasUnsupportedDriverDisk)

    $nvmeVolumes = @()
    if ($SectorDiagnostics -and $SectorDiagnostics.Volumes) {
        $nvmeVolumes = @($SectorDiagnostics.Volumes | Where-Object { $_.IsNvmeVolume })
    }

    $stornvmeVolumes = @($nvmeVolumes | Where-Object {
        $_.IsStornvme -or [string]::IsNullOrWhiteSpace([string]$_.DriverService)
    })

    $oversizedVolumes = @()
    $evaluatedSectorCount = 0

    foreach ($vol in $stornvmeVolumes) {
        $isOver4K = $false
        $hasDataForVol = $false

        if ($vol.Fsutil -and $vol.Fsutil.Success) {
            $hasDataForVol = $true
            $evaluatedSectorCount++
            if (
                ($null -ne $vol.Fsutil.PhysicalBytesPerSectorForAtomicity -and [long]$vol.Fsutil.PhysicalBytesPerSectorForAtomicity -gt 4096) -or
                ($null -ne $vol.Fsutil.PhysicalBytesPerSectorForPerformance -and [long]$vol.Fsutil.PhysicalBytesPerSectorForPerformance -gt 4096) -or
                ($null -ne $vol.Fsutil.FileSystemEffectivePhysicalBytesPerSectorForAtomicity -and [long]$vol.Fsutil.FileSystemEffectivePhysicalBytesPerSectorForAtomicity -gt 4096)
            ) {
                $isOver4K = $true
            }
        } elseif ($null -ne $vol.FallbackPhysicalSectorSize) {
            $hasDataForVol = $true
            $evaluatedSectorCount++
            if ([long]$vol.FallbackPhysicalSectorSize -gt 4096) {
                $isOver4K = $true
            }
        }

        if ($hasDataForVol -and $isOver4K) {
            $oversizedVolumes += $vol
        }
    }

    # Si no hubo volúmenes con letra asignada pero el disco físico stornvme reporta > 4096
    $oversizedDisksWithoutVol = @()
    if ($DiskInfo -and $DiskInfo.Disks -and $stornvmeVolumes.Count -eq 0) {
        foreach ($d in @($DiskInfo.Disks | Where-Object { ($_.IsStornvme -or ([string]::IsNullOrWhiteSpace([string]$_.DriverService) -and (-not $DiskInfo.HasUnsupportedDriverDisk))) -and $null -ne $_.PhysicalSectorSize })) {
            $evaluatedSectorCount++
            if ([long]$d.PhysicalSectorSize -gt 4096) {
                $oversizedDisksWithoutVol += $d
            }
        }
    }

    $hasSectorOver4K = ($oversizedVolumes.Count -gt 0) -or ($oversizedDisksWithoutVol.Count -gt 0)
    $hasAnySectorData = ($evaluatedSectorCount -gt 0)
    $allNvmeSectorsLe4K = ($hasAnySectorData -and (-not $hasSectorOver4K))

    $hasSqlFindings = [bool]($SqlLogResult -and $SqlLogResult.HasFindings)
    $requiresElevation = [bool]($SectorDiagnostics -and $SectorDiagnostics.RequiresElevation)

    if ($OsInfo) {
        $buildLabel = if ($OsInfo.BuildNumber -gt 0) { "Build $($OsInfo.BuildNumber)" } else { 'Build desconocido' }
        $reasons.Add("Sistema operativo (informativo): $($OsInfo.ProductName) ($buildLabel).")
    }

    $status = 'NotCandidate'
    $canApplyByDefault = $false
    $requiresReboot = $false

    if (-not $hasNvme) {
        $status = 'NotCandidate'
        $reasons.Add('No se detectaron discos NVMe en el equipo.')
        if ($has4095) {
            $reasons.Add('La regla ForcedPhysicalSectorSizeInBytes (* 4095) está presente en el Registro aunque no hay discos NVMe.')
        }
    } elseif ($allUnsupportedDriver) {
        $status = 'UnsupportedDriver'
        $drivers = (@($DiskInfo.Disks | ForEach-Object { $_.DriverService } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) -join ', '
        $reasons.Add("Los discos NVMe detectados utilizan el driver '$drivers' en lugar de 'stornvme'.")
        $reasons.Add('ForcedPhysicalSectorSizeInBytes solo aplica al driver inbox de Microsoft (stornvme); escribir esta clave no tendrá efecto con el driver actual.')
    } elseif ($has4095) {
        if ($hasSectorOver4K) {
            $status = 'AlreadyAppliedPendingReboot'
            $requiresReboot = $true
            $volNames = (@($oversizedVolumes | ForEach-Object { "$($_.DeviceID) ($($_.EffectiveMaxPhysicalSector) bytes)" })) -join ', '
            $reasons.Add('El valor ForcedPhysicalSectorSizeInBytes ya contiene "* 4095" con tipo REG_MULTI_SZ válido.')
            $reasons.Add("Los volúmenes NVMe aún reportan sector físico > 4096 bytes ($volNames). Es necesario reiniciar Windows para que stornvme aplique el cambio.")
        } elseif ($allNvmeSectorsLe4K) {
            $status = 'AlreadyFixed'
            $reasons.Add('El valor ForcedPhysicalSectorSizeInBytes (* 4095) está aplicado en el Registro y todos los volúmenes NVMe reportan <= 4096 bytes.')
            if ($requiresElevation) {
                $reasons.Add('Nota: la verificación se apoyó en Get-PhysicalDisk porque fsutil requiere permisos de Administrador.')
            }
        } else {
            $status = 'AlreadyAppliedPendingReboot'
            $requiresReboot = $true
            $reasons.Add('El valor ForcedPhysicalSectorSizeInBytes (* 4095) ya existe en el Registro, pero no se pudo confirmar el tamaño efectivo del sector.')
        }
    } elseif ($hasStornvme -or (-not $DiskInfo.HasUnsupportedDriverDisk)) {
        if ($hasSectorOver4K) {
            $status = 'Candidate'
            $canApplyByDefault = $true
            if ($oversizedVolumes.Count -gt 0) {
                $volDesc = (@($oversizedVolumes | ForEach-Object { "$($_.DeviceID) ($($_.EffectiveMaxPhysicalSector) bytes via $($_.DataSource))" })) -join ', '
                $reasons.Add("Se detectó tamaño de sector físico > 4096 bytes en volumen NVMe bajo stornvme: $volDesc.")
            }
            if ($oversizedDisksWithoutVol.Count -gt 0) {
                $diskDesc = (@($oversizedDisksWithoutVol | ForEach-Object { "$($_.FriendlyName) ($($_.PhysicalSectorSize) bytes)" })) -join ', '
                $reasons.Add("Se detectó disco físico NVMe sin letra montada con sector > 4096 bytes: $diskDesc.")
            }
            if ($valueExists -and (-not $valueTypeValid)) {
                $reasons.Add("El valor existente en Registro tiene tipo incorrecto ($($RegistryState.ValueKind)); debe reemplazarse por REG_MULTI_SZ (* 4095).")
            } else {
                $reasons.Add('No existe la regla "* 4095" en stornvme\Parameters\Device.')
            }
            if ($hasSqlFindings) {
                $reasons.Add("Confirmado en SQL ERRORLOG: $($SqlLogResult.Summary)")
            }
        } else {
            $status = 'NotCandidate'
            if ($allNvmeSectorsLe4K) {
                $reasons.Add('Todos los volúmenes NVMe bajo stornvme reportan sectores físicos <= 4096 bytes.')
            } else {
                $reasons.Add('No hay lecturas de sector > 4096 bytes disponibles para volúmenes NVMe.')
            }
            if ($valueExists -and (-not $valueTypeValid)) {
                $reasons.Add("Nota: existe ForcedPhysicalSectorSizeInBytes con tipo incorrecto ($($RegistryState.ValueKind)) en lugar de MultiString.")
            }
            if ($hasSqlFindings) {
                $reasons.Add("Atención: SQL ERRORLOG contiene incidencias ($($SqlLogResult.Summary)), pero los sectores NVMe medidos son <= 4096 bytes (posible VM, SAN u otra causa). No se habilita automáticamente; usa Modo avanzado solo si corresponde.")
            }
        }
    }

    if ($hasMixedDrivers) {
        $otherDrvs = (@($DiskInfo.Disks | Where-Object { -not $_.IsStornvme } | ForEach-Object { "$($_.FriendlyName) [$($_.DriverService)]" })) -join ', '
        $reasons.Add("Advertencia (discos mixtos): existen unidades NVMe con otro driver ($otherDrvs) a las que esta clave no aplicará.")
    }

    if ($requiresElevation -and $status -ne 'AlreadyFixed') {
        $reasons.Add('fsutil requirió elevación de Administrador; ejecute dztools como Administrador para medición oficial con fsutil y para aplicar cambios.')
    }

    return [PSCustomObject]@{
        Status            = $status
        CanApplyByDefault = $canApplyByDefault
        RequiresReboot    = $requiresReboot
        Reasons           = @($reasons.ToArray())
        HasOversizedNvme  = $hasSectorOver4K
        HasSqlFindings    = $hasSqlFindings
    }
}

<#
.SYNOPSIS
Orquesta el análisis completo del sistema (SO, discos NVMe, fsutil, Registro y SQL ERRORLOG).
#>
function Invoke-NvmeSystemAnalysis {
    [CmdletBinding()]
    param(
        [switch]$IncludeSqlLogs,
        [string]$RootPath = $script:NvmeDefaultRegistryRoot,
        [string[]]$LogDirectories,
        [switch]$StreamJobProgress
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($StreamJobProgress) { Write-Output ([PSCustomObject]@{ Type = 'Progress'; Percent = 15; Message = 'Consultando versión de Windows...' }) }
    $osInfo = Get-NvmeOsInfo

    if ($StreamJobProgress) { Write-Output ([PSCustomObject]@{ Type = 'Progress'; Percent = 30; Message = 'Detectando discos NVMe y controlador (stornvme)...' }) }
    $diskInfo = Get-NvmeDiskInfo -ServiceRegistryPath $RootPath

    if ($StreamJobProgress) { Write-Output ([PSCustomObject]@{ Type = 'Progress'; Percent = 55; Message = 'Analizando sectores físicos de volúmenes NVMe...' }) }
    $sectorDiag = Get-NvmeSectorDiagnostics -DiskInfo $diskInfo

    if ($StreamJobProgress) { Write-Output ([PSCustomObject]@{ Type = 'Progress'; Percent = 75; Message = 'Inspeccionando clave stornvme en el Registro...' }) }
    $regState = Get-NvmeRegistryState -RootPath $RootPath

    if ($IncludeSqlLogs -and $StreamJobProgress) {
        Write-Output ([PSCustomObject]@{ Type = 'Progress'; Percent = 88; Message = 'Revisando ERRORLOG de SQL Server...' })
    }
    $sqlLogs = if ($IncludeSqlLogs) {
        if ($PSBoundParameters.ContainsKey('LogDirectories')) {
            Find-SqlMisalignedIoErrors -LogDirectories $LogDirectories
        } else {
            Find-SqlMisalignedIoErrors
        }
    } else {
        [PSCustomObject]@{
            Scanned             = $false
            SearchedDirectories = @()
            ScannedFiles        = @()
            Findings            = @()
            HasFindings         = $false
            Summary             = 'Revisión de ERRORLOG omitida por el usuario.'
        }
    }

    if ($StreamJobProgress) { Write-Output ([PSCustomObject]@{ Type = 'Progress'; Percent = 95; Message = 'Evaluando dictamen de elegibilidad...' }) }
    $verdict = Test-NvmeSqlFixCandidate `
        -OsInfo $osInfo `
        -DiskInfo $diskInfo `
        -SectorDiagnostics $sectorDiag `
        -RegistryState $regState `
        -SqlLogResult $sqlLogs

    $sw.Stop()

    $analysisObj = [PSCustomObject]@{
        OsInfo            = $osInfo
        DiskInfo          = $diskInfo
        SectorDiagnostics = $sectorDiag
        RegistryState     = $regState
        SqlLogs           = $sqlLogs
        Verdict           = $verdict
        ElapsedMs         = [int]$sw.ElapsedMilliseconds
        AnalyzedAt        = (Get-Date).ToString('o')
    }

    if ($StreamJobProgress) {
        Write-Output ([PSCustomObject]@{
            Type     = 'Result'
            Ok       = $true
            Analysis = $analysisObj
            Error    = $null
        })
        return
    }

    return $analysisObj
}

#endregion

#region Sección C - Respaldo, Aplicación, Verificación y Restauración

<#
.SYNOPSIS
Genera un respaldo obligatorio (.reg + .json) antes de modificar la clave stornvme en el Registro.
#>
function Backup-NvmeRegistryState {
    [CmdletBinding()]
    param(
        [string]$RootPath = $script:NvmeDefaultRegistryRoot,
        [string]$BackupRoot = $script:NvmeDefaultBackupRoot,
        [string]$DriverService = '',
        [string]$OsBuild = ''
    )

    try {
        if (-not (Test-Path -LiteralPath $BackupRoot)) {
            New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null
        }

        $regState = Get-NvmeRegistryState -RootPath $RootPath
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupId = "nvme_backup_$stamp"
        $jsonPath = Join-Path $BackupRoot "$backupId.json"
        if (Test-Path -LiteralPath $jsonPath) {
            $backupId = "nvme_backup_${stamp}_$((Get-Date).ToString('fff'))"
            $jsonPath = Join-Path $BackupRoot "$backupId.json"
        }
        $regPath = Join-Path $BackupRoot "$backupId.reg"

        $exportTarget = $null
        if ($regState.DeviceKeyExists) {
            $exportTarget = $regState.DevicePath
        } elseif ($regState.ParametersKeyExists) {
            $exportTarget = $regState.ParametersPath
        } elseif ($regState.RootKeyExists) {
            $exportTarget = $regState.RootPath
        }

        $exportedRegPath = $null
        if (-not [string]::IsNullOrWhiteSpace($exportTarget)) {
            $regExeExportKey = ConvertTo-RegExePath -RegistryPath $exportTarget
            $expRes = Invoke-RegExe -Arguments @('export', $regExeExportKey, $regPath, '/y')
            if ($expRes.ExitCode -ne 0 -or (-not (Test-Path -LiteralPath $regPath))) {
                return [PSCustomObject]@{
                    Success  = $false
                    BackupId = $backupId
                    JsonPath = $null
                    RegPath  = $null
                    Error    = "Fallo reg.exe export ($regExeExportKey): $($expRes.Output)"
                }
            }
            $exportedRegPath = $regPath
        }

        if ([string]::IsNullOrWhiteSpace($OsBuild)) {
            $os = Get-NvmeOsInfo
            $OsBuild = [string]$os.BuildNumber
        }

        $snapshot = [ordered]@{
            BackupId             = $backupId
            Timestamp            = (Get-Date).ToString('o')
            ComputerName         = [string]$env:COMPUTERNAME
            UserName             = [string]$env:USERNAME
            OsBuild              = [string]$OsBuild
            TargetKey            = [string](ConvertTo-RegExePath -RegistryPath $regState.DevicePath)
            ParametersKeyExisted = [bool]$regState.ParametersKeyExists
            DeviceKeyExisted     = [bool]$regState.DeviceKeyExists
            ValueExisted         = [bool]$regState.ValueExists
            PreviousValueType    = if ($regState.ValueExists) { [string]$regState.ValueKind } else { $null }
            PreviousValueData    = if ($regState.ValueExists) { @($regState.ValueData) } else { @() }
            DriverService        = [string]$DriverService
            RegExportPath        = $exportedRegPath
            RestoredAt           = $null
        }

        $jsonText = $snapshot | ConvertTo-Json -Depth 5
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($jsonPath, $jsonText, $utf8NoBom)

        return [PSCustomObject]@{
            Success  = $true
            BackupId = $backupId
            JsonPath = $jsonPath
            RegPath  = $exportedRegPath
            Snapshot = [PSCustomObject]$snapshot
            Summary  = "Respaldo creado: $backupId (DeviceKeyExisted=$($regState.DeviceKeyExists), ValueExisted=$($regState.ValueExists))"
            Error    = $null
        }
    } catch {
        return [PSCustomObject]@{
            Success  = $false
            BackupId = $null
            JsonPath = $null
            RegPath  = $null
            Error    = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
Aplica de forma segura ForcedPhysicalSectorSizeInBytes = * 4095 (REG_MULTI_SZ) previo respaldo obligatorio.
#>
function Set-NvmePhysicalSectorFix {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$RootPath = $script:NvmeDefaultRegistryRoot,
        [string]$BackupRoot = $script:NvmeDefaultBackupRoot,
        [string]$DriverService = 'stornvme'
    )

    if (-not (Test-NvmeAdminPrivilege)) {
        return [PSCustomObject]@{
            Success = $false
            Error   = 'Se requieren permisos de Administrador para modificar el Registro.'
        }
    }

    $parametersPath = Join-Path $RootPath 'Parameters'
    $devicePath = Join-Path $parametersPath 'Device'

    if (-not $PSCmdlet.ShouldProcess($devicePath, 'Configurar ForcedPhysicalSectorSizeInBytes = * 4095')) {
        return [PSCustomObject]@{
            Success = $false
            Error   = 'Operación cancelada por ShouldProcess.'
        }
    }

    $backup = Backup-NvmeRegistryState -RootPath $RootPath -BackupRoot $BackupRoot -DriverService $DriverService
    if (-not $backup.Success) {
        Write-NvmeAuditLog -Action 'Apply' -BackupId 'N/A' -Result 'FailedBackup' -Details $backup.Error -BackupRoot $BackupRoot
        return [PSCustomObject]@{
            Success = $false
            Error   = "No se pudo crear el respaldo previo obligatorio: $($backup.Error)"
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $devicePath)) {
            New-Item -Path $devicePath -Force -ErrorAction Stop | Out-Null
        }

        $currentState = Get-NvmeRegistryState -RootPath $RootPath
        $targetValues = New-Object System.Collections.Generic.List[string]
        $seen = @{}

        if ($currentState.ValueExists -and $currentState.ValueKind -eq 'MultiString') {
            foreach ($entry in @($currentState.ValueData)) {
                $clean = ([string]$entry).Trim()
                if ([string]::IsNullOrWhiteSpace($clean)) { continue }
                $normKey = $clean.ToLowerInvariant()
                if (-not $seen.ContainsKey($normKey)) {
                    $seen[$normKey] = $true
                    $targetValues.Add($clean)
                }
            }
        }

        $has4095 = $false
        foreach ($item in $targetValues) {
            if ($item -match '^\*\s*4095$') {
                $has4095 = $true
                break
            }
        }
        if (-not $has4095) {
            $targetValues.Add('* 4095')
        }

        $valueArray = [string[]]$targetValues.ToArray()
        Set-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Value $valueArray -Type MultiString -Force -ErrorAction Stop

        $postState = Get-NvmeRegistryState -RootPath $RootPath
        $verified = $postState.Has4095Rule -and ($postState.RegQueryExitCode -eq 0) -and ($postState.RawRegQueryOutput -match '\*\s*4095')

        if (-not $verified) {
            Write-NvmeAuditLog -Action 'Apply' -BackupId $backup.BackupId -Result 'VerificationFailed' -Details $postState.RawRegQueryOutput -BackupRoot $BackupRoot
            return [PSCustomObject]@{
                Success        = $false
                BackupId       = $backup.BackupId
                JsonPath       = $backup.JsonPath
                RegPath        = $backup.RegPath
                RegQueryOutput = $postState.RawRegQueryOutput
                Error          = 'La escritura finalizó pero la verificación con REG QUERY no confirmó "* 4095".'
            }
        }

        Write-NvmeAuditLog -Action 'Apply' -BackupId $backup.BackupId -Result 'Success' -Details "Values=$($valueArray -join '; ')" -BackupRoot $BackupRoot

        return [PSCustomObject]@{
            Success        = $true
            BackupId       = $backup.BackupId
            JsonPath       = $backup.JsonPath
            RegPath        = $backup.RegPath
            AppliedValues  = $valueArray
            RegQueryOutput = $postState.RawRegQueryOutput
            PostState      = $postState
            Message        = 'Parámetro ForcedPhysicalSectorSizeInBytes (* 4095) aplicado y verificado correctamente.'
        }
    } catch {
        Write-NvmeAuditLog -Action 'Apply' -BackupId $backup.BackupId -Result 'Error' -Details $_.Exception.Message -BackupRoot $BackupRoot
        return [PSCustomObject]@{
            Success  = $false
            BackupId = $backup.BackupId
            JsonPath = $backup.JsonPath
            RegPath  = $backup.RegPath
            Error    = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
Lista los respaldos NVMe (.json) ordenados del más reciente al más antiguo.
#>
function Get-NvmeRegistryBackups {
    [CmdletBinding()]
    param(
        [string]$BackupRoot = $script:NvmeDefaultBackupRoot
    )

    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
        return @()
    }

    $files = @(Get-ChildItem -LiteralPath $BackupRoot -Filter 'nvme_backup_*.json' -File -ErrorAction SilentlyContinue)
    $items = @()

    foreach ($file in $files) {
        try {
            $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            $data = $raw | ConvertFrom-Json
            if (-not $data) { continue }
            $isRestored = (-not [string]::IsNullOrWhiteSpace([string]$data.RestoredAt))
            $prevDesc = if ($data.ValueExisted) {
                "$($data.PreviousValueType): $((@($data.PreviousValueData)) -join ', ')"
            } else {
                'Sin valor previo'
            }
            $items += [PSCustomObject]@{
                BackupId             = [string]$data.BackupId
                Timestamp            = [string]$data.Timestamp
                ComputerName         = [string]$data.ComputerName
                UserName             = [string]$data.UserName
                DriverService        = [string]$data.DriverService
                ParametersKeyExisted = [bool]$data.ParametersKeyExisted
                DeviceKeyExisted     = [bool]$data.DeviceKeyExisted
                ValueExisted         = [bool]$data.ValueExisted
                PreviousValueType    = [string]$data.PreviousValueType
                PreviousValueData    = @($data.PreviousValueData)
                RegExportPath        = [string]$data.RegExportPath
                RestoredAt           = if ($isRestored) { [string]$data.RestoredAt } else { $null }
                IsRestored           = $isRestored
                IsLatest             = $false
                PreviousSummary      = $prevDesc
                JsonPath             = $file.FullName
                Display              = ''
            }
        } catch {
            Write-NvmeDebug -Message "`t[DEBUG][Get-NvmeRegistryBackups] Error leyendo '$($file.FullName)': $($_.Exception.Message)" -Color Yellow
        }
    }

    $sorted = @($items | Sort-Object Timestamp, BackupId -Descending)
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $sorted[$i].IsLatest = ($i -eq 0)
        $tagParts = @()
        if ($i -eq 0) { $tagParts += 'Más reciente' }
        if ($sorted[$i].IsRestored) { $tagParts += 'restaurado' }
        $tagText = if ($tagParts.Count -gt 0) { " [$($tagParts -join ', ')]" } else { '' }
        $sorted[$i].Display = "{0} | {1} | {2}{3}" -f $sorted[$i].BackupId, $sorted[$i].Timestamp, $sorted[$i].PreviousSummary, $tagText
    }

    return @($sorted)
}

<#
.SYNOPSIS
Restaura el estado exacto del Registro usando exclusivamente el snapshot JSON como fuente de verdad.
#>
function Restore-NvmeRegistryBackup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupJsonPath,
        [string]$RootPath = $script:NvmeDefaultRegistryRoot,
        [string]$BackupRoot = $script:NvmeDefaultBackupRoot
    )

    if (-not (Test-NvmeAdminPrivilege)) {
        return [PSCustomObject]@{
            Success = $false
            Error   = 'Se requieren permisos de Administrador para restaurar el Registro.'
        }
    }

    if (-not (Test-Path -LiteralPath $BackupJsonPath -PathType Leaf)) {
        return [PSCustomObject]@{
            Success = $false
            Error   = "No existe el archivo de respaldo: $BackupJsonPath"
        }
    }

    try {
        $raw = [System.IO.File]::ReadAllText($BackupJsonPath, [System.Text.Encoding]::UTF8)
        $snapshot = $raw | ConvertFrom-Json
        if (-not $snapshot -or [string]::IsNullOrWhiteSpace([string]$snapshot.BackupId)) {
            throw 'El archivo JSON de respaldo no es válido.'
        }

        $parametersPath = Join-Path $RootPath 'Parameters'
        $devicePath = Join-Path $parametersPath 'Device'

        if (-not $PSCmdlet.ShouldProcess($devicePath, "Restaurar respaldo $($snapshot.BackupId)")) {
            return [PSCustomObject]@{
                Success = $false
                Error   = 'Operación cancelada por ShouldProcess.'
            }
        }

        if (-not [bool]$snapshot.ValueExisted) {
            if (Test-Path -LiteralPath $devicePath) {
                $devKey = Get-Item -LiteralPath $devicePath -ErrorAction Stop
                if (@($devKey.GetValueNames()) -contains $script:NvmeValueName) {
                    Remove-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Force -ErrorAction Stop
                }
            }

            if ((-not [bool]$snapshot.DeviceKeyExisted) -and (Test-Path -LiteralPath $devicePath)) {
                $devKeyAfter = Get-Item -LiteralPath $devicePath -ErrorAction Stop
                if ($devKeyAfter.ValueCount -eq 0 -and $devKeyAfter.SubKeyCount -eq 0) {
                    Remove-Item -LiteralPath $devicePath -Force -ErrorAction Stop
                }
            }

            if ((-not [bool]$snapshot.ParametersKeyExisted) -and (Test-Path -LiteralPath $parametersPath)) {
                $paramKeyAfter = Get-Item -LiteralPath $parametersPath -ErrorAction Stop
                if ($paramKeyAfter.ValueCount -eq 0 -and $paramKeyAfter.SubKeyCount -eq 0) {
                    Remove-Item -LiteralPath $parametersPath -Force -ErrorAction Stop
                }
            }
        } else {
            if (-not (Test-Path -LiteralPath $devicePath)) {
                New-Item -Path $devicePath -Force -ErrorAction Stop | Out-Null
            }

            $prevType = [string]$snapshot.PreviousValueType
            $prevArray = @($snapshot.PreviousValueData)

            switch ($prevType) {
                'MultiString' {
                    $strArr = [string[]]@($prevArray | ForEach-Object { [string]$_ })
                    Set-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Value $strArr -Type MultiString -Force -ErrorAction Stop
                }
                'String' {
                    $strVal = if ($prevArray.Count -gt 0) { [string]$prevArray[0] } else { '' }
                    Set-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Value $strVal -Type String -Force -ErrorAction Stop
                }
                'ExpandString' {
                    $expVal = if ($prevArray.Count -gt 0) { [string]$prevArray[0] } else { '' }
                    Set-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Value $expVal -Type ExpandString -Force -ErrorAction Stop
                }
                'DWord' {
                    $dwVal = if ($prevArray.Count -gt 0) { [int]$prevArray[0] } else { 0 }
                    Set-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Value $dwVal -Type DWord -Force -ErrorAction Stop
                }
                'QWord' {
                    $qwVal = if ($prevArray.Count -gt 0) { [long]$prevArray[0] } else { 0L }
                    Set-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Value $qwVal -Type QWord -Force -ErrorAction Stop
                }
                'Binary' {
                    $binVal = [byte[]]@($prevArray | ForEach-Object { [byte]$_ })
                    Set-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Value $binVal -Type Binary -Force -ErrorAction Stop
                }
                default {
                    $fallbackArr = [string[]]@($prevArray | ForEach-Object { [string]$_ })
                    Set-ItemProperty -LiteralPath $devicePath -Name $script:NvmeValueName -Value $fallbackArr -Type MultiString -Force -ErrorAction Stop
                }
            }
        }

        $restoredAt = (Get-Date).ToString('o')
        $snapshot | Add-Member -NotePropertyName 'RestoredAt' -NotePropertyValue $restoredAt -Force
        $updatedJson = $snapshot | ConvertTo-Json -Depth 5
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($BackupJsonPath, $updatedJson, $utf8NoBom)

        $postState = Get-NvmeRegistryState -RootPath $RootPath
        Write-NvmeAuditLog -Action 'Restore' -BackupId ([string]$snapshot.BackupId) -Result 'Success' -Details "ValueExisted=$($snapshot.ValueExisted)" -BackupRoot $BackupRoot

        return [PSCustomObject]@{
            Success           = $true
            BackupId          = [string]$snapshot.BackupId
            RestoredAt        = $restoredAt
            RegQueryOutput    = $postState.RawRegQueryOutput
            ManualRegFilePath = [string]$snapshot.RegExportPath
            PostState         = $postState
            Message           = "Respaldo '$($snapshot.BackupId)' restaurado correctamente."
        }
    } catch {
        $bId = if ($snapshot -and $snapshot.BackupId) { [string]$snapshot.BackupId } else { [System.IO.Path]::GetFileNameWithoutExtension($BackupJsonPath) }
        Write-NvmeAuditLog -Action 'Restore' -BackupId $bId -Result 'Error' -Details $_.Exception.Message -BackupRoot $BackupRoot
        return [PSCustomObject]@{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

#endregion

#region Sección D - Interfaz Modal WPF (Show-NvmeRegFixDialog)

function Format-NvmeDiagnosticLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Analysis
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("===== ANÁLISIS NVMe / SQL SECTOR 4KB ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) =====")
    [void]$sb.AppendLine("Tiempo de análisis: $($Analysis.ElapsedMs) ms")
    [void]$sb.AppendLine('')

    if ($Analysis.OsInfo) {
        $os = $Analysis.OsInfo
        [void]$sb.AppendLine("[SO] $($os.ProductName) | Version=$($os.Version) | Build=$($os.BuildNumber) | Display=$($os.DisplayVersion) | Server=$($os.IsServer)")
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('[DISCOS Y CONTROLADORES NVMe]')
    if ($Analysis.DiskInfo -and $Analysis.DiskInfo.Disks.Count -gt 0) {
        foreach ($d in $Analysis.DiskInfo.Disks) {
            [void]$sb.AppendLine("  - Disk #$($d.DeviceId): $($d.FriendlyName) | Bus=$($d.BusType) | Driver=$($d.DriverService) ($($d.DriverDetectionSource)) | Physical=$($d.PhysicalSectorSize) | Logical=$($d.LogicalSectorSize)")
        }
    } else {
        [void]$sb.AppendLine('  (No se detectaron discos NVMe)')
    }
    if ($Analysis.DiskInfo) {
        [void]$sb.AppendLine("  Servicio stornvme: Exists=$($Analysis.DiskInfo.StornvmeServiceExists) | Start=$($Analysis.DiskInfo.StornvmeStart) | DriverState=$($Analysis.DiskInfo.StornvmeDriverState)")
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('[VOLÚMENES NVMe Y FSUTIL]')
    if ($Analysis.SectorDiagnostics -and $Analysis.SectorDiagnostics.Volumes.Count -gt 0) {
        foreach ($v in $Analysis.SectorDiagnostics.Volumes) {
            [void]$sb.AppendLine("  --- Unidad $($v.DeviceID) ($($v.VolumeName)) [Origen: $($v.DataSource) | Driver: $($v.DriverService)] ---")
            if ($v.Fsutil -and -not [string]::IsNullOrWhiteSpace($v.Fsutil.RawOutput)) {
                [void]$sb.AppendLine($v.Fsutil.RawOutput.Trim())
            }
            if ($null -ne $v.FallbackPhysicalSectorSize) {
                [void]$sb.AppendLine("  Get-PhysicalDisk.PhysicalSectorSize = $($v.FallbackPhysicalSectorSize)")
            }
        }
    } else {
        [void]$sb.AppendLine('  (Sin volúmenes NVMe con letra de unidad)')
    }
    if ($Analysis.SectorDiagnostics -and $Analysis.SectorDiagnostics.SkippedNonNvmeDrives.Count -gt 0) {
        $skipText = ($Analysis.SectorDiagnostics.SkippedNonNvmeDrives | ForEach-Object { "$($_.DeviceID) ($($_.BusType))" }) -join ', '
        [void]$sb.AppendLine("  Unidades excluidas (no NVMe): $skipText")
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('[REGISTRO stornvme\Parameters\Device]')
    if ($Analysis.RegistryState) {
        $r = $Analysis.RegistryState
        [void]$sb.AppendLine("  ParametersKeyExists=$($r.ParametersKeyExists) | DeviceKeyExists=$($r.DeviceKeyExists) | ValueExists=$($r.ValueExists) | Kind=$($r.ValueKind) | Has4095=$($r.Has4095Rule)")
        if (-not [string]::IsNullOrWhiteSpace($r.RawRegQueryOutput)) {
            [void]$sb.AppendLine($r.RawRegQueryOutput.Trim())
        }
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('[SQL SERVER ERRORLOG]')
    if ($Analysis.SqlLogs) {
        [void]$sb.AppendLine("  $($Analysis.SqlLogs.Summary)")
        if ($Analysis.SqlLogs.Findings.Count -gt 0) {
            foreach ($f in ($Analysis.SqlLogs.Findings | Select-Object -First 15)) {
                [void]$sb.AppendLine("  [$($f.MatchType)] $($f.FilePath): $($f.Line)")
            }
        }
    }

    return $sb.ToString()
}

function Show-NvmeBackupPickerDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Backups,
        [Parameter(Mandatory = $true)]
        $Theme,
        [System.Windows.Window]$Owner
    )

    $pickerXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Seleccionar respaldo NVMe"
        Width="680" Height="360"
        WindowStartupLocation="CenterOwner"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10">
    <Grid Margin="14">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="0,0,0,10">
        <TextBlock Text="Seleccionar respaldo a restaurar" FontWeight="SemiBold" FontSize="13" Foreground="{DynamicResource FormFg}"/>
        <TextBlock Text="Se restaurará el estado registrado en el archivo .json seleccionado." FontSize="10.5" Foreground="{DynamicResource AccentMuted}" Margin="0,2,0,0"/>
      </StackPanel>
      <ListBox Grid.Row="1"
               Name="lbBackups"
               Background="{DynamicResource PanelBg}"
               Foreground="{DynamicResource FormFg}"
               BorderBrush="{DynamicResource BorderBrushColor}"
               BorderThickness="1"
               DisplayMemberPath="Display"
               Padding="6"/>
      <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
        <Button Name="btnConfirmPick" Content="Restaurar seleccionado" Height="32" Padding="14,6" Margin="0,0,10,0" Background="{DynamicResource AccentPrimary}" Foreground="{DynamicResource OnAccentFg}" BorderThickness="0" Cursor="Hand"/>
        <Button Name="btnCancelPick" Content="Cancelar" Height="32" Padding="14,6" IsCancel="True" Background="{DynamicResource ControlBg}" Foreground="{DynamicResource ControlFg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@

    $ui = New-WpfWindow -Xaml $pickerXaml -PassThru
    $pw = $ui.Window
    $pc = $ui.Controls
    Set-DzWpfThemeResources -Window $pw -Theme $Theme
    if ($Owner) { $pw.Owner = $Owner }

    $pc['lbBackups'].ItemsSource = @($Backups)
    $pc['lbBackups'].SelectedIndex = 0

    $pickState = [ordered]@{ Selected = $null }
    $pc['btnConfirmPick'].Add_Click({
        $pickState.Selected = $pc['lbBackups'].SelectedItem
        $pw.Close()
    }.GetNewClosure())
    $pc['btnCancelPick'].Add_Click({
        $pickState.Selected = $null
        $pw.Close()
    }.GetNewClosure())

    $null = $pw.ShowDialog()
    return $pickState.Selected
}

function Start-NvmeDialogAsyncAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    if ($Context.IsAnalyzing -or $Context.IsClosing) { return }
    $Context.IsAnalyzing = $true
    $Context.PendingJobResult = $null
    $Context.LastProgressPercent = 5
    & $Context.UpdateButtonStates
    & $Context.SetStatus 'Analizando sistema (discos NVMe, fsutil, Registro y SQL ERRORLOG)...' 'Info'

    $c = $Context.Controls
    $w = $Context.Window
    $includeSql = ($c['chkIncludeSqlLogs'].IsChecked -eq $true)
    $modPath = $Context.ModulePath

    $progressWin = $null
    if (Get-Command Show-WpfProgressBar -ErrorAction SilentlyContinue) {
        $progressWin = Show-WpfProgressBar `
            -Title 'Analizando sistema NVMe' `
            -Message 'Iniciando motor de diagnóstico NVMe y SQL...' `
            -Owner $w `
            -IsIndeterminate $false `
            -BlockOwner `
            -ProgrammaticCloseOnly
        if ($progressWin -and (Get-Command Update-WpfProgressBar -ErrorAction SilentlyContinue)) {
            Update-WpfProgressBar -Window $progressWin -Percent 5 -Message 'Iniciando diagnóstico en segundo plano...'
        }
    }
    $Context.ProgressWindow = $progressWin

    $workerBlock = {
        param([string]$ModulePath, [bool]$ScanSql)
        try {
            Import-Module $ModulePath -Force -DisableNameChecking -ErrorAction Stop
            Invoke-NvmeSystemAnalysis -IncludeSqlLogs:$ScanSql -StreamJobProgress
        } catch {
            Write-Output ([PSCustomObject]@{
                Type     = 'Result'
                Ok       = $false
                Analysis = $null
                Error    = $_.Exception.Message
            })
        }
    }

    try {
        $job = Start-Job -ScriptBlock $workerBlock -ArgumentList $modPath, $includeSql -ErrorAction Stop
        $Context.Job = $job

        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(200)
        $Context.Timer = $timer

        $timer.Add_Tick({
            if ($Context.IsClosing) {
                $timer.Stop()
                return
            }

            $j = $Context.Job
            if (-not $j) {
                $timer.Stop()
                return
            }

            $streamItems = @(Receive-Job -Job $j -ErrorAction SilentlyContinue)
            $gotProgress = $false
            foreach ($item in $streamItems) {
                if (-not $item) { continue }
                if ($item.PSObject.Properties['Type']) {
                    if ($item.Type -eq 'Progress') {
                        $gotProgress = $true
                        $pct = [int]$item.Percent
                        if ($pct -gt $Context.LastProgressPercent) { $Context.LastProgressPercent = $pct }
                        if ($Context.ProgressWindow -and (Get-Command Update-WpfProgressBar -ErrorAction SilentlyContinue)) {
                            Update-WpfProgressBar -Window $Context.ProgressWindow -Percent $Context.LastProgressPercent -Message ([string]$item.Message)
                        }
                        & $Context.SetStatus ([string]$item.Message) 'Info'
                    } elseif ($item.Type -eq 'Result') {
                        $Context.PendingJobResult = $item
                    }
                } elseif ($null -ne $item.PSObject.Properties['Ok']) {
                    $Context.PendingJobResult = $item
                }
            }

            if ($j.State -notin @('Completed', 'Failed', 'Stopped')) {
                if (-not $gotProgress -and $Context.LastProgressPercent -lt 14) {
                    $Context.LastProgressPercent = [int]$Context.LastProgressPercent + 1
                    if ($Context.ProgressWindow -and (Get-Command Update-WpfProgressBar -ErrorAction SilentlyContinue)) {
                        Update-WpfProgressBar -Window $Context.ProgressWindow -Percent $Context.LastProgressPercent
                    }
                }
                return
            }

            $timer.Stop()
            $Context.Timer = $null
            $jobResult = $Context.PendingJobResult
            $jobErr = $null

            try {
                $tailItems = @(Receive-Job -Job $j -ErrorAction SilentlyContinue)
                foreach ($item in $tailItems) {
                    if ($item -and (($item.PSObject.Properties['Type'] -and $item.Type -eq 'Result') -or ($null -ne $item.PSObject.Properties['Ok']))) {
                        $jobResult = $item
                    }
                }

                if (-not $jobResult -or -not $jobResult.Ok) {
                    if ($jobResult -and $jobResult.Error) {
                        $jobErr = [string]$jobResult.Error
                    } elseif ($j.ChildJobs.Count -gt 0 -and $j.ChildJobs[0].JobStateInfo.Reason) {
                        $jobErr = $j.ChildJobs[0].JobStateInfo.Reason.Message
                    } else {
                        $jobErr = 'El análisis finalizó sin devolver resultado.'
                    }
                } elseif ($Context.ProgressWindow -and (Get-Command Update-WpfProgressBar -ErrorAction SilentlyContinue)) {
                    Update-WpfProgressBar -Window $Context.ProgressWindow -Percent 100 -Message 'Análisis completado.'
                }
            } catch {
                $jobErr = $_.Exception.Message
            } finally {
                try { Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
                $Context.Job = $null
                $Context.PendingJobResult = $null
                $Context.IsAnalyzing = $false
                if ($Context.ProgressWindow) {
                    if (Get-Command Close-WpfProgressBar -ErrorAction SilentlyContinue) {
                        Close-WpfProgressBar -Window $Context.ProgressWindow
                    }
                    $Context.ProgressWindow = $null
                }
            }

            if ($jobErr) {
                & $Context.UpdateButtonStates
                & $Context.SetStatus "Error en el análisis: $jobErr" 'Error'
                $Context.Controls['txtTechLog'].Text = "Error ejecutando análisis:`r`n$jobErr"
                $Context.PendingPostApplyInfo = $null
                $Context.PendingPostRestoreMessage = $null
                return
            }

            $rawAnalysis = $jobResult.Analysis
            $recomputedVerdict = Test-NvmeSqlFixCandidate `
                -OsInfo $rawAnalysis.OsInfo `
                -DiskInfo $rawAnalysis.DiskInfo `
                -SectorDiagnostics $rawAnalysis.SectorDiagnostics `
                -RegistryState $rawAnalysis.RegistryState `
                -SqlLogResult $rawAnalysis.SqlLogs

            $analysisData = [PSCustomObject]@{
                OsInfo            = $rawAnalysis.OsInfo
                DiskInfo          = $rawAnalysis.DiskInfo
                SectorDiagnostics = $rawAnalysis.SectorDiagnostics
                RegistryState     = $rawAnalysis.RegistryState
                SqlLogs           = $rawAnalysis.SqlLogs
                Verdict           = $recomputedVerdict
                ElapsedMs         = [int]$rawAnalysis.ElapsedMs
                AnalyzedAt        = [string]$rawAnalysis.AnalyzedAt
            }

            & $Context.RenderAnalysis $analysisData

            if ($Context.PendingPostApplyInfo) {
                $applyInfo = $Context.PendingPostApplyInfo
                $Context.PendingPostApplyInfo = $null
                $rebootPrompt = "La corrección NVMe se aplicó y verificó correctamente.`n`nRespaldo guardado en:`n$($applyInfo.JsonPath)`n`nEs necesario reiniciar Windows para que el driver stornvme aplique el tamaño de sector de 4 KB.`n¿Desea reiniciar el equipo ahora?"
                if (& $Context.UiConfirm $rebootPrompt 'Reinicio requerido') {
                    & shutdown.exe /r /t 10 /c 'Reinicio para aplicar emulacion de sector 4KB NVMe para SQL Server'
                } else {
                    Show-WpfMessageBoxSafe -Message 'Recuerde reiniciar Windows manualmente antes de instalar o iniciar SQL Server.' -Title 'Reinicio pendiente' -Buttons 'OK' -Icon 'Information' -Owner $Context.Window | Out-Null
                }
            } elseif ($Context.PendingPostRestoreMessage) {
                $restoreInfo = $Context.PendingPostRestoreMessage
                $Context.PendingPostRestoreMessage = $null
                $rebootRestorePrompt = "$($restoreInfo.Message)`n`nRespaldo manual .reg disponible en: $($restoreInfo.ManualRegFilePath)`n`nPara que el controlador stornvme recargue el estado restaurado puede ser necesario reiniciar Windows.`n¿Desea reiniciar el equipo ahora?"
                if (& $Context.UiConfirm $rebootRestorePrompt 'Restauración completada') {
                    & shutdown.exe /r /t 10 /c 'Reinicio tras restauracion de configuracion NVMe en Registro'
                }
            }
        }.GetNewClosure())

        $timer.Start()
    } catch {
        $Context.IsAnalyzing = $false
        if ($Context.ProgressWindow) {
            if (Get-Command Close-WpfProgressBar -ErrorAction SilentlyContinue) {
                Close-WpfProgressBar -Window $Context.ProgressWindow
            }
            $Context.ProgressWindow = $null
        }
        & $Context.UpdateButtonStates
        & $Context.SetStatus "No se pudo iniciar el análisis asíncrono: $($_.Exception.Message)" 'Error'
    }
}

<#
.SYNOPSIS
Abre el modal WPF para diagnóstico, respaldo, aplicación y reversión de la corrección NVMe 4KB.
#>
function Show-NvmeRegFixDialog {
    [CmdletBinding()]
    param(
        [System.Windows.Window]$Owner
    )

    Write-NvmeDebug -Message "`t[DEBUG][Show-NvmeRegFixDialog] INICIO" -Color Cyan
    $theme = Get-DzUiTheme
    $backupRoot = $script:NvmeDefaultBackupRoot
    $isAdmin = Test-NvmeAdminPrivilege

    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Corrección NVMe 4KB para SQL Server (Regedit)"
        Width="790" Height="660"
        MinWidth="760" MinHeight="600"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="CanResizeWithGrip"
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
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.48"/>
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
    <Style x:Key="WarningButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource AccentAmber}"/>
      <Setter Property="Foreground" Value="#111111"/>
    </Style>
    <Style x:Key="CardStyle" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="8,6"/>
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
            <TextBlock Text="Corrección NVMe 4KB para SQL Server (Regedit)"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12.5"/>
            <TextBlock Text="Analiza sectores físicos NVMe/stornvme, respalda y aplica * 4095"
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
              Name="borderAdminWarning"
              Visibility="Collapsed"
              Background="#33F59E0B"
              BorderBrush="{DynamicResource AccentAmber}"
              BorderThickness="1"
              CornerRadius="8"
              Padding="10,7"
              Margin="12,0,12,8">
        <TextBlock Name="txtAdminWarning"
                   Text="⚠ Ejecutando sin permisos de Administrador. fsutil no podrá consultar sectores reales y Aplicar / Revertir permanecerán bloqueados."
                   Foreground="{DynamicResource FormFg}"
                   FontSize="10.5"
                   TextWrapping="Wrap"/>
      </Border>

      <Grid Grid.Row="2" Margin="12,0,12,8">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="PASO 1: Análisis del sistema"
                     FontWeight="SemiBold"
                     Foreground="{DynamicResource FormFg}"
                     VerticalAlignment="Center"
                     Margin="0,0,14,0"/>
          <Button Name="btnAnalyze"
                  Content="🔍 Analizar estado actual"
                  Style="{StaticResource PrimaryButtonStyle}"
                  MinWidth="175"
                  Margin="0,0,14,0"/>
          <CheckBox Name="chkIncludeSqlLogs"
                    Content="Revisar ERRORLOG de SQL Server"
                    Foreground="{DynamicResource FormFg}"
                    IsChecked="True"
                    VerticalAlignment="Center"/>
        </StackPanel>

        <Grid Grid.Row="1" Margin="0,0,0,8">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="6"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="6"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="6"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <Border Grid.Row="0" Grid.Column="0" Style="{StaticResource CardStyle}">
            <StackPanel>
              <TextBlock Text="Sistema Operativo" FontSize="9.5" Foreground="{DynamicResource AccentMuted}"/>
              <TextBlock Name="lblOsSummary" Text="--" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="0" Grid.Column="2" Style="{StaticResource CardStyle}">
            <StackPanel>
              <TextBlock Text="Discos NVMe / Driver" FontSize="9.5" Foreground="{DynamicResource AccentMuted}"/>
              <TextBlock Name="lblDisksSummary" Text="--" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="0" Grid.Column="4" Style="{StaticResource CardStyle}">
            <StackPanel>
              <TextBlock Text="Sector NVMe" FontSize="9.5" Foreground="{DynamicResource AccentMuted}"/>
              <TextBlock Name="lblSectorSummary" Text="--" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>

          <Border Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="3" Style="{StaticResource CardStyle}">
            <StackPanel>
              <TextBlock Text="Registro stornvme\Parameters\Device" FontSize="9.5" Foreground="{DynamicResource AccentMuted}"/>
              <TextBlock Name="lblRegSummary" Text="--" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="2" Grid.Column="4" Style="{StaticResource CardStyle}">
            <StackPanel>
              <TextBlock Text="SQL ERRORLOG" FontSize="9.5" Foreground="{DynamicResource AccentMuted}"/>
              <TextBlock Name="lblSqlSummary" Text="--" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>
        </Grid>

        <Grid Grid.Row="2">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0"
                     Text="Log técnico (Consolas - salida fsutil, REG QUERY, errores SQL):"
                     FontSize="10"
                     Foreground="{DynamicResource AccentMuted}"
                     Margin="0,0,0,4"/>
          <TextBox Grid.Row="1"
                   Name="txtTechLog"
                   IsReadOnly="True"
                   AcceptsReturn="True"
                   FontFamily="Consolas"
                   FontSize="10.5"
                   Background="{DynamicResource PanelBg}"
                   Foreground="{DynamicResource PanelFg}"
                   BorderBrush="{DynamicResource BorderBrushColor}"
                   BorderThickness="1"
                   Padding="8"
                   VerticalScrollBarVisibility="Auto"
                   HorizontalScrollBarVisibility="Auto"
                   TextWrapping="NoWrap"
                   Text='&gt; Presiona "Analizar estado actual" para inspeccionar el equipo...'/>
        </Grid>
      </Grid>

      <StackPanel Grid.Row="3" Margin="12,0,12,8">
        <TextBlock Text="PASO 2: Dictamen de elegibilidad"
                   FontWeight="SemiBold"
                   Foreground="{DynamicResource FormFg}"
                   Margin="0,0,0,4"/>
        <Border Name="borderVerdict"
                Background="{DynamicResource PanelBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="8"
                Padding="10,8"
                Margin="0,0,0,6">
          <StackPanel>
            <TextBlock Name="lblVerdictStatus"
                       Text="Estado: Pendiente de análisis"
                       FontWeight="Bold"
                       FontSize="11.5"
                       Foreground="{DynamicResource FormFg}"/>
            <TextBlock Name="txtVerdictReasons"
                       Text="- Ejecuta el Paso 1 para determinar si el equipo es candidato."
                       Foreground="{DynamicResource PanelFg}"
                       FontSize="10.5"
                       TextWrapping="Wrap"
                       Margin="0,4,0,0"/>
          </StackPanel>
        </Border>
        <StackPanel Orientation="Horizontal">
          <CheckBox Name="chkAdvancedMode"
                    Content="Modo avanzado (forzar habilitación en casos borde)"
                    Foreground="{DynamicResource FormFg}"
                    IsEnabled="False"/>
          <TextBlock Name="lblAdvancedWarning"
                     Text=" ⚠ Modo manual activo bajo criterio del técnico."
                     Foreground="{DynamicResource AccentAmber}"
                     FontWeight="SemiBold"
                     FontSize="10.5"
                     Visibility="Collapsed"
                     VerticalAlignment="Center"/>
        </StackPanel>
      </StackPanel>

      <Grid Grid.Row="4" Margin="12,0,12,12">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="8"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0"
                Background="{DynamicResource PanelBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="8"
                Padding="10,6">
          <TextBlock Name="lblStatus"
                     Text="Listo."
                     Foreground="{DynamicResource PanelFg}"
                     TextWrapping="Wrap"/>
        </Border>

        <Grid Grid.Row="2">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <StackPanel Grid.Column="0" Orientation="Horizontal">
            <Button Name="btnOpenBackups"
                    Content="📂 Respaldos"
                    Style="{StaticResource SecondaryButtonStyle}"
                    MinWidth="110"
                    Margin="0,0,8,0"/>
            <Button Name="btnRestore"
                    Content="↩️ Revertir / Restaurar"
                    Style="{StaticResource WarningButtonStyle}"
                    MinWidth="150"
                    IsEnabled="False"/>
          </StackPanel>

          <StackPanel Grid.Column="2" Orientation="Horizontal">
            <Button Name="btnApplyFix"
                    Content="🛠️ Aplicar corrección"
                    Style="{StaticResource PrimaryButtonStyle}"
                    MinWidth="155"
                    Margin="0,0,8,0"
                    IsEnabled="False"/>
            <Button Name="btnCloseFooter"
                    Content="Cerrar"
                    Style="{StaticResource SecondaryButtonStyle}"
                    MinWidth="90"
                    IsCancel="True"/>
          </StackPanel>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

    try {
        $ui = New-WpfWindow -Xaml $stringXaml -PassThru
    } catch {
        Write-NvmeDebug -Message "`t[DEBUG][Show-NvmeRegFixDialog] ERROR creando ventana: $($_.Exception.Message)" -Color Red
        Show-WpfMessageBox -Message "No se pudo crear la ventana de corrección NVMe." -Title "Error" -Buttons OK -Icon Error | Out-Null
        return
    }

    $w = $ui.Window
    $c = $ui.Controls
    Set-DzWpfThemeResources -Window $w -Theme $theme

    if ($Owner -is [System.Windows.Window]) {
        $w.Owner = $Owner
    } else {
        try { Set-WpfDialogOwner -Dialog $w } catch { Write-Verbose $_.Exception.Message }
    }

    if (-not $isAdmin) {
        $c['borderAdminWarning'].Visibility = [System.Windows.Visibility]::Visible
    }

    $fnStartAsync = ${function:Start-NvmeDialogAsyncAnalysis}
    $fnFormatLog = ${function:Format-NvmeDiagnosticLog}
    $fnPickBackup = ${function:Show-NvmeBackupPickerDialog}

    $uiState = [ordered]@{
        IsAdmin                   = $isAdmin
        IsAnalyzing               = $false
        IsClosing                 = $false
        BackupRoot                = $backupRoot
        ModulePath                = $script:RegistryUtilitiesModulePath
        Window                    = $w
        Controls                  = $c
        LastAnalysis              = $null
        LastVerdict               = $null
        Job                       = $null
        Timer                     = $null
        ProgressWindow            = $null
        PendingJobResult          = $null
        UpdateButtonStates        = $null
        RenderAnalysis            = $null
        SetStatus                 = $null
        UiConfirm                 = $null
        AppendLogAfterAnalysis    = $null
        PendingPostApplyInfo      = $null
        PendingPostRestoreMessage = $null
    }

    $UiConfirm = {
        param([string]$Message, [string]$Title = 'Confirmar')
        (Show-WpfMessageBoxSafe -Message $Message -Title $Title -Buttons 'YesNo' -Icon 'Question' -Owner $w) -eq [System.Windows.MessageBoxResult]::Yes
    }.GetNewClosure()
    $uiState.UiConfirm = $UiConfirm

    $setStatus = {
        param([string]$Text, [string]$Level = 'Info')
        $c['lblStatus'].Text = $Text
        switch ($Level) {
            'Ok' { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::ForestGreen }
            'Warn' { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::DarkGoldenrod }
            'Error' { $c['lblStatus'].Foreground = [System.Windows.Media.Brushes]::Firebrick }
            default { $c['lblStatus'].SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'PanelFg') }
        }
    }.GetNewClosure()
    $uiState.SetStatus = $setStatus

    $updateButtonStates = {
        if ($uiState.IsAnalyzing) {
            $c['btnAnalyze'].IsEnabled = $false
            $c['btnApplyFix'].IsEnabled = $false
            $c['chkAdvancedMode'].IsEnabled = $false
            $c['btnRestore'].IsEnabled = $false
            $c['chkIncludeSqlLogs'].IsEnabled = $false
            return
        }

        $c['btnAnalyze'].IsEnabled = $true
        $c['chkIncludeSqlLogs'].IsEnabled = $true

        $backups = @(Get-NvmeRegistryBackups -BackupRoot $uiState.BackupRoot)
        $hasBackups = ($backups.Count -gt 0)
        $c['btnRestore'].IsEnabled = ($uiState.IsAdmin -and $hasBackups)

        if (-not $uiState.IsAdmin) {
            $c['btnApplyFix'].IsEnabled = $false
            $c['chkAdvancedMode'].IsEnabled = $false
            $c['chkAdvancedMode'].IsChecked = $false
            $c['lblAdvancedWarning'].Visibility = [System.Windows.Visibility]::Collapsed
            return
        }

        if ($null -eq $uiState.LastVerdict) {
            $c['btnApplyFix'].IsEnabled = $false
            $c['chkAdvancedMode'].IsEnabled = $false
            $c['chkAdvancedMode'].IsChecked = $false
            $c['lblAdvancedWarning'].Visibility = [System.Windows.Visibility]::Collapsed
            return
        }

        $vStatus = [string]$uiState.LastVerdict.Status
        if ($vStatus -eq 'Candidate') {
            $c['chkAdvancedMode'].IsEnabled = $false
            $c['chkAdvancedMode'].IsChecked = $false
            $c['lblAdvancedWarning'].Visibility = [System.Windows.Visibility]::Collapsed
            $c['btnApplyFix'].IsEnabled = $true
        } else {
            $c['chkAdvancedMode'].IsEnabled = $true
            $advChecked = ($c['chkAdvancedMode'].IsChecked -eq $true)
            $c['btnApplyFix'].IsEnabled = $advChecked
            if ($advChecked) {
                $c['lblAdvancedWarning'].Visibility = [System.Windows.Visibility]::Visible
                if ($vStatus -eq 'UnsupportedDriver') {
                    $c['lblAdvancedWarning'].Text = ' ⚠ Advertencia: la clave no tendrá efecto con el driver actual.'
                } else {
                    $c['lblAdvancedWarning'].Text = ' ⚠ Modo manual activo bajo criterio del técnico.'
                }
            } else {
                $c['lblAdvancedWarning'].Visibility = [System.Windows.Visibility]::Collapsed
            }
        }
    }.GetNewClosure()
    $uiState.UpdateButtonStates = $updateButtonStates

    $renderAnalysis = {
        param($Analysis)

        $uiState.LastAnalysis = $Analysis
        $uiState.LastVerdict = $Analysis.Verdict

        if ($Analysis.OsInfo) {
            $buildTxt = if ($Analysis.OsInfo.BuildNumber -gt 0) { "Build $($Analysis.OsInfo.BuildNumber)" } else { 'Build --' }
            $c['lblOsSummary'].Text = "$($Analysis.OsInfo.ProductName) ($buildTxt)"
        }

        if ($Analysis.DiskInfo -and $Analysis.DiskInfo.Disks.Count -gt 0) {
            $diskText = ($Analysis.DiskInfo.Disks | ForEach-Object {
                $drv = if ([string]::IsNullOrWhiteSpace($_.DriverService)) { '?' } else { $_.DriverService }
                "$($_.FriendlyName) [$drv]"
            }) -join '; '
            $c['lblDisksSummary'].Text = $diskText
        } else {
            $c['lblDisksSummary'].Text = 'Sin discos NVMe'
        }

        if ($Analysis.SectorDiagnostics -and $Analysis.SectorDiagnostics.Volumes.Count -gt 0) {
            $secText = ($Analysis.SectorDiagnostics.Volumes | ForEach-Object {
                $val = if ($null -ne $_.EffectiveMaxPhysicalSector) { "$($_.EffectiveMaxPhysicalSector) B" } else { 'N/D' }
                "$($_.DeviceID) $val ($($_.DataSource))"
            }) -join '; '
            $c['lblSectorSummary'].Text = $secText
        } else {
            $c['lblSectorSummary'].Text = 'N/D'
        }

        if ($Analysis.RegistryState) {
            $r = $Analysis.RegistryState
            $c['lblRegSummary'].Text = if ($r.Has4095Rule) {
                'Aplicado: * 4095 (REG_MULTI_SZ)'
            } elseif ($r.ValueExists) {
                "Valor presente ($($r.ValueKind)): $($r.ValueData -join ', ')"
            } elseif ($r.DeviceKeyExists) {
                'Clave Device existe, sin valor'
            } else {
                'Sin clave Device ni valor'
            }
        }

        if ($Analysis.SqlLogs) {
            if (-not $Analysis.SqlLogs.Scanned) {
                $c['lblSqlSummary'].Text = 'Omitido'
            } elseif ($Analysis.SqlLogs.HasFindings) {
                $c['lblSqlSummary'].Text = "$($Analysis.SqlLogs.Findings.Count) alerta(s)"
            } else {
                $c['lblSqlSummary'].Text = "Limpio ($($Analysis.SqlLogs.ScannedFiles.Count) logs)"
            }
        }

        $c['txtTechLog'].Text = & $fnFormatLog -Analysis $Analysis
        if (-not [string]::IsNullOrWhiteSpace($uiState.AppendLogAfterAnalysis)) {
            $c['txtTechLog'].AppendText($uiState.AppendLogAfterAnalysis)
            $c['txtTechLog'].ScrollToEnd()
            $uiState.AppendLogAfterAnalysis = $null
        }

        $v = $Analysis.Verdict
        $c['lblVerdictStatus'].Text = switch ($v.Status) {
            'Candidate' { 'Estado: CANDIDATO (requiere corrección NVMe 4KB)' }
            'AlreadyAppliedPendingReboot' { 'Estado: YA APLICADO - REINICIO PENDIENTE' }
            'AlreadyFixed' { 'Estado: YA CORREGIDO Y ACTIVO (<= 4096 bytes)' }
            'UnsupportedDriver' { 'Estado: DRIVER NO SOPORTADO (no usa stornvme)' }
            default { 'Estado: NO CANDIDATO' }
        }
        $c['lblVerdictStatus'].Foreground = switch ($v.Status) {
            'Candidate' { [System.Windows.Media.Brushes]::DarkGoldenrod }
            'AlreadyAppliedPendingReboot' { [System.Windows.Media.Brushes]::DodgerBlue }
            'AlreadyFixed' { [System.Windows.Media.Brushes]::ForestGreen }
            'UnsupportedDriver' { [System.Windows.Media.Brushes]::Firebrick }
            default { [System.Windows.Media.Brushes]::Gray }
        }
        $c['txtVerdictReasons'].Text = ($v.Reasons | ForEach-Object { "- $_" }) -join [Environment]::NewLine

        & $updateButtonStates
        & $setStatus "Análisis completado en $($Analysis.ElapsedMs) ms. Dictamen: $($v.Status)." 'Ok'
    }.GetNewClosure()
    $uiState.RenderAnalysis = $renderAnalysis

    $w.WindowStartupLocation = 'Manual'
    $w.Add_Loaded({
        try {
            $own = $w.Owner
            if (-not $own) { $w.WindowStartupLocation = 'CenterScreen'; return }
            $ob = $own.RestoreBounds
            $targetW = if ($w.ActualWidth -gt 0) { $w.ActualWidth } else { $w.Width }
            $targetH = if ($w.ActualHeight -gt 0) { $w.ActualHeight } else { $w.Height }
            $left = $ob.Left + (($ob.Width - $targetW) / 2)
            $top = $ob.Top + (($ob.Height - $targetH) / 2)
            $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($own).Handle
            $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
            $wa = $screen.WorkingArea
            if ($left -lt $wa.Left) { $left = $wa.Left }
            if ($top -lt $wa.Top) { $top = $wa.Top }
            if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
            if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
            $w.Left = [double]$left
            $w.Top = [double]$top
        } catch { Write-Verbose $_.Exception.Message }
    }.GetNewClosure())

    $w.Add_Closing({
        $uiState.IsClosing = $true
        if ($uiState.Timer) {
            try { $uiState.Timer.Stop() } catch { Write-Verbose $_.Exception.Message }
            $uiState.Timer = $null
        }
        if ($uiState.Job) {
            try { Stop-Job -Job $uiState.Job -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
            try { Remove-Job -Job $uiState.Job -Force -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
            $uiState.Job = $null
        }
        if ($uiState.ProgressWindow) {
            if (Get-Command Close-WpfProgressBar -ErrorAction SilentlyContinue) {
                try { Close-WpfProgressBar -Window $uiState.ProgressWindow } catch { Write-Verbose $_.Exception.Message }
            }
            $uiState.ProgressWindow = $null
        }
    }.GetNewClosure())

    $c['HeaderBar'].Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) { $w.DragMove() }
    })
    $c['btnClose'].Add_Click({ $w.Close() })
    $c['btnCloseFooter'].Add_Click({ $w.Close() })

    $c['btnAnalyze'].Add_Click({ & $fnStartAsync -Context $uiState }.GetNewClosure())

    $c['chkAdvancedMode'].Add_Checked({
        if ($uiState.LastVerdict -and $uiState.LastVerdict.Status -ne 'Candidate') {
            $warnMsg = if ($uiState.LastVerdict.Status -eq 'UnsupportedDriver') {
                "ADVERTENCIA: Los discos NVMe detectados no usan el driver stornvme. La clave del Registro no tendrá efecto con el driver actual.`n`nModo avanzado habilitado bajo criterio del técnico."
            } else {
                "Modo avanzado habilitado: el equipo no cumple el dictamen automático de candidato. Procede únicamente si estás seguro."
            }
            Show-WpfMessageBoxSafe -Message $warnMsg -Title 'Modo avanzado' -Buttons 'OK' -Icon 'Warning' -Owner $w | Out-Null
        }
        & $updateButtonStates
    }.GetNewClosure())

    $c['chkAdvancedMode'].Add_Unchecked({
        & $updateButtonStates
    }.GetNewClosure())

    $c['btnOpenBackups'].Add_Click({
        try {
            if (-not (Test-Path -LiteralPath $uiState.BackupRoot)) {
                New-Item -Path $uiState.BackupRoot -ItemType Directory -Force | Out-Null
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList $uiState.BackupRoot
        } catch {
            Show-WpfMessageBoxSafe -Message "No se pudo abrir la carpeta de respaldos:`n$($_.Exception.Message)" -Title 'Error' -Buttons 'OK' -Icon 'Error' -Owner $w | Out-Null
        }
    }.GetNewClosure())

    $c['btnApplyFix'].Add_Click({
        if ($uiState.IsAnalyzing -or (-not $uiState.IsAdmin)) {
            if (-not $uiState.IsAdmin) {
                Show-WpfMessageBoxSafe -Message 'Se requieren permisos de Administrador para aplicar la corrección.' -Title 'Permisos requeridos' -Buttons 'OK' -Icon 'Warning' -Owner $w | Out-Null
            }
            return
        }

        $isAdv = ($c['chkAdvancedMode'].IsChecked -eq $true)
        $advNotice = if ($isAdv) {
            if ($uiState.LastVerdict -and $uiState.LastVerdict.Status -eq 'UnsupportedDriver') {
                "`n`n⚠ ADVERTENCIA (MODO AVANZADO): El driver detectado NO es stornvme; el cambio podría no tener efecto."
            } else {
                "`n`n⚠ MODO AVANZADO ACTIVO: Se aplica fuera de dictamen candidato bajo criterio del técnico."
            }
        } else { '' }

        $confirmMsg = "Se configurará en el Registro:`n`nClave: HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device`nValor: ForcedPhysicalSectorSizeInBytes (REG_MULTI_SZ)`nDato: * 4095`n`nAntes de modificar se creará un respaldo automático (.reg y .json) en:`n$($uiState.BackupRoot)$advNotice`n`n¿Deseas continuar?"
        if (-not (& $UiConfirm $confirmMsg 'Confirmar aplicación NVMe 4KB')) {
            return
        }

        $detectedDriver = if ($uiState.LastAnalysis -and $uiState.LastAnalysis.DiskInfo -and $uiState.LastAnalysis.DiskInfo.Disks.Count -gt 0) {
            ($uiState.LastAnalysis.DiskInfo.Disks | ForEach-Object { $_.DriverService } | Where-Object { $_ } | Select-Object -Unique) -join ','
        } else { '' }

        & $setStatus 'Respaldando y aplicando corrección en el Registro...' 'Info'
        $res = Set-NvmePhysicalSectorFix -BackupRoot $uiState.BackupRoot -DriverService $detectedDriver -Confirm:$false
        if (-not $res.Success) {
            & $setStatus "Error aplicando corrección: $($res.Error)" 'Error'
            Show-WpfMessageBoxSafe -Message "No se pudo aplicar la corrección:`n$($res.Error)" -Title 'Error' -Buttons 'OK' -Icon 'Error' -Owner $w | Out-Null
            return
        }

        $c['chkAdvancedMode'].IsChecked = $false
        $uiState.AppendLogAfterAnalysis = "`r`n`r`n[APLICACIÓN EXITOSA - $($res.BackupId)]`r`nRespaldo JSON: $($res.JsonPath)`r`nRespaldo REG: $($res.RegPath)`r`n$($res.RegQueryOutput)"
        $uiState.PendingPostApplyInfo = $res
        & $fnStartAsync -Context $uiState
    }.GetNewClosure())

    $c['btnRestore'].Add_Click({
        if ($uiState.IsAnalyzing -or (-not $uiState.IsAdmin)) { return }
        $backups = @(Get-NvmeRegistryBackups -BackupRoot $uiState.BackupRoot)
        if ($backups.Count -eq 0) {
            & $updateButtonStates
            Show-WpfMessageBoxSafe -Message 'No se encontraron respaldos disponibles.' -Title 'Sin respaldos' -Buttons 'OK' -Icon 'Information' -Owner $w | Out-Null
            return
        }

        $chosen = if ($backups.Count -eq 1) {
            $backups[0]
        } else {
            & $fnPickBackup -Backups $backups -Theme $theme -Owner $w
        }

        if (-not $chosen) { return }

        if (-not $chosen.IsLatest) {
            $olderOk = & $UiConfirm "El respaldo seleccionado ($($chosen.BackupId)) NO es el más reciente.`nAl restaurarlo se sobrescribirá un estado posterior del Registro.`n`n¿Deseas continuar?" 'Respaldo anterior seleccionado'
            if (-not $olderOk) { return }
        }

        $confirmRestoreMsg = "¿Confirmas restaurar el respaldo '$($chosen.BackupId)' ($($chosen.Timestamp))?`n`nEstado previo registrado: $($chosen.PreviousSummary)`nArchivo .reg de respaldo manual: $($chosen.RegExportPath)"
        if (-not (& $UiConfirm $confirmRestoreMsg 'Confirmar restauración')) {
            return
        }

        & $setStatus "Restaurando respaldo $($chosen.BackupId)..." 'Info'
        $res = Restore-NvmeRegistryBackup -BackupJsonPath $chosen.JsonPath -BackupRoot $uiState.BackupRoot -Confirm:$false
        if (-not $res.Success) {
            & $setStatus "Error al restaurar: $($res.Error)" 'Error'
            Show-WpfMessageBoxSafe -Message "Error restaurando respaldo:`n$($res.Error)" -Title 'Error' -Buttons 'OK' -Icon 'Error' -Owner $w | Out-Null
            return
        }

        $c['chkAdvancedMode'].IsChecked = $false
        $uiState.AppendLogAfterAnalysis = "`r`n`r`n[RESTAURACIÓN EXITOSA - $($res.BackupId)]`r`n$($res.Message)`r`n$($res.RegQueryOutput)"
        $uiState.PendingPostRestoreMessage = $res
        & $fnStartAsync -Context $uiState
    }.GetNewClosure())

    & $updateButtonStates
    $null = $w.ShowDialog()
    Write-NvmeDebug -Message "`t[DEBUG][Show-NvmeRegFixDialog] FIN" -Color Cyan
}

#endregion

Export-ModuleMember -Function @(
    'Show-LZMADialog',
    'Get-NvmeOsInfo',
    'Get-NvmeDiskInfo',
    'ConvertFrom-FsutilSectorInfo',
    'Get-NvmeSectorDiagnostics',
    'Get-NvmeRegistryState',
    'Find-SqlMisalignedIoErrors',
    'Test-NvmeSqlFixCandidate',
    'Invoke-NvmeSystemAnalysis',
    'Backup-NvmeRegistryState',
    'Set-NvmePhysicalSectorFix',
    'Get-NvmeRegistryBackups',
    'Restore-NvmeRegistryBackup',
    'Show-NvmeRegFixDialog'
)
