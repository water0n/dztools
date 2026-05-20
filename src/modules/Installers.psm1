#requires -Version 5.0
#Installers.psm1 - Módulo de gestión de instaladores y paquetes Chocolatey
function Check-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        $result = Show-WpfMessageBox `
            -Message "Chocolatey no está instalado. ¿Desea instalarlo ahora?" `
            -Title "Chocolatey no encontrado" `
            -Buttons "YesNo" `
            -Icon "Question"
        if ($result -eq [System.Windows.MessageBoxResult]::No) {
            Write-Host "`nEl usuario canceló la instalación de Chocolatey." -ForegroundColor Red
            return $false
        }
        Write-Host "`nInstalando Chocolatey..." -ForegroundColor Cyan
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            Write-Host "`nChocolatey se instaló correctamente." -ForegroundColor Green
            Write-Host "`nConfigurando Chocolatey..." -ForegroundColor Yellow
            choco config set cacheLocation C:\Choco\cache
            Show-WpfMessageBox `
                -Message "Chocolatey se instaló correctamente y ha sido configurado. Por favor, reinicie PowerShell antes de continuar." `
                -Title "Reinicio requerido" `
                -Buttons "OK" `
                -Icon "Information" | Out-Null
            Write-Host "`nCerrando la aplicación para permitir reinicio de PowerShell..." -ForegroundColor Red
            Stop-Process -Id $PID -Force
            return $false
        } catch {
            Write-Host "`nError al instalar Chocolatey: $_" -ForegroundColor Red
            Show-WpfMessageBox `
                -Message "Error al instalar Chocolatey. Por favor, inténtelo manualmente.`n`nDetalle: $($_.Exception.Message)" `
                -Title "Error de instalación" `
                -Buttons "OK" `
                -Icon "Error" | Out-Null
            return $false
        }
    } else {
        Write-Host "`tChocolatey ya está instalado." -ForegroundColor Green
        return $true
    }
}
function Test-ChocolateyInstalled {
    return $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
}
function Install-Software {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SQL2014', 'SQL2019', 'SSMS', '7Zip', 'MegaTools')]
        [string]$Software,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Error "Chocolatey no está instalado. Use Check-Chocolatey primero."
        return $false
    }
    switch ($Software) {
        'SQL2014' {
            Write-Host "Instalando SQL Server 2014 Express..." -ForegroundColor Cyan
            $arguments = @(
                'install', 'sql-server-express',
                '-y',
                '--version=2014.0.2000.8',
                '--params', '"/SQLUSER:sa /SQLPASSWORD:National09 /INSTANCENAME:NationalSoft /FEATURES:SQL"'
            )
        }
        'SQL2019' {
            Write-Host "Instalando SQL Server 2019 Express..." -ForegroundColor Cyan
            $arguments = @(
                'install', 'sql-server-express',
                '-y',
                '--version=2019.20190106',
                '--params', '"/SQLUSER:sa /SQLPASSWORD:National09 /INSTANCENAME:SQL2019 /FEATURES:SQL"'
            )
        }
        'SSMS' {
            Write-Host "Instalando SQL Server Management Studio..." -ForegroundColor Cyan
            $arguments = @('install', 'sql-server-management-studio', '-y')
        }
        '7Zip' {
            Write-Host "Instalando 7-Zip..." -ForegroundColor Cyan
            $arguments = @('install', '7zip', '-y')
        }
        'MegaTools' {
            Write-Host "Instalando MegaTools..." -ForegroundColor Cyan
            $arguments = @('install', 'megatools', '-y')
        }
    }
    try {
        Start-Process choco -ArgumentList $arguments -NoNewWindow -Wait
        Write-Host "$Software instalado correctamente" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Error instalando $Software : $_"
        return $false
    }
}
function Download-File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $false)]
        [switch]$ShowProgress
    )
    try {
        if ($ShowProgress) {
            $webClient = New-Object System.Net.WebClient
            $eventHandler = {
                $global:downloadPercentage = $_.ProgressPercentage
                Write-Progress -Activity "Descargando..." -Status "$($global:downloadPercentage)%" `
                    -PercentComplete $global:downloadPercentage
            }
            $webClient.add_DownloadProgressChanged($eventHandler)
            $webClient.DownloadFileAsync((New-Object System.Uri($Url)), $OutputPath)
            while ($webClient.IsBusy) { Start-Sleep -Milliseconds 100 }
            $webClient.remove_DownloadProgressChanged($eventHandler)
            Write-Progress -Activity "Descargando..." -Completed
        } else {
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
        }
        Write-Verbose "Archivo descargado: $OutputPath"
        return $true
    } catch {
        Write-Error "Error descargando archivo: $_"
        return $false
    }
}
function Expand-ArchiveFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    try {
        if ($Force -and (Test-Path $DestinationPath)) { Remove-Item $DestinationPath -Recurse -Force }
        if (-not (Test-Path $DestinationPath)) { New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null }
        Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
        Write-Verbose "Archivo extraído a: $DestinationPath"
        return $true
    } catch {
        Write-Error "Error extrayendo archivo: $_"
        return $false
    }
}
function Show-SSMSInstallerDialog {
    $theme = Get-DzUiTheme
    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Instalar SSMS"
        Height="200" Width="380"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="$($theme.FormBackground)">
<Window.Resources>
    <Style TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource PanelFg}"/>
    </Style>
    <Style TargetType="TextBox">
        <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
        <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
        <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style x:Key="BaseButtonStyle" TargetType="Button">
        <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
        <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Opacity" Value="1"/>
        <Setter Property="Padding" Value="12,6"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="6"
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
        <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
        <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Style.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="{DynamicResource AccentSecondary}"/>
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
    <Style TargetType="DataGrid">
        <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
        <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="RowBackground" Value="{DynamicResource PanelBg}"/>
        <Setter Property="AlternatingRowBackground" Value="{DynamicResource ControlBg}"/>
        <Setter Property="GridLinesVisibility" Value="Horizontal"/>
        <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource BorderBrushColor}"/>
        <Setter Property="VerticalGridLinesBrush" Value="{DynamicResource BorderBrushColor}"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
        <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
        <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
        <Setter Property="BorderThickness" Value="0,0,0,1"/>
        <Setter Property="Padding" Value="8,6"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="DataGridRow">
        <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
        <Style.Triggers>
            <Trigger Property="IsSelected" Value="True">
                <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
            </Trigger>
        </Style.Triggers>
    </Style>
    <Style TargetType="DataGridCell">
        <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
        <Setter Property="BorderThickness" Value="0,0,0,1"/>
        <Style.Triggers>
            <Trigger Property="IsSelected" Value="True">
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
            </Trigger>
        </Style.Triggers>
    </Style>
</Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0"
                  Text="Elige la versión a instalar:"
                  FontSize="13"
                  FontWeight="Bold"
                  Margin="0,0,0,15"/>
        <ComboBox Grid.Row="1"
                 Name="cmbVersion"
                 FontSize="12"
                 Padding="8"
                 Margin="0,0,0,20">
            <ComboBoxItem Content="Último disponible" IsSelected="True"/>
            <ComboBoxItem Content="SSMS 14 (2014)"/>
        </ComboBox>
        <Grid Grid.Row="2"/>
        <StackPanel Grid.Row="3"
                   Orientation="Horizontal"
                   HorizontalAlignment="Right">
            <Button Name="btnOK"
                   Content="Instalar"
                   Width="140"
                   Margin="0,0,10,0"/>
            <Button Name="btnCancel"
                   Content="Cancelar"
                   Width="140"/>
        </StackPanel>
    </Grid>
</Window>
"@
    try {
        [xml]$xaml = $stringXaml
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)
        $cmbVersion = $window.FindName("cmbVersion")
        $btnOK = $window.FindName("btnOK")
        $btnCancel = $window.FindName("btnCancel")
        $script:selectedVersion = $null
        $btnOK.Add_Click({
                $selectedIndex = $cmbVersion.SelectedIndex
                $script:selectedVersion = switch ($selectedIndex) {
                    0 { "latest" }
                    1 { "ssms14" }
                    default { "latest" }
                }
                $window.DialogResult = $true
                $window.Close()
            })
        $btnCancel.Add_Click({
                $script:selectedVersion = $null
                $window.DialogResult = $false
                $window.Close()
            })
        $result = $window.ShowDialog()
        if ($result) { return $script:selectedVersion }
        return $null
    } catch {
        Write-Error "Error mostrando diálogo de SSMS: $_"
        return $null
    }
}
function Test-7ZipInstalled {
    $paths = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { return $true }
    }
    return $false
}
function Test-MegaToolsInstalled {
    return $null -ne (Get-Command megatools -ErrorAction SilentlyContinue)
}
function Get-InstalledChocoPackages {
    if (-not (Test-ChocolateyInstalled)) {
        Write-Warning "Chocolatey no está instalado"
        return @()
    }
    try {
        $output = choco list --local-only --limit-output
        $packages = @()
        foreach ($line in $output) {
            if ($line -match '^(?<name>[^\|]+)\|(?<version>.+)$') {
                $packages += [PSCustomObject]@{
                    Name    = $Matches['name']
                    Version = $Matches['version']
                }
            }
        }
        return $packages
    } catch {
        Write-Error "Error obteniendo paquetes instalados: $_"
        return @()
    }
}
function Search-ChocoPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    if (-not (Test-ChocolateyInstalled)) {
        Write-Warning "Chocolatey no está instalado"
        return @()
    }
    try {
        $output = choco search $Query --page-size=20
        $packages = @()
        $pattern = '^(?<name>[A-Za-z0-9\.\+\-_]+)\s+(?<version>[0-9][A-Za-z0-9\.\-]*)\s+(?<description>.+)$'
        foreach ($line in $output) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^Chocolatey') { continue }
            if ($line -match 'packages?\s+found' -or $line -match 'page size') { continue }
            if ($line -match $pattern) {
                $packages += [PSCustomObject]@{
                    Name        = $Matches['name']
                    Version     = $Matches['version']
                    Description = $Matches['description'].Trim()
                }
            }
        }
        return $packages
    } catch {
        Write-Error "Error buscando paquetes: $_"
        return @()
    }
}
function Install-ChocoPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        [Parameter(Mandatory = $false)]
        [string]$Version = $null
    )
    if (-not (Test-ChocolateyInstalled)) {
        Write-Error "Chocolatey no está instalado"
        return $false
    }
    try {
        $arguments = "install $PackageName -y"
        if (-not [string]::IsNullOrWhiteSpace($Version)) {
            $arguments = "install $PackageName --version=$Version -y"
        }
        Write-Host "Instalando $PackageName..." -ForegroundColor Cyan
        Start-Process choco -ArgumentList $arguments -NoNewWindow -Wait
        Write-Host "$PackageName instalado correctamente" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Error instalando $PackageName : $_"
        return $false
    }
}
function Uninstall-ChocoPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName
    )
    if (-not (Test-ChocolateyInstalled)) {
        Write-Error "Chocolatey no está instalado"
        return $false
    }
    try {
        $arguments = "uninstall $PackageName -y"
        Write-Host "Desinstalando $PackageName..." -ForegroundColor Yellow
        Start-Process choco -ArgumentList $arguments -NoNewWindow -Wait
        Write-Host "$PackageName desinstalado correctamente" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Error desinstalando $PackageName : $_"
        return $false
    }
}
function Show-ChocolateyInstallerMenu {
    $theme = Get-DzUiTheme
    $stringXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Instaladores (Chocolatey)"
        Width="720" Height="520"
        MinWidth="720" MinHeight="520"
        MaxWidth="720" MaxHeight="520"
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

        <!-- Botón X -->
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

        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="RowBackground" Value="{DynamicResource PanelBg}"/>
            <Setter Property="AlternatingRowBackground" Value="{DynamicResource ControlBg}"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="VerticalGridLinesBrush" Value="{DynamicResource BorderBrushColor}"/>
        </Style>

        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <Style TargetType="DataGridRow">
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
                    <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="DataGridCell">
            <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <!-- CONTENEDOR REAL -->
    <Border Background="{DynamicResource FormBg}"
            BorderBrush="{DynamicResource BorderBrushColor}"
            BorderThickness="1"
            CornerRadius="12"
            Margin="10"
            SnapsToDevicePixels="True">
        <Border.Effect>
            <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
        </Border.Effect>

        <Grid Margin="12">
            <Grid.RowDefinitions>
                <RowDefinition Height="52"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- HEADER draggable -->
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

                    <Button Grid.Column="0"
                            Name="btnExitInstaladores"
                            Content="Salir"
                            Width="120"
                            Height="34"
                            Margin="0,0,12,0"
                            Style="{StaticResource OutlineButtonStyle}"/>

                    <StackPanel Grid.Column="1" Orientation="Vertical">
                        <TextBlock Text="Chocolatey Installer"
                                   Foreground="{DynamicResource FormFg}"
                                   FontSize="16"
                                   FontWeight="SemiBold"/>
                        <TextBlock Text="Busca, instala y desinstala paquetes"
                                   Foreground="{DynamicResource AccentMuted}"
                                   Margin="0,2,0,0"/>
                    </StackPanel>

                    <Button Grid.Column="2"
                            Name="btnCloseX"
                            Style="{StaticResource IconButtonStyle}"
                            Content="✕"
                            ToolTip="Cerrar"/>
                </Grid>
            </Border>

            <!-- SEARCH / ACTIONS -->
            <Border Grid.Row="1"
                    Background="{DynamicResource PanelBg}"
                    BorderBrush="{DynamicResource BorderBrushColor}"
                    BorderThickness="1"
                    CornerRadius="10"
                    Padding="12"
                    Margin="0,10,0,10">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <TextBox Name="txtChocoSearch"
                                 Height="34"
                                 Padding="10,6"
                                 VerticalContentAlignment="Center"/>
                        <Button Grid.Column="1"
                                Name="btnBuscarChoco"
                                Content="Buscar"
                                Width="140"
                                Height="34"
                                Margin="10,0,0,0"
                                Style="{StaticResource ActionButtonStyle}"/>
                    </Grid>

                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,10,0,0">
                        <TextBlock Text="Presets:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <Button Name="btnPresetSSMS"
                                Content="SSMS"
                                Width="90"
                                Height="30"
                                Margin="0,0,10,0"
                                Background="{DynamicResource AccentMuted}"
                                Foreground="{DynamicResource FormFg}"
                                BorderThickness="0"
                                Cursor="Hand"/>
                        <Button Name="btnPresetHeidi"
                                Content="Heidi"
                                Width="90"
                                Height="30"
                                Background="{DynamicResource AccentMuted}"
                                Foreground="{DynamicResource FormFg}"
                                BorderThickness="0"
                                Cursor="Hand"/>
                    </StackPanel>

                    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,12,0,0">
                        <Button Name="btnShowInstalledChoco"
                                Content="Mostrar instalados"
                                Width="170"
                                Height="34"
                                Style="{StaticResource OutlineButtonStyle}"/>
                        <Button Name="btnInstallSelectedChoco"
                                Content="Instalar seleccionado"
                                Width="190"
                                Height="34"
                                Margin="10,0,0,0"
                                IsEnabled="False"
                                Style="{StaticResource ActionButtonStyle}"/>
                        <Button Name="btnUninstallSelectedChoco"
                                Content="Desinstalar seleccionado"
                                Width="200"
                                Height="34"
                                Margin="10,0,0,0"
                                IsEnabled="False"
                                Style="{StaticResource OutlineButtonStyle}"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- RESULTS -->
            <Border Grid.Row="2"
                    Background="{DynamicResource PanelBg}"
                    BorderBrush="{DynamicResource BorderBrushColor}"
                    BorderThickness="1"
                    CornerRadius="10"
                    Padding="10">
                <DataGrid Name="dgvChocoResults"
                          IsReadOnly="True"
                          AutoGenerateColumns="False"
                          SelectionMode="Single"
                          CanUserAddRows="False">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Paquete" Binding="{Binding Name}" Width="220"/>
                        <DataGridTextColumn Header="Versión" Binding="{Binding Version}" Width="140"/>
                        <DataGridTextColumn Header="Descripción" Binding="{Binding Description}" Width="*"/>
                    </DataGrid.Columns>
                </DataGrid>
            </Border>

            <!-- STATUS -->
            <Border Grid.Row="3"
                    Background="{DynamicResource PanelBg}"
                    BorderBrush="{DynamicResource BorderBrushColor}"
                    BorderThickness="1"
                    CornerRadius="10"
                    Padding="10"
                    Margin="0,10,0,0">
                <TextBlock Name="txtStatus"
                           Text="Listo."
                           VerticalAlignment="Center"/>
            </Border>

        </Grid>
    </Border>
</Window>
"@
    try {
        $result = New-WpfWindow -Xaml $stringXaml -PassThru
        $window = $result.Window
        $c = $result.Controls
        Set-DzWpfThemeResources -Window $window -Theme $theme
        try { Set-WpfDialogOwner -Dialog $window } catch {}
        try { if (-not $window.Owner -and $global:MainWindow -is [System.Windows.Window]) { $window.Owner = $global:MainWindow } } catch {}
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
        if ($c.ContainsKey('HeaderBar') -and $c['HeaderBar']) {
            $c['HeaderBar'].Add_MouseLeftButtonDown({
                    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                        try { $window.DragMove() } catch {}
                    }
                })
        }
        if ($c.ContainsKey('btnCloseX') -and $c['btnCloseX']) {
            $c['btnCloseX'].Add_Click({ try { $window.Close() } catch {} })
        }
        $window.Add_PreviewKeyDown({
                param($sender, $e)
                if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                    try { $window.Close() } catch {}
                }
            })
    } catch {
        Write-Host "Error creando ventana: $_" -ForegroundColor Red
        return
    }
    $txtChocoSearch = $window.FindName("txtChocoSearch")
    $btnBuscarChoco = $window.FindName("btnBuscarChoco")
    $btnPresetSSMS = $window.FindName("btnPresetSSMS")
    $btnPresetHeidi = $window.FindName("btnPresetHeidi")
    $btnShowInstalledChoco = $window.FindName("btnShowInstalledChoco")
    $btnInstallSelectedChoco = $window.FindName("btnInstallSelectedChoco")
    $btnUninstallSelectedChoco = $window.FindName("btnUninstallSelectedChoco")
    $dgvChocoResults = $window.FindName("dgvChocoResults")
    $btnExitInstaladores = $window.FindName("btnExitInstaladores")
    $txtStatus = $window.FindName("txtStatus")
    $chocoResultsCollection = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
    $resetChocoUi = {
        $window.Dispatcher.Invoke([action] {
                $chocoResultsCollection.Clear()
                $dgvChocoResults.SelectedItem = $null
                $txtChocoSearch.Text = ""
                $txtStatus.Text = "Listo."
                $btnInstallSelectedChoco.IsEnabled = $false
                $btnUninstallSelectedChoco.IsEnabled = $false
            }) | Out-Null
    }
    $dgvChocoResults.ItemsSource = $chocoResultsCollection
    $addChocoResult = {
        param($line)
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        if ($line -match '^Chocolatey') { return }
        if ($line -match 'packages?\s+found' -or $line -match 'page size') { return }
        if ($line -match '^(?<name>[A-Za-z0-9\.\+\-_]+)\s+(?<version>[0-9][A-Za-z0-9\.\-]*)\s+(?<description>.+)$') {
            $window.Dispatcher.Invoke([action] {
                    $chocoResultsCollection.Add([PSCustomObject]@{
                            Name        = $Matches['name']
                            Version     = $Matches['version']
                            Description = $Matches['description'].Trim()
                        })
                }) | Out-Null
        } elseif ($line -match '^(?<name>[A-Za-z0-9\.\+\-_]+)\s+\|\s+(?<version>[0-9][A-Za-z0-9\.\-]*)$') {
            $window.Dispatcher.Invoke([action] {
                    $chocoResultsCollection.Add([PSCustomObject]@{
                            Name        = $Matches['name']
                            Version     = $Matches['version']
                            Description = "Paquete instalado"
                        })
                }) | Out-Null
        }
    }
    $addChocoInstalled = {
        param($line)
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        if ($line -match '^Chocolatey') { return }
        if ($line -match '^(?<name>[^|]+)\|(?<version>.+)$') {
            $name = $Matches['name'].Trim()
            $ver = $Matches['version'].Trim()
            $window.Dispatcher.Invoke([action] {
                    $chocoResultsCollection.Add([PSCustomObject]@{
                            Name        = $name
                            Version     = $ver
                            Description = "Paquete instalado"
                        })
                }) | Out-Null
        }
    }
    $updateActionButtons = {
        $hasValidSelection = $false
        if ($dgvChocoResults.SelectedItem) {
            $selectedItem = $dgvChocoResults.SelectedItem
            if ($selectedItem.Name -and $selectedItem.Version -match '^[0-9]') { $hasValidSelection = $true }
        }
        $btnInstallSelectedChoco.IsEnabled = $hasValidSelection
        $btnUninstallSelectedChoco.IsEnabled = $hasValidSelection
    }
    $dgvChocoResults.Add_SelectionChanged({ & $updateActionButtons })
    $btnBuscarChoco.Add_Click({
            $chocoResultsCollection.Clear()
            & $updateActionButtons
            $query = $txtChocoSearch.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($query)) {
                Show-WpfMessageBox -Message "Ingresa un término para buscar" -Title "Búsqueda" -Buttons "OK" -Icon "Information" -Owner $window | Out-Null
                return
            }
            if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
                Show-WpfMessageBox -Message "Chocolatey no está instalado." -Title "Error" -Buttons "OK" -Icon "Error" -Owner $window | Out-Null
                return
            }
            $btnBuscarChoco.IsEnabled = $false
            $progress = Show-WpfProgressBar -Title "Buscando paquetes" -Message "Iniciando búsqueda..."
            try {
                Update-WpfProgressBar -Window $progress -Percent 20 -Message "Verificando Chocolatey..."
                Start-Sleep -Milliseconds 300
                Update-WpfProgressBar -Window $progress -Percent 40 -Message "Buscando '$query'..."
                $searchOutput = & choco search $query --page-size=20 2>&1
                Update-WpfProgressBar -Window $progress -Percent 70 -Message "Procesando resultados..."
                foreach ($line in $searchOutput) { & $addChocoResult $line }
                Update-WpfProgressBar -Window $progress -Percent 100 -Message "Búsqueda completada"
                Start-Sleep -Milliseconds 300
                if ($chocoResultsCollection.Count -eq 0) {
                    Show-WpfMessageBox -Message "No se encontraron paquetes." -Title "Sin resultados" -Buttons "OK" -Icon "Information" -Owner $window | Out-Null
                }
            } catch {
                Write-Error "Error: $_"
                Show-WpfMessageBox -Message "Error durante la búsqueda:`n`n$($_.Exception.Message)" -Title "Error" -Buttons "OK" -Icon "Error" -Owner $window | Out-Null
            } finally {
                Close-WpfProgressBar -Window $progress
                $btnBuscarChoco.IsEnabled = $true
            }
        })
    $btnPresetSSMS.Add_Click({
            $txtChocoSearch.Text = "ssms"
            $btnBuscarChoco.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        })
    $btnPresetHeidi.Add_Click({
            $txtChocoSearch.Text = "heidi"
            $btnBuscarChoco.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        })
    $btnShowInstalledChoco.Add_Click({
            $chocoResultsCollection.Clear()
            & $updateActionButtons
            if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
                Show-WpfMessageBox -Message "Chocolatey no está instalado." -Title "Error" -Buttons "OK" -Icon "Error" -Owner $window | Out-Null
                return
            }
            $btnShowInstalledChoco.IsEnabled = $false
            $progress = Show-WpfProgressBar -Title "Listando instalados" -Message "Recuperando paquetes..."
            try {
                Update-WpfProgressBar -Window $progress -Percent 30 -Message "Consultando paquetes instalados..."
                $installedOutput = & choco list --local-only --limit-output 2>&1
                Update-WpfProgressBar -Window $progress -Percent 70 -Message "Procesando resultados..."
                foreach ($line in $installedOutput) { & $addChocoInstalled $line }
                Update-WpfProgressBar -Window $progress -Percent 100 -Message "Completado"
                Start-Sleep -Milliseconds 200
                if ($chocoResultsCollection.Count -eq 0) {
                    Show-WpfMessageBox -Message "No hay paquetes instalados (o no se pudo leer la salida)." -Title "Sin resultados" -Buttons "OK" -Icon "Information" -Owner $window | Out-Null
                }
            } catch {
                Write-Error "Error: $_"
                Show-WpfMessageBox -Message "Error consultando paquetes:`n`n$($_.Exception.Message)" -Title "Error" -Buttons "OK" -Icon "Error" -Owner $window | Out-Null
            } finally {
                Close-WpfProgressBar -Window $progress
                $btnShowInstalledChoco.IsEnabled = $true
            }
        })
    $btnInstallSelectedChoco.Add_Click({
            Write-DzDebug "`t[DEBUG] [Install-ChocoPackage] Iniciando instalación del paquete seleccionado."
            if (-not $dgvChocoResults.SelectedItem) {
                Show-WpfMessageBox -Message "Seleccione un paquete." -Title "Instalación" -Buttons "OK" -Icon "Information" -Owner $window | Out-Null
                return
            }
            $packageName = $dgvChocoResults.SelectedItem.Name
            $result = Show-WpfMessageBoxSafe -Message "¿Instalar $packageName?" -Title "Confirmar" -Buttons "YesNo" -Icon "Question" -Owner $window
            Write-DzDebug "`t[DEBUG][Install-ChocoPackage] User response: $result"
            if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
            $progress = Show-WpfProgressBar -Title "Instalando" -Message "Preparando instalación..."
            try {
                Update-WpfProgressBar -Window $progress -Percent 20 -Message "Verificando paquete..."
                Start-Sleep -Milliseconds 300
                Update-WpfProgressBar -Window $progress -Percent 40 -Message "Instalando $packageName..."
                $installProcess = Start-Process -FilePath "choco" `
                    -ArgumentList "install", $packageName, "-y" `
                    -NoNewWindow -PassThru -Wait
                Update-WpfProgressBar -Window $progress -Percent 90 -Message "Verificando instalación..."
                Start-Sleep -Milliseconds 500
                if ($installProcess.ExitCode -eq 0) {
                    Update-WpfProgressBar -Window $progress -Percent 100 -Message "Instalación completada"
                    Start-Sleep -Milliseconds 500
                    Show-WpfMessageBox -Message "Paquete instalado exitosamente." -Title "Éxito" -Buttons "OK" -Icon "Information" -Owner $window | Out-Null
                    try { $resetChocoUi.Invoke() } catch { }
                } else {
                    throw "Error de instalación: código $($installProcess.ExitCode)"
                }
            } catch {
                Write-Error $_
                Show-WpfMessageBox -Message "Error: $($_.Exception.Message)" -Title "Error" -Buttons "OK" -Icon "Error" -Owner $window | Out-Null
            } finally {
                Close-WpfProgressBar -Window $progress
            }
        })
    $btnUninstallSelectedChoco.Add_Click({
            if (-not $dgvChocoResults.SelectedItem) {
                Show-WpfMessageBox -Message "Seleccione un paquete." -Title "Desinstalación" -Buttons "OK" -Icon "Information" -Owner $window | Out-Null
                return
            }
            $packageName = $dgvChocoResults.SelectedItem.Name
            $result = Show-WpfMessageBox -Message "¿Desinstalar $packageName?" -Title "Confirmar" -Buttons "YesNo" -Icon "Warning" -Owner $window
            if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
            $progress = Show-WpfProgressBar -Title "Desinstalando" -Message "Preparando desinstalación..."
            try {
                Update-WpfProgressBar -Window $progress -Percent 30 -Message "Desinstalando $packageName..."
                $uninstallProcess = Start-Process -FilePath "choco" `
                    -ArgumentList "uninstall", $packageName, "-y" `
                    -NoNewWindow -PassThru -Wait
                Update-WpfProgressBar -Window $progress -Percent 90 -Message "Verificando desinstalación..."
                Start-Sleep -Milliseconds 500
                if ($uninstallProcess.ExitCode -eq 0) {
                    Update-WpfProgressBar -Window $progress -Percent 100 -Message "Desinstalación completada"
                    Start-Sleep -Milliseconds 500
                    Show-WpfMessageBox -Message "Paquete desinstalado exitosamente." -Title "Éxito" -Buttons "OK" -Icon "Information" -Owner $window | Out-Null
                    try { $resetChocoUi.Invoke() } catch { }
                } else {
                    throw "Error: código $($uninstallProcess.ExitCode)"
                }
            } catch {
                Write-Error $_
                Show-WpfMessageBox -Message "Error:`n`n$($_.Exception.Message)" -Title "Error" -Buttons "OK" -Icon "Error" -Owner $window | Out-Null
            } finally {
                Close-WpfProgressBar -Window $progress
            }
        })
    $btnExitInstaladores.Add_Click({
            & $resetChocoUi
            $window.Close()
        })
    $window.ShowDialog() | Out-Null
}
function Invoke-PortableTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,
        [Parameter(Mandatory)]
        [string]$Url,
        [Parameter(Mandatory)]
        [string]$ZipPath,
        [Parameter(Mandatory)]
        [string]$ExtractPath,
        [Parameter(Mandatory)]
        [string]$ExeName,
        [System.Windows.Controls.TextBlock]$InfoTextBlock,
        [System.Windows.Window]$OwnerWindow
    )
    try {
        $exePath = Join-Path $ExtractPath $ExeName
        Write-DzDebug "`t[DEBUG][Invoke-PortableTool] ToolName=$ToolName" ([System.ConsoleColor]::DarkGray)
        Write-DzDebug "`t[DEBUG][Invoke-PortableTool] Url=$Url" ([System.ConsoleColor]::DarkGray)
        Write-DzDebug "`t[DEBUG][Invoke-PortableTool] Zip=$ZipPath" ([System.ConsoleColor]::DarkGray)
        Write-DzDebug "`t[DEBUG][Invoke-PortableTool] Extract=$ExtractPath" ([System.ConsoleColor]::DarkGray)
        Write-DzDebug "`t[DEBUG][Invoke-PortableTool] ExePath=$exePath" ([System.ConsoleColor]::DarkGray)
        if (Test-Path -LiteralPath $exePath) {
            $msg = "$ToolName ya existe en:`n$exePath`n`nSí = Abrir local`nNo = Volver a descargar`nCancelar = Cancelar operación"
            $rExist = Show-WpfMessageBox -Message $msg -Title "Ya existe" -Buttons "YesNoCancel" -Icon "Question" -Owner $OwnerWindow
            Write-DzDebug "`t[DEBUG][Invoke-PortableTool] rExist=$rExist" ([System.ConsoleColor]::Cyan)
            if ($rExist -eq [System.Windows.MessageBoxResult]::Yes) {
                Start-Process $exePath
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Abriendo $ToolName existente..." }
                return $true
            }
            if ($rExist -eq [System.Windows.MessageBoxResult]::Cancel) {
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Operación cancelada." }
                return $false
            }
        } else {
            $r = Show-WpfMessageBox -Message "¿Deseas descargar $ToolName?" -Title "Confirmar descarga" -Buttons "YesNo" -Icon "Question" -Owner $OwnerWindow
            Write-DzDebug "`t[DEBUG][Invoke-PortableTool] confirm=$r" ([System.ConsoleColor]::Cyan)
            if ($r -ne [System.Windows.MessageBoxResult]::Yes) {
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Operación cancelada." }
                return $false
            }
        }
        $pw = Show-WpfProgressBar -Title "Descargando $ToolName" -Message "Iniciando..."
        if ($null -eq $pw -or $null -eq $pw.ProgressBar) {
            Write-DzDebug "`t[DEBUG][Invoke-PortableTool] ERROR: No progress window" ([System.ConsoleColor]::Red)
            return $false
        }
        try {
            if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue }
            Update-WpfProgressBar -Window $pw -Percent 0 -Message "Preparando descarga..."
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Preparando descarga..." }
            $ok = Download-FileWithProgressWpfStream -Url $Url -OutFile $ZipPath -Window $pw -OnStatus {
                param($p, $m)
                Write-DzDebug "`t[DEBUG][Invoke-PortableTool] $p% - $m" ([System.ConsoleColor]::DarkGray)
                if ($InfoTextBlock) { $InfoTextBlock.Text = $m }
            }
            if (-not $ok) { throw "Descarga fallida." }
            Update-WpfProgressBar -Window $pw -Percent 100 -Message "Extrayendo..."
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Extrayendo..." }
            $exeRunning = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -ieq $exePath }
            if (-not $exeRunning) {
                if (Test-Path -LiteralPath $ExtractPath) { Remove-Item -LiteralPath $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue }
            } else {
                Write-DzDebug "`t[DEBUG][Invoke-PortableTool] WARN: $ExeName está en ejecución, no se limpia carpeta" ([System.ConsoleColor]::Yellow)
            }
            Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force
            if (-not (Test-Path -LiteralPath $exePath)) { throw "No se encontró el ejecutable: $exePath" }
            Update-WpfProgressBar -Window $pw -Percent 100 -Message "Ejecutando..."
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Ejecutando..." }
            Start-Process $exePath
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Listo: Ejecutado $ToolName" }
            Write-DzDebug "`t[DEBUG][Invoke-PortableTool] OK: Ejecutado $ToolName" ([System.ConsoleColor]::Cyan)
            return $true
        } catch {
            $err = $_.Exception.Message
            Write-DzDebug "`t[DEBUG][Invoke-PortableTool] ERROR: $err" ([System.ConsoleColor]::Red)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: $err" }
            return $false
        } finally {
            Close-WpfProgressBar -Window $pw
        }
    } catch {
        Write-DzDebug "`t[DEBUG][Invoke-PortableTool] FATAL: $($_.Exception.Message)`n$($_.ScriptStackTrace)" ([System.ConsoleColor]::Magenta)
        return $false
    }
}
function Invoke-LectorDP {
    [CmdletBinding()]
    param(
        [System.Windows.Controls.TextBlock]$InfoTextBlock,
        [System.Windows.Window]$OwnerWindow
    )
    $pwPs = $null
    $pwDrv = $null
    try {
        $rMain = Show-WpfMessageBox `
            -Message "Este proceso ejecutará cambios de permisos con PsExec (SYSTEM) y puede descargar/instalar un driver.`n`n¿Deseas continuar?" `
            -Title "Confirmar operación" `
            -Buttons "YesNo" `
            -Icon "Warning" `
            -Owner $OwnerWindow
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Confirmación principal (rMain) = $rMain" ([System.ConsoleColor]::Cyan)
        if ($rMain -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Operación cancelada por el usuario." ([System.ConsoleColor]::Cyan)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Operación cancelada." }
            return $false
        }
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Iniciando proceso..." ([System.ConsoleColor]::DarkGray)
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Iniciando..." }
        $psexecPath = "C:\Temp\PsExec\PsExec.exe"
        $psexecZip = "C:\Temp\PSTools.zip"
        $psexecUrl = "https://download.sysinternals.com/files/PSTools.zip"
        $psexecExtractPath = "C:\Temp\PsExec"
        if (-not (Test-Path $psexecPath)) {
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] PsExec no encontrado. Descargando PSTools.zip" ([System.ConsoleColor]::Yellow)
            if (-not (Test-Path "C:\Temp")) { New-Item -Path "C:\Temp" -ItemType Directory | Out-Null }
            $pwPs = Show-WpfProgressBar -Title "Descargando PsExec" -Message "Preparando descarga..."
            if ($null -eq $pwPs -or $null -eq $pwPs.ProgressBar) {
                Write-DzDebug "`t[DEBUG][Invoke-LectorDP] ERROR: No se pudo crear progress bar para PsExec." ([System.ConsoleColor]::Red)
                return $false
            }
            if (Test-Path $psexecZip) { Remove-Item $psexecZip -Force -ErrorAction SilentlyContinue }
            try {
                Update-WpfProgressBar -Window $pwPs -Percent 0 -Message "Preparando descarga..."
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Descargando PsExec..." }
                $okPs = Download-FileWithProgressWpfStream `
                    -Url $psexecUrl `
                    -OutFile $psexecZip `
                    -Window $pwPs `
                    -OnStatus {
                    param($p, $m)
                    Write-DzDebug "`t[DEBUG][Invoke-LectorDP] PsExec: $p% - $m" ([System.ConsoleColor]::DarkGray)
                    if ($InfoTextBlock) { $InfoTextBlock.Text = "PsExec: $m" }
                }
                if (-not $okPs) { throw "Descarga de PSTools.zip fallida." }
                Update-WpfProgressBar -Window $pwPs -Percent 100 -Message "Extrayendo..."
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Extrayendo PsExec..." }
                if (Test-Path $psexecExtractPath) { Remove-Item $psexecExtractPath -Recurse -Force -ErrorAction SilentlyContinue }
                Expand-Archive -Path $psexecZip -DestinationPath $psexecExtractPath -Force
                if (-not (Test-Path $psexecPath)) { throw "No se pudo extraer PsExec.exe." }
                Write-DzDebug "`t[DEBUG][Invoke-LectorDP] PsExec descargado correctamente." ([System.ConsoleColor]::Cyan)
            } catch {
                Write-DzDebug "`t[DEBUG][Invoke-LectorDP] ERROR PsExec: $($_.Exception.Message)" ([System.ConsoleColor]::Red)
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Error PsExec: $($_.Exception.Message)" }
                return $false
            } finally {
                if ($pwPs) {
                    try { Close-WpfProgressBar -Window $pwPs } catch {}
                    $pwPs = $null
                }
            }
        } else {
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] PsExec ya instalado en: $psexecPath" ([System.ConsoleColor]::Cyan)
        }
        $grupoAdmin = ""
        $gruposLocales = net localgroup | Where-Object { $_ -match "Administrators|Administradores" }
        if ($gruposLocales -match "Administrators") {
            $grupoAdmin = "Administrators"
        } elseif ($gruposLocales -match "Administradores") {
            $grupoAdmin = "Administradores"
        } else {
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] ERROR: No se encontró grupo de administradores." ([System.ConsoleColor]::Red)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: No se encontró grupo Administradores." }
            return $false
        }
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Grupo admin detectado: $grupoAdmin" ([System.ConsoleColor]::Cyan)
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Grupo admin: $grupoAdmin" }
        $comando1 = "icacls C:\Windows\System32\en-us /grant `"$grupoAdmin`":F"
        $comando2 = "icacls C:\Windows\System32\en-us /grant `"NT AUTHORITY\SYSTEM`":F"
        $psexecCmd1 = "`"$psexecPath`" /accepteula /s cmd /c `"$comando1`""
        $psexecCmd2 = "`"$psexecPath`" /accepteula /s cmd /c `"$comando2`""
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Ejecutando: $comando1" ([System.ConsoleColor]::Yellow)
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Ejecutando icacls (1)..." }
        $output1 = & cmd /c $psexecCmd1
        Write-DzDebug ([string]$output1) ([System.ConsoleColor]::Gray)
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Ejecutando: $comando2" ([System.ConsoleColor]::Yellow)
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Ejecutando icacls (2)..." }
        $output2 = & cmd /c $psexecCmd2
        Write-DzDebug ([string]$output2) ([System.ConsoleColor]::Gray)
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Permisos actualizados." ([System.ConsoleColor]::Cyan)
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Permisos actualizados." }
        $ResponderDriver = Show-WpfMessageBox `
            -Message "¿Desea descargar e instalar el driver del lector?" `
            -Title "Descargar Driver" `
            -Buttons "YesNo" `
            -Icon "Question" `
            -Owner $OwnerWindow
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Respuesta driver = $ResponderDriver" ([System.ConsoleColor]::Cyan)
        if ($ResponderDriver -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Driver omitido por el usuario." ([System.ConsoleColor]::Cyan)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Proceso completado. Driver omitido." }
            return $true
        }
        $driverUrl = "https://softrestaurant.com/drivers?download=120:dp"
        $zipPath = "C:\Temp\Driver_DP.zip"
        $extractPath = "C:\Temp\Driver_DP"
        $msiPath = "C:\Temp\Driver_DP\x64\Setup.msi"
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Driver URL=$driverUrl" ([System.ConsoleColor]::DarkGray)
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] msiPath=$msiPath" ([System.ConsoleColor]::DarkGray)
        if (Test-Path $msiPath) {
            $rExistDrv = Show-WpfMessageBox `
                -Message "El driver ya existe en:`n$msiPath`n`nSí = Instalar local`nNo = Volver a descargar`nCancelar = Cancelar operación" `
                -Title "Driver ya existe" `
                -Buttons "YesNoCancel" `
                -Icon "Question" `
                -Owner $OwnerWindow
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Resultado existe driver = $rExistDrv" ([System.ConsoleColor]::Cyan)
            if ($rExistDrv -eq [System.Windows.MessageBoxResult]::Yes) {
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Instalando driver existente..." }
                Start-Process "msiexec.exe" -ArgumentList "/i `"$msiPath`" /passive" -Wait
                Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Driver instalado correctamente." ([System.ConsoleColor]::Cyan)
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Driver instalado correctamente." }
                return $true
            }
            if ($rExistDrv -eq [System.Windows.MessageBoxResult]::Cancel) {
                Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Instalación de driver cancelada." ([System.ConsoleColor]::Cyan)
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Instalación cancelada." }
                return $true
            }
        } else {
            $rDrv = Show-WpfMessageBox `
                -Message "¿Deseas descargar el driver del lector ahora?" `
                -Title "Confirmar descarga" `
                -Buttons "YesNo" `
                -Icon "Question" `
                -Owner $OwnerWindow
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Confirmación descarga = $rDrv" ([System.ConsoleColor]::Cyan)
            if ($rDrv -ne [System.Windows.MessageBoxResult]::Yes) {
                Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Descarga cancelada." ([System.ConsoleColor]::Cyan)
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Descarga cancelada." }
                return $true
            }
        }
        $pwDrv = Show-WpfProgressBar -Title "Descargando Driver DP" -Message "Preparando descarga..."
        if ($null -eq $pwDrv -or $null -eq $pwDrv.ProgressBar) {
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] ERROR: No se pudo crear progress bar para Driver." ([System.ConsoleColor]::Red)
            return $false
        }
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
        try {
            Update-WpfProgressBar -Window $pwDrv -Percent 0 -Message "Preparando descarga..."
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Descargando driver..." }
            $okDrv = Download-FileWithProgressWpfStream `
                -Url $driverUrl `
                -OutFile $zipPath `
                -Window $pwDrv `
                -OnStatus {
                param($p, $m)
                Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Driver: $p% - $m" ([System.ConsoleColor]::DarkGray)
                if ($InfoTextBlock) { $InfoTextBlock.Text = "Driver: $m" }
            }
            if (-not $okDrv) { throw "Descarga del driver fallida." }
            Update-WpfProgressBar -Window $pwDrv -Percent 100 -Message "Extrayendo..."
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Extrayendo driver..." }
            if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            if (-not (Test-Path $msiPath)) { throw "No se encontró $msiPath" }
            Update-WpfProgressBar -Window $pwDrv -Percent 100 -Message "Instalando..."
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Instalando driver..." }
            try { $pwDrv.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action] {}) | Out-Null } catch {}
            try {
                $pwDrv.Dispatcher.Invoke([action] {
                        $pwDrv.Topmost = $false
                        $pwDrv.WindowState = [System.Windows.WindowState]::Minimized
                    }) | Out-Null
            } catch {}
            Start-Process "msiexec.exe" -ArgumentList "/i `"$msiPath`" /passive" -Wait
            try {
                $pwDrv.Dispatcher.Invoke([action] {
                        $pwDrv.WindowState = [System.Windows.WindowState]::Normal
                    }) | Out-Null
            } catch {}
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] Driver instalado correctamente." ([System.ConsoleColor]::Cyan)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Driver instalado correctamente." }
            return $true
        } catch {
            Write-DzDebug "`t[DEBUG][Invoke-LectorDP] ERROR Driver: $($_.Exception.Message)" ([System.ConsoleColor]::Red)
            if ($InfoTextBlock) { $InfoTextBlock.Text = "Error Driver: $($_.Exception.Message)" }
            return $false
        }
    } catch {
        Write-DzDebug "`t[DEBUG][Invoke-LectorDP] FATAL: $($_.Exception.Message)`n$($_.ScriptStackTrace)" ([System.ConsoleColor]::Magenta)
        if ($InfoTextBlock) { $InfoTextBlock.Text = "Error: $($_.Exception.Message)" }
        return $false
    } finally {
        if ($pwDrv) {
            try { Close-WpfProgressBar -Window $pwDrv } catch {}
            $pwDrv = $null
        }
        if ($pwPs) {
            try { Close-WpfProgressBar -Window $pwPs } catch {}
            $pwPs = $null
        }
    }
}
Export-ModuleMember -Function @(
    'Check-Chocolatey', 'Test-ChocolateyInstalled', 'Install-Software', 'Download-File',
    'Expand-ArchiveFile', 'Show-SSMSInstallerDialog', 'Test-7ZipInstalled', 'Test-MegaToolsInstalled',
    'Get-InstalledChocoPackages', 'Search-ChocoPackages', 'Install-ChocoPackage', 'Uninstall-ChocoPackage',
    'Show-ChocolateyInstallerMenu', 'Invoke-PortableTool', 'Invoke-LectorDP'
)