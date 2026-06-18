#requires -Version 5.0

$script:DzR2WorkerUrl = "https://dztools-api.waterbetrayer.workers.dev"

function Get-R2WorkerUrl {
    [CmdletBinding()]
    param()
    return $script:DzR2WorkerUrl
}

function Test-R2CloudConfigured {
    [CmdletBinding()]
    param()
    return $true
}

function Invoke-R2WorkerJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Body,
        [string]$WorkerUrl = (Get-R2WorkerUrl),
        [Parameter(Mandatory = $true)][string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($WorkerUrl)) { throw "La URL del Worker está vacía." }
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

Export-ModuleMember -Function @(
    'Get-R2WorkerUrl',
    'Test-R2CloudConfigured',
    'Request-R2PresignedUploadUrl',
    'Send-FileToR2',
    'Get-R2DownloadLink',
    'Test-R2WorkerToken'
)
