#requires -Version 5.0

$script:DzCloudSection = "cloud"
$script:DzCloudUrlKey = "R2WorkerUrl"

function Get-R2WorkerUrl {
    [CmdletBinding()]
    param()
    $map = Get-DzIniSectionMap -Section $script:DzCloudSection
    if ($map.ContainsKey($script:DzCloudUrlKey)) {
        return ([string]$map[$script:DzCloudUrlKey]).Trim().TrimEnd("/")
    }
    return ""
}

function Set-R2WorkerUrl {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Url)
    Update-DzIniSetting -Section $script:DzCloudSection -Key $script:DzCloudUrlKey -Value $Url.Trim().TrimEnd("/")
}

function Test-R2CloudConfigured {
    [CmdletBinding()]
    param()
    return -not [string]::IsNullOrWhiteSpace((Get-R2WorkerUrl))
}

function Invoke-R2WorkerJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Body,
        [string]$WorkerUrl = (Get-R2WorkerUrl),
        [Parameter(Mandatory = $true)][string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($WorkerUrl)) { throw "No se ha configurado la URL del Worker." }
    if ([string]::IsNullOrWhiteSpace($Token)) { throw "No se ha configurado el token de nube." }

    $uri = "{0}{1}" -f $WorkerUrl.TrimEnd("/"), $Path
    $headers = @{ Authorization = "Bearer $Token" }
    $jsonBody = $Body | ConvertTo-Json -Depth 6 -Compress

    try {
        return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
    } catch {
        $message = $_.Exception.Message
        try {
            $response = $_.Exception.Response
            if ($response) {
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $bodyText = $reader.ReadToEnd()
                    if (-not [string]::IsNullOrWhiteSpace($bodyText)) { $message = $bodyText }
                }
            }
        } catch {}
        throw "Error llamando al Worker: $message"
    }
}

function Request-R2PresignedUploadUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$WorkerUrl = (Get-R2WorkerUrl),
        [Parameter(Mandatory = $true)][string]$Token
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "No existe el archivo para subir: $FilePath"
    }

    $item = Get-Item -LiteralPath $FilePath
    Invoke-R2WorkerJson -Path "/v1/uploads" -WorkerUrl $WorkerUrl -Token $Token -Body @{
        fileName = $item.Name
        size = [int64]$item.Length
        contentType = "application/zip"
    }
}

function Send-FileToR2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$UploadUrl,
        [string]$ContentType = "application/zip",
        [scriptblock]$ProgressCallback
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "No existe el archivo para subir: $FilePath"
    }

    $file = Get-Item -LiteralPath $FilePath
    $request = [System.Net.HttpWebRequest]::Create($UploadUrl)
    $request.Method = "PUT"
    $request.ContentType = $ContentType
    $request.ContentLength = [int64]$file.Length
    $request.AllowWriteStreamBuffering = $false
    $request.Timeout = 300000
    $request.ReadWriteTimeout = 300000

    $buffer = New-Object byte[] (1024 * 1024)
    $inputStream = $null
    $requestStream = $null
    $response = $null
    try {
        $inputStream = [System.IO.File]::OpenRead($FilePath)
        $requestStream = $request.GetRequestStream()
        $sent = [int64]0
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $requestStream.Write($buffer, 0, $read)
            $sent += $read
            if ($ProgressCallback) {
                & $ProgressCallback $sent ([int64]$file.Length)
            }
        }
        $requestStream.Flush()
        $response = $request.GetResponse()
        return @{
            Success = $true
            StatusCode = [int]$response.StatusCode
            StatusDescription = $response.StatusDescription
        }
    } catch {
        throw "Error subiendo archivo a R2: $($_.Exception.Message)"
    } finally {
        if ($response) { try { $response.Close() } catch {} }
        if ($requestStream) { try { $requestStream.Dispose() } catch {} }
        if ($inputStream) { try { $inputStream.Dispose() } catch {} }
    }
}

function Get-R2DownloadLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ObjectKey,
        [int]$TtlSeconds = 259200,
        [string]$WorkerUrl = (Get-R2WorkerUrl),
        [Parameter(Mandatory = $true)][string]$Token
    )

    Invoke-R2WorkerJson -Path "/v1/downloads" -WorkerUrl $WorkerUrl -Token $Token -Body @{
        objectKey = $ObjectKey
        ttlSeconds = $TtlSeconds
    }
}

function Test-R2WorkerToken {
    [CmdletBinding()]
    param(
        [string]$WorkerUrl = (Get-R2WorkerUrl),
        [Parameter(Mandatory = $true)][string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($WorkerUrl)) { return $false }
    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }

    try {
        $uri = "{0}/v1/health" -f $WorkerUrl.TrimEnd("/")
        $result = Invoke-RestMethod -Method Get -Uri $uri -ErrorAction Stop
        return ($result.ok -eq $true)
    } catch {
        return $false
    }
}

function Show-R2CloudConfigDialog {
    [CmdletBinding()]
    param($Owner)

    Add-Type -AssemblyName PresentationFramework
    $theme = Get-DzUiTheme
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Configurar acceso nube"
        Width="520" Height="190"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="{DynamicResource FormBg}"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Height" Value="32"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="Height" Value="32"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="105"/>
      <Setter Property="Padding" Value="12,5"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
    </Style>
  </Window.Resources>
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="URL del Worker" FontWeight="SemiBold" Margin="0,0,0,6"/>
    <TextBox Grid.Row="1" Name="txtWorkerUrl" Margin="0,0,0,12"/>
    <TextBlock Grid.Row="2" Text="El secret/token no se guarda; se captura manualmente en cada respaldo." TextWrapping="Wrap" Margin="0,0,0,12"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="btnCancel" Content="Cancelar" IsCancel="True"/>
      <Button Name="btnSave" Content="Guardar" IsDefault="True"/>
    </StackPanel>
  </Grid>
</Window>
"@

    $ui = New-WpfWindow -Xaml $xaml -PassThru
    $window = $ui.Window
    $c = $ui.Controls
    Set-DzWpfThemeResources -Window $window -Theme $theme
    try { if ($Owner) { $window.Owner = $Owner } else { Set-WpfDialogOwner -Dialog $window } } catch {}
    $txtWorkerUrl = $c["txtWorkerUrl"]
    $btnSave = $c["btnSave"]
    $btnCancel = $c["btnCancel"]
    if (-not $txtWorkerUrl -or -not $btnSave -or -not $btnCancel) {
        throw "Controles WPF incompletos en configuración nube."
    }

    $txtWorkerUrl.Text = Get-R2WorkerUrl

    $btnCancel.Add_Click({ $window.DialogResult = $false; $window.Close() })
    $btnSave.Add_Click({
        $url = ([string]$txtWorkerUrl.Text).Trim().TrimEnd("/")
        if ([string]::IsNullOrWhiteSpace($url)) {
            Ui-Warn "Captura la URL del Worker." "Datos incompletos" $window
            return
        }
        if ($url -notmatch '^https://') {
            Ui-Warn "La URL del Worker debe iniciar con https://." "URL inválida" $window
            return
        }
        Set-R2WorkerUrl -Url $url
        Ui-Info "URL del Worker guardada en dztools.ini. El secret se pedirá en cada respaldo." "Configuración guardada" $window
        $window.DialogResult = $true
        $window.Close()
    })

    return ($window.ShowDialog() -eq $true)
}

Export-ModuleMember -Function @(
    'Get-R2WorkerUrl',
    'Set-R2WorkerUrl',
    'Test-R2CloudConfigured',
    'Request-R2PresignedUploadUrl',
    'Send-FileToR2',
    'Get-R2DownloadLink',
    'Test-R2WorkerToken',
    'Show-R2CloudConfigDialog'
)
