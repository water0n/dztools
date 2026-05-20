#requires -Version 5.0
#NationalUtilities.psm1 - Módulo de utilidades NS
function Show-DllRegistrationDialog {
    [CmdletBinding()]
    param()
    Write-DzDebug "`t[DEBUG][Show-DllRegistrationDialog] INICIO"
    $theme = Get-DzUiTheme
    $defaultList = @(
        "#Asi se ve uno deshabilitado: C:\Windows\SysWOW64\slicensing.dll (no agregar comillas)"
        "C:\Windows\SysWOW64\Nslicensing.dll"
        "C:\Windows\SysWOW64\Nslicensingr1.dll"
        "C:\Windows\SysWOW64\Nsservices1_0.dll"
        "C:\Windows\SysWOW64\Nsservices1_0r1.dll"
    ) -join "`r`n"
    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Registro de DLLs"
        Width="760" Height="420"
        MinWidth="760" MinHeight="420"
        MaxWidth="760" MaxHeight="420"
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

    <!-- Tipografías base -->
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>

    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>

    <!-- Botón base parecido a tus otros diálogos -->
    <Style x:Key="BaseButtonStyle" TargetType="Button">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center"
                                VerticalAlignment="Center"/>
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

  </Window.Resources>

  <!-- CONTENEDOR / SOMBRA -->
  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">

    <Border.Effect>
      <DropShadowEffect Color="Black"
                        Direction="270"
                        ShadowDepth="4"
                        BlurRadius="14"
                        Opacity="0.25"/>
    </Border.Effect>

    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header draggable -->
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
            <TextBlock Text="Registro de DLLs"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Registrar / deregistrar con regsvr32"
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

      <!-- Hint -->
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <StackPanel>
          <TextBlock Text="Escribe las rutas a registrar o deregistrar (una por línea)."
                     FontWeight="SemiBold"
                     Foreground="{DynamicResource FormFg}"/>
          <TextBlock Text="Nota: si un renglón empieza con #, se omitirá."
                     Foreground="{DynamicResource AccentMuted}"
                     Margin="0,4,0,0"/>
        </StackPanel>
      </Border>

      <!-- Editor -->
      <Border Grid.Row="2"
              Background="{DynamicResource ControlBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10"
              Margin="12,0,12,10">
        <RichTextBox Name="rtbDlls"
                     VerticalScrollBarVisibility="Auto"
                     Background="{DynamicResource ControlBg}"
                     Foreground="{DynamicResource ControlFg}"
                     BorderThickness="0"/>
      </Border>

      <!-- Footer -->
      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
          <RadioButton Name="rbRegister" Content="Registrar (regsvr32)" IsChecked="True" Margin="0,0,16,0"/>
          <RadioButton Name="rbUnregister" Content="Deregistrar (regsvr32 /u)"/>
        </StackPanel>

        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button Name="btnRun"
                  Content="Ejecutar"
                  Width="130"
                  Height="34"
                  Margin="0,0,10,0"
                  Style="{StaticResource PrimaryButtonStyle}"/>
          <Button Name="btnClose"
                  Content="Cerrar"
                  Width="120"
                  Height="34"
                  IsCancel="True"
                  Style="{StaticResource SecondaryButtonStyle}"/>
        </StackPanel>
      </Grid>

    </Grid>
  </Border>
</Window>
"@
    try {
        $ui = New-WpfWindow -Xaml $stringXaml -PassThru
        $w = $ui.Window
        $c = $ui.Controls
        $theme = Get-DzUiTheme
        Set-DzWpfThemeResources -Window $w -Theme $theme
        try { Set-WpfDialogOwner -Dialog $w } catch {}
        # Asegura el centrado real como bdd_RenameFromTree
        $w.WindowStartupLocation = "Manual"
        $w.Add_Loaded({
                try {
                    $owner = $w.Owner
                    if (-not $owner) { $w.WindowStartupLocation = "CenterScreen"; return }
                    $ob = $owner.RestoreBounds
                    $targetW = $w.ActualWidth; if ($targetW -le 0) { $targetW = $w.Width }
                    $targetH = $w.ActualHeight; if ($targetH -le 0) { $targetH = $w.Height }
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
        if ($c.ContainsKey('HeaderBar') -and $c['HeaderBar']) {
            $c['HeaderBar'].Add_MouseLeftButtonDown({
                    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                        try { $w.DragMove() } catch {}
                    }
                })
        }
        if ($c.ContainsKey('btnCloseX') -and $c['btnCloseX']) {
            $c['btnCloseX'].Add_Click({ try { $w.Close() } catch {} })
        }
        $w.Add_PreviewKeyDown({
                param($sender, $e)
                if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                    try { $w.Close() } catch {}
                }
            })
        $rtb = $c['rtbDlls']
        $textRange = New-Object System.Windows.Documents.TextRange($rtb.Document.ContentStart, $rtb.Document.ContentEnd)
        $textRange.Text = $defaultList
        $script:dllFormatting = $false
        $GetTextPointerFromOffset = {
            param(
                [System.Windows.Documents.FlowDocument]$Document,
                [int]$Offset
            )
            $navigator = $Document.ContentStart
            $count = 0
            while ($navigator -ne $null) {
                $context = $navigator.GetPointerContext([System.Windows.Documents.LogicalDirection]::Forward)
                if ($context -eq [System.Windows.Documents.TextPointerContext]::Text) {
                    $text = $navigator.GetTextInRun([System.Windows.Documents.LogicalDirection]::Forward)
                    if (($count + $text.Length) -ge $Offset) { return $navigator.GetPositionAtOffset($Offset - $count) }
                    $count += $text.Length
                    $navigator = $navigator.GetPositionAtOffset($text.Length)
                } else {
                    $navigator = $navigator.GetNextContextPosition([System.Windows.Documents.LogicalDirection]::Forward)
                }
            }
            return $Document.ContentEnd
        }.GetNewClosure()
        $applyHighlight = {
            if ($script:dllFormatting) { return }
            $script:dllFormatting = $true
            try {
                $caret = $rtb.CaretPosition

                $range = New-Object System.Windows.Documents.TextRange(
                    $rtb.Document.ContentStart,
                    $rtb.Document.ContentEnd
                )

                $text = $range.Text -replace "`r", ""

                $rtb.Document.Blocks.Clear()
                $p = New-Object System.Windows.Documents.Paragraph
                $p.Margin = "0"

                foreach ($line in $text -split "`n", -1) {
                    $run = New-Object System.Windows.Documents.Run($line)
                    if ($line.TrimStart().StartsWith("#")) {
                        $run.Foreground = [System.Windows.Media.Brushes]::Gray
                    }
                    $p.Inlines.Add($run)
                    $p.Inlines.Add((New-Object System.Windows.Documents.LineBreak))
                }

                $rtb.Document.Blocks.Add($p)
                $rtb.CaretPosition = $caret
            } finally {
                $script:dllFormatting = $false
            }
        }.GetNewClosure()

        & $applyHighlight
        $rtb.Add_TextChanged({ & $applyHighlight })
        $c['btnRun'].Add_Click({
                Write-DzDebug "`t[DEBUG][Show-DllRegistrationDialog] Ejecutando registro"
                if (-not (Test-Administrator)) {
                    Show-WpfMessageBox -Message "Esta acción requiere permisos de administrador." -Title "Permisos requeridos" -Buttons OK -Icon Warning | Out-Null
                    return
                }
                $range = New-Object System.Windows.Documents.TextRange($rtb.Document.ContentStart, $rtb.Document.ContentEnd)
                $rawText = ($range.Text -replace "`r", "")
                $lines = $rawText -split "`n"
                $paths = @()
                $currentDir = $null
                foreach ($line in $lines) {
                    $trim = $line.Trim()
                    if ([string]::IsNullOrWhiteSpace($trim)) { continue }
                    if ($trim.StartsWith("#")) { continue }
                    if (Test-Path -LiteralPath $trim -PathType Container) {
                        $currentDir = $trim
                        continue
                    }
                    $candidate = $trim
                    if (-not [System.IO.Path]::IsPathRooted($candidate) -and $currentDir) { $candidate = Join-Path $currentDir $candidate }
                    $paths += $candidate
                }
                if (-not $paths -or $paths.Count -eq 0) {
                    Show-WpfMessageBox -Message "No se encontraron rutas válidas para procesar." -Title "Sin datos" -Buttons OK -Icon Warning | Out-Null
                    return
                }
                $isUnregister = ($c['rbUnregister'].IsChecked -eq $true)
                $success = @()
                $errors = @()
                foreach ($path in $paths) {
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                        $errors += "No existe: $path"
                        continue
                    }
                    $args = if ($isUnregister) { "/s /u `"$path`"" } else { "/s `"$path`"" }
                    Write-DzDebug "`t[DEBUG][Show-DllRegistrationDialog] regsvr32 $args"
                    try {
                        $proc = Start-Process -FilePath "regsvr32.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru
                        if ($proc.ExitCode -eq 0) { $success += $path } else { $errors += "Error ($($proc.ExitCode)) en: $path" }
                    } catch {
                        $errors += "Error en $path`: $($_.Exception.Message)"
                    }
                }
                $summary = @()
                if ($success.Count -gt 0) { $summary += "Procesados correctamente: $($success.Count)" }
                if ($errors.Count -gt 0) { $summary += "Errores: $($errors.Count)" }
                $detail = ($summary -join "`n")
                if ($errors.Count -gt 0) { $detail += "`n`nDetalles:`n$($errors -join "`n")" }
                $title = if ($errors.Count -gt 0) { "Proceso con errores" } else { "Proceso completado" }
                $icon = if ($errors.Count -gt 0) { "Warning" } else { "Information" }
                Show-WpfMessageBox -Message $detail -Title $title -Buttons OK -Icon $icon | Out-Null
            })
        $c['btnClose'].Add_Click({ $w.Close() })
        $w.ShowDialog() | Out-Null
    } catch {
        Write-DzDebug "`t[DEBUG][Show-DllRegistrationDialog] ERROR creando ventana: $($_.Exception.Message)" Red
        Show-WpfMessageBox -Message "No se pudo crear la ventana de registro de DLLs." -Title "Error" -Buttons OK -Icon Error | Out-Null
    }
    Write-DzDebug "`t[DEBUG][Show-DllRegistrationDialog] FIN"
}
function Check-Permissions {
    [CmdletBinding()]
    param(
        [string]$folderPath = "C:\NationalSoft",
        [System.Windows.Window]$Owner
    )
    $uiInfo = {
        param([string]$msg, [string]$title = "Información")
        if (Get-Command Ui-Info -ErrorAction SilentlyContinue) { Ui-Info -Message $msg -Title $title -Owner $Owner; return }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) { Show-WpfMessageBox -Message $msg -Title $title -Buttons OK -Icon Information -Owner $Owner | Out-Null; return }
        Write-Host $msg -ForegroundColor Cyan
    }.GetNewClosure()
    $uiWarn = {
        param([string]$msg, [string]$title = "Atención")
        if (Get-Command Ui-Warn -ErrorAction SilentlyContinue) { Ui-Warn -Message $msg -Title $title -Owner $Owner; return }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) { Show-WpfMessageBox -Message $msg -Title $title -Buttons OK -Icon Warning -Owner $Owner | Out-Null; return }
        Write-Host $msg -ForegroundColor Yellow
    }.GetNewClosure()
    $uiError = {
        param([string]$msg, [string]$title = "Error")
        if (Get-Command Ui-Error -ErrorAction SilentlyContinue) { Ui-Error -Message $msg -Title $title -Owner $Owner; return }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) { Show-WpfMessageBox -Message $msg -Title $title -Buttons OK -Icon Error -Owner $Owner | Out-Null; return }
        Write-Host $msg -ForegroundColor Red
    }.GetNewClosure()
    $uiConfirm = {
        param([string]$msg, [string]$title = "Confirmar")
        if (Get-Command Ui-Confirm -ErrorAction SilentlyContinue) { return (Ui-Confirm -Message $msg -Title $title -Owner $Owner) }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) {
            return ((Show-WpfMessageBox -Message $msg -Title $title -Buttons YesNo -Icon Question -Owner $Owner) -eq [System.Windows.MessageBoxResult]::Yes)
        }
        return $false
    }.GetNewClosure()
    Write-DzDebug "`t[DEBUG][Check-Permissions] INICIO folderPath='$folderPath'"
    if (-not (Test-Path -LiteralPath $folderPath)) {
        $msg = "La carpeta '$folderPath' no existe en este equipo.`r`nCrea la carpeta o corrige la ruta antes de continuar."
        Write-Host $msg -ForegroundColor Red
        & $uiWarn $msg "Carpeta no encontrada"
        return
    }
    try {
        $directoryInfo = [System.IO.DirectoryInfo]::new($folderPath)
        $acl = $directoryInfo.GetAccessControl()
    } catch {
        $msg1 = $_.Exception.Message
        if ($msg1 -match "Get-Acl.*m[oó]dulo 'Microsoft\.PowerShell\.Security'.*no pudo cargarse" -or $msg1 -match "Microsoft\.PowerShell\.Security") {
            try {
                Import-Module Microsoft.PowerShell.Security -ErrorAction Stop | Out-Null
            } catch {
                $msg2 = $_.Exception.Message
                if ($msg2 -match "TypeData" -or $msg2 -match "Ya existe el miembro" -or $msg2 -match "extended type data") {
                    try {
                        Import-Module Microsoft.PowerShell.Security -DisableNameChecking -ErrorAction Stop | Out-Null
                    } catch {
                        $errMsg = "No se pudo cargar el módulo Microsoft.PowerShell.Security.`r`n`r`n$($_.Exception.Message)"
                        Write-Host "Error cargando Microsoft.PowerShell.Security: $($_.Exception.Message)" -ForegroundColor Red
                        & $uiError $errMsg "Error de PowerShell"
                        return
                    }
                } else {
                    $errMsg = "No se pudo cargar el módulo Microsoft.PowerShell.Security.`r`n`r`n$msg2"
                    Write-Host "Error cargando Microsoft.PowerShell.Security: $msg2" -ForegroundColor Red
                    & $uiError $errMsg "Error de PowerShell"
                    return
                }
            }
            try {
                $acl = Get-Acl -LiteralPath $folderPath -ErrorAction Stop
            } catch {
                $errMsg = "Error obteniendo permisos de '$folderPath':`r`n$($_.Exception.Message)"
                Write-Host "Error obteniendo ACL de $folderPath : $($_.Exception.Message)" -ForegroundColor Red
                & $uiError $errMsg "Error al obtener permisos"
                return
            }
        } else {
            $errMsg = "Error obteniendo permisos de '$folderPath':`r`n$msg1"
            Write-Host "Error obteniendo ACL de $folderPath : $msg1" -ForegroundColor Red
            & $uiError $errMsg "Error al obtener permisos"
            return
        }
    }
    $permissions = @()
    $everyoneSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
    $everyonePermissions = @()
    $everyoneHasFullControl = $false
    $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])
    foreach ($access in $rules) {
        $permissions += [PSCustomObject]@{
            Usuario = $access.IdentityReference.Value
            Permiso = $access.FileSystemRights
            Tipo    = $access.AccessControlType
        }
        if ($access.IdentityReference.Value -match '^(Everyone|Todos)$') {
            $everyonePermissions += $access.FileSystemRights
            if ($access.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) { $everyoneHasFullControl = $true }
        }
    }
    Write-Host ""
    Write-Host "Permisos en $folderPath :" -ForegroundColor Cyan
    $permissions | ForEach-Object { Write-Host "`t$($_.Usuario) - $($_.Tipo) - $($_.Permiso)" -ForegroundColor Green }
    if ($everyonePermissions.Count -gt 0) { Write-Host "`tEveryone tiene: $($everyonePermissions -join ', ')" -ForegroundColor Green } else { Write-Host "`tNo hay permisos para 'Everyone'" -ForegroundColor Red }
    if (-not $everyoneHasFullControl) {
        $ask = "El usuario 'Everyone' no tiene permisos de 'Full Control'. ¿Deseas concederlo?"
        $doIt = & $uiConfirm $ask "Permisos 'Everyone'"
        if ($doIt) {
            try {
                if (-not (Test-Administrator)) {
                    & $uiWarn "Esta acción requiere permisos de administrador." "Permisos requeridos"
                    return
                }
                $directoryInfo = New-Object System.IO.DirectoryInfo($folderPath)
                $dirAcl = $directoryInfo.GetAccessControl()
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $everyoneSid,
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit",
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $dirAcl.AddAccessRule($accessRule)
                $dirAcl.SetAccessRuleProtection($false, $true)
                $directoryInfo.SetAccessControl($dirAcl)
                Write-Host "Se ha concedido 'Full Control' a 'Everyone'." -ForegroundColor Green
                & $uiInfo "Se ha concedido 'Full Control' a 'Everyone' en '$folderPath'." "Permisos actualizados"
            } catch {
                $errMsg = "Error aplicando permisos a '$folderPath':`r`n$($_.Exception.Message)"
                Write-Host "Error aplicando permisos: $($_.Exception.Message)" -ForegroundColor Red
                & $uiError $errMsg "Error al aplicar permisos"
            }
        }
    } else {
        $msg = "El usuario 'Everyone' ya tiene permisos de 'Full Control' en '$folderPath'."
        Write-Host $msg -ForegroundColor Green
        & $uiInfo $msg "Permisos OK"
    }
    Write-DzDebug "`t[DEBUG][Check-Permissions] FIN"
}
function Show-InstallerExtractorDialog {
    Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] INICIO"
    $theme = Get-DzUiTheme

    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Extractor de instalador"
        Height="350" Width="720"
        MinHeight="350" MinWidth="720"
        MaxHeight="350" MaxWidth="720"
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
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{DynamicResource PanelFg}"/>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Height" Value="34"/>
        </Style>

        <Style x:Key="BaseButtonStyle" TargetType="Button">
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Opacity" Value="1"/>
                    <Setter Property="Cursor" Value="Arrow"/>
                    <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
                    <Setter Property="Foreground" Value="{DynamicResource AccentMuted}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="ActionButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Background" Value="{DynamicResource AccentMagenta}"/>
            <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentMagentaHover}"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
                    <Setter Property="Foreground" Value="{DynamicResource AccentMuted}"/>
                    <Setter Property="BorderThickness" Value="1"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="OutlineButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentSecondary}"/>
                    <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
                    <Setter Property="BorderThickness" Value="0"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="CloseButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Width" Value="30"/>
            <Setter Property="Height" Value="26"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Content" Value="✕"/>
        </Style>
    </Window.Resources>

    <!-- CONTENEDOR REAL (como bdd_RenameFromTree) -->
    <Border Background="{DynamicResource FormBg}"
            BorderBrush="{DynamicResource BorderBrushColor}"
            BorderThickness="1"
            CornerRadius="12"
            Margin="10"
            SnapsToDevicePixels="True">

        <Border.Effect>
            <DropShadowEffect Color="Black"
                              Direction="270"
                              ShadowDepth="4"
                              BlurRadius="14"
                              Opacity="0.25"/>
        </Border.Effect>

        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="52"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Header draggable -->
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
                            Background="{DynamicResource AccentMagenta}"
                            Margin="0,4,10,4"/>

                    <StackPanel Grid.Column="1" Orientation="Vertical">
                        <TextBlock Text="Extractor de instalador"
                                   Foreground="{DynamicResource FormFg}"
                                   FontWeight="SemiBold"
                                   FontSize="12"/>
                        <TextBlock Text="Seleccione el instalador y el destino de extracción."
                                   Foreground="{DynamicResource AccentMuted}"
                                   FontSize="10"
                                   Margin="0,2,0,0"/>
                    </StackPanel>

                    <Button Grid.Column="2"
                            Name="btnClose"
                            Style="{StaticResource CloseButtonStyle}"
                            ToolTip="Cerrar"/>
                </Grid>
            </Border>

            <!-- Content -->
            <Grid Grid.Row="1" Margin="12,0,12,10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Panel principal -->
                <Border Grid.Row="0"
                        Background="{DynamicResource PanelBg}"
                        BorderBrush="{DynamicResource BorderBrushColor}"
                        BorderThickness="1"
                        CornerRadius="10"
                        Padding="12"
                        Margin="0,0,0,10">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <TextBlock Grid.Row="0" Text="Instalador (.exe)" Margin="0,0,0,6"/>
                        <Grid Grid.Row="1" Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button Name="btnPickInstaller"
                                    Content="📁"
                                    Width="42" Height="34"
                                    Margin="0,0,8,0"
                                    ToolTip="Seleccionar instalador"
                                    Style="{StaticResource OutlineButtonStyle}"/>
                            <TextBox Name="txtInstallerPath"
                                     Grid.Column="1"
                                     IsReadOnly="True"
                                     VerticalContentAlignment="Center"
                                     Text=""/>
                        </Grid>

                        <Border Grid.Row="2"
                                Background="{DynamicResource ControlBg}"
                                BorderBrush="{DynamicResource BorderBrushColor}"
                                BorderThickness="1"
                                CornerRadius="8"
                                Padding="10"
                                Margin="0,0,0,12">
                            <StackPanel>
                                <TextBlock Name="lblVersionInfo" Text="Versión: -"/>
                                <TextBlock Name="lblLastWrite" Text="Última modificación: -" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Border>

                        <TextBlock Grid.Row="3" Text="Destino" Margin="0,0,0,6"/>
                        <Grid Grid.Row="4">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button Name="btnPickDestination"
                                    Content="📁"
                                    Width="42" Height="34"
                                    Margin="0,0,8,0"
                                    ToolTip="Seleccionar destino"
                                    Style="{StaticResource OutlineButtonStyle}"/>
                            <TextBox Name="txtDestinationPath"
                                     Grid.Column="1"
                                     IsReadOnly="False"
                                     VerticalContentAlignment="Center"
                                     Text=""/>
                        </Grid>
                    </Grid>
                </Border>

                <!-- Footer -->
                <Grid Grid.Row="1" Margin="0,0,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Column="0"
                               Text="Enter: Extraer   |   Esc: Cerrar"
                               Foreground="{DynamicResource AccentMuted}"
                               VerticalAlignment="Center"/>

                    <StackPanel Grid.Column="1" Orientation="Horizontal">
                        <Button Name="btnCancel"
                                Content="Cancelar"
                                Width="120"
                                Height="34"
                                Margin="0,0,10,0"
                                IsCancel="True"
                                Style="{StaticResource OutlineButtonStyle}"/>
                        <Button Name="btnExtract"
                                Content="Extraer"
                                Width="140"
                                Height="34"
                                IsDefault="True"
                                Style="{StaticResource ActionButtonStyle}"/>
                    </StackPanel>
                </Grid>
            </Grid>

            <!-- (Opcional) si luego agregas status, puedes meter otro row aquí -->
        </Grid>
    </Border>
