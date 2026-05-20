#requires -Version 5.0
#GUI.psm1 - Módulo de funciones GUI WPF para DzTools
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
function Get-DzUiTheme {
    $iniMode = "dark"
    if (Get-Command Get-DzUiMode -ErrorAction SilentlyContinue) { $iniMode = Get-DzUiMode }
    $themes = @{
        Light = @{
            FormBackground = "#F4F6F8"; FormForeground = "#111111"
            InfoBackground = "#FFFFFF"; InfoForeground = "#111111"
            InfoHoverBackground = "#FF8C00"; InfoHoverForeground = "#111111"
            ControlBackground = "#FFFFFF"; ControlForeground = "#111111"
            BorderColor = "#CFCFCF"
            ButtonGeneralBackground = "#E6E6E6"; ButtonGeneralForeground = "#111111"
            ButtonSystemBackground = "#FFB000"; ButtonSystemForeground = "#111111"
            ButtonNationalBackground = "#EA5C00"; ButtonNationalForeground = "#111111"
            ConsoleBackground = "#FFFFFF"; ConsoleForeground = "#111111"
            AccentPrimary = "#72a6f4"; AccentSecondary = "#2E7D32"; AccentMuted = "#6B7280"
            UiFontFamily = "Segoe UI"; UiFontSize = 12
            CodeFontFamily = "Consolas"; CodeFontSize = 12
            AccentBlue = "#FFB000"
            AccentBlueHover = "#E09B00"
            AccentOrange = "#EA5C00"
            AccentOrangeHover = "#D45200"
            AccentMagenta = "#DC267F"
            AccentMagentaHover = "#C21F72"
            AccentDatabase = "#A7C6DB"
            AccentDatabaseHover = "#93B4CC"
            OnAccentForeground = "#FFFFFF"
            AccentGreen = "#22C55E"
            AccentGreenHover = "#16A34A"
            AccentDisconnectBlue = "#3B82F6"
            AccentDisconnectBlueHover = "#2563EB"
            AccentRed = "#EF4444"
            AccentRedHover = "#DC2626"
            DbOnline = "#22C55E"           # Verde para ONLINE
            DbOffline = "#EF4444"          # Rojo para OFFLINE
            DbRestoring = "#F59E0B"        # Naranja para RESTORING/RECOVERING
            DbSuspect = "#A855F7"          # Púrpura para SUSPECT/EMERGENCY
            DbReadOnly = "#3B82F6"         # Azul para READ_ONLY
            DbSingleUser = "#F97316"       # Naranja claro para SINGLE_USER
            DbRestricted = "#EC4899"       # Rosa para RESTRICTED_USER

        }
        Dark  = @{
            FormBackground = "#000000"; FormForeground = "#FFFFFF"
            InfoBackground = "#1E1E1E"; InfoForeground = "#FFFFFF"
            InfoHoverBackground = "#FF8C00"; InfoHoverForeground = "#000000"
            ControlBackground = "#1C1C1C"; ControlForeground = "#FFFFFF"
            BorderColor = "#4C4C4C"
            ButtonGeneralBackground = "#2F2F2F"; ButtonGeneralForeground = "#FFFFFF"
            ButtonSystemBackground = "#FFB000"; ButtonSystemForeground = "#000000"
            ButtonNationalBackground = "#EA5C00"; ButtonNationalForeground = "#000000"
            ConsoleBackground = "#012456"; ConsoleForeground = "#FFFFFF"
            AccentPrimary = "#72a6f4"; AccentSecondary = "#4CAF50"; AccentMuted = "#9CA3AF"
            UiFontFamily = "Segoe UI"; UiFontSize = 12
            CodeFontFamily = "Consolas"; CodeFontSize = 12
            AccentBlue = "#FFB000"
            AccentBlueHover = "#E09B00"
            AccentOrange = "#EA5C00"
            AccentOrangeHover = "#D45200"
            AccentMagenta = "#DC267F"
            AccentMagentaHover = "#C21F72"
            AccentDatabase = "#A7C6DB"
            AccentDatabaseHover = "#93B4CC"
            OnAccentForeground = "#FFFFFF"
            AccentGreen = "#22C55E"
            AccentGreenHover = "#16A34A"
            AccentDisconnectBlue = "#3B82F6"
            AccentDisconnectBlueHover = "#2563EB"
            AccentRed = "#EF4444"
            AccentRedHover = "#DC2626"
            DbOnline = "#22C55E"           # Verde para ONLINE
            DbOffline = "#EF4444"          # Rojo para OFFLINE
            DbRestoring = "#F59E0B"        # Naranja para RESTORING/RECOVERING
            DbSuspect = "#A855F7"          # Púrpura para SUSPECT/EMERGENCY
            DbReadOnly = "#3B82F6"         # Azul para READ_ONLY
            DbSingleUser = "#F97316"       # Naranja claro para SINGLE_USER
            DbRestricted = "#EC4899"       # Rosa para RESTRICTED_USER
        }
    }
    $selectedMode = if ($iniMode -match '^(dark|light)$') { ($iniMode.Substring(0, 1).ToUpper() + $iniMode.Substring(1).ToLower()) } else { "Dark" }
    $themes[$selectedMode]
}
function New-WpfWindow {
    param([Parameter(Mandatory)][object]$Xaml, [switch]$PassThru)
    $xmlReader = $null; $stringReader = $null
    try {
        $xamlText = switch ($Xaml.GetType().FullName) {
            'System.String' { $Xaml }
            'System.Xml.XmlDocument' { $Xaml.OuterXml }
            default { [string]$Xaml }
        }
        if ([string]::IsNullOrWhiteSpace($xamlText)) { throw "XAML vacío o nulo." }
        $stringReader = New-Object System.IO.StringReader($xamlText)
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $xmlReader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        $window = [Windows.Markup.XamlReader]::Load($xmlReader)
        if ($PassThru) {
            [xml]$xmlDoc = $xamlText
            $controls = @{}
            $nodes = $xmlDoc.SelectNodes("//*[@Name]")
            foreach ($node in $nodes) {
                $n = $node.GetAttribute("Name")
                if (-not [string]::IsNullOrWhiteSpace($n)) {
                    $controls[$n] = $window.FindName($n)
                }
            }
            return @{ Window = $window; Controls = $controls }
        }
        $window
    } catch {
        Write-Error "Error cargando XAML: $($_.Exception.Message)"
        throw
    } finally {
        if ($xmlReader) { $xmlReader.Close() }
        if ($stringReader) { $stringReader.Close() }
    }
}
function Set-BrushResource {
    param([Parameter(Mandatory)][System.Windows.ResourceDictionary]$Resources, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Hex)
    if ([string]::IsNullOrWhiteSpace($Hex)) { throw "Theme error: el color para '$Key' llegó vacío/nulo." }
    if ($Hex -notmatch '^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$') { throw "Theme error: el color para '$Key' no es HEX válido: '$Hex' (usa #RRGGBB o #AARRGGBB)." }
    $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex)
    if ($brush -is [System.Windows.Freezable] -and $brush.CanFreeze) { $brush.Freeze() }
    $Resources[$Key] = $brush
}
function Set-DzWpfThemeResources {
    param([Parameter(Mandatory)][System.Windows.Window]$Window, [Parameter(Mandatory)]$Theme)
    Set-BrushResource -Resources $Window.Resources -Key "FormBg" -Hex $Theme.FormBackground
    Set-BrushResource -Resources $Window.Resources -Key "FormFg" -Hex $Theme.FormForeground
    Set-BrushResource -Resources $Window.Resources -Key "PanelBg" -Hex $Theme.InfoBackground
    Set-BrushResource -Resources $Window.Resources -Key "PanelFg" -Hex $Theme.InfoForeground
    Set-BrushResource -Resources $Window.Resources -Key "ControlBg" -Hex $Theme.ControlBackground
    Set-BrushResource -Resources $Window.Resources -Key "ControlFg" -Hex $Theme.ControlForeground
    Set-BrushResource -Resources $Window.Resources -Key "BorderBrushColor" -Hex $Theme.BorderColor
    Set-BrushResource -Resources $Window.Resources -Key "AccentPrimary" -Hex $Theme.AccentPrimary
    Set-BrushResource -Resources $Window.Resources -Key "AccentSecondary" -Hex $Theme.AccentSecondary
    Set-BrushResource -Resources $Window.Resources -Key "AccentMuted" -Hex $Theme.AccentMuted
    Set-BrushResource -Resources $Window.Resources -Key "ComboBoxBg" -Hex "#FFFFFF"
    Set-BrushResource -Resources $Window.Resources -Key "ComboBoxFg" -Hex "#111111"
    Set-BrushResource -Resources $Window.Resources -Key "ComboBoxBorder" -Hex $Theme.BorderColor
    Set-BrushResource -Resources $Window.Resources -Key "ComboBoxDropBg" -Hex "#FFFFFF"
    Set-BrushResource -Resources $Window.Resources -Key "ComboBoxDropFg" -Hex "#111111"
    Set-BrushResource -Resources $Window.Resources -Key "AccentBlue" -Hex $Theme.AccentBlue
    Set-BrushResource -Resources $Window.Resources -Key "AccentBlueHover" -Hex $Theme.AccentBlueHover
    Set-BrushResource -Resources $Window.Resources -Key "AccentOrange" -Hex $Theme.AccentOrange
    Set-BrushResource -Resources $Window.Resources -Key "AccentOrangeHover" -Hex $Theme.AccentOrangeHover
    Set-BrushResource -Resources $Window.Resources -Key "AccentMagenta" -Hex $Theme.AccentMagenta
    Set-BrushResource -Resources $Window.Resources -Key "AccentMagentaHover" -Hex $Theme.AccentMagentaHover
    Set-BrushResource -Resources $Window.Resources -Key "AccentDatabase" -Hex $Theme.AccentDatabase
    Set-BrushResource -Resources $Window.Resources -Key "AccentDatabaseHover" -Hex $Theme.AccentDatabaseHover
    Set-BrushResource -Resources $Window.Resources -Key "AccentGreen" -Hex $Theme.AccentGreen
    Set-BrushResource -Resources $Window.Resources -Key "AccentGreenHover" -Hex $Theme.AccentGreenHover
    Set-BrushResource -Resources $Window.Resources -Key "AccentDisconnectBlue" -Hex $Theme.AccentDisconnectBlue
    Set-BrushResource -Resources $Window.Resources -Key "AccentDisconnectBlueHover" -Hex $Theme.AccentDisconnectBlueHover
    Set-BrushResource -Resources $Window.Resources -Key "AccentRed" -Hex $Theme.AccentRed
    Set-BrushResource -Resources $Window.Resources -Key "AccentRedHover" -Hex $Theme.AccentRedHover
    Set-BrushResource -Resources $Window.Resources -Key "DbOnline" -Hex $Theme.DbOnline
    Set-BrushResource -Resources $Window.Resources -Key "DbOffline" -Hex $Theme.DbOffline
    Set-BrushResource -Resources $Window.Resources -Key "DbRestoring" -Hex $Theme.DbRestoring
    Set-BrushResource -Resources $Window.Resources -Key "DbSuspect" -Hex $Theme.DbSuspect
    Set-BrushResource -Resources $Window.Resources -Key "DbReadOnly" -Hex $Theme.DbReadOnly
    Set-BrushResource -Resources $Window.Resources -Key "DbSingleUser" -Hex $Theme.DbSingleUser
    Set-BrushResource -Resources $Window.Resources -Key "DbRestricted" -Hex $Theme.DbRestricted
    $onAccent = "#000000"
    if ($Theme -and $Theme.PSObject -and ($Theme.PSObject.Properties.Match('OnAccentForeground').Count -gt 0)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Theme.OnAccentForeground)) { $onAccent = [string]$Theme.OnAccentForeground }
    }
    Set-BrushResource -Resources $Window.Resources -Key "OnAccentFg" -Hex $onAccent
    $Window.Resources["UiFontFamily"] = [System.Windows.Media.FontFamily]::new($Theme.UiFontFamily)
    $Window.Resources["UiFontSize"] = [double]$Theme.UiFontSize
    $Window.Resources["CodeFontFamily"] = [System.Windows.Media.FontFamily]::new($Theme.CodeFontFamily)
    $Window.Resources["CodeFontSize"] = [double]$Theme.CodeFontSize
    try {
        $cbType = [Type]'System.Windows.Controls.ComboBox'
        $cbiType = [Type]'System.Windows.Controls.ComboBoxItem'
        $tbType = [Type]'System.Windows.Controls.TextBox'
        $bg = $Window.Resources["ComboBoxBg"]
        $fg = $Window.Resources["ComboBoxFg"]
        $brd = $Window.Resources["ComboBoxBorder"]
        $dropBg = $Window.Resources["ComboBoxDropBg"]
        $dropFg = $Window.Resources["ComboBoxDropFg"]
        if ($Window.Resources.Contains($cbType)) { $Window.Resources.Remove($cbType) }
        if ($Window.Resources.Contains($cbiType)) { $Window.Resources.Remove($cbiType) }
        $comboStyle = New-Object System.Windows.Style($cbType)
        [void]$comboStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BackgroundProperty, $bg)))
        [void]$comboStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $fg)))
        [void]$comboStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderBrushProperty, $brd)))
        [void]$comboStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderThicknessProperty, [System.Windows.Thickness]::new(1))))
        $editTbStyle = New-Object System.Windows.Style($tbType)
        $editTbStyle.BasedOn = $Window.TryFindResource($tbType)
        [void]$editTbStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BackgroundProperty, $bg)))
        [void]$editTbStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $fg)))
        [void]$editTbStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderThicknessProperty, [System.Windows.Thickness]::new(0))))
        if ([System.Windows.Controls.ComboBox]::TextBoxStyleProperty -ne $null) {
            $comboStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ComboBox]::TextBoxStyleProperty, $editTbStyle)))
        }
        $itemStyle = New-Object System.Windows.Style($cbiType)
        [void]$itemStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BackgroundProperty, $dropBg)))
        [void]$itemStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $dropFg)))
        [void]$itemStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::PaddingProperty, [System.Windows.Thickness]::new(6, 4, 6, 4))))
        $tHover = New-Object System.Windows.Trigger
        $tHover.Property = [System.Windows.Controls.ComboBoxItem]::IsHighlightedProperty
        $tHover.Value = $true
        [void]$tHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BackgroundProperty, $Window.Resources["AccentPrimary"])))
        [void]$tHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $Window.Resources["OnAccentFg"])))
        $tSel = New-Object System.Windows.Trigger
        $tSel.Property = [System.Windows.Controls.Primitives.Selector]::IsSelectedProperty
        $tSel.Value = $true
        [void]$tSel.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BackgroundProperty, $Window.Resources["AccentPrimary"])))
        [void]$tSel.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $Window.Resources["OnAccentFg"])))
        [void]$itemStyle.Triggers.Add($tHover)
        [void]$itemStyle.Triggers.Add($tSel)
        $Window.Resources.Add($cbType, $comboStyle)
        $Window.Resources.Add($cbiType, $itemStyle)
    } catch {
        Write-DzDebug "`t[DEBUG] ComboBox unified (light-like) style failed: $($_.Exception.Message)" -Color DarkGray
    }
}
function Set-WpfDialogOwner {
    param([Parameter(Mandatory)][System.Windows.Window]$Dialog)
    try { if ($Global:window -is [System.Windows.Window]) { $Dialog.Owner = $Global:window; return } } catch {}
    try { if ($Global:MainWindow -is [System.Windows.Window]) { $Dialog.Owner = $Global:MainWindow; return } } catch {}
    try { if ($script:window -is [System.Windows.Window]) { $Dialog.Owner = $script:window; return } } catch {}
}
function ConvertTo-MessageBoxResult {
    param([object]$Value)
    if ($null -eq $Value) { return [System.Windows.MessageBoxResult]::None }
    if ($Value -is [System.Windows.MessageBoxResult]) { return $Value }
    if ($Value -is [int]) {
        switch ($Value) {
            6 { return [System.Windows.MessageBoxResult]::Yes }
            7 { return [System.Windows.MessageBoxResult]::No }
            2 { return [System.Windows.MessageBoxResult]::Cancel }
            1 { return [System.Windows.MessageBoxResult]::OK }
            default { return [System.Windows.MessageBoxResult]::None }
        }
    }
    $s = ($Value.ToString()).Trim().ToLowerInvariant()
    switch ($s) {
        'yes' { [System.Windows.MessageBoxResult]::Yes }
        'no' { [System.Windows.MessageBoxResult]::No }
        'cancel' { [System.Windows.MessageBoxResult]::Cancel }
        'ok' { [System.Windows.MessageBoxResult]::OK }
        'true' { [System.Windows.MessageBoxResult]::Yes }
        'false' { [System.Windows.MessageBoxResult]::No }
        default { [System.Windows.MessageBoxResult]::None }
    }
}
function Show-WpfMessageBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = "Mensaje",
        [ValidateSet("OK", "OKCancel", "YesNo", "YesNoCancel")][string]$Buttons = "OK",
        [ValidateSet("Information", "Warning", "Error", "Question")][string]$Icon = "Information",
        [System.Windows.Window]$Owner
    )

    try {
        $safeTitle = [Security.SecurityElement]::Escape($Title)
        $safeMsg = [Security.SecurityElement]::Escape($Message)

        $subtitle = switch ($Icon) {
            "Information" { "Información" }
            "Warning" { "Atención" }
            "Error" { "Error" }
            "Question" { "Confirmación" }
            default { "Mensaje" }
        }
        $safeSubtitle = [Security.SecurityElement]::Escape($subtitle)

        $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$safeTitle"
        Width="560" Height="260"
        MinWidth="560" MinHeight="260"
        MaxWidth="560" MaxHeight="260"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="True"
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

    <Style x:Key="SecondaryButtonStyle"
           TargetType="Button"
           BasedOn="{StaticResource PrimaryButtonStyle}">
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
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource PanelBg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
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
            <TextBlock Text="$safeTitle"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Name="txtSubtitle"
                       Text="$safeSubtitle"
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
              Background="{DynamicResource ControlBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="12"
              Margin="12,0,12,10">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <Border Grid.Column="0"
                  Width="44" Height="44"
                  CornerRadius="12"
                  Background="{DynamicResource PanelBg}"
                  BorderBrush="{DynamicResource BorderBrushColor}"
                  BorderThickness="1"
                  VerticalAlignment="Top">
            <TextBlock Name="txtIcon"
                       Text="i"
                       FontSize="20"
                       FontWeight="Bold"
                       HorizontalAlignment="Center"
                       VerticalAlignment="Center"
                       Foreground="{DynamicResource AccentPrimary}"/>
          </Border>

          <TextBlock Grid.Column="1"
                     Name="txtMessage"
                     Text="$safeMsg"
                     TextWrapping="Wrap"
                     Margin="12,2,0,0"
                     Foreground="{DynamicResource PanelFg}"/>
        </Grid>
      </Border>

      <Grid Grid.Row="2" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Column="0"
                   Name="txtFooterHint"
                   Text="Enter: Aceptar   |   Esc: Cerrar"
                   Foreground="{DynamicResource AccentMuted}"
                   VerticalAlignment="Center"/>

        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button Name="btn1"
                  Content="Cancelar"
                  Style="{StaticResource SecondaryButtonStyle}"
                  Width="120"
                  Margin="0,0,10,0"
                  Visibility="Collapsed"/>
          <Button Name="btn2"
                  Content="No"
                  Style="{StaticResource SecondaryButtonStyle}"
                  Width="120"
                  Margin="0,0,10,0"
                  Visibility="Collapsed"/>
          <Button Name="btn3"
                  Content="Aceptar"
                  Style="{StaticResource PrimaryButtonStyle}"
                  Width="140"
                  Visibility="Collapsed"/>
        </StackPanel>
      </Grid>

    </Grid>
  </Border>
</Window>
"@

        $ui = New-WpfWindow -Xaml $xaml -PassThru
        if (-not $ui -or -not $ui.Window) { throw "Show-WpfMessageBox: ventana no creada." }

        $w = $ui.Window
        $c = $ui.Controls

        $dzState = @{ Result = [System.Windows.MessageBoxResult]::None; Completed = $false }

        $theme = Get-DzUiTheme
        try { Set-DzWpfThemeResources -Window $w -Theme $theme } catch {}

        try {
            if ($Owner) { $w.Owner = $Owner }
            else {
                try { if (-not $w.Owner -and $global:MainWindow -is [System.Windows.Window]) { $w.Owner = $global:MainWindow } } catch {}
            }
        } catch {}

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

        if ($c['HeaderBar']) {
            $c['HeaderBar'].Add_MouseLeftButtonDown({
                    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                        try { $w.DragMove() } catch {}
                    }
                })
        }

        $txtIcon = $c['txtIcon']
        if ($txtIcon) {
            switch ($Icon) {
                "Information" { $txtIcon.Text = "i"; try { $txtIcon.Foreground = $w.FindResource("AccentPrimary") } catch {} }
                "Warning" { $txtIcon.Text = "!"; try { $txtIcon.Foreground = $w.FindResource("AccentOrange") } catch {} }
                "Error" { $txtIcon.Text = "×"; try { $txtIcon.Foreground = $w.FindResource("AccentRed") } catch {} }
                "Question" { $txtIcon.Text = "?"; try { $txtIcon.Foreground = $w.FindResource("AccentSecondary") } catch {} }
            }
        }

        $btnClose = $c['btnClose']
        $btn1 = $c['btn1']
        $btn2 = $c['btn2']
        $btn3 = $c['btn3']

        $allButtons = @($btn1, $btn2, $btn3, $btnClose) | Where-Object { $_ }

        $w.Add_Closing({
                if (-not $dzState.Completed) {
                    $dzState.Result = [System.Windows.MessageBoxResult]::Cancel
                    $dzState.Completed = $true
                }
            }.GetNewClosure())

        $finish = {
            param([System.Windows.MessageBoxResult]$rv)
            if ($dzState.Completed) { return }
            $dzState.Result = $rv
            $dzState.Completed = $true
            foreach ($b in $allButtons) { try { $b.IsEnabled = $false } catch {} }
            try { $w.DialogResult = $true } catch {}
            try { $w.Close() } catch {}
        }.GetNewClosure()

        $setBtn = {
            param(
                $btn,
                [string]$text,
                [System.Windows.MessageBoxResult]$rv,
                [bool]$isPrimary,
                [bool]$isCancel
            )
            if (-not $btn) { return }
            $btn.Content = $text
            $btn.Visibility = "Visible"
            $btn.IsDefault = $false
            $btn.IsCancel = $false
            if ($isPrimary) { $btn.IsDefault = $true }
            if ($isCancel) { $btn.IsCancel = $true }

            $localText = $text
            $localRv = $rv
            $localFinish = $finish
            $btn.Add_Click({
                    $localFinish.Invoke($localRv)
                }.GetNewClosure())
        }.GetNewClosure()

        if ($btnClose) {
            $localFinish2 = $finish
            $btnClose.Add_Click({
                    $localFinish2.Invoke([System.Windows.MessageBoxResult]::Cancel)
                }.GetNewClosure())
        }

        $hint = switch ($Buttons) {
            "OK" { "Enter: OK   |   Esc: Cerrar" }
            "OKCancel" { "Enter: OK   |   Esc: Cancelar" }
            "YesNo" { "Enter: Sí   |   Esc: No" }
            "YesNoCancel" { "Enter: Sí   |   Esc: Cancelar" }
        }
        if ($c['txtFooterHint']) { $c['txtFooterHint'].Text = $hint }

        foreach ($b in @($btn1, $btn2, $btn3)) { if ($b) { $b.Visibility = "Collapsed" } }

        switch ($Buttons) {
            "OK" {
                $setBtn.Invoke($btn3, "OK", ([System.Windows.MessageBoxResult]::OK), $true, $false)
            }
            "OKCancel" {
                $setBtn.Invoke($btn2, "Cancelar", ([System.Windows.MessageBoxResult]::Cancel), $false, $true)
                $setBtn.Invoke($btn3, "OK", ([System.Windows.MessageBoxResult]::OK), $true, $false)
            }
            "YesNo" {
                $setBtn.Invoke($btn2, "No", ([System.Windows.MessageBoxResult]::No), $false, $true)
                $setBtn.Invoke($btn3, "Sí", ([System.Windows.MessageBoxResult]::Yes), $true, $false)
            }
            "YesNoCancel" {
                $setBtn.Invoke($btn1, "Cancelar", ([System.Windows.MessageBoxResult]::Cancel), $false, $true)
                $setBtn.Invoke($btn2, "No", ([System.Windows.MessageBoxResult]::No), $false, $false)
                $setBtn.Invoke($btn3, "Sí", ([System.Windows.MessageBoxResult]::Yes), $true, $false)
            }
        }

        $w.Add_PreviewKeyDown({
                param($sender, $e)
                if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                    $finish.Invoke([System.Windows.MessageBoxResult]::Cancel)
                    $e.Handled = $true
                }
            }.GetNewClosure())

        $null = $w.ShowDialog()
        return [System.Windows.MessageBoxResult]$dzState.Result
    } catch {
        Write-Warning "Show-WpfMessageBox falló: $($_.Exception.Message)"
        switch ($Buttons) {
            "YesNo" { return [System.Windows.MessageBoxResult]::No }
            "YesNoCancel" { return [System.Windows.MessageBoxResult]::Cancel }
            "OKCancel" { return [System.Windows.MessageBoxResult]::Cancel }
            default { return [System.Windows.MessageBoxResult]::OK }
        }
    }
}

function Show-WpfMessageBoxSafe {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][ValidateSet("OK", "OKCancel", "YesNo", "YesNoCancel")][string]$Buttons,
        [Parameter(Mandatory)][ValidateSet("Information", "Warning", "Error", "Question")][string]$Icon,
        [System.Windows.Window]$Owner
    )
    ConvertTo-MessageBoxResult (Show-WpfMessageBox -Message $Message -Title $Title -Buttons $Buttons -Icon $Icon -Owner $Owner)
}
function Show-WpfProgressBar {
    param([string]$Title = "Procesando", [string]$Message = "Por favor espere...")
    $theme = Get-DzUiTheme
    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="$Title" Height="220" Width="500" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" FontFamily="{DynamicResource UiFontFamily}" FontSize="{DynamicResource UiFontSize}">
  <Border Background="{DynamicResource FormBg}" CornerRadius="8" BorderBrush="{DynamicResource AccentPrimary}" BorderThickness="2" Padding="20">
    <Border.Effect><DropShadowEffect Color="Black" Direction="270" ShadowDepth="5" BlurRadius="15" Opacity="0.3"/></Border.Effect>
    <StackPanel>
      <TextBlock Text="$Title" FontWeight="Bold" Foreground="{DynamicResource AccentPrimary}" HorizontalAlignment="Center" Margin="0,0,0,20"/>
      <TextBlock Name="lblMessage" Text="$Message" Foreground="{DynamicResource FormFg}" TextAlignment="Center" TextWrapping="Wrap" Margin="0,0,0,15" MinHeight="30"/>
      <ProgressBar Name="progressBar" Height="25" Minimum="0" Maximum="100" IsIndeterminate="True" Value="0" Foreground="{DynamicResource AccentSecondary}" Background="{DynamicResource ControlBg}" Margin="0,0,0,10"/>
      <TextBlock Name="lblPercent" Text="0%" FontWeight="Bold" Foreground="{DynamicResource AccentPrimary}" HorizontalAlignment="Center"/>
    </StackPanel>
  </Border>
</Window>
"@
    try {
        $result = New-WpfWindow -Xaml $stringXaml -PassThru
        $window = $result.Window
        Set-DzWpfThemeResources -Window $window -Theme $theme
        $window | Add-Member -MemberType NoteProperty -Name ProgressBar -Value $result.Controls['progressBar'] | Out-Null
        $window | Add-Member -MemberType NoteProperty -Name MessageLabel -Value $result.Controls['lblMessage'] | Out-Null
        $window | Add-Member -MemberType NoteProperty -Name PercentLabel -Value $result.Controls['lblPercent'] | Out-Null
        $window | Add-Member -MemberType NoteProperty -Name IsClosed -Value $false | Out-Null
        $window.Add_Closed({ $window.IsClosed = $true })
        $window.Show()
        $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action] {}) | Out-Null
        $window
    } catch {
        Write-Error "Error al crear barra de progreso: $_"
        $null
    }
}
function Update-WpfProgressBar {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Window]$Window,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100)][int]$Percent,
        [string]$Message = $null
    )
    if ($null -eq $Window) { return }
    if ($Window.PSObject.Properties.Match('IsClosed').Count -gt 0 -and $Window.IsClosed) { return }
    if ($null -eq $Window.Dispatcher -or $Window.Dispatcher.HasShutdownStarted) { return }
    $p = [Math]::Min($Percent, 100)
    $m = $Message
    $doUpdate = {
        try {
            if ($Window.PSObject.Properties.Match('IsClosed').Count -gt 0 -and $Window.IsClosed) { return }
            if ($Window.PSObject.Properties.Match('ProgressBar').Count -gt 0 -and $Window.ProgressBar) {
                $Window.ProgressBar.IsIndeterminate = $false
                $Window.ProgressBar.Value = $p
            }
            if ($Window.PSObject.Properties.Match('PercentLabel').Count -gt 0 -and $Window.PercentLabel) {
                $Window.PercentLabel.Text = "$p%"
            }
            if (-not [string]::IsNullOrWhiteSpace($m) -and $Window.PSObject.Properties.Match('MessageLabel').Count -gt 0 -and $Window.MessageLabel) {
                $Window.MessageLabel.Text = $m
            }
        } catch {
            if (-not ($Window.PSObject.Properties.Match('IsClosed').Count -gt 0 -and $Window.IsClosed)) {
                Write-Warning "Error actualizando ProgressBar: $($_.Exception.Message)"
            }
        }
    }
    try {
        if ($Window.Dispatcher.CheckAccess()) { & $doUpdate }
        else {
            $Window.Dispatcher.Invoke(
                [System.Windows.Threading.DispatcherPriority]::Normal,
                $doUpdate
            )
        }
    } catch {
        if (-not ($Window.PSObject.Properties.Match('IsClosed').Count -gt 0 -and $Window.IsClosed)) {
            Write-DzDebug "ERROR actualizando ProgressBar: $($_.Exception.Message)" -Color Red
        }
    }
}
function Close-WpfProgressBar {
    param([Parameter(Mandatory = $true)]$Window)
    if ($null -eq $Window) { return }
    if (-not ($Window -is [System.Windows.Window])) { Write-Warning "Close-WpfProgressBar: El objeto recibido NO es WPF Window. Tipo: $($Window.GetType().FullName)"; return }
    if ($Window.PSObject.Properties.Match('IsClosed').Count -gt 0 -and $Window.IsClosed) { return }
    if ($null -eq $Window.Dispatcher -or $Window.Dispatcher.HasShutdownStarted -or $Window.Dispatcher.HasShutdownFinished) { return }
    try { $Window.Dispatcher.Invoke([action] { if (-not $Window.IsClosed) { $Window.Close() } }, [System.Windows.Threading.DispatcherPriority]::Normal) } catch { Write-Warning "Error cerrando barra de progreso: $($_.Exception.Message)" }
}
function Show-ProgressBar { Show-WpfProgressBar -Title "Progreso de Actualización" -Message "Iniciando proceso..." }
function Set-WpfControlEnabled {
    param([Parameter(Mandatory = $true)]$Control, [Parameter(Mandatory = $true)][bool]$Enabled)
    if ($null -eq $Control) { Write-Warning "Control es null."; return }
    try {
        if ($Control.Dispatcher.CheckAccess()) { $Control.IsEnabled = $Enabled }
        else { $Control.Dispatcher.Invoke([action] { $Control.IsEnabled = $Enabled }) }
    } catch {
        Write-Warning "Error cambiando estado del control: $_"
    }
}
function New-WpfInputDialog {
    param([string]$Title = "Entrada", [string]$Prompt = "Ingrese un valor:", [string]$DefaultValue = "")
    $theme = Get-DzUiTheme
    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="$Title" Height="180" Width="400" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" ShowInTaskbar="False" Background="{DynamicResource FormBg}" FontFamily="{DynamicResource UiFontFamily}" FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{DynamicResource FormFg}"/></Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,4"/>
    </Style>
    <Style x:Key="SystemButtonStyle" TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,6"/>
    </Style>
  </Window.Resources>
  <StackPanel Margin="20" Background="{DynamicResource FormBg}">
    <TextBlock Text="$Prompt" Margin="0,0,0,10"/>
    <TextBox Name="txtInput" Text="$DefaultValue" Margin="0,0,0,20"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="btnOK" Content="Aceptar" Width="90" Margin="0,0,10,0" IsDefault="True" Style="{StaticResource SystemButtonStyle}"/>
      <Button Name="btnCancel" Content="Cancelar" Width="90" IsCancel="True" Background="{DynamicResource ControlBg}" Foreground="{DynamicResource ControlFg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" Padding="10,6"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $result = New-WpfWindow -Xaml $stringXaml -PassThru
    $window = $result.Window
    Set-DzWpfThemeResources -Window $window -Theme $theme
    $controls = $result.Controls
    $script:inputValue = $null
    $script:__inputOk = $false
    $controls['btnOK'].Add_Click({ $script:inputValue = $controls['txtInput'].Text; $script:__inputOk = $true; $window.Close() })
    $controls['btnCancel'].Add_Click({ $script:__inputOk = $false; $window.Close() })
    $null = $window.ShowDialog()
    if ($script:__inputOk) { return $script:inputValue }
    return $null
}
function Get-WpfPasswordBoxText {
    param([Parameter(Mandatory = $true)][System.Windows.Controls.PasswordBox]$PasswordBox)
    $PasswordBox.Password
}
function Show-WpfFolderDialog {
    param([string]$Description = "Seleccione una carpeta", [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop'))
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { Write-Warning "Show-WpfFolderDialog requiere STA. Ejecuta PowerShell con -STA."; return $null }
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.SelectedPath = $InitialDirectory
    $dialog.ShowNewFolderButton = $true
    $r = $dialog.ShowDialog()
    if ($r -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.SelectedPath } else { $null }
}
function Ui-Info {
    param(        [string]$Message, [string]$Title = "Información", [System.Windows.Window]$Owner    )
    Show-WpfMessageBoxSafe -Message $Message -Title $Title -Buttons "OK" -Icon "Information" -Owner $Owner | Out-Null
}
function Ui-Warn {
    param(        [string]$Message, [string]$Title = "Atención", [System.Windows.Window]$Owner    )
    Show-WpfMessageBoxSafe -Message $Message -Title $Title -Buttons "OK" -Icon "Warning" -Owner $Owner | Out-Null
}
function Ui-Error {
    param(        [string]$Message, [string]$Title = "Error", [System.Windows.Window]$Owner    )
    Show-WpfMessageBoxSafe -Message $Message -Title $Title -Buttons "OK" -Icon "Error" -Owner $Owner | Out-Null
}
function Ui-Confirm {
    param(        [string]$Message, [string]$Title = "Confirmar", [System.Windows.Window]$Owner    )
    (Show-WpfMessageBoxSafe `
        -Message $Message `
        -Title $Title `
        -Buttons "YesNo" `
        -Icon "Question" `
        -Owner $Owner
    ) -eq [System.Windows.MessageBoxResult]::Yes
}
function Get-MainWindowXaml {
    param([hashtable]$Theme)
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Gerardo Zermeño Tools"
        Height="650" Width="900" MinHeight="600" MinWidth="1000"
        WindowStartupLocation="CenterScreen" WindowState="Normal"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
    <Window.Resources>
        <Style TargetType="{x:Type Control}">
            <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
            <Setter Property="FontSize" Value="{DynamicResource UiFontSize}"/>
        </Style>
        <Style TargetType="{x:Type TextBlock}">
            <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
            <Setter Property="FontSize" Value="{DynamicResource UiFontSize}"/>
            <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
        </Style>
        <Style TargetType="{x:Type Label}">
            <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
        </Style>
        <Style TargetType="{x:Type TabControl}">
            <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource PanelFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="{x:Type TabItem}">
            <Setter Property="Foreground" Value="{DynamicResource PanelFg}"/>
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="2,0,0,0"/>
            <Setter Property="Template">
                <Setter.Value>
                <ControlTemplate TargetType="{x:Type TabItem}">
                    <Grid>
                    <Border
                        x:Name="Bd"
                        Background="{TemplateBinding Background}"
                        BorderBrush="{TemplateBinding BorderBrush}"
                        BorderThickness="{TemplateBinding BorderThickness}"
                        CornerRadius="6,6,0,0"
                        Padding="{TemplateBinding Padding}">
                        <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    </Grid>
                    <ControlTemplate.Triggers>
                    <!-- TAB NO SELECCIONADA -->
                    <Trigger Property="IsSelected" Value="False">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource ControlBg}"/>
                        <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
                    </Trigger>

                    <!-- TAB SELECCIONADA: COLOREA TODO -->
                    <Trigger Property="IsSelected" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentPrimary}"/>
                        <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                        <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
                    </Trigger>

                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                    </Trigger>

                    <Trigger Property="IsEnabled" Value="False">
                        <Setter Property="Opacity" Value="0.55"/>
                    </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
                </Setter.Value>
            </Setter>
            </Style>
        <Style TargetType="{x:Type TextBox}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
        </Style>
        <Style TargetType="{x:Type PasswordBox}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
        </Style>
        <Style TargetType="{x:Type ComboBox}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="{x:Type CheckBox}">
            <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
        </Style>
        <Style TargetType="{x:Type RichTextBox}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
        </Style>
        <Style TargetType="{x:Type Paragraph}">
            <Setter Property="Margin" Value="0"/>
        </Style>
        <Style TargetType="{x:Type DataGrid}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="RowBackground" Value="{DynamicResource ControlBg}"/>
            <Setter Property="AlternatingRowBackground" Value="{DynamicResource PanelBg}"/>
        </Style>
        <Style TargetType="{x:Type DataGridRow}">
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
                    <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="{x:Type DataGridColumnHeader}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
        </Style>
        <Style TargetType="{x:Type DataGridCell}">
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
        </Style>
        <Style x:Key="InfoHeaderTextBoxStyle" TargetType="{x:Type TextBox}" BasedOn="{StaticResource {x:Type TextBox}}">
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="TextAlignment" Value="Center"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="IsTabStop" Value="False"/>
        </Style>
        <Style x:Key="ConsoleTextBoxStyle" TargetType="{x:Type TextBox}" BasedOn="{StaticResource {x:Type TextBox}}">
            <Setter Property="FontFamily" Value="{DynamicResource CodeFontFamily}"/>
            <Setter Property="FontSize" Value="{DynamicResource CodeFontSize}"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
            <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource PanelFg}"/>
        </Style>
        <Style x:Key="GeneralButtonStyle" TargetType="{x:Type Button}">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Button}">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8"
                                SnapsToDevicePixels="True">
                            <ContentPresenter
                                Margin="{TemplateBinding Padding}"
                                HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                                RecognizesAccessKey="True"
                                TextElement.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentPrimary}"/>
                                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
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
        <Style x:Key="Column1ButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource GeneralButtonStyle}">
            <Setter Property="Background" Value="{DynamicResource AccentMagenta}"/>
            <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentMagentaHover}"/>
                    <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="SystemButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource GeneralButtonStyle}">
            <Setter Property="Background" Value="{DynamicResource AccentBlue}"/>
            <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentBlueHover}"/>
                    <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="DatabaseButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource GeneralButtonStyle}">
            <Setter Property="Background" Value="{DynamicResource AccentDatabase}"/>
            <Setter Property="Foreground" Value="#111111"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentDatabaseHover}"/>
                    <Setter Property="Foreground" Value="#111111"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="DbConnectButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource GeneralButtonStyle}">
            <Setter Property="Background" Value="{DynamicResource AccentGreen}"/>
            <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentGreenHover}"/>
                    <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="DbDisconnectButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource GeneralButtonStyle}">
            <Setter Property="Background" Value="{DynamicResource AccentRed}"/>
            <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentRedHover}"/>
                    <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="NationalSoftButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource GeneralButtonStyle}">
            <Setter Property="Background" Value="{DynamicResource AccentOrange}"/>
            <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentOrangeHover}"/>
                    <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="TogglePillStyle" TargetType="{x:Type ToggleButton}">
            <Setter Property="Width" Value="84"/>
            <Setter Property="Height" Value="30"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ToggleButton}">
                        <Grid Width="{TemplateBinding Width}" Height="{TemplateBinding Height}">
                            <Border x:Name="SwitchBorder"
                                    Background="{DynamicResource BorderBrushColor}"
                                    BorderBrush="{DynamicResource BorderBrushColor}"
                                    BorderThickness="1"
                                    CornerRadius="15"/>
                            <Border x:Name="SwitchThumb"
                                    Width="22" Height="22"
                                    Background="{DynamicResource FormBg}"
                                    CornerRadius="11"
                                    HorizontalAlignment="Left"
                                    Margin="4,4,0,4"/>
                            <TextBlock x:Name="SwitchLabel"
                                       Text="OFF"
                                       Foreground="{DynamicResource FormFg}"
                                       FontWeight="Bold"
                                       HorizontalAlignment="Right"
                                       VerticalAlignment="Center"
                                       Margin="0,0,8,0"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="SwitchBorder" Property="Background" Value="{DynamicResource AccentPrimary}"/>
                                <Setter TargetName="SwitchBorder" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                                <Setter TargetName="SwitchThumb" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="SwitchThumb" Property="Margin" Value="0,4,4,4"/>
                                <Setter TargetName="SwitchLabel" Property="Text" Value="ON"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="SwitchBorder" Property="BorderBrush" Value="{DynamicResource AccentSecondary}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Background="{DynamicResource FormBg}">
        <TabControl Name="tabControl" Margin="5">
            <TabItem Name="tabAplicaciones">
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🧩" Margin="0,0,6,0"/>
                        <TextBlock Text="Aplicaciones"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="{DynamicResource PanelBg}">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <UniformGrid Grid.Row="0" Rows="1" Columns="4" Margin="10">
                        <TextBox Name="lblHostname" Style="{StaticResource InfoHeaderTextBoxStyle}" Text="HOSTNAME"/>
                        <TextBox Name="lblPort" Style="{StaticResource InfoHeaderTextBoxStyle}" Text="Puerto: No disponible"/>
                        <TextBox Name="txt_IpAdress" Style="{StaticResource InfoHeaderTextBoxStyle}"/>
                        <TextBox Name="txt_AdapterStatus" Style="{StaticResource InfoHeaderTextBoxStyle}"/>
                    </UniformGrid>
                    <Grid Grid.Row="1" Margin="10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="220"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Margin="0,0,10,0" VerticalAlignment="Top">
                            <Button Content="Instalar Herramientas" Name="btnInstalarHerramientas" Margin="0,0,0,10" Style="{StaticResource Column1ButtonStyle}"/>
                            <Button Content="Ejecutar ExpressProfiler" Name="btnProfiler" Margin="0,0,0,10" Style="{StaticResource Column1ButtonStyle}"/>
                            <Button Content="Ejecutar Database4" Name="btnDatabase" Margin="0,0,0,10" Style="{StaticResource Column1ButtonStyle}"/>
                            <Button Content="Ejecutar Manager" Name="btnSQLManager" Margin="0,0,0,10" Style="{StaticResource Column1ButtonStyle}"/>
                            <Button Content="Ejecutar Management" Name="btnSQLManagement" Margin="0,0,0,10" Style="{StaticResource Column1ButtonStyle}"/>
                            <Button Content="Printer Tools" Name="btnPrinterTool" Margin="0,0,0,10" Style="{StaticResource Column1ButtonStyle}"/>
                            <Button Content="Clear AnyDesk" Name="btnClearAnyDesk" Style="{StaticResource Column1ButtonStyle}"/>
                        </StackPanel>

                        <StackPanel Grid.Column="1" Margin="0,0,10,0" VerticalAlignment="Top">
                            <Button Content="Lector DP - Permisos" Name="btnLectorDPicacls" Margin="0,0,0,10" Style="{StaticResource SystemButtonStyle}"/>
                            <Button Content="Buscar Instalador LZMA" Name="LZMAbtnBuscarCarpeta" Margin="0,0,0,10" Style="{StaticResource SystemButtonStyle}"/>
                            <Button Content="Agregar IPs" Name="btnConfigurarIPs" Margin="0,0,0,10" Style="{StaticResource SystemButtonStyle}"/>
                            <Button Content="Agregar usuario de Windows" Name="btnAddUser" Margin="0,0,0,10" Style="{StaticResource SystemButtonStyle}"/>
                            <Button Content="Configuraciones de Firewall" Name="btnFirewallConfig" Margin="0,0,0,10" Style="{StaticResource SystemButtonStyle}"/>
                            <Button Content="Actualizar datos del sistema" Name="btnForzarActualizacion" Margin="0,0,0,10" Style="{StaticResource SystemButtonStyle}"/>
                            <Button Content="Mostrar Impresoras" Name="btnShowPrinters" Margin="0,0,0,10" Style="{StaticResource SystemButtonStyle}"/>
                            <Button Content="Instalar impresora" Name="btnInstallPrinter" Margin="0,0,0,10" Style="{StaticResource SystemButtonStyle}"/>
                            <Button Content="Limpia y Reinicia Cola de Impresión" Name="btnClearPrintJobs" Style="{StaticResource SystemButtonStyle}"/>
                        </StackPanel>

                        <StackPanel Grid.Column="2" Margin="0,0,10,0" VerticalAlignment="Top">
                            <Button Content="Aplicaciones National Soft" Name="btnAplicacionesNS" Margin="0,0,0,10" Style="{StaticResource NationalSoftButtonStyle}"/>
                            <Button Content="Cambiar OTM a SQL/DBF" Name="btnCambiarOTM" Margin="0,0,0,10" Style="{StaticResource NationalSoftButtonStyle}"/>
                            <Button Content="Permisos C:\NationalSoft" Name="btnCheckPermissions" Margin="0,0,0,10" Style="{StaticResource NationalSoftButtonStyle}"/>
                            <Button Content="Creación de SRM APK" Name="btnCreateAPK" Margin="0,0,0,10" Style="{StaticResource NationalSoftButtonStyle}"/>
                            <Button Content="Extractor de Instalador" Name="btnExtractInstaller" Margin="0,0,0,10" Style="{StaticResource NationalSoftButtonStyle}"/>
                            <Button Content="Instaladores NS" Name="btnInstaladoresNS" Margin="0,0,0,10" Style="{StaticResource NationalSoftButtonStyle}"/>
                            <Button Content="Registro de dlls" Name="btnRegisterDlls" Margin="0,0,0,10" Style="{StaticResource NationalSoftButtonStyle}"/>
                            <Button Content="Log Monitor Servicios" Name="btnMonitorServiciosLog" Style="{StaticResource NationalSoftButtonStyle}"/>
                        </StackPanel>

                        <StackPanel Grid.Column="3" VerticalAlignment="Top">
                            <TextBox Name="txt_InfoInstrucciones" Height="300" Margin="0,0,0,20" Style="{StaticResource ConsoleTextBoxStyle}" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                            <Border Name="cardQuickSettings"
                                    Height="150"
                                    Background="{DynamicResource ControlBg}"
                                    BorderBrush="{DynamicResource BorderBrushColor}"
                                    BorderThickness="1"
                                    CornerRadius="10"
                                    Padding="10">
                                <Border.Effect>
                                    <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="12" Opacity="0.25"/>
                                </Border.Effect>
                                <StackPanel>
                                    <TextBlock Text="Ajustes rápidos" FontWeight="Bold" Foreground="{DynamicResource AccentPrimary}" Margin="0,0,0,8"/>
                                    <Grid Margin="0,0,0,6">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="10"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                    </Grid>
                                    <Grid Margin="0,0,0,6">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="10"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <ToggleButton Name="tglDarkMode" Grid.Column="0" Style="{StaticResource TogglePillStyle}"/>
                                        <TextBlock Grid.Column="2" Text="🌙 Dark Mode" VerticalAlignment="Center"/>
                                    </Grid>
                                    <Grid Margin="0,0,0,6">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="10"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <ToggleButton Name="tglDebugMode" Grid.Column="0" Style="{StaticResource TogglePillStyle}"/>
                                        <TextBlock Grid.Column="2" Text="🐞 DEBUG" VerticalAlignment="Center"/>
                                    </Grid>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </Grid>
                </Grid>
            </TabItem>
            <TabItem Name="tabProSql">
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🗄️" Margin="0,0,6,0"/>
                        <TextBlock Text="SSMS portable"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="{DynamicResource PanelBg}">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0" Margin="8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="280" MinWidth="220"/>
                            <ColumnDefinition Width="4"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <!-- COLUMNA IZQUIERDA: Conexión + Ejecutar + TreeView -->
                        <Grid Grid.Column="0">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>

                            <!-- PANEL DE CONEXIÓN (contraíble) -->
                            <Border Grid.Row="0" Margin="0,0,0,8" Padding="8"
                                    BorderBrush="{DynamicResource BorderBrushColor}"
                                    BorderThickness="1" CornerRadius="6"
                                    Background="{DynamicResource ControlBg}">
                                <StackPanel>
                                    <Grid Margin="0,0,0,6">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock Text="🔌 Conexión"
                                                FontWeight="SemiBold"
                                                VerticalAlignment="Center"
                                                FontSize="12"/>
                                        <ToggleButton Name="btnSsmsPanelToggle"
                                                    Grid.Column="1"
                                                    Width="20" Height="20"
                                                    Content="▼"
                                                    ToolTip="Contraer/Expandir"
                                                    FontSize="9"
                                                    IsChecked="True"/>
                                    </Grid>

                                    <StackPanel Name="panelSsmsContent">
                                        <!-- Botones Conectar/Desconectar -->
                                        <Grid Margin="0,0,0,8">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>
                                            <Button Name="btnConnectDb" Grid.Column="0"
                                                    Height="32" Margin="0,0,4,0"
                                                    Style="{StaticResource DbConnectButtonStyle}"
                                                    ToolTip="Conectar">
                                                <StackPanel Orientation="Horizontal">
                                                    <TextBlock Text="🔌✅" FontSize="12" Margin="0,0,4,0"/>
                                                    <TextBlock Text="Conectar" FontSize="10"/>
                                                </StackPanel>
                                            </Button>
                                            <Button Name="btnDisconnectDb" Grid.Column="1"
                                                    Height="32" Margin="4,0,0,0"
                                                    Style="{StaticResource DbDisconnectButtonStyle}"
                                                    ToolTip="Desconectar" IsEnabled="False">
                                                <StackPanel Orientation="Horizontal">
                                                    <TextBlock Text="🔌✖" FontSize="12" Margin="0,0,4,0"/>
                                                    <TextBlock Text="Desconectar" FontSize="10"/>
                                                </StackPanel>
                                            </Button>
                                        </Grid>

                                        <!-- Servidor -->
                                        <StackPanel Margin="0,0,0,6">
                                            <TextBlock Text="Servidor:" FontSize="10" Margin="0,0,0,2"/>
                                            <ComboBox Name="txtServer"
                                                    IsEditable="True"
                                                    Text=".\NationalSoft"
                                                    FontSize="11"
                                                    Height="24"/>
                                        </StackPanel>

                                        <!-- Usuario -->
                                        <StackPanel Margin="0,0,0,6">
                                            <TextBlock Text="Usuario:" FontSize="10" Margin="0,0,0,2"/>
                                            <TextBox Name="txtUser"
                                                    Text="sa"
                                                    FontSize="11"
                                                    Height="24"/>
                                        </StackPanel>

                                        <!-- Contraseña -->
                                        <StackPanel Margin="0,0,0,6">
                                            <TextBlock Text="Contraseña:" FontSize="10" Margin="0,0,0,2"/>
                                            <PasswordBox Name="txtPassword" Height="24"/>
                                        </StackPanel>

                                        <!-- Base de datos -->
                                        <StackPanel>
                                            <TextBlock Text="Base de datos:" FontSize="10" Margin="0,0,0,2"/>
                                            <ComboBox Name="cmbDatabases"
                                                    IsEnabled="False"
                                                    FontSize="11"
                                                    Height="24"/>
                                        </StackPanel>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <!-- PANEL DE EJECUCIÓN Y QUERIES -->
                            <Border Grid.Row="1" Margin="0,0,0,8" Padding="8"
                                    BorderBrush="{DynamicResource BorderBrushColor}"
                                    BorderThickness="1" CornerRadius="6"
                                    Background="{DynamicResource ControlBg}">
                                <StackPanel>
                                    <TextBlock Text="▶ Ejecución"
                                            FontWeight="SemiBold"
                                            FontSize="12"
                                            Margin="0,0,0,8"/>

                                    <!-- Botón Ejecutar -->
                                    <Button Content="▶ Ejecutar (F5)" Name="btnExecute"
                                            Height="32" Margin="0,0,0,8"
                                            Style="{StaticResource DatabaseButtonStyle}"
                                            IsEnabled="False" FontSize="11"/>

                                    <!-- Queries Predefinidas -->
                                    <TextBlock Text="Queries:" FontSize="10" Margin="0,0,0,2"/>
                                    <ComboBox Name="cmbQueries"
                                            Height="24"
                                            IsEnabled="False"
                                            ToolTip="Consultas predefinidas"
                                            FontSize="11"/>
                                </StackPanel>
                            </Border>

                            <!-- EXPLORADOR (TreeView) -->
                            <Border Grid.Row="2"
                                    BorderBrush="{DynamicResource BorderBrushColor}"
                                    BorderThickness="1" CornerRadius="6"
                                    Background="{DynamicResource ControlBg}">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="*"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Grid.Row="0" Text="📁 Explorador"
                                            Padding="8,6" FontWeight="SemiBold"
                                            Background="{DynamicResource AccentPrimary}"
                                            Foreground="{DynamicResource OnAccentFg}"
                                            FontSize="12"/>
                                    <TreeView Grid.Row="1" Name="tvDatabases"
                                            Padding="4" FontSize="11"/>
                                </Grid>
                            </Border>
                        </Grid>

                        <GridSplitter Grid.Column="1" Width="4"
                                    HorizontalAlignment="Stretch"
                                    Background="{DynamicResource BorderBrushColor}"/>

                        <!-- COLUMNA DERECHA: Queries y Resultados -->
                        <Grid Grid.Column="2">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="1.5*" MinHeight="120"/>
                                <RowDefinition Height="4"/>
                                <RowDefinition Height="*" MinHeight="150"/>
                            </Grid.RowDefinitions>
                            <!-- Pestañas de Queries -->
                            <TabControl Name="tcQueries" Grid.Row="0"
                                        Background="{DynamicResource ControlBg}">
                            <TabControl.ItemContainerStyle>
                                <Style TargetType="{x:Type TabItem}" BasedOn="{StaticResource {x:Type TabItem}}">
                                <Setter Property="FontSize" Value="10"/>
                                <Setter Property="Padding" Value="6,2"/>
                                <Setter Property="Margin" Value="1,0,0,0"/>
                                <Setter Property="MinHeight" Value="24"/>
                                </Style>
                            </TabControl.ItemContainerStyle>

                            <TabItem Header="+" Name="tabAddQuery"
                                    IsEnabled="True" ToolTip="Nueva consulta"/>
                            </TabControl>
                            <GridSplitter Grid.Row="1" Height="4"
                                        HorizontalAlignment="Stretch"
                                        Background="{DynamicResource BorderBrushColor}"/>
                            <!-- Pestañas de Resultados -->
                            <TabControl Name="tcResults" Grid.Row="2"
                                        Background="{DynamicResource ControlBg}">
                                <TabControl.ItemContainerStyle>
                                    <Style TargetType="{x:Type TabItem}" BasedOn="{StaticResource {x:Type TabItem}}">
                                    <Setter Property="FontSize" Value="10"/>
                                    <Setter Property="Padding" Value="6,2"/>
                                    <Setter Property="Margin" Value="1,0,0,0"/>
                                    <Setter Property="MinHeight" Value="24"/>
                                    </Style>
                                </TabControl.ItemContainerStyle>
                                <TabItem Header="📊 Resultados">
                                    <DataGrid Name="dgResults"
                                            IsReadOnly="True"
                                            FontSize="10"
                                            AutoGenerateColumns="True"
                                            CanUserAddRows="False"
                                            CanUserDeleteRows="False"
                                            RowHeight="20"
                                            ColumnHeaderHeight="22"/>
                                </TabItem>

                                <TabItem Header="💬 Mensajes">
                                    <TextBox Name="txtMessages"
                                            IsReadOnly="True"
                                            VerticalScrollBarVisibility="Auto"
                                            FontFamily="Consolas"
                                            FontSize="10"
                                            Padding="4,2"
                                            Background="Transparent"
                                            BorderThickness="0"/>
                                </TabItem>
                            </TabControl>
                        </Grid>
                    </Grid>
                    <!-- BARRA DE ESTADO -->
                    <StatusBar Grid.Row="1"
                            Background="{DynamicResource ControlBg}"
                            Foreground="{DynamicResource ControlFg}"
                            Height="26">
                        <StatusBarItem>
                            <TextBlock Name="lblConnectionStatus"
                                    Text="⚫ Desconectado" FontSize="11"/>
                        </StatusBarItem>
                        <Separator/>
                        <StatusBarItem>
                            <TextBlock Name="lblExecutionTimer"
                                    Text="⏱️ --" FontSize="11"/>
                        </StatusBarItem>
                        <Separator/>
                        <StatusBarItem>
                            <TextBlock Name="lblRowCount"
                                    Text="📊 --" FontSize="11"/>
                        </StatusBarItem>
                        <Separator/>
                        <!-- Botones en la barra de estado -->
                        <StatusBarItem HorizontalAlignment="Right">
                            <StackPanel Orientation="Horizontal">
                                <Button Content="🗑️ Limpiar" Name="btnClearQuery"
                                        Height="20" Padding="6,2"
                                        Style="{StaticResource DatabaseButtonStyle}"
                                        IsEnabled="False" FontSize="10"
                                        Margin="0,0,4,0"/>
                                <Button Content="💾 Exportar" Name="btnExport"
                                        Height="20" Padding="6,2"
                                        Style="{StaticResource DatabaseButtonStyle}"
                                        IsEnabled="False" FontSize="10"
                                        Margin="0,0,4,0"/>
                                <Button Content="📋 Historial" Name="btnHistorial"
                                        Height="20" Padding="6,2"
                                        Style="{StaticResource DatabaseButtonStyle}"
                                        IsEnabled="False" FontSize="10"/>
                            </StackPanel>
                        </StatusBarItem>
                    </StatusBar>
                </Grid>
            </TabItem>
        </TabControl>
    </Grid>
</Window>
"@
}
function New-MainWindow {
    [CmdletBinding()]
    param()
    try {
        Write-Host "  ✓ Formulario creado listo para mostrar." -ForegroundColor Green
        $theme = Get-DzUiTheme
        $xaml = Get-MainWindowXaml -Theme $theme
        $result = New-WpfWindow -Xaml $xaml -PassThru
        $window = $result.Window
        Set-DzWpfThemeResources -Window $window -Theme $theme
        return @{
            Window   = $window
            Controls = $result.Controls
        }
    } catch {
        Write-Host "`n[ERROR] No se pudo crear la ventana principal: $_" -ForegroundColor Red
        throw
    }
}
Export-ModuleMember -Function @(
    'Get-DzUiTheme', 'New-WpfWindow', 'Show-WpfMessageBox', 'Show-WpfMessageBoxSafe', 'ConvertTo-MessageBoxResult',
    'New-WpfInputDialog', 'Show-WpfProgressBar', 'Update-WpfProgressBar', 'Close-WpfProgressBar', 'Show-ProgressBar',
    'Set-WpfControlEnabled', 'Get-WpfPasswordBoxText', 'Show-WpfFolderDialog', 'Set-WpfDialogOwner', 'Set-DzWpfThemeResources',
    'Ui-Info', 'Ui-Warn', 'Ui-Error', 'Ui-Confirm', 'Get-MainWindowXaml', 'New-MainWindow'
)