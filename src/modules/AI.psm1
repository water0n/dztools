#requires -Version 5.0

$script:DzAiApiKey = $null
$script:DzAiModel = "gemini-2.5-flash"
$script:DzAiCurrentRunspace = $null
$script:DzAiCurrentPowerShell = $null
$script:DzAiCurrentAsync = $null
$script:DzAiCurrentTimer = $null
$script:DzAiCurrentJob = $null
$script:DzAiCurrentResult = $null
$script:DzAiCurrentStartedAt = $null
$script:DzAiCurrentLastWaitLogAt = [DateTime]::MinValue
$script:DzAiCurrentTimeoutSeconds = 100

function Write-DzAiDebug {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    $line = "[DEBUG][IA] $Message"
    if (Get-Command Write-DzDebug -ErrorAction SilentlyContinue) {
        Write-DzDebug $line $Color
    } else {
        Write-Host $line -ForegroundColor $Color
    }
}

function Clear-DzAiRequestState {
    try {
        if ($script:DzAiCurrentJob) {
            Remove-Job -Job $script:DzAiCurrentJob -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    try { if ($script:DzAiCurrentPowerShell) { $script:DzAiCurrentPowerShell.Dispose() } } catch {}
    try {
        if ($script:DzAiCurrentRunspace) {
            $script:DzAiCurrentRunspace.Close()
            $script:DzAiCurrentRunspace.Dispose()
        }
    } catch {}
    $script:DzAiCurrentPowerShell = $null
    $script:DzAiCurrentRunspace = $null
    $script:DzAiCurrentAsync = $null
    $script:DzAiCurrentTimer = $null
    $script:DzAiCurrentJob = $null
    $script:DzAiCurrentResult = $null
    $script:DzAiCurrentStartedAt = $null
    $script:DzAiCurrentLastWaitLogAt = [DateTime]::MinValue
}

function Get-DzAiTabHeaderText {
    param([Parameter(Mandatory = $true)]$TabItem)

    if ($TabItem.Header -is [string]) { return [string]$TabItem.Header }
    if ($TabItem.Header -is [System.Windows.Controls.StackPanel]) {
        foreach ($child in $TabItem.Header.Children) {
            if ($child -is [System.Windows.Controls.TextBlock]) {
                return [string]$child.Text
            }
        }
    }
    if ($TabItem.Header) { return [string]$TabItem.Header }
    return ""
}

function Move-DzAiTabLast {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.Windows.Controls.TabControl]$TabControl)

    $aiTab = $null
    foreach ($item in $TabControl.Items) {
        if ($item -isnot [System.Windows.Controls.TabItem]) { continue }
        $header = Get-DzAiTabHeaderText -TabItem $item
        if ($header -eq "IA") {
            $aiTab = $item
            break
        }
    }
    if (-not $aiTab) { return $null }

    $lastIndex = $TabControl.Items.Count - 1
    if ($TabControl.Items.IndexOf($aiTab) -ne $lastIndex) {
        $selected = $TabControl.SelectedItem
        $TabControl.Items.Remove($aiTab)
        [void]$TabControl.Items.Add($aiTab)
        if ($selected) { $TabControl.SelectedItem = $selected }
    }
    return $aiTab
}

function Ensure-DzAiTab {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.Windows.Controls.TabControl]$TabControl)

    return (Move-DzAiTabLast -TabControl $TabControl)
}

function Set-DzAiStatus {
    param([string]$Text)
    Write-DzAiDebug "Estado UI: $Text" ([System.ConsoleColor]::DarkGray)
    try {
        if ($global:lblDzAiStatus) { $global:lblDzAiStatus.Text = $Text }
    } catch {}
}

function Set-DzAiOutput {
    param([string]$Text)
    $len = if ($null -eq $Text) { 0 } else { ([string]$Text).Length }
    Write-DzAiDebug "Actualizando salida IA. Caracteres=$len" ([System.ConsoleColor]::DarkGray)
    try {
        if ($global:txtDzAiOutput) {
            $global:txtDzAiOutput.Text = $Text
            $global:txtDzAiOutput.SelectionStart = 0
            $global:txtDzAiOutput.SelectionLength = 0
            $global:txtDzAiOutput.ScrollToHome()
        }
    } catch {}
}

function Set-DzAiBusy {
    param([bool]$IsBusy)
    Write-DzAiDebug "Busy=$IsBusy" ([System.ConsoleColor]::DarkGray)
    try {
        if ($global:btnDzAiExplainQuery) { $global:btnDzAiExplainQuery.IsEnabled = -not $IsBusy }
        if ($global:btnDzAiExplainMessages) { $global:btnDzAiExplainMessages.IsEnabled = -not $IsBusy }
        if ($global:btnDzAiUseApiKey) { $global:btnDzAiUseApiKey.IsEnabled = -not $IsBusy }
    } catch {}
}

function Show-DzAiKeyPrompt {
    param([string]$Message = "")
    Write-DzAiDebug "Mostrando captura de API key. Mensaje='$Message'" ([System.ConsoleColor]::Yellow)
    $script:DzAiApiKey = $null
    try {
        if ($global:pnlDzAiKeyPrompt) { $global:pnlDzAiKeyPrompt.Visibility = [System.Windows.Visibility]::Visible }
        if ($global:pnlDzAiActions) { $global:pnlDzAiActions.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($global:pwdDzAiApiKey) {
            $global:pwdDzAiApiKey.Clear()
            $global:pwdDzAiApiKey.Focus() | Out-Null
        }
    } catch {}
    if (-not [string]::IsNullOrWhiteSpace($Message)) { Set-DzAiOutput $Message }
    Set-DzAiStatus "API key requerida"
}

function Confirm-DzAiApiKey {
    Write-DzAiDebug "Click/Aceptar API key recibido." ([System.ConsoleColor]::Cyan)
    try {
        if (-not $global:pwdDzAiApiKey) { return }
        $key = [string]$global:pwdDzAiApiKey.Password
        Write-DzAiDebug ("API key capturada en PasswordBox. Longitud={0}" -f $key.Length) ([System.ConsoleColor]::DarkGray)
        if ([string]::IsNullOrWhiteSpace($key)) {
            Set-DzAiOutput "Escribe la API key de Gemini para habilitar la pestaña IA."
            Set-DzAiStatus "API key requerida"
            return
        }
        $script:DzAiApiKey = $key.Trim()
        Write-DzAiDebug ("API key guardada solo en memoria. Longitud={0}" -f $script:DzAiApiKey.Length) ([System.ConsoleColor]::Green)
        $global:pwdDzAiApiKey.Clear()
        if ($global:pnlDzAiKeyPrompt) { $global:pnlDzAiKeyPrompt.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($global:pnlDzAiActions) { $global:pnlDzAiActions.Visibility = [System.Windows.Visibility]::Visible }
        Set-DzAiOutput "API key cargada solo en memoria. Elige una accion."
        Set-DzAiStatus "Gemini listo"
    } catch {
        Write-DzAiDebug ("Error aceptando API key: {0}" -f $_.Exception.Message) ([System.ConsoleColor]::Red)
        Set-DzAiOutput ("No se pudo cargar la API key: {0}" -f $_.Exception.Message)
        Set-DzAiStatus "Error"
    }
}

function Get-DzAiActiveQueryText {
    try {
        if (-not $global:tcQueries) { return "" }
        $editor = Get-ActiveQueryRichTextBox -TabControl $global:tcQueries
        if (-not $editor) { return "" }
        $text = Get-SqlEditorText -Editor $editor
        if ($null -eq $text) { return "" }
        Write-DzAiDebug ("Query activo obtenido. Caracteres={0}" -f ([string]$text).Length) ([System.ConsoleColor]::DarkGray)
        return ([string]$text).Trim()
    } catch {
        Write-DzAiDebug ("Error obteniendo query activo: {0}" -f $_.Exception.Message) ([System.ConsoleColor]::Red)
        return ""
    }
}

function Invoke-DzGeminiGenerateContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$SystemInstruction = "",
        [string]$Model = "gemini-2.5-flash",
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [double]$Temperature = 0.2,
        [int]$MaxOutputTokens = 2048
    )

    if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "No se ha capturado la API key de Gemini." }
    if ([string]::IsNullOrWhiteSpace($Model)) { $Model = "gemini-2.5-flash" }
    if ($MaxOutputTokens -lt 128) { $MaxOutputTokens = 128 }

    $modelName = if ($Model -match '^models/') { $Model } else { "models/$Model" }
    $uri = "https://generativelanguage.googleapis.com/v1beta/$modelName`:generateContent?key=$ApiKey"
    Write-DzAiDebug "Invoke-DzGeminiGenerateContent modelo=$modelName uri=v1beta/...:generateContent" ([System.ConsoleColor]::Cyan)
    $bodyObject = @{
        contents = @(
            @{
                parts = @(@{ text = $Prompt })
            }
        )
        generationConfig = @{
            temperature = $Temperature
            maxOutputTokens = $MaxOutputTokens
        }
    }
    if ($modelName -match 'gemini-2\.5') {
        $bodyObject.generationConfig.thinkingConfig = @{ thinkingBudget = 0 }
    }
    if (-not [string]::IsNullOrWhiteSpace($SystemInstruction)) {
        $bodyObject.systemInstruction = @{
            parts = @(@{ text = $SystemInstruction })
        }
    }

    $body = $bodyObject | ConvertTo-Json -Depth 12
    $headers = @{
        "Content-Type" = "application/json"
    }

    try {
        Write-DzAiDebug ("Enviando request Gemini. PromptChars={0} BodyChars={1}" -f $Prompt.Length, $body.Length) ([System.ConsoleColor]::Cyan)
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 75
        Write-DzAiDebug "Respuesta HTTP recibida de Gemini." ([System.ConsoleColor]::Green)
        $text = $response.candidates[0].content.parts[0].text
        Write-DzAiDebug ("Texto Gemini recibido. Caracteres={0} FinishReason={1}" -f $text.Length, $response.candidates[0].finishReason) ([System.ConsoleColor]::Green)
        if ([string]::IsNullOrWhiteSpace($text)) { throw "Gemini no devolvio texto." }
        return $text
    } catch {
        $message = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $message = "$message $($_.ErrorDetails.Message)" }
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                $apiError = $reader.ReadToEnd()
                if (-not [string]::IsNullOrWhiteSpace($apiError)) { $message = $apiError }
            }
        } catch {}
        Write-DzAiDebug "Error Gemini: $message" ([System.ConsoleColor]::Red)
        throw "Error llamando a Gemini: $message"
    }
}

function Start-DzAiRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$SystemInstruction,
        [string]$WorkingText = "Consultando Gemini..."
    )

    Write-DzAiDebug ("Start-DzAiRequest. PromptChars={0} SystemChars={1}" -f $Prompt.Length, $SystemInstruction.Length) ([System.ConsoleColor]::Cyan)

    if ([string]::IsNullOrWhiteSpace($script:DzAiApiKey)) {
        Write-DzAiDebug "No hay API key en memoria." ([System.ConsoleColor]::Yellow)
        Show-DzAiKeyPrompt -Message "Escribe la API key de Gemini para usar IA."
        return
    }
    if (($script:DzAiCurrentAsync -and -not $script:DzAiCurrentAsync.IsCompleted) -or
        ($script:DzAiCurrentJob -and $script:DzAiCurrentJob.State -eq 'Running')) {
        Write-DzAiDebug "Solicitud IA ignorada porque ya hay una en curso." ([System.ConsoleColor]::Yellow)
        Set-DzAiOutput "Ya hay una consulta de IA en curso. Espera a que termine."
        return
    }

    Set-DzAiBusy $true
    Set-DzAiStatus $WorkingText
    Set-DzAiOutput $WorkingText

    $worker = {
        param($Prompt, $SystemInstruction, $Model, $ApiKey)

        function Send-WorkerLog {
            param([string]$Message)
            Write-Output @{ type = 'log'; message = $Message }
        }

        try {
            Send-WorkerLog "Worker iniciado."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $fallback = if ($Model -match '^models/') { $Model } else { "models/$Model" }
            $preferredModels = @(
                'models/gemini-2.5-flash',
                'models/gemini-2.0-flash',
                'models/gemini-flash-latest',
                'models/gemini-1.5-flash-latest'
            )

            $modelName = $fallback
            try {
                Send-WorkerLog "Consultando modelos disponibles..."
                $modelsUri = "https://generativelanguage.googleapis.com/v1beta/models?key=$ApiKey"
                $modelsResponse = Invoke-RestMethod -Uri $modelsUri -Method Get -TimeoutSec 30
                $generateModels = @($modelsResponse.models | Where-Object { $_.supportedGenerationMethods -contains 'generateContent' })
                foreach ($preferred in $preferredModels) {
                    $match = $generateModels | Where-Object { $_.name -eq $preferred } | Select-Object -First 1
                    if ($null -ne $match) {
                        $modelName = $match.name
                        break
                    }
                }
                if ($modelName -eq $fallback -and $generateModels.Count -gt 0) {
                    $modelName = $generateModels[0].name
                }
                Send-WorkerLog "Modelo seleccionado: $modelName"
            } catch {
                $msg = $_.Exception.Message
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = "$msg $($_.ErrorDetails.Message)" }
                Send-WorkerLog "No se pudieron listar modelos. Usando fallback $fallback. Error: $msg"
                $modelName = $fallback
            }

            $uri = "https://generativelanguage.googleapis.com/v1beta/$($modelName):generateContent?key=$ApiKey"
            Send-WorkerLog "Preparando request generateContent. Modelo=$modelName PromptChars=$($Prompt.Length)"
            $bodyObject = @{
                contents = @(
                    @{
                        parts = @(@{ text = $Prompt })
                    }
                )
                generationConfig = @{
                    temperature = 0.2
                    maxOutputTokens = 900
                }
            }
            if ($modelName -match 'gemini-2\.5') {
                $bodyObject.generationConfig.thinkingConfig = @{ thinkingBudget = 0 }
            }
            if (-not [string]::IsNullOrWhiteSpace($SystemInstruction)) {
                $bodyObject.systemInstruction = @{ parts = @(@{ text = $SystemInstruction }) }
            }
            $body = $bodyObject | ConvertTo-Json -Depth 12 -Compress
            $headers = @{
                "Content-Type" = "application/json"
            }
            Send-WorkerLog "Enviando request a Gemini. BodyChars=$($body.Length)"
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 90
            Send-WorkerLog "Respuesta recibida de Gemini."
            if ($response.candidates -and $response.candidates[0].finishReason) {
                Send-WorkerLog "FinishReason=$($response.candidates[0].finishReason)"
            }
            $text = $response.candidates[0].content.parts[0].text
            if ([string]::IsNullOrWhiteSpace($text)) { throw "Gemini no devolvio texto." }
            Send-WorkerLog "Texto recibido. Caracteres=$($text.Length)"
            Write-Output @{ type = 'result'; Ok = $true; Text = $text }
        } catch {
            $message = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $message = "$message $($_.ErrorDetails.Message)" }
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $apiError = $reader.ReadToEnd()
                    if (-not [string]::IsNullOrWhiteSpace($apiError)) { $message = $apiError }
                }
            } catch {}
            Send-WorkerLog "ERROR: $message"
            Write-Output @{ type = 'result'; Ok = $false; Error = $message }
        }
    }

    $script:DzAiCurrentResult = $null
    $script:DzAiCurrentStartedAt = [DateTime]::Now
    $script:DzAiCurrentLastWaitLogAt = [DateTime]::MinValue
    $job = Start-Job -ScriptBlock $worker -ArgumentList @(
        $Prompt,
        $SystemInstruction,
        $script:DzAiModel,
        $script:DzAiApiKey
    )
    $script:DzAiCurrentJob = $job
    $startedAt = $script:DzAiCurrentStartedAt
    $timeoutSeconds = $script:DzAiCurrentTimeoutSeconds
    $stateBag = @{
        Result = $null
        LastWaitLogAt = [DateTime]::MinValue
    }
    Write-DzAiDebug ("Start-Job IA lanzado. Id={0}" -f $job.Id) ([System.ConsoleColor]::Cyan)

    $processJobOutput = {
        param(
            [object[]]$Items,
            [hashtable]$StateBag
        )

        foreach ($item in @($Items)) {
            if ($null -eq $item) { continue }
            $itemType = $null
            if ($item -is [System.Collections.IDictionary]) {
                $itemType = [string]$item['type']
            } elseif ($item.PSObject.Properties['type']) {
                $itemType = [string]$item.type
            }

            if ($itemType -eq 'log') {
                $msg = if ($item -is [System.Collections.IDictionary]) { [string]$item['message'] } else { [string]$item.message }
                if (-not [string]::IsNullOrWhiteSpace($msg)) {
                    Write-DzAiDebug "[Worker] $msg" ([System.ConsoleColor]::DarkGray)
                }
            } elseif ($itemType -eq 'result') {
                $StateBag.Result = $item
                Write-DzAiDebug "Resultado del worker recibido." ([System.ConsoleColor]::Cyan)
            } else {
                Write-DzAiDebug "[WorkerOutput] $item" ([System.ConsoleColor]::DarkGray)
            }
        }
    }

    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(600)
    $timer.Add_Tick({
        if (-not $job) { return }

        $elapsed = 0
        try {
            if ($startedAt) {
                $elapsed = [int]([DateTime]::Now - $startedAt).TotalSeconds
            }
        } catch { $elapsed = 0 }

        $state = $job.State
        if ($state -ne 'Completed' -and $state -ne 'Failed' -and $state -ne 'Stopped') {
            try {
                $newOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable runningErrors)
                & $processJobOutput -Items $newOutput -StateBag $stateBag
                foreach ($runningError in @($runningErrors)) {
                    Write-DzAiDebug ("[WorkerError] {0}" -f $runningError.Exception.Message) ([System.ConsoleColor]::Red)
                }
            } catch {
                Write-DzAiDebug ("Error leyendo salida parcial del job: {0}" -f $_.Exception.Message) ([System.ConsoleColor]::Red)
            }

            if ($elapsed -gt 0 -and ([DateTime]::Now - $stateBag.LastWaitLogAt).TotalSeconds -ge 5) {
                Write-DzAiDebug "Esperando respuesta de Gemini... ${elapsed}s EstadoJob=$state" ([System.ConsoleColor]::DarkYellow)
                $stateBag.LastWaitLogAt = [DateTime]::Now
            }
            if ($elapsed -ge $timeoutSeconds) {
                Write-DzAiDebug "Timeout IA alcanzado (${elapsed}s). Deteniendo job." ([System.ConsoleColor]::Red)
                try { $timer.Stop() } catch {}
                try { Stop-Job -Job $job -ErrorAction SilentlyContinue } catch {}
                Set-DzAiOutput "Gemini no respondio antes del tiempo limite (${elapsed}s). Revisa consola/debug, red, cuota o API key."
                Set-DzAiStatus "Timeout"
                Set-DzAiBusy $false
                Clear-DzAiRequestState
            }
            return
        }

        try {
            Write-DzAiDebug "Job IA finalizado. Estado=$state. Procesando salida..." ([System.ConsoleColor]::Cyan)
            $timer.Stop()
            try {
                $remaining = @(Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable receiveErrors)
                & $processJobOutput -Items $remaining -StateBag $stateBag
                foreach ($receiveError in @($receiveErrors)) {
                    Write-DzAiDebug ("[WorkerError] {0}" -f $receiveError.Exception.Message) ([System.ConsoleColor]::Red)
                }
            } catch {
                Write-DzAiDebug ("Error leyendo salida final del job: {0}" -f $_.Exception.Message) ([System.ConsoleColor]::Red)
            }
            $result = $stateBag.Result
            $script:DzAiCurrentResult = $result
            if ($result -and $result.Ok) {
                Write-DzAiDebug ("Respuesta OK. Caracteres={0}" -f ([string]$result.Text).Length) ([System.ConsoleColor]::Green)
                Set-DzAiOutput ([string]$result.Text)
                Set-DzAiStatus "Gemini listo"
            } else {
                $err = if ($result -and $result.Error) { [string]$result.Error } else { "Error desconocido llamando a Gemini." }
                Write-DzAiDebug "Respuesta con error: $err" ([System.ConsoleColor]::Red)
                Set-DzAiOutput ("No se pudo obtener respuesta de Gemini.`n`n{0}" -f $err)
                Set-DzAiStatus "Error"
                if ($err -match "API_KEY_INVALID|API key not valid|PERMISSION_DENIED|invalid.*key") {
                    Show-DzAiKeyPrompt -Message "La API key no fue aceptada por Gemini. Escríbela de nuevo."
                }
            }
        } catch {
            Write-DzAiDebug ("Error procesando respuesta: {0}" -f $_.Exception.Message) ([System.ConsoleColor]::Red)
            Set-DzAiOutput ("Error procesando la respuesta de Gemini:`n{0}" -f $_.Exception.Message)
            Set-DzAiStatus "Error"
        } finally {
            Set-DzAiBusy $false
            Clear-DzAiRequestState
        }
    }.GetNewClosure())
    $script:DzAiCurrentTimer = $timer
    $timer.Start()
    Write-DzAiDebug "Timer IA iniciado." ([System.ConsoleColor]::DarkGray)
}

function Invoke-DzAiExplainQuery {
    Write-DzAiDebug "Boton 'Explica el Query' presionado." ([System.ConsoleColor]::Cyan)
    $query = Get-DzAiActiveQueryText
    if ([string]::IsNullOrWhiteSpace($query)) {
        Write-DzAiDebug "No hay query activo para explicar." ([System.ConsoleColor]::Yellow)
        Set-DzAiOutput "No hay query en la pestaña activa."
        return
    }

    $system = "Eres un asistente experto en SQL Server y soporte tecnico. Responde en espanol claro, practico y breve. Maximo 8 lineas. No uses introducciones largas, no repitas el query completo, no ejecutes SQL ni inventes objetos que no aparecen en el texto."
    $prompt = @"
Explica el siguiente query SQL para un tecnico o administrador.

Formato:
- 3 a 6 bullets cortos.
- Menciona tablas/filtros/joins importantes si aparecen.
- Si modifica datos, marca el riesgo.
- Si aplica, da 1 revision concreta.

QUERY:
$query
"@
    Start-DzAiRequest -Prompt $prompt -SystemInstruction $system -WorkingText "Explicando query con Gemini..."
}

function Invoke-DzAiExplainMessages {
    Write-DzAiDebug "Boton 'Explica los mensajes' presionado." ([System.ConsoleColor]::Cyan)
    $messages = ""
    try {
        if ($global:txtMessages) { $messages = [string]$global:txtMessages.Text }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($messages)) {
        Write-DzAiDebug "No hay mensajes para explicar." ([System.ConsoleColor]::Yellow)
        Set-DzAiOutput "Primero ejecuta un query."
        return
    }
    Write-DzAiDebug ("Mensajes obtenidos. Caracteres={0}" -f $messages.Length) ([System.ConsoleColor]::DarkGray)

    $query = Get-DzAiActiveQueryText
    $querySection = "QUERY ACTIVO: No disponible."
    if (-not [string]::IsNullOrWhiteSpace($query)) {
        $querySection = "QUERY ACTIVO:`n$query"
        Write-DzAiDebug ("Query incluido con mensajes. Caracteres={0}" -f $query.Length) ([System.ConsoleColor]::DarkGray)
    } else {
        Write-DzAiDebug "No hay query activo para adjuntar a mensajes." ([System.ConsoleColor]::DarkGray)
    }

    $system = "Eres un asistente experto en SQL Server y soporte tecnico. Explica mensajes de ejecucion en espanol claro y accionable. Maximo 8 lineas. No repitas los mensajes completos ni des pasos genericos de SSMS salvo que sean necesarios. Usa el query activo para diagnosticar si viene incluido. No inventes detalles fuera del texto."
    $prompt = @"
Explica los siguientes mensajes generados por la ejecucion de un query SQL.

Formato:
- 1 linea con la causa probable.
- 2 a 4 bullets con que corregir/revisar.
- Si el query no coincide con el error, dilo claramente.

$querySection

MENSAJES:
$messages
"@
    Start-DzAiRequest -Prompt $prompt -SystemInstruction $system -WorkingText "Explicando mensajes con Gemini..."
}

function Initialize-DzAiTab {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.Windows.Window]$Window)

    try {
        Write-DzAiDebug "Inicializando pestaña IA." ([System.ConsoleColor]::Cyan)
        $global:pnlDzAiKeyPrompt = $Window.FindName("pnlDzAiKeyPrompt")
        $global:pnlDzAiActions = $Window.FindName("pnlDzAiActions")
        $global:pwdDzAiApiKey = $Window.FindName("pwdDzAiApiKey")
        $global:btnDzAiUseApiKey = $Window.FindName("btnDzAiUseApiKey")
        $global:btnDzAiExplainQuery = $Window.FindName("btnDzAiExplainQuery")
        $global:btnDzAiExplainMessages = $Window.FindName("btnDzAiExplainMessages")
        $global:txtDzAiOutput = $Window.FindName("txtDzAiOutput")
        $global:lblDzAiStatus = $Window.FindName("lblDzAiStatus")

        if ($global:tcResults) { [void](Move-DzAiTabLast -TabControl $global:tcResults) }
        Write-DzAiDebug "Controles IA localizados y pestaña movida al final." ([System.ConsoleColor]::DarkGray)

        if ($global:btnDzAiUseApiKey) {
            $global:btnDzAiUseApiKey.Add_Click({ Confirm-DzAiApiKey }.GetNewClosure())
        }
        if ($global:pwdDzAiApiKey) {
            $global:pwdDzAiApiKey.Add_KeyDown({
                param($sender, $e)
                if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                    Confirm-DzAiApiKey
                    $e.Handled = $true
                }
            }.GetNewClosure())
        }
        if ($global:btnDzAiExplainQuery) {
            $global:btnDzAiExplainQuery.Add_Click({ Invoke-DzAiExplainQuery }.GetNewClosure())
        }
        if ($global:btnDzAiExplainMessages) {
            $global:btnDzAiExplainMessages.Add_Click({ Invoke-DzAiExplainMessages }.GetNewClosure())
        }

        Show-DzAiKeyPrompt -Message "Escribe la API key de Gemini. No se guardara en archivos ni configuraciones; solo vivira hasta cerrar la aplicacion."
    } catch {
        Write-DzAiDebug ("Error inicializando pestaña IA: {0}" -f $_.Exception.Message) ([System.ConsoleColor]::Red)
        Write-Host "[IA] Error inicializando pestaña IA: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Export-ModuleMember -Function @(
    'Initialize-DzAiTab',
    'Ensure-DzAiTab',
    'Move-DzAiTabLast',
    'Invoke-DzGeminiGenerateContent',
    'Invoke-DzAiExplainQuery',
    'Invoke-DzAiExplainMessages',
    'Confirm-DzAiApiKey',
    'Show-DzAiKeyPrompt',
    'Clear-DzAiRequestState',
    'Set-DzAiStatus',
    'Set-DzAiOutput',
    'Set-DzAiBusy',
    'Write-DzAiDebug'
)