</Window>
"@

    try {
        $ui = New-WpfWindow -Xaml $stringXaml -PassThru
        $window = $ui.Window
        Set-DzWpfThemeResources -Window $window -Theme $theme
        try { Set-WpfDialogOwner -Dialog $window } catch {}
        $window.WindowStartupLocation = "Manual"
        $window.Add_Loaded({
                try {
                    $owner = $window.Owner
                    if (-not $owner) { $window.WindowStartupLocation = "CenterScreen"; return }
                    $ob = $owner.RestoreBounds
                    $targetW = $window.ActualWidth; if ($targetW -le 0) { $targetW = $window.Width }
                    $targetH = $window.ActualHeight; if ($targetH -le 0) { $targetH = $window.Height }
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
    } catch {
        Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] ERROR creando ventana: $($_.Exception.Message)" Red
        Show-WpfMessageBox -Message "No se pudo crear la ventana del extractor." -Title "Error" -Buttons OK -Icon Error | Out-Null
        return
    }

    $c = $ui.Controls

    $installerPath = $null
    $defaultFolderName = $null
    $destinationManuallySet = $false

    if ($c.ContainsKey('btnClose') -and $c['btnClose']) { $c['btnClose'].Add_Click({ $window.Close() }) }
    $header = $window.FindName("HeaderBar")
    if ($header) {
        $header.Add_MouseLeftButtonDown({
                param($sender, $e)
                if ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                    try { $window.DragMove() } catch {}
                }
            })
    }
    $updateStatus = {
        param([string]$msg)
        if ($c.ContainsKey('txtStatus') -and $c['txtStatus']) { $c['txtStatus'].Text = $msg }
    }

    $updateInstallerInfo = {
        param([string]$path)
        $c['lblVersionInfo'].Text = "Versión: -"
        $c['lblLastWrite'].Text = "Última modificación: -"
        Set-Variable -Name defaultFolderName -Value $null -Scope 1
        if ([string]::IsNullOrWhiteSpace($path)) { return }
        try {
            $file = Get-Item -Path $path -ErrorAction Stop
            $fileInfo = (Get-ItemProperty $file.FullName).VersionInfo
            $creationDate = $file.LastWriteTime
            $formattedDate = $creationDate.ToString("yyMMdd")
            $versionText = if ($fileInfo.FileVersion) { $fileInfo.FileVersion } else { "N/D" }
            $c['lblVersionInfo'].Text = "Versión: $versionText"
            $c['lblLastWrite'].Text = "Última modificación: $($creationDate.ToString('dd/MM/yyyy HH:mm')) ($formattedDate)"
            $computedDefault = if ($versionText -ne "N/D") { "$versionText`_$formattedDate" } else { $formattedDate }
            Set-Variable -Name defaultFolderName -Value $computedDefault -Scope 1
            if (-not $destinationManuallySet) { $c['txtDestinationPath'].Text = Join-Path "C:\Temp" $computedDefault }
        } catch {
            Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] ERROR leyendo info del instalador: $($_.Exception.Message)" Red
            Show-WpfMessageBox -Message "No se pudo leer la información del instalador." -Title "Error" -Buttons OK -Icon Error | Out-Null
        }
    }

    $c['btnPickInstaller'].Add_Click({
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Filter = "Instalador (*.exe)|*.exe"
                $dialog.Title = "Seleccionar instalador"
                $dialog.Multiselect = $false
                if ($dialog.ShowDialog() -ne $true) { return }
                $selectedPath = $dialog.FileName
                if ([System.IO.Path]::GetExtension($selectedPath).ToLowerInvariant() -ne ".exe") {
                    Show-WpfMessageBox -Message "El instalador debe ser un archivo .EXE." -Title "Formato inválido" -Buttons OK -Icon Warning | Out-Null
                    return
                }
                Set-Variable -Name installerPath -Value $selectedPath -Scope 1
                $c['txtInstallerPath'].Text = $selectedPath
                & $updateInstallerInfo $selectedPath
                & $updateStatus "Instalador seleccionado."
            } catch {
                Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] ERROR seleccionando instalador: $($_.Exception.Message)" Red
                Show-WpfMessageBox -Message "Error al seleccionar el instalador." -Title "Error" -Buttons OK -Icon Error | Out-Null
            }
        })

    $c['btnPickDestination'].Add_Click({
            try {
                $initialDir = "C:\Temp"
                if (-not [string]::IsNullOrWhiteSpace($c['txtDestinationPath'].Text)) {
                    $initialDir = Split-Path -Path $c['txtDestinationPath'].Text -Parent
                }
                $selectedFolder = Show-WpfFolderDialog -Description "Seleccionar destino de extracción" -InitialDirectory $initialDir
                if (-not $selectedFolder) { return }
                Set-Variable -Name destinationManuallySet -Value $true -Scope 1
                if ($defaultFolderName) {
                    $c['txtDestinationPath'].Text = Join-Path $selectedFolder $defaultFolderName
                } else {
                    $c['txtDestinationPath'].Text = $selectedFolder
                }
                & $updateStatus "Destino seleccionado."
            } catch {
                Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] ERROR seleccionando destino: $($_.Exception.Message)" Red
                Show-WpfMessageBox -Message "Error al seleccionar el destino." -Title "Error" -Buttons OK -Icon Error | Out-Null
            }
        })

    $c['btnExtract'].Add_Click({
            try {
                if (-not $installerPath) {
                    Show-WpfMessageBox -Message "Seleccione un instalador primero." -Title "Falta instalador" -Buttons OK -Icon Warning | Out-Null
                    return
                }
                if ([System.IO.Path]::GetExtension($installerPath).ToLowerInvariant() -ne ".exe") {
                    Show-WpfMessageBox -Message "El instalador debe ser un archivo .EXE." -Title "Formato inválido" -Buttons OK -Icon Warning | Out-Null
                    return
                }
                $destinationPath = $c['txtDestinationPath'].Text.Trim()
                if ([string]::IsNullOrWhiteSpace($destinationPath)) {
                    Show-WpfMessageBox -Message "Seleccione un destino válido." -Title "Falta destino" -Buttons OK -Icon Warning | Out-Null
                    return
                }
                if (-not (Test-Path -Path $destinationPath)) { New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null }
                $arguments = "/extract `"$destinationPath`""
                Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] Ejecutando: '$installerPath' $arguments"
                & $updateStatus "Extrayendo..."
                $proc = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
                if ($proc.ExitCode -ne 0) {
                    Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] ExitCode: $($proc.ExitCode)" Yellow
                    Show-WpfMessageBox -Message "El instalador devolvió código de salida $($proc.ExitCode)." -Title "Atención" -Buttons OK -Icon Warning | Out-Null
                    & $updateStatus "El instalador devolvió código $($proc.ExitCode)."
                    return
                }
                Show-WpfMessageBox -Message "Extracción completada en:`n$destinationPath" -Title "Éxito" -Buttons OK -Icon Information | Out-Null
                try {
                    if (Test-Path -Path $destinationPath) { Start-Process -FilePath "explorer.exe" -ArgumentList "`"$destinationPath`"" }
                } catch {
                    Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] No se pudo abrir Explorer: $($_.Exception.Message)" Yellow
                }
                $window.Close()
            } catch {
                Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] ERROR extracción: $($_.Exception.Message)" Red
                Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] Stack: $($_.ScriptStackTrace)" Red
                Show-WpfMessageBox -Message "Error al extraer el instalador." -Title "Error" -Buttons OK -Icon Error | Out-Null
            }
        })

    $c['btnCancel'].Add_Click({ $window.Close() })

    $window.ShowDialog() | Out-Null
    Write-DzDebug "`t[DEBUG][Show-InstallerExtractorDialog] FIN"
}
function Invoke-CreateApk {
    [CmdletBinding()]
    param(
        [string]$DllPath = "C:\Inetpub\wwwroot\ComanderoMovil\info\up.dll",
        [string]$InfoPath = "C:\Inetpub\wwwroot\ComanderoMovil\info\info.txt",
        [System.Windows.Controls.TextBlock]$InfoTextBlock
    )
    Write-DzDebug "`t[DEBUG][Invoke-CreateApk] INICIO" ([System.ConsoleColor]::DarkGray)
    try {
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Validando componentes..." }
        Write-Host "`nIniciando proceso de creación de APK..." -ForegroundColor Cyan
        if (-not (Test-Path -LiteralPath $DllPath)) {
            $msg = "Componente necesario no encontrado:`n$DllPath`n`nVerifique la instalación del Enlace Android."
            Write-Host $msg -ForegroundColor Red
            Show-WpfMessageBox -Message $msg -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: no existe up.dll" }
            return $false
        }
        if (-not (Test-Path -LiteralPath $InfoPath)) {
            $msg = "Archivo de configuración no encontrado:`n$InfoPath`n`nVerifique la instalación del Enlace Android."
            Write-Host $msg -ForegroundColor Red
            Show-WpfMessageBox -Message $msg -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: no existe info.txt" }
            return $false
        }
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Leyendo versión..." }
        $jsonContent = Get-Content -LiteralPath $InfoPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $versionApp = [string]$jsonContent.versionApp
        if ([string]::IsNullOrWhiteSpace($versionApp)) {
            $msg = "No se pudo leer 'versionApp' desde:`n$InfoPath"
            Write-Host $msg -ForegroundColor Red
            Show-WpfMessageBox -Message $msg -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: versionApp vacío" }
            return $false
        }
        Write-Host "Versión detectada: $versionApp" -ForegroundColor Green
        $confirmMsg = "Se creará el APK versión: $versionApp`n¿Desea continuar?"
        $confirmation = Show-WpfMessageBox -Message $confirmMsg -Title "Confirmación" -Buttons "YesNo" -Icon "Question"
        if ($confirmation -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-Host "Proceso cancelado por el usuario" -ForegroundColor Yellow
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Cancelado." }
            return $false
        }
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Selecciona dónde guardar..." }
        $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
        $saveDialog.Filter = "Archivo APK (*.apk)|*.apk"
        $saveDialog.FileName = "SRM_$versionApp.apk"
        $saveDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        if ($saveDialog.ShowDialog() -ne $true) {
            Write-Host "Guardado cancelado por el usuario" -ForegroundColor Yellow
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Guardado cancelado." }
            return $false
        }
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Copiando APK..." }
        Copy-Item -LiteralPath $DllPath -Destination $saveDialog.FileName -Force -ErrorAction Stop
        $okMsg = "APK generado exitosamente en:`n$($saveDialog.FileName)"
        Write-Host $okMsg -ForegroundColor Green
        Show-WpfMessageBox -Message "APK creado correctamente!" -Title "Éxito" -Buttons "OK" -Icon "Information" | Out-Null
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Listo: APK creado." }
        return $true
    } catch {
        $err = $_.Exception.Message
        Write-Host "Error durante el proceso: $err" -ForegroundColor Red
        Write-DzDebug "`t[DEBUG][Invoke-CreateApk] ERROR: $err`n$($_.ScriptStackTrace)" ([System.ConsoleColor]::Magenta)
        Show-WpfMessageBox -Message "Error durante la creación del APK:`n$err" -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: $err" }
        return $false
    }
}
function Show-NSApplicationsIniReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Resultados
    )
    $columnas = @("Aplicacion", "INI", "DataSource", "Catalog", "Usuario")
    $anchos = @{}
    foreach ($col in $columnas) { $anchos[$col] = $col.Length }
    foreach ($res in $Resultados) {
        foreach ($col in $columnas) {
            $val = [string]$res.$col
            if ($val.Length -gt $anchos[$col]) { $anchos[$col] = $val.Length }
        }
    }
    $titulos = $columnas | ForEach-Object { $_.PadRight($anchos[$_] + 2) }
    Write-Host ($titulos -join "") -ForegroundColor Cyan
    $separador = $columnas | ForEach-Object { ("-" * $anchos[$_]).PadRight($anchos[$_] + 2) }
    Write-Host ($separador -join "") -ForegroundColor Cyan
    foreach ($res in $Resultados) {
        $fila = $columnas | ForEach-Object { ([string]$res.$_).PadRight($anchos[$_] + 2) }
        if ($res.INI -eq "No encontrado") { Write-Host ($fila -join "") -ForegroundColor Red } else { Write-Host ($fila -join "") }
    }
    $found = @($Resultados | Where-Object { $_.INI -ne "No encontrado" })
    if (-not $found -or $found.Count -eq 0) { return }
    $theme = Get-DzUiTheme
    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Aplicaciones National Soft"
        Width="600" Height="300"
        MinWidth="600" MinHeight="300"
        MaxWidth="600" MaxHeight="300"
        WindowStartupLocation="CenterOwner"
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
                        <TextBlock Text="Aplicaciones National Soft"
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
                <DataGrid Name="dgApps" IsReadOnly="True">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Aplicación" Binding="{Binding Aplicacion}" Width="Auto"/>
                        <DataGridTextColumn Header="INI" Binding="{Binding INI}" Width="Auto"/>
                        <DataGridTextColumn Header="DataSource" Binding="{Binding DataSource}" Width="Auto"/>
                        <DataGridTextColumn Header="Catalog" Binding="{Binding Catalog}" Width="Auto"/>
                        <DataGridTextColumn Header="Usuario" Binding="{Binding Usuario}" Width="*"/>
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
        try {
            Set-WpfDialogOwner -Dialog $w
            try {
                if ($w.Owner) {
                    $w.WindowStartupLocation = "Manual"
                    $w.Top = $w.Owner.Top
                    $w.Left = $w.Owner.Left + $w.Owner.Width + 10
                }
            } catch {}
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
        $c['dgApps'].ItemsSource = $found
        $grid = $c['dgApps']
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
                        if ([string]::IsNullOrEmpty($value)) {
                            $value = [string]$item
                        }
                        Set-ClipboardTextSafe -Text $value -Owner $w | Out-Null
                        Write-Host "`n✅ Valor copiado al portapapeles: '$value'" -ForegroundColor Green
                    } catch {
                        Write-Host "`n❌ Error copiando celda: $($_.Exception.Message)" -ForegroundColor Red
                        Write-DzDebug "`t[DEBUG][Show-NSApplicationsIniReport] Error copiando celda: $($_.Exception.Message)"
                    }
                }.GetNewClosure())
            [void]$menu.Items.Add($menuItem)
            $grid.ContextMenu = $menu
        }
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
        $w.Show() | Out-Null
    } catch {
        Write-Host "`n❌ ERROR creando ventana: $($_.Exception.Message)" -ForegroundColor Red
        Write-DzDebug "`t[DEBUG][Show-NSApplicationsIniReport] ERROR creando ventana: $($_.Exception.Message)" Red
    }
}
function Invoke-CambiarOTMConfig {
    [CmdletBinding()]
    param(
        [string]$SyscfgPath = "C:\Windows\SysWOW64\Syscfg45_2.0.dll",
        [string]$IniPath = "C:\NationalSoft\OnTheMinute4.5",
        [System.Windows.Controls.TextBlock]$InfoTextBlock
    )
    Write-DzDebug "`t[DEBUG][Invoke-CambiarOTMConfig] INICIO" ([System.ConsoleColor]::DarkGray)
    try {
        if (-not (Test-Path -LiteralPath $SyscfgPath)) {
            Show-WpfMessageBox -Message "El archivo de configuración no existe:`n$SyscfgPath" -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
            Write-DzDebug "`t[DEBUG][OTM] Syscfg no existe: $SyscfgPath" ([System.ConsoleColor]::Red)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: no existe Syscfg." }
            return $false
        }
        if (-not (Test-Path -LiteralPath $IniPath)) {
            Show-WpfMessageBox -Message "No existe la ruta de INIs:`n$IniPath" -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
            Write-DzDebug "`t[DEBUG][OTM] IniPath no existe: $IniPath" ([System.ConsoleColor]::Red)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: no existe ruta INI." }
            return $false
        }
        $current = Get-OtmConfigFromSyscfg -SyscfgPath $SyscfgPath
        if (-not $current) {
            Show-WpfMessageBox -Message "No se detectó una configuración válida de SQL o DBF en:`n$SyscfgPath" -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
            Write-DzDebug "`t[DEBUG][OTM] No se detectó config válida" ([System.ConsoleColor]::Red)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: config inválida." }
            return $false
        }
        $ini = Get-OtmIniFiles -IniPath $IniPath
        if (-not $ini) {
            Show-WpfMessageBox -Message "No se encontraron los archivos INI esperados en:`n$IniPath" -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
            Write-DzDebug "`t[DEBUG][OTM] No se encontraron INIs esperados" ([System.ConsoleColor]::Red)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: faltan INIs." }
            return $false
        }
        $new = if ($current -eq "SQL") { "DBF" } else { "SQL" }
        $msg = "Actualmente tienes configurado: $current.`n¿Quieres cambiar a $new?"
        $res = Show-WpfMessageBox -Message $msg -Title "Cambiar Configuración" -Buttons "YesNo" -Icon "Question"
        if ($res -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-DzDebug "`t[DEBUG][OTM] Usuario canceló" ([System.ConsoleColor]::Cyan)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Operación cancelada." }
            return $false
        }
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Aplicando cambios..." }
        Set-OtmSyscfgConfig -SyscfgPath $SyscfgPath -Target $new
        Rename-OtmIniForTarget -Target $new -IniSqlFile $ini.SQL -IniDbfFile $ini.DBF
        Show-WpfMessageBox -Message "Configuración cambiada exitosamente a $new." -Title "Éxito" -Buttons "OK" -Icon "Information" | Out-Null
        Write-DzDebug "`t[DEBUG][OTM] OK cambiado a $new" ([System.ConsoleColor]::Green)
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Listo: cambiado a $new." }
        return $true
    } catch {
        $err = $_.Exception.Message
        Write-DzDebug "`t[DEBUG][Invoke-CambiarOTMConfig] ERROR: $err`n$($_.ScriptStackTrace)" ([System.ConsoleColor]::Magenta)
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: $err" }
        Show-WpfMessageBox -Message "Error: $err" -Title "Error" -Buttons "OK" -Icon "Error" | Out-Null
        return $false
    }
}
function Get-OtmConfigFromSyscfg {
    param(
        [Parameter(Mandatory)][string]$SyscfgPath
    )
    $fileContent = Get-Content -LiteralPath $SyscfgPath -ErrorAction Stop
    $isSQL = ($fileContent -match "494E5354414C4C=1") -and ($fileContent -match "56455253495354454D41=3")
    $isDBF = ($fileContent -match "494E5354414C4C=2") -and ($fileContent -match "56455253495354454D41=2")
    if ($isSQL) { return "SQL" }
    if ($isDBF) { return "DBF" }
    return $null
}
function Get-OtmIniFiles {
    param(
        [Parameter(Mandatory)][string]$IniPath
    )
    $iniFiles = Get-ChildItem -LiteralPath $IniPath -Filter "*.ini" -ErrorAction Stop
    if (-not $iniFiles -or $iniFiles.Count -eq 0) { return $null }
    $iniSQLFile = $null
    $iniDBFFile = $null
    foreach ($iniFile in $iniFiles) {
        $content = Get-Content -LiteralPath $iniFile.FullName -ErrorAction SilentlyContinue
        if (-not $iniDBFFile -and ($content -match "Provider=VFPOLEDB\.1")) { $iniDBFFile = $iniFile }
        if (-not $iniSQLFile -and ($content -match "Provider=SQLOLEDB\.1")) { $iniSQLFile = $iniFile }
        if ($iniSQLFile -and $iniDBFFile) { break }
    }
    if (-not $iniSQLFile -or -not $iniDBFFile) { return $null }
    return [pscustomobject]@{
        SQL = $iniSQLFile
        DBF = $iniDBFFile
        All = $iniFiles
    }
}
function Set-OtmSyscfgConfig {
    param(
        [Parameter(Mandatory)][string]$SyscfgPath,
        [Parameter(Mandatory)][ValidateSet("SQL", "DBF")][string]$Target
    )

    if ($Target -eq "SQL") {
        Write-DzDebug "`t[DEBUG][OTM] Cambiando Syscfg a SQL" ([System.ConsoleColor]::Yellow)

        (Get-Content -LiteralPath $SyscfgPath) `
            -replace "494E5354414C4C=2", "494E5354414C4C=1" `
            -replace "56455253495354454D41=2", "56455253495354454D41=3" |
        Set-Content -LiteralPath $SyscfgPath
    } else {
        Write-DzDebug "`t[DEBUG][OTM] Cambiando Syscfg a DBF" ([System.ConsoleColor]::Yellow)

        (Get-Content -LiteralPath $SyscfgPath) `
            -replace "494E5354414C4C=1", "494E5354414C4C=2" `
            -replace "56455253495354454D41=3", "56455253495354454D41=2" |
        Set-Content -LiteralPath $SyscfgPath
    }
}
function Rename-OtmIniForTarget {
    param(
        [Parameter(Mandatory)][ValidateSet("SQL", "DBF")][string]$Target,
        [Parameter(Mandatory)]$IniSqlFile,
        [Parameter(Mandatory)]$IniDbfFile
    )

    # Para evitar conflicto si "checadorsql.ini" ya existe, renombramos con cuidado:
    $iniDir = Split-Path -Parent $IniSqlFile.FullName
    $finalIni = Join-Path $iniDir "checadorsql.ini"

    if ($Target -eq "SQL") {
        # DBF -> backup
        Rename-Item -LiteralPath $IniDbfFile.FullName -NewName "checadorsql_DBF_old.ini" -ErrorAction Stop
        # SQL -> activo
        Rename-Item -LiteralPath $IniSqlFile.FullName -NewName "checadorsql.ini" -ErrorAction Stop
    } else {
        # SQL -> backup
        Rename-Item -LiteralPath $IniSqlFile.FullName -NewName "checadorsql_SQL_old.ini" -ErrorAction Stop
        # DBF -> activo
        Rename-Item -LiteralPath $IniDbfFile.FullName -NewName "checadorsql.ini" -ErrorAction Stop
    }
}
function Invoke-NSMonitorServicesLogSetup {
    [CmdletBinding()]
    param(
        [System.Windows.Window]$Owner
    )
    $uiInfo = {
        param([string]$msg, [string]$title = "Información")
        if (Get-Command Ui-Info -ErrorAction SilentlyContinue) { Ui-Info -Message $msg -Title $title -Owner $Owner; return }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) { Show-WpfMessageBox -Message $msg -Title $title -Buttons OK -Icon Information -Owner $Owner | Out-Null; return }
        Write-Host $msg -ForegroundColor Cyan
    }.GetNewClosure()
    $uiWarn = {
        param([string]$msg, [string]$title = "Atención")
        if (Get-Command Ui-Warn -ErrorAction SilentlyContinue) { Ui-Warn -Message $msg -Title $title -Owner $Owner; return }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) { Show-WpfMessageBox -Message $msg -Title $title -Buttons OK -Icon Warning -Owner $Owner | Out-Null; return }
        Write-Host $msg -ForegroundColor Yellow
    }.GetNewClosure()
    $uiError = {
        param([string]$msg, [string]$title = "Error")
        if (Get-Command Ui-Error -ErrorAction SilentlyContinue) { Ui-Error -Message $msg -Title $title -Owner $Owner; return }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) { Show-WpfMessageBox -Message $msg -Title $title -Buttons OK -Icon Error -Owner $Owner | Out-Null; return }
        Write-Host $msg -ForegroundColor Red
    }.GetNewClosure()
    $uiConfirm = {
        param([string]$msg, [string]$title = "Confirmar")
        if (Get-Command Ui-Confirm -ErrorAction SilentlyContinue) { return (Ui-Confirm -Message $msg -Title $title -Owner $Owner) }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) {
            return ((Show-WpfMessageBox -Message $msg -Title $title -Buttons YesNo -Icon Question -Owner $Owner) -eq [System.Windows.MessageBoxResult]::Yes)
        }
        return $false
    }.GetNewClosure()
    Write-DzDebug "`t[DEBUG][Invoke-NSMonitorServicesLogSetup] INICIO"
    $programRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique
    $monitorFolders = foreach ($root in $programRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -Path $root -Directory -Filter "MonitorServicios*" -ErrorAction SilentlyContinue
    }
    $monitorEntries = foreach ($dir in ($monitorFolders | Where-Object { $_ })) {
        $exePath = Join-Path $dir.FullName "ServiciosNS.exe"
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { continue }
        $versionText = ($dir.Name -replace "^MonitorServicios", "").Trim()
        if ([string]::IsNullOrWhiteSpace($versionText)) { $versionText = "Desconocida" }
        [pscustomobject]@{
            Name    = $dir.Name
            Path    = $dir.FullName
            Version = $versionText
        }
    }
    if (-not $monitorEntries -or $monitorEntries.Count -eq 0) {
        $uiWarn.Invoke("No se encontró una instalación válida de Monitor de Servicios en Program Files.`nSe requiere la carpeta 'MonitorServiciosX' con el ejecutable ServiciosNS.exe.")
        Write-DzDebug "`t[DEBUG][Invoke-NSMonitorServicesLogSetup] No hay instalaciones válidas" ([System.ConsoleColor]::Yellow)
        return
    }
    if ($monitorEntries.Count -gt 1) {
        $detalle = ($monitorEntries | Sort-Object Path | ForEach-Object { "- $($_.Path)" }) -join "`n"
        $msg = "Se detectaron varias instalaciones de Monitor de Servicios:`n$detalle`n`nEsto puede ocasionar errores. Se recomienda desinstalar las versiones sobrantes antes de continuar.`n¿Deseas continuar usando la versión más reciente?"
        if (-not $uiConfirm.Invoke($msg, "Múltiples instalaciones")) {
            Write-DzDebug "`t[DEBUG][Invoke-NSMonitorServicesLogSetup] Usuario canceló por múltiples instalaciones" ([System.ConsoleColor]::Yellow)
            return
        }
    }
    $selectedMonitor = $monitorEntries | Sort-Object -Property @{
        Expression = {
            $parsed = [version]"0.0"
            if ([version]::TryParse($_.Version, [ref]$parsed)) { $parsed } else { [version]"0.0" }
        }
    } -Descending | Select-Object -First 1
    $monitorPath = $selectedMonitor.Path
    Write-DzDebug "`t[DEBUG][Invoke-NSMonitorServicesLogSetup] Seleccionado: $monitorPath" ([System.ConsoleColor]::Cyan)
    $service = Get-Service -Name "SrvReportesSR" -ErrorAction SilentlyContinue
    $process = Get-Process -Name "ServiciosNS" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        $confirmStop = $uiConfirm.Invoke("El servicio 'ReportesSR' (SrvReportesSR) está en ejecución.`nPara activar el log es necesario detener el servicio.`n¿Deseas detenerlo ahora?", "Servicio en ejecución")
        if (-not $confirmStop) {
            $uiWarn.Invoke("Operación cancelada. El servicio debe estar detenido para continuar.")
            return
        }
        try {
            Stop-Service -Name "SrvReportesSR" -Force -ErrorAction Stop
            $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
        } catch {
            $uiError.Invoke("No se pudo detener el servicio SrvReportesSR.`n$($_.Exception.Message)")
            return
        }
    }
    if ($process) {
        $uiWarn.Invoke("ServiciosNS.exe está en ejecución.`nSe recomienda cerrarlo antes de continuar para evitar bloqueos.")
    }
    $configFiles = @("SrvReportesSR.exe.Config", "ServiciosNS.exe.Config")
    $updated = @()
    $skipped = @()
    foreach ($configName in $configFiles) {
        $configPath = Join-Path $monitorPath $configName
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            $skipped += $configPath
            continue
        }
        try {
            [xml]$xml = Get-Content -LiteralPath $configPath -Raw
        } catch {
            $skipped += $configPath
            continue
        }
        $appSettings = $xml.configuration.appSettings
        if (-not $appSettings) {
            $appSettings = $xml.CreateElement("appSettings")
            $xml.configuration.AppendChild($appSettings) | Out-Null
        }
        $logNode = $appSettings.SelectSingleNode("add[@key='log']")
        $logQueryNode = $appSettings.SelectSingleNode("add[@key='logQuery']")
        if ($logNode -and $logQueryNode) {
            $isEnabled = ($logNode.value -eq "true" -and $logQueryNode.value -eq "true")
            $prompt = if ($isEnabled) {
                "El log ya está activado en:`n$configPath`n¿Deseas desactivarlo?"
            } else {
                "El log está desactivado en:`n$configPath`n¿Deseas activarlo?"
            }
            if (-not $uiConfirm.Invoke($prompt, "Confirmar cambio")) { continue }
            $newValue = if ($isEnabled) { "false" } else { "true" }
            $logNode.SetAttribute("value", $newValue)
            $logQueryNode.SetAttribute("value", $newValue)
            $updated += "$configPath ($newValue)"
        } else {
            if (-not $logNode) {
                $logNode = $xml.CreateElement("add")
                $logNode.SetAttribute("key", "log")
                $logNode.SetAttribute("value", "true")
                $appSettings.AppendChild($logNode) | Out-Null
            }
            if (-not $logQueryNode) {
                $logQueryNode = $xml.CreateElement("add")
                $logQueryNode.SetAttribute("key", "logQuery")
                $logQueryNode.SetAttribute("value", "true")
                $appSettings.AppendChild($logQueryNode) | Out-Null
            }
            $updated += "$configPath (true)"
        }
        try {
            $xml.Save($configPath)
        } catch {
            $skipped += $configPath
            continue
        }
    }
    if ($updated.Count -gt 0) {
        $uiInfo.Invoke("Cambios aplicados en:`n$($updated -join "`n")", "Log actualizado")
    }
    if ($skipped.Count -gt 0) {
        $uiWarn.Invoke("No se pudieron actualizar estos archivos:`n$($skipped -join "`n")", "Archivos omitidos")
    }
    $monitorLocalPath = "C:\NationalSoft\MonitorLocal"
    if (-not (Test-Path -LiteralPath $monitorLocalPath)) {
        try {
            New-Item -Path $monitorLocalPath -ItemType Directory -Force | Out-Null
        } catch {
            $uiError.Invoke("No se pudo crear la carpeta:`n$monitorLocalPath`n$($_.Exception.Message)")
            return
        }
    }
    try {
        Start-Process -FilePath "explorer.exe" -ArgumentList "`"$monitorLocalPath`""
    } catch {
        $uiWarn.Invoke("No se pudo abrir la carpeta:`n$monitorLocalPath")
    }
    Write-DzDebug "`t[DEBUG][Invoke-NSMonitorServicesLogSetup] FIN"
}
Export-ModuleMember -Function @('Show-DllRegistrationDialog', 'Check-Permissions', 'Show-InstallerExtractorDialog', 'Invoke-CreateApk',
    'Invoke-CambiarOTMConfig', 'Show-NSApplicationsIniReport', 'Invoke-NSMonitorServicesLogSetup')