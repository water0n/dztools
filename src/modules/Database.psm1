if ($PSVersionTable.PSVersion.Major -lt 5) { throw "Se requiere PowerShell 5.0 o superior." }
$script:queryTabCounter = 1
#Database.psm1 - Módulo de funciones de acceso a bases de datos SQL Server
function New-DzSqlConnectionFromCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential
    )
    $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
    $connectionString = "Server=$Server;Database=$Database;User Id=$($Credential.UserName);Password=$plainPassword;MultipleActiveResultSets=True"
    @{
        Connection    = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        PlainPassword = $plainPassword
        PasswordBstr  = $passwordBstr
    }
}
function New-DzSqlConnectionFromPlain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $connectionString = "Server=$Server;Database=$Database;User Id=$User;Password=$Password;MultipleActiveResultSets=True"
    New-Object System.Data.SqlClient.SqlConnection($connectionString)
}
function Resolve-DzSqlMessageSummary {
    [CmdletBinding()]
    param([Parameter()][System.Collections.Generic.List[string]]$Messages)
    if (-not $Messages) { return "" }
    $unique = @($Messages | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($unique.Count -eq 0) { return "" }
    $unique -join "`n"
}
function Write-DzSqlResultSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Result,
        [Parameter()][string]$Context
    )
    $prefix = if ([string]::IsNullOrWhiteSpace($Context)) { "" } else { "[$Context] " }
    if (-not $Result.Success) {
        Write-Host "$prefix Error SQL: $($Result.ErrorMessage)" -ForegroundColor Red
        return
    }
    if ($Result.ContainsKey('ResultSets') -and $Result.ResultSets -and $Result.ResultSets.Count -gt 0) {
        $totalRows = ($Result.ResultSets | Measure-Object -Property RowCount -Sum).Sum
        Write-Host "$prefix Resultado: $($Result.ResultSets.Count) conjunto(s), $totalRows fila(s)."
        return
    }
    if ($Result.ContainsKey('DataTable') -and $Result.DataTable) {
        Write-Host "$prefix Resultado: $($Result.DataTable.Rows.Count) fila(s)."
        return
    }
    if ($Result.ContainsKey('RowsAffected')) {
        Write-Host "$prefix Filas afectadas: $($Result.RowsAffected)"
        return
    }
    Write-Host "$prefix Sin resultados."
}
function Invoke-DzSqlCommandInternal {
    [CmdletBinding(DefaultParameterSetName = "Credential")]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(ParameterSetName = "Credential", Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(ParameterSetName = "Plain", Mandatory = $true)][string]$User,
        [Parameter(ParameterSetName = "Plain", Mandatory = $true)][string]$Password,
        [Parameter()][scriptblock]$InfoMessageCallback,
        [Parameter()][switch]$CollectMessages
    )
    $connection = $null
    $passwordBstr = [IntPtr]::Zero
    $plainPassword = $null
    $messages = New-Object System.Collections.Generic.List[string]
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-DzDebug "`t[DEBUG][Invoke-DzSqlCommandInternal] INICIO"
    Write-DzDebug "`t[DEBUG][Invoke-DzSqlCommandInternal] Server='$Server' Database='$Database'"
    try {
        if ($PSCmdlet.ParameterSetName -eq "Credential") {
            $connInfo = New-DzSqlConnectionFromCredential -Server $Server -Database $Database -Credential $Credential
            $connection = $connInfo.Connection
            $plainPassword = $connInfo.PlainPassword
            $passwordBstr = $connInfo.PasswordBstr
        } else {
            $connection = New-DzSqlConnectionFromPlain -Server $Server -Database $Database -User $User -Password $Password
        }
        if ($CollectMessages -or $InfoMessageCallback) {
            $connection.add_InfoMessage({
                    param($sender, $e)
                    $msg = [string]$e.Message
                    if (-not [string]::IsNullOrWhiteSpace($msg)) {
                        try { [void]$messages.Add($msg) } catch {}
                        if ($InfoMessageCallback) { try { & $InfoMessageCallback $msg } catch { Write-DzDebug "`t[DEBUG][Invoke-DzSqlCommandInternal] Error en InfoMessageCallback: $_" } }
                    }
                })
            $connection.FireInfoMessageEventOnUserErrors = $true
        }
        Write-DzDebug "`t[DEBUG][Invoke-DzSqlCommandInternal] Abriendo conexión..."
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 0
        $returnsResultSet = $Query -match "(?si)^\s*(SELECT|WITH)" -or $Query -match "(?si)\bOUTPUT\b"
        if ($returnsResultSet) {
            $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
            $dataTable = New-Object System.Data.DataTable
            [void]$adapter.Fill($dataTable)
            return @{
                Success    = $true
                DataTable  = $dataTable
                Type       = "Query"
                DurationMs = $stopwatch.ElapsedMilliseconds
                Messages   = $messages
            }
        }
        $rowsAffected = $command.ExecuteNonQuery()
        return @{
            Success      = $true
            RowsAffected = $rowsAffected
            Type         = "NonQuery"
            DurationMs   = $stopwatch.ElapsedMilliseconds
            Messages     = $messages
        }
    } catch {
        Write-DzDebug "`t[DEBUG][Invoke-DzSqlCommandInternal] CATCH: $($_.Exception.Message)"
        Write-DzDebug "`t[DEBUG][Invoke-DzSqlCommandInternal] Tipo de excepción: $($_.Exception.GetType().FullName)"
        Write-DzDebug "`t[DEBUG][Invoke-DzSqlCommandInternal] Stack: $($_.ScriptStackTrace)"
        return @{
            Success      = $false
            ErrorMessage = $_.Exception.Message
            ErrorRecord  = $_
            Type         = "Error"
            DurationMs   = $stopwatch.ElapsedMilliseconds
            Messages     = $messages
        }
    } finally {
        if ($plainPassword) { $plainPassword = $null }
        if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
        if ($null -ne $connection) {
            try { if ($connection.State -eq [System.Data.ConnectionState]::Open) { $connection.Close() } } catch {}
            try { $connection.Dispose() } catch {}
        }
        try { $stopwatch.Stop() } catch {}
        Write-DzDebug "`t[DEBUG][Invoke-DzSqlCommandInternal] FIN"
    }
}
function Invoke-DzSqlBatchInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter()][scriptblock]$InfoMessageCallback
    )
    [string]$Query = $Query
    $connection = $null
    $passwordBstr = [IntPtr]::Zero
    $plainPassword = $null
    $messages = New-Object System.Collections.Generic.List[string]
    $debugLog = New-Object System.Collections.Generic.List[string]
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:HadSqlError = $false
    function Add-Debug([string]$m) {
        try { [void]$debugLog.Add(("{0} {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $m)) } catch {}
        try { Write-DzDebug "`t[DEBUG][Invoke-DzSqlBatchInternal] $m" } catch {}
    }
    Add-Debug "INICIO"
    Add-Debug ("Server='{0}' DB='{1}' User='{2}' QueryLen={3}" -f $Server, $Database, $Credential.UserName, ($Query?.Length))
    try {
        $connInfo = New-DzSqlConnectionFromCredential -Server $Server -Database $Database -Credential $Credential
        $connection = $connInfo.Connection
        $plainPassword = $connInfo.PlainPassword
        $passwordBstr = $connInfo.PasswordBstr
        $connection.add_InfoMessage({
                param($sender, $e)
                $msg = [string]$e.Message
                if (-not [string]::IsNullOrWhiteSpace($msg)) {
                    try { [void]$messages.Add($msg) } catch {}
                    try { if ($InfoMessageCallback) { & $InfoMessageCallback $msg } } catch {}
                }
                if ($e.Errors) {
                    foreach ($err in $e.Errors) {
                        $em = [string]$err.Message
                        if ([string]::IsNullOrWhiteSpace($em)) { continue }
                        if ($err.Class -ge 11) { $script:HadSqlError = $true }
                    }
                }
            })
        $connection.FireInfoMessageEventOnUserErrors = $true
        Add-Debug "Abriendo conexión..."
        $connection.Open()
        Add-Debug ("Estado conexión: {0}" -f $connection.State)
        $batches = @([System.Text.RegularExpressions.Regex]::Split($Query, '(?im)^\s*GO\s*$') | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Add-Debug ("Batches: {0}" -f $batches.Count)
        if ($batches.Count -gt 0) {
            $preview = $batches[0]
            if ($preview.Length -gt 100) { $preview = $preview.Substring(0, 100) + "..." }
            Add-Debug ("Batch[0] Preview: {0}" -f $preview.Replace("`r", " ").Replace("`n", " "))
        }
        $resultSets = New-Object System.Collections.Generic.List[object]
        $recordsAffected = $null
        $totalRowsAffected = 0
        $batchErrors = New-Object System.Collections.Generic.List[string]
        for ($batchIndex = 0; $batchIndex -lt $batches.Count; $batchIndex++) {
            $oneBatch = $batches[$batchIndex]
            $command = $connection.CreateCommand()
            $command.CommandTimeout = 0
            $command.CommandText = $oneBatch
            Add-Debug ("Ejecutando batch #{0} (len={1})..." -f ($batchIndex + 1), $oneBatch.Length)
            $isSelect = $oneBatch -match "(?si)^\s*(SELECT|WITH|EXEC|EXECUTE|DECLARE.*SELECT)" -or $oneBatch -match "(?si)\bOUTPUT\b"
            try {
                if ($isSelect) {
                    try {
                        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
                        $ds = New-Object System.Data.DataSet
                        $filledTables = $adapter.Fill($ds)
                        Add-Debug ("Adapter.Fill OK. ds.Tables={0} filledTables={1}" -f $ds.Tables.Count, $filledTables)
                        if ($ds.Tables.Count -gt 0) {
                            foreach ($t in $ds.Tables) {
                                for ($i = 0; $i -lt $t.Columns.Count; $i++) {
                                    if ([string]::IsNullOrWhiteSpace($t.Columns[$i].ColumnName)) {
                                        $t.Columns[$i].ColumnName = "Column$($i+1)"
                                    }
                                }
                                $resultSets.Add([PSCustomObject]@{ DataTable = $t; RowCount = $t.Rows.Count })
                                Add-Debug ("RS#{0} Filas={1} Cols={2}" -f $resultSets.Count, $t.Rows.Count, $t.Columns.Count)
                            }
                        }
                    } catch {
                        Add-Debug ("Adapter.Fill EX: {0}" -f $_.Exception.Message)
                        [void]$batchErrors.Add("Batch #$($batchIndex + 1): $($_.Exception.Message)")
                        [void]$messages.Add("Batch #$($batchIndex + 1): $($_.Exception.Message)")
                        break
                    }
                } else {
                    try {
                        $rows = $command.ExecuteNonQuery()
                        $totalRowsAffected += $rows
                        Add-Debug ("ExecuteNonQuery RowsAffected={0} (Total acumulado={1})" -f $rows, $totalRowsAffected)
                    } catch {
                        Add-Debug ("ExecuteNonQuery EX: {0}" -f $_.Exception.Message)
                        [void]$batchErrors.Add("Batch #$($batchIndex + 1): $($_.Exception.Message)")
                        [void]$messages.Add("Batch #$($batchIndex + 1): $($_.Exception.Message)")
                        break
                    }
                }
                $command.Dispose()
                $command = $null
            } catch {
                Add-Debug ("Error general en batch #{0}: {1}" -f ($batchIndex + 1), $_.Exception.Message)
                [void]$batchErrors.Add("Batch #$($batchIndex + 1): $($_.Exception.Message)")
                [void]$messages.Add("Batch #$($batchIndex + 1): $($_.Exception.Message)")
                break
            }
        }
        $allMsgs = Resolve-DzSqlMessageSummary -Messages $messages
        Add-Debug ("FIN loop. resultSets={0} totalRowsAffected={1} HadSqlError={2} messages={3} batchErrors={4}" -f $resultSets.Count, $totalRowsAffected, $script:HadSqlError, $messages.Count, $batchErrors.Count)
        if ($batchErrors.Count -gt 0) {
            $errorMessage = "Error en batch: " + ($batchErrors -join "; ")
            return @{
                Success      = $false
                Type         = "Error"
                ErrorMessage = $errorMessage
                Messages     = $messages
                ResultSets   = $resultSets.ToArray()  # Devolver los resultados que SÍ se obtuvieron
                DebugLog     = $debugLog
                DurationMs   = $stopwatch.ElapsedMilliseconds
            }
        }
        if ($script:HadSqlError) {
            if ([string]::IsNullOrWhiteSpace($allMsgs)) { $allMsgs = "Error SQL." }
            return @{
                Success      = $false
                Type         = "Error"
                ErrorMessage = $allMsgs
                Messages     = $messages
                ResultSets   = $resultSets.ToArray()
                DebugLog     = $debugLog
                DurationMs   = $stopwatch.ElapsedMilliseconds
            }
        }
        if ($resultSets.Count -gt 0) {
            return @{
                Success      = $true
                ResultSets   = $resultSets.ToArray()
                Messages     = $messages
                DebugLog     = $debugLog
                DurationMs   = $stopwatch.ElapsedMilliseconds
                RowsAffected = if ($totalRowsAffected -gt 0) { $totalRowsAffected } else { $null }
            }
        }
        return @{
            Success      = $true
            ResultSets   = @()
            RowsAffected = $totalRowsAffected
            Messages     = $messages
            DebugLog     = $debugLog
            DurationMs   = $stopwatch.ElapsedMilliseconds
        }
    } catch {
        Add-Debug ("CATCH: {0}" -f $_.Exception.Message)
        $summary = Resolve-DzSqlMessageSummary -Messages $messages
        $errorMessage = if (-not [string]::IsNullOrWhiteSpace($_.Exception.Message)) { $_.Exception.Message } elseif (-not [string]::IsNullOrWhiteSpace($summary)) { $summary } else { "Error ejecutando consulta." }
        return @{
            Success      = $false
            Type         = "Error"
            ErrorMessage = $errorMessage
            ErrorRecord  = $_
            Messages     = $messages
            ResultSets   = @()
            DebugLog     = $debugLog
            DurationMs   = $stopwatch.ElapsedMilliseconds
        }
    } finally {
        if ($plainPassword) { $plainPassword = $null }
        if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
        if ($connection) {
            try { if ($connection.State -eq [System.Data.ConnectionState]::Open) { $connection.Close() } } catch {}
            try { $connection.Dispose() } catch {}
        }
        try { $stopwatch.Stop() } catch {}
        try { Add-Debug "FIN" } catch {}
    }
}
function Invoke-SqlQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $false)][scriptblock]$InfoMessageCallback
    )
    Invoke-DzSqlCommandInternal -Server $Server -Database $Database -Query $Query -Credential $Credential -InfoMessageCallback $InfoMessageCallback
}
function Invoke-SqlQueryMultiResultSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $false)][scriptblock]$InfoMessageCallback
    )
    Invoke-DzSqlBatchInternal -Server $Server -Database $Database -Query $Query -Credential $Credential -InfoMessageCallback $InfoMessageCallback
}
function Remove-SqlComments {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Query)
    [string]$query = $Query
    $query = $query -replace '(?s)/\*.*?\*/', ''
    $query = $query -replace '(?m)^\s*--.*\n?', ''
    $query = $query -replace '(?<!\w)--.*$', ''
    return [string]($query.Trim())
}
function Get-SqlDatabases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential
    )
    $query = @"
SELECT name
FROM sys.databases
WHERE name NOT IN ('tempdb','model','msdb')

ORDER BY CASE WHEN name = 'master' THEN 0 ELSE 1 END, name
"@
    #AND state_desc = 'ONLINE' de momento mostrar todas!
    $result = Invoke-SqlQuery -Server $Server -Database "master" -Query $query -Credential $Credential
    if (-not $result.Success) { throw "Error obteniendo bases de datos: $($result.ErrorMessage)" }
    $databases = @()
    foreach ($row in $result.DataTable.Rows) { $databases += $row["name"] }
    $databases
}
function Get-SqlDatabasesInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential
    )
    $query = @"
SELECT
    name,
    state_desc,
    user_access_desc,
    CAST(is_read_only AS bit) AS is_read_only
FROM sys.databases
WHERE name NOT IN ('tempdb', 'model', 'msdb')
ORDER BY
    CASE WHEN name = 'master' THEN 0 ELSE 1 END,
    name
"@
    $result = Invoke-SqlQuery -Server $Server -Database "master" -Query $query -Credential $Credential
    if (-not $result.Success) {
        throw "Error obteniendo bases de datos: $($result.ErrorMessage)"
    }
    $databases = @()
    foreach ($row in $result.DataTable.Rows) {
        $databases += [PSCustomObject]@{
            Name           = $row["name"]
            StateDesc      = $row["state_desc"]
            UserAccessDesc = $row["user_access_desc"]
            IsReadOnly     = [bool]$row["is_read_only"]
        }
    }
    Write-DzDebug "`t[DEBUG][Get-SqlDatabasesInfo] Retornando $($databases.Count) bases de datos"
    return $databases
}
function Execute-SqlQuery {
    param([string]$server, [string]$database, [string]$query)
    $result = Invoke-DzSqlCommandInternal -Server $server -Database $database -Query $query -User $global:user -Password $global:password -CollectMessages
    if (-not $result.Success) { throw $result.ErrorMessage }
    return $result
}
function Get-IniConnections {
    $connections = @()
    $pathsToCheck = @(
        @{ Path = "C:\NationalSoft\Softrestaurant9.5.0Pro"; INI = "restaurant.ini"; Nombre = "SR9.5" },
        @{ Path = "C:\NationalSoft\Softrestaurant10.0"; INI = "restaurant.ini"; Nombre = "SR10" },
        @{ Path = "C:\NationalSoft\Softrestaurant11.0"; INI = "restaurant.ini"; Nombre = "SR11" },
        @{ Path = "C:\NationalSoft\Softrestaurant12.0"; INI = "restaurant.ini"; Nombre = "SR12" },
        @{ Path = "C:\Program Files (x86)\NsBackOffice1.0"; INI = "DbConfig.ini"; Nombre = "NSBackOffice" },
        @{ Path = "C:\NationalSoft\NationalSoftHoteles3.0"; INI = "nshoteles.ini"; Nombre = "Hoteles" },
        @{ Path = "C:\NationalSoft\OnTheMinute4.5"; INI = "checadorsql.ini"; Nombre = "OnTheMinute" }
    )
    function Get-IniValue {
        param([string]$FilePath, [string]$Key)
        if (Test-Path $FilePath) {
            $line = Get-Content $FilePath | Where-Object { $_ -match "^$Key\s*=" } | Select-Object -First 1
            if ($line) { return $line.Split('=')[1].Trim() }
        }
        $null
    }
    foreach ($entry in $pathsToCheck) {
        $mainIni = Join-Path $entry.Path $entry.INI
        if (Test-Path $mainIni) {
            $dataSource = Get-IniValue -FilePath $mainIni -Key "DataSource"
            if ($dataSource -and $dataSource -notin $connections) { $connections += $dataSource }
        }
        $inisFolder = Join-Path $entry.Path "INIS"
        if (Test-Path $inisFolder) {
            $iniFiles = Get-ChildItem -Path $inisFolder -Filter "*.ini" -ErrorAction SilentlyContinue
            foreach ($iniFile in $iniFiles) {
                $dataSource = Get-IniValue -FilePath $iniFile.FullName -Key "DataSource"
                if ($dataSource -and $dataSource -notin $connections) { $connections += $dataSource }
            }
        }
    }
    $connections | Sort-Object
}
function Load-IniConnectionsToComboBox {
    param([Parameter(Mandatory = $true)]$Combo)
    $connections = Get-IniConnections
    $savedConnections = @()
    if (Get-Command Get-DzSavedSqlConnections -ErrorAction SilentlyContinue) {
        $savedConnections = Get-DzSavedSqlConnections
    }
    foreach ($saved in $savedConnections) {
        if ($saved.Server -and $saved.Server -notin $connections) {
            $connections += $saved.Server
        }
    }
    $Combo.Items.Clear()
    if ($connections.Count -gt 0) {
        foreach ($c in ($connections | Sort-Object)) { [void]$Combo.Items.Add($c) }
    } else {
        Write-Host "`tNo se encontraron conexiones en archivos INI" -ForegroundColor Yellow
    }
    if ($connections.Count -gt 0) {
        if ($connections -contains ".\\NationalSoft") {
            $Combo.Text = ".\NationalSoft"
        } else {
            $Combo.Text = [string]($connections | Select-Object -First 1)
        }
    } else {
        $Combo.Text = ".\NationalSoft"
    }
}
function Show-MultipleResultSets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.TabControl]$TabControl,
        [Parameter()][AllowEmptyCollection()][array]$ResultSets = @()
    )
    Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] INICIO"
    Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] ResultSets Count: $($ResultSets.Count)"
    $messagesTab = $null
    $messagesTabIndex = -1
    for ($ti = 0; $ti -lt $TabControl.Items.Count; $ti++) {
        $item = $TabControl.Items[$ti]
        if ($item -isnot [System.Windows.Controls.TabItem]) { continue }
        $header = $null
        if ($item.Header -is [string]) {
            $header = $item.Header
        } elseif ($item.Header -is [System.Windows.Controls.StackPanel]) {
            foreach ($child in $item.Header.Children) {
                if ($child -is [System.Windows.Controls.TextBlock]) {
                    $header = $child.Text
                    break
                }
            }
        }
        if ($header -and $header -match "Mensajes") {
            $messagesTab = $item
            $messagesTabIndex = $ti
            Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] ✓ Pestaña de Mensajes encontrada en índice $ti"
            break
        }
    }
    $itemsToRemove = New-Object System.Collections.ArrayList
    foreach ($item in $TabControl.Items) {
        if ($item -isnot [System.Windows.Controls.TabItem]) { continue }
        $header = $null
        if ($item.Header -is [string]) {
            $header = $item.Header
        } elseif ($item.Header -is [System.Windows.Controls.StackPanel]) {
            foreach ($child in $item.Header.Children) {
                if ($child -is [System.Windows.Controls.TextBlock]) {
                    $header = $child.Text
                    break
                }
            }
        }
        if (-not ($header -and $header -match "Mensajes")) {
            [void]$itemsToRemove.Add($item)
        }
    }
    foreach ($item in $itemsToRemove) {
        $TabControl.Items.Remove($item)
    }
    Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Pestañas removidas: $($itemsToRemove.Count)"
    Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Pestañas restantes: $($TabControl.Items.Count)"
    if (-not $ResultSets -or $ResultSets.Count -eq 0) {
        $tab = New-Object System.Windows.Controls.TabItem
        $headerPanel = New-Object System.Windows.Controls.StackPanel
        $headerPanel.Orientation = "Horizontal"
        $iconText = New-Object System.Windows.Controls.TextBlock
        $iconText.Text = "📊"
        $iconText.Margin = "0,0,6,0"
        $iconText.FontSize = 10
        $iconText.Margin = "0,0,4,0"
        $titleText = New-Object System.Windows.Controls.TextBlock
        $titleText.Text = "Resultado"
        $titleText.FontSize = 10
        $titleText.Margin = "0"
        $titleText.VerticalAlignment = "Center"
        [void]$headerPanel.Children.Add($iconText)
        [void]$headerPanel.Children.Add($titleText)
        $tab.Header = $headerPanel
        $text = New-Object System.Windows.Controls.TextBlock
        $text.Text = "La consulta no devolvió resultados."
        $text.Margin = "10"
        $tab.Content = $text
        if ($messagesTab) {
            $TabControl.Items.Insert(0, $tab)
            Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Pestaña vacía insertada en índice 0 (antes de Mensajes)"
        } else {
            [void]$TabControl.Items.Add($tab)
            Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Pestaña vacía agregada (no hay Mensajes)"
        }
        if ($global:lblRowCount) { $global:lblRowCount.Text = "📊 0" }
        Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] FIN (sin resultados)"
        return
    }
    $theme = $null
    try { $theme = Get-DzUiTheme } catch { $theme = $null }
    $isDark = $false
    try {
        if ($theme -and $theme.FormBackground) {
            $bg = [string]$theme.FormBackground
            if ($bg -match '^#') {
                $c = [System.Windows.Media.ColorConverter]::ConvertFromString($bg)
                $lum = (0.2126 * $c.R) + (0.7152 * $c.G) + (0.0722 * $c.B)
                if ($lum -lt 128) { $isDark = $true }
            } else {
                if ($bg -match '(?i)black|dark|#0|#1|#2') { $isDark = $true }
            }
        }
    } catch { $isDark = $false }
    $gridBg = $null
    $gridFg = $null
    $headerBg = $null
    $headerFg = $null
    $gridLine = $null
    $rowAlt = $null
    if ($isDark) {
        $gridBg = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#171717")
        $rowAlt = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1F1F1F")
        $gridFg = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E6E6E6")
        $headerBg = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#232323")
        $headerFg = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $gridLine = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2E2E2E")
    } else {
        $gridBg = [System.Windows.Media.Brushes]::White
        $rowAlt = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F3F3F3")
        $gridFg = [System.Windows.Media.Brushes]::Black
        $headerBg = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E9E9E9")
        $headerFg = [System.Windows.Media.Brushes]::Black
        $gridLine = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D0D0")
    }
    $nullBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FDFBAC")
    $nullFg = [System.Windows.Media.Brushes]::Black
    $hdrStyle = New-Object System.Windows.Style([System.Windows.Controls.Primitives.DataGridColumnHeader])
    [void]$hdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BackgroundProperty, $headerBg)))
    [void]$hdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $headerFg)))
    [void]$hdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)))
    [void]$hdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::VerticalContentAlignmentProperty, [System.Windows.VerticalAlignment]::Center)))
    [void]$hdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::PaddingProperty, (New-Object System.Windows.Thickness(4, 2, 4, 2)))))
    [void]$hdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderBrushProperty, $gridLine)))
    [void]$hdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderThicknessProperty, (New-Object System.Windows.Thickness(0, 0, 1, 1)))))
    $rowHdrStyle = New-Object System.Windows.Style([System.Windows.Controls.Primitives.DataGridRowHeader])
    [void]$rowHdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BackgroundProperty, $headerBg)))
    [void]$rowHdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $headerFg)))
    [void]$rowHdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)))
    [void]$rowHdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::VerticalContentAlignmentProperty, [System.Windows.VerticalAlignment]::Center)))
    [void]$rowHdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderBrushProperty, $gridLine)))
    [void]$rowHdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderThicknessProperty, (New-Object System.Windows.Thickness(0, 0, 1, 1)))))
    [void]$rowHdrStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.FrameworkElement]::WidthProperty, [double]::NaN)))
    $cellStyle = New-Object System.Windows.Style([System.Windows.Controls.DataGridCell])
    [void]$cellStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::PaddingProperty, (New-Object System.Windows.Thickness(4, 1, 4, 1)))))
    [void]$cellStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderBrushProperty, $gridLine)))
    [void]$cellStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderThicknessProperty, (New-Object System.Windows.Thickness(0, 0, 1, 1)))))
    [void]$cellStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)))
    [void]$cellStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::VerticalContentAlignmentProperty, [System.Windows.VerticalAlignment]::Center)))
    $textStyleBase = New-Object System.Windows.Style([System.Windows.Controls.TextBlock])
    [void]$textStyleBase.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::TextTrimmingProperty, [System.Windows.TextTrimming]::CharacterEllipsis)))
    [void]$textStyleBase.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::TextWrappingProperty, [System.Windows.TextWrapping]::NoWrap)))
    [void]$textStyleBase.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)))
    $tNull = New-Object System.Windows.Trigger
    $tNull.Property = [System.Windows.Controls.TextBlock]::TextProperty
    $tNull.Value = "NULL"
    [void]$tNull.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::BackgroundProperty, $nullBrush)))
    [void]$tNull.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::ForegroundProperty, $nullFg)))
    [void]$textStyleBase.Triggers.Add($tNull)
    $i = 0
    foreach ($rs in $ResultSets) {
        $i++
        $tab = New-Object System.Windows.Controls.TabItem
        $rowCount = if ($rs.RowCount -ne $null) { $rs.RowCount } else { $rs.DataTable.Rows.Count }
        $headerPanel = New-Object System.Windows.Controls.StackPanel
        $headerPanel.Orientation = "Horizontal"
        $iconText = New-Object System.Windows.Controls.TextBlock
        #dgResults construyendo la pestaña de resultados:
        $iconText.Text = "📊"
        $iconText.Margin = "0,0,6,0"
        $iconText.FontSize = 10
        $iconText.Margin = "0,0,4,0"
        $titleText = New-Object System.Windows.Controls.TextBlock
        $titleText.Text = "Resultado $i ($rowCount filas)"
        $titleText.VerticalAlignment = "Center"
        $titleText.FontSize = 10
        $titleText.Margin = "0"
        [void]$headerPanel.Children.Add($iconText)
        [void]$headerPanel.Children.Add($titleText)
        $tab.Header = $headerPanel
        $dg = New-Object System.Windows.Controls.DataGrid
        $dg.AutoGenerateColumns = $true
        $dg.ItemsSource = $rs.DataTable.DefaultView
        $dg.IsReadOnly = $true
        $dg.CanUserAddRows = $false
        $dg.CanUserDeleteRows = $false
        $dg.SelectionUnit = "CellOrRowHeader"
        $dg.SelectionMode = "Extended"
        $dg.HeadersVisibility = "All"
        $dg.GridLinesVisibility = "None"
        $dg.HorizontalGridLinesBrush = $gridLine
        $dg.VerticalGridLinesBrush = $gridLine
        $dg.Background = $gridBg
        $dg.Foreground = $gridFg
        $dg.RowBackground = $gridBg
        $dg.AlternatingRowBackground = $rowAlt
        $dg.BorderBrush = $gridLine
        $dg.BorderThickness = "1"
        #NUEVOS TAMAÑOS
        $dg.FontSize = 10
        $dg.RowHeight = 20
        $dg.ColumnHeaderHeight = 22
        $dg.RowHeaderWidth = 38
        $dg.HorizontalScrollBarVisibility = "Auto"
        $dg.VerticalScrollBarVisibility = "Auto"
        $dg.CanUserResizeColumns = $true
        $dg.CanUserSortColumns = $true
        $dg.AlternationCount = 2
        $dg.ColumnHeaderStyle = $hdrStyle
        $dg.RowHeaderStyle = $rowHdrStyle
        $dg.CellStyle = $cellStyle
        $dg.Add_LoadingRow({
                param($s, $e)
                try {
                    $e.Row.Header = ($e.Row.GetIndex() + 1).ToString()
                } catch {
                    Write-DzDebug "`t[DEBUG][DataGrid] Error en LoadingRow: $_"
                }
            })
        $CopyToClipboard = {
            param([bool]$IncludeHeaders)
            try {
                $grid = $dg
                $sb = New-Object System.Text.StringBuilder
                $visibleCols = @($grid.Columns | Where-Object { $_.Visibility -eq 'Visible' } | Sort-Object DisplayIndex)
                if ($grid.SelectedItems -and $grid.SelectedItems.Count -gt 0) {
                    $columns = $visibleCols
                    if ($IncludeHeaders) {
                        $headers = foreach ($col in $columns) {
                            $h = if ($col.Header -is [string]) { $col.Header } elseif ($col.Header) { $col.Header.ToString() } else { "" }
                            ($h -replace '__', '_' -replace "`t", " ")
                        }
                        [void]$sb.AppendLine(($headers -join "`t"))
                    }
                    foreach ($row in @($grid.SelectedItems)) {
                        $values = foreach ($col in $columns) {
                            $propName = $null
                            if ($col -is [System.Windows.Controls.DataGridBoundColumn]) {
                                $binding = $col.Binding
                                if ($binding -and $binding.Path) { $propName = $binding.Path.Path }
                            }
                            if (-not $propName -and $col.SortMemberPath) { $propName = $col.SortMemberPath }
                            if (-not $propName -and $col.Header) {
                                $h2 = $col.Header
                                $propName = if ($h2 -is [string]) { ($h2 -replace '__', '_') } else { $h2.ToString() }
                            }
                            $cellValue = ""
                            try {
                                $val = $null
                                if ($row -is [System.Data.DataRowView]) { $val = $row[$propName] }
                                elseif ($row.PSObject.Properties[$propName]) { $val = $row.PSObject.Properties[$propName].Value }
                                else { $val = $row.$propName }
                                if ($null -eq $val -or $val -is [System.DBNull]) { $cellValue = "NULL" }
                                elseif ($val -is [datetime]) { $cellValue = ([datetime]$val).ToString("yyyy-MM-dd HH:mm:ss.fff") }
                                elseif ($val -is [bool]) { $cellValue = if ($val) { "True" } else { "False" } }
                                else { $cellValue = $val.ToString() }
                            } catch { $cellValue = "" }
                            $cellValue -replace "`t", " " -replace "`r`n", " " -replace "`n", " " -replace "`r", " "
                        }
                        [void]$sb.AppendLine(($values -join "`t"))
                    }
                    $textToCopy = $sb.ToString().TrimEnd("`r", "`n")
                    [System.Windows.Clipboard]::SetText($textToCopy)
                    $headerMsg = if ($IncludeHeaders) { "con encabezados" } else { "sin encabezados" }
                    Write-DzDebug "`t[DEBUG][DataGrid] ✓ Copiado: $($grid.SelectedItems.Count) filas × $($columns.Count) columnas ($headerMsg)"
                    #Write-DzDebug "`t[DEBUG][DataGrid] Texto copiado:`n$textToCopy"
                    return
                }
                if ((-not $grid.SelectedItems -or $grid.SelectedItems.Count -eq 0) -and
                    ($grid.SelectedCells -and $grid.SelectedCells.Count -gt 0)) {
                    $rowsFromCells = @(
                        $grid.SelectedCells |
                        Select-Object -ExpandProperty Item -Unique
                    )
                    if ($grid.SelectedCells.Count -eq 1) {
                        $row = $rowsFromCells[0]
                        $columns = $visibleCols
                        if ($IncludeHeaders) {
                            $headers = foreach ($col in $columns) {
                                $h = if ($col.Header -is [string]) { $col.Header } elseif ($col.Header) { $col.Header.ToString() } else { "" }
                                ($h -replace '__', '_' -replace "`t", " ")
                            }
                            [void]$sb.AppendLine(($headers -join "`t"))
                        }
                        $values = foreach ($col in $columns) {
                            $propName = $null
                            if ($col -is [System.Windows.Controls.DataGridBoundColumn]) {
                                $binding = $col.Binding
                                if ($binding -and $binding.Path) { $propName = $binding.Path.Path }
                            }
                            if (-not $propName -and $col.SortMemberPath) { $propName = $col.SortMemberPath }
                            if (-not $propName -and $col.Header) {
                                $h2 = $col.Header
                                $propName = if ($h2 -is [string]) { (($h2 -replace '__', '_')) } else { ($h2.ToString() -replace '__', '_') }
                            }
                            $cellValue = ""
                            try {
                                $val = $null
                                if ($row -is [System.Data.DataRowView]) { $val = $row[$propName] }
                                elseif ($row.PSObject.Properties[$propName]) { $val = $row.PSObject.Properties[$propName].Value }
                                else { $val = $row.$propName }
                                if ($null -eq $val -or $val -is [System.DBNull]) { $cellValue = "NULL" }
                                elseif ($val -is [datetime]) { $cellValue = ([datetime]$val).ToString("yyyy-MM-dd HH:mm:ss.fff") }
                                elseif ($val -is [bool]) { $cellValue = if ($val) { "True" } else { "False" } }
                                else { $cellValue = $val.ToString() }
                            } catch { $cellValue = "" }
                            $cellValue -replace "`t", " " -replace "`r`n", " " -replace "`n", " " -replace "`r", " "
                        }
                        [void]$sb.AppendLine(($values -join "`t"))
                        $textToCopy = $sb.ToString().TrimEnd("`r", "`n")
                        [System.Windows.Clipboard]::SetText($textToCopy)
                        $headerMsg = if ($IncludeHeaders) { "con encabezados" } else { "sin encabezados" }
                        Write-DzDebug "`t[DEBUG][DataGrid] ✓ Copiado (por celda en 1 fila): 1 filas × $($columns.Count) columnas ($headerMsg)"
                        #Write-DzDebug "`t[DEBUG][DataGrid] Texto copiado:`n$textToCopy"
                        return
                    }
                }
                # 2) Si NO hay filas seleccionadas, copiar por CELDAS (usar copiado nativo del DataGrid)
                if (-not $grid.SelectedCells -or $grid.SelectedCells.Count -eq 0) { return }
                $oldMode = $grid.ClipboardCopyMode
                try {
                    if ($IncludeHeaders) {
                        $grid.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::IncludeHeader
                    } else {
                        $grid.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::ExcludeHeader
                    }
                    [System.Windows.Input.ApplicationCommands]::Copy.Execute($null, $grid)
                    $textToCopy = [System.Windows.Clipboard]::GetText()
                    if ($null -eq $textToCopy) { $textToCopy = "" }
                    $textToCopy = $textToCopy.TrimEnd("`r", "`n")
                    if ([string]::IsNullOrWhiteSpace($textToCopy)) { return }
                    [System.Windows.Clipboard]::SetText($textToCopy)
                    $headerMsg = if ($IncludeHeaders) { "con encabezados" } else { "sin encabezados" }
                    Write-DzDebug "`t[DEBUG][DataGrid] ✓ Copiado (nativo): celdas seleccionadas ($headerMsg)"
                    #Write-DzDebug "`t[DEBUG][DataGrid] Texto copiado:`n$textToCopy"
                    return
                } catch {
                    Write-DzDebug "`t[DEBUG][DataGrid] Error en copiar (nativo): $_" -Color Red
                    return
                } finally {
                    # Volver al modo anterior SIEMPRE
                    $grid.ClipboardCopyMode = $oldMode
                }
                $selectedCells = @(
                    $grid.SelectedCells |
                    Sort-Object -Property @{ Expression = { $_.Item } }, @{ Expression = { $_.Column.DisplayIndex } }
                )
                if ($selectedCells.Count -eq 0) { return }
                $rowGroups = @($selectedCells | Group-Object -Property { $_.Item })
                $columns = @($selectedCells | Select-Object -ExpandProperty Column -Unique | Sort-Object DisplayIndex)
                if ($IncludeHeaders) {
                    $headers = foreach ($col in $columns) {
                        $h = if ($col.Header -is [string]) { $col.Header } elseif ($col.Header) { $col.Header.ToString() } else { "" }
                        ($h -replace '__', '_' -replace "`t", " ")
                    }
                    [void]$sb.AppendLine(($headers -join "`t"))
                }
                foreach ($rg in $rowGroups) {
                    $row = $rg.Group[0].Item
                    $values = foreach ($col in $columns) {
                        $cellFound = $rg.Group | Where-Object { $_.Column -eq $col } | Select-Object -First 1
                        if (-not $cellFound) { "" ; continue }
                        $propName = $null
                        if ($col -is [System.Windows.Controls.DataGridBoundColumn]) {
                            $binding = $col.Binding
                            if ($binding -and $binding.Path) { $propName = $binding.Path.Path }
                        }
                        if (-not $propName -and $col.SortMemberPath) { $propName = $col.SortMemberPath }
                        if (-not $propName -and $col.Header) {
                            $h2 = $col.Header
                            $propName = if ($h2 -is [string]) { ($h2 -replace '__', '_') } else { $h2.ToString() }
                        }
                        $cellValue = ""
                        try {
                            $val = $null
                            if ($row -is [System.Data.DataRowView]) { $val = $row[$propName] }
                            elseif ($row.PSObject.Properties[$propName]) { $val = $row.PSObject.Properties[$propName].Value }
                            else { $val = $row.$propName }
                            if ($null -eq $val -or $val -is [System.DBNull]) { $cellValue = "NULL" }
                            elseif ($val -is [datetime]) { $cellValue = ([datetime]$val).ToString("yyyy-MM-dd HH:mm:ss.fff") }
                            elseif ($val -is [bool]) { $cellValue = if ($val) { "True" } else { "False" } }
                            else { $cellValue = $val.ToString() }
                        } catch { $cellValue = "" }
                        $cellValue -replace "`t", " " -replace "`r`n", " " -replace "`n", " " -replace "`r", " "
                    }
                    [void]$sb.AppendLine(($values -join "`t"))
                }
                $textToCopy = $sb.ToString().TrimEnd("`r", "`n")
                [System.Windows.Clipboard]::SetText($textToCopy)
                $headerMsg = if ($IncludeHeaders) { "con encabezados" } else { "sin encabezados" }
                Write-DzDebug "`t[DEBUG][DataGrid] ✓ Copiado: $($rowGroups.Count) filas × $($columns.Count) columnas ($headerMsg)"
                #Write-DzDebug "`t[DEBUG][DataGrid] Texto copiado:`n$textToCopy"
            } catch {
                Write-DzDebug "`t[DEBUG][DataGrid] Error en copiar: $_" -Color Red
            }
        }.GetNewClosure()
        $copyFn = $CopyToClipboard
        $dg.Add_PreviewKeyDown({
                param($s, $e)
                $isCtrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
                $isShift = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0
                if ($e.Key -eq [System.Windows.Input.Key]::C -and $isCtrl -and $isShift) {
                    $copyFn.Invoke($true)
                    $e.Handled = $true
                } elseif ($e.Key -eq [System.Windows.Input.Key]::C -and $isCtrl) {
                    $copyFn.Invoke($false)
                    $e.Handled = $true
                } elseif ($e.Key -eq [System.Windows.Input.Key]::A -and $isCtrl) {
                    $s.SelectAllCells()
                    $e.Handled = $true
                }
            }.GetNewClosure())
        $contextMenu = New-Object System.Windows.Controls.ContextMenu
        $menuCopy = New-Object System.Windows.Controls.MenuItem
        $menuCopy.Header = "Copiar                                    Ctrl+C"
        $menuCopy.Add_Click({ & $CopyToClipboard $false }.GetNewClosure())
        [void]$contextMenu.Items.Add($menuCopy)
        $menuCopyHeaders = New-Object System.Windows.Controls.MenuItem
        $menuCopyHeaders.Header = "Copiar con encabezados       Ctrl+Shift+C"
        $menuCopyHeaders.Add_Click({ & $CopyToClipboard $true }.GetNewClosure())
        [void]$contextMenu.Items.Add($menuCopyHeaders)
        [void]$contextMenu.Items.Add((New-Object System.Windows.Controls.Separator))
        $menuSelectAll = New-Object System.Windows.Controls.MenuItem
        $menuSelectAll.Header = "Seleccionar todo                  Ctrl+A"
        $menuSelectAll.Add_Click({ $dg.SelectAllCells() }.GetNewClosure())
        [void]$contextMenu.Items.Add($menuSelectAll)
        $dg.ContextMenu = $contextMenu
        $dg.Add_AutoGeneratingColumn({
                param($s, $e)
                $prop = $e.PropertyName
                $hdr = [string]$e.Column.Header
                $hdr = $hdr -replace '_', '__'
                $e.Column.Header = $hdr
                if ($e.PropertyType -eq [datetime]) {
                    $col = New-Object System.Windows.Controls.DataGridTextColumn
                    $col.Header = $hdr
                    $b = New-Object System.Windows.Data.Binding($prop)
                    $b.StringFormat = "yyyy-MM-dd HH:mm:ss.fff"
                    $b.TargetNullValue = "NULL"
                    $col.Binding = $b
                    $ts = New-Object System.Windows.Style([System.Windows.Controls.TextBlock])
                    $ts.BasedOn = $textStyleBase
                    $col.ElementStyle = $ts
                    $e.Column = $col
                    return
                }
                if ($e.PropertyType -eq [bool]) {
                    if ($e.Column -is [System.Windows.Controls.DataGridCheckBoxColumn]) {
                        $e.Column.IsThreeState = $true
                        $cbBind = $e.Column.Binding
                        if ($cbBind -is [System.Windows.Data.Binding]) { $cbBind.TargetNullValue = $null }
                    }
                    return
                }
                if ($e.PropertyType -in @([int], [long], [decimal], [double], [single])) {
                    if ($e.Column -is [System.Windows.Controls.DataGridTextColumn]) {
                        $b = $e.Column.Binding
                        if (-not ($b -is [System.Windows.Data.Binding])) { $b = New-Object System.Windows.Data.Binding($prop) }
                        $b.TargetNullValue = "NULL"
                        $e.Column.Binding = $b
                        $ts = New-Object System.Windows.Style([System.Windows.Controls.TextBlock])
                        $ts.BasedOn = $textStyleBase
                        [void]$ts.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::TextAlignmentProperty, [System.Windows.TextAlignment]::Center)))
                        $e.Column.ElementStyle = $ts
                    }
                    return
                }
                if ($e.Column -is [System.Windows.Controls.DataGridTextColumn]) {
                    $b = $e.Column.Binding
                    if (-not ($b -is [System.Windows.Data.Binding])) { $b = New-Object System.Windows.Data.Binding($prop) }
                    $b.TargetNullValue = "NULL"
                    $e.Column.Binding = $b
                    $ts = New-Object System.Windows.Style([System.Windows.Controls.TextBlock])
                    $ts.BasedOn = $textStyleBase
                    $e.Column.ElementStyle = $ts
                }
            })
        $dg.Add_AutoGeneratedColumns({
                param($s, $e)
                try {
                    $min = 60
                    $max = 900
                    $pad = 14
                    $sampleMax = 60
                    $dv = $s.ItemsSource
                    $dt = $null
                    try { $dt = $dv.Table } catch { $dt = $null }
                    $dpi = 96.0
                    try {
                        $src = [System.Windows.PresentationSource]::FromVisual($s)
                        if ($src -and $src.CompositionTarget -and $src.CompositionTarget.TransformToDevice) {
                            $dpi = 96.0 * $src.CompositionTarget.TransformToDevice.M11
                        }
                    } catch { $dpi = 96.0 }
                    $typeface = New-Object System.Windows.Media.Typeface($s.FontFamily, $s.FontStyle, $s.FontWeight, $s.FontStretch)
                    $fontSize = [double]$s.FontSize
                    foreach ($col in $s.Columns) {
                        $col.MinWidth = $min
                        $col.MaxWidth = $max
                    }
                    $s.Dispatcher.BeginInvoke([action] {
                            try {
                                $s.UpdateLayout()
                                foreach ($col in $s.Columns) {
                                    $prop = $null
                                    try { $prop = $col.SortMemberPath } catch { $prop = $null }
                                    if ([string]::IsNullOrWhiteSpace($prop)) {
                                        try { $prop = $col.Header.ToString() } catch { $prop = $null }
                                    }
                                    $best = 0.0
                                    $hText = ""
                                    try { $hText = [string]$col.Header } catch { $hText = "" }
                                    if (-not [string]::IsNullOrEmpty($hText)) {
                                        $ftH = New-Object System.Windows.Media.FormattedText(
                                            $hText,
                                            [System.Globalization.CultureInfo]::CurrentCulture,
                                            [System.Windows.FlowDirection]::LeftToRight,
                                            $typeface,
                                            $fontSize,
                                            [System.Windows.Media.Brushes]::Black,
                                            $dpi
                                        )
                                        $best = [Math]::Max($best, $ftH.WidthIncludingTrailingWhitespace)
                                    }
                                    $count = 0
                                    if ($dt -and $prop -and $dt.Columns.Contains($prop)) {
                                        foreach ($row in $dt.Rows) {
                                            if ($count -ge $sampleMax) { break }
                                            $val = $row[$prop]
                                            $txt = $null
                                            if ($null -eq $val -or $val -is [System.DBNull]) {
                                                $txt = "NULL"
                                            } else {
                                                if ($val -is [datetime]) {
                                                    $txt = ([datetime]$val).ToString("yyyy-MM-dd HH:mm:ss.fff")
                                                } else {
                                                    $txt = [string]$val
                                                }
                                            }
                                            if (-not [string]::IsNullOrEmpty($txt)) {
                                                $ft = New-Object System.Windows.Media.FormattedText(
                                                    $txt,
                                                    [System.Globalization.CultureInfo]::CurrentCulture,
                                                    [System.Windows.FlowDirection]::LeftToRight,
                                                    $typeface,
                                                    $fontSize,
                                                    [System.Windows.Media.Brushes]::Black,
                                                    $dpi
                                                )
                                                if ($ft.WidthIncludingTrailingWhitespace -gt $best) {
                                                    $best = $ft.WidthIncludingTrailingWhitespace
                                                }
                                            }
                                            $count++
                                        }
                                    } else {
                                        $best = [Math]::Max($best, 120.0)
                                    }
                                    $w = [Math]::Ceiling($best + $pad)
                                    if ($w -lt $col.MinWidth) { $w = $col.MinWidth }
                                    if ($w -gt $col.MaxWidth) { $w = $col.MaxWidth }
                                    $col.Width = $w
                                }
                            } catch { }
                        }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
                } catch { }
            })
        $tab.Content = $dg
        if ($messagesTab) {
            $TabControl.Items.Insert($i - 1, $tab)
            Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Pestaña $i insertada en índice $($i-1) (antes de Mensajes)"
        } else {
            [void]$TabControl.Items.Add($tab)
            Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Pestaña $i agregada (no hay Mensajes)"
        }
        Write-Host "`tPestaña $i creada con $rowCount filas" -ForegroundColor Green
    }
    if ($global:lblRowCount) {
        $totalRows = ($ResultSets | Measure-Object -Property RowCount -Sum).Sum
        if ($ResultSets.Count -eq 1) {
            $global:lblRowCount.Text = "📊 $totalRows"
        } else {
            $global:lblRowCount.Text = "📊 $totalRows ($($ResultSets.Count) resultsets)"
        }
    }
    $TabControl.SelectedIndex = 0
    Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Pestañas totales: $($TabControl.Items.Count)"
    Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Pestaña seleccionada: índice $($TabControl.SelectedIndex)"
    Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] FIN"
}
function Export-ResultSetToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ResultSet,
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not $ResultSet -or -not $ResultSet.DataTable) { throw "No hay datos para exportar." }
    $ResultSet.DataTable | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}
function Export-ResultSetToDelimitedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ResultSet,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter()][string]$Separator = "|"
    )
    if ([string]::IsNullOrWhiteSpace($Separator)) { $Separator = "|" }
    $dt = $null
    if ($ResultSet -is [System.Data.DataTable]) {
        $dt = $ResultSet
    } elseif ($ResultSet -and $ResultSet.DataTable) {
        $dt = $ResultSet.DataTable
    }
    if (-not $dt) { throw "No hay datos para exportar." }
    $encoding = New-Object System.Text.UTF8Encoding($true)
    $writer = New-Object System.IO.StreamWriter($Path, $false, $encoding)
    try {
        $escape = {
            param([string]$value, [string]$sep)
            if ($null -eq $value) { return "" }
            $text = [string]$value
            if ($text -match "[`r`n]" -or $text.Contains($sep) -or $text.Contains('"')) {
                $text = $text.Replace('"', '""')
                return '"' + $text + '"'
            }
            return $text
        }
        $headers = @()
        foreach ($col in $dt.Columns) {
            $headers += & $escape $col.ColumnName $Separator
        }
        $writer.WriteLine(($headers -join $Separator))
        foreach ($row in $dt.Rows) {
            $cells = @()
            foreach ($col in $dt.Columns) {
                $value = $row[$col]
                if ($value -is [System.DBNull]) { $value = $null }
                $cells += & $escape $value $Separator
            }
            $writer.WriteLine(($cells -join $Separator))
        }
    } finally {
        $writer.Dispose()
    }
}
function Get-PredefinedQueries {
    return @{
        "Monitor de Servicios | Ventas a subir"           = @"
SELECT DISTINCT TOP (10)
    nofacturable,
    tablaventa.IDEMPRESA,
    codigo_unico_af AS ticket_cu,
    e.CLAVEUNICAEMPRESA AS empresa_id,
    numcheque AS ticket_folio,
    seriefolio AS ticket_serie,
    tablaventa.FOLIO AS ticket_folioSR,
    CONVERT(nvarchar(30), FECHA, 120) AS ticket_fecha,
    subtotal AS ticket_subtotal,
    total AS ticket_total,
    descuento AS ticket_descuento,
    totalconpropina AS ticket_totalconpropina,
    totalsindescuento AS ticket_totalsindescuento,
    (totalimpuestod1 + totalimpuestod2 + totalimpuestod3) AS ticket_totalimpuesto,
    totalotros AS ticket_totalotros,
    descuentoimporte AS ticket_totaldescuento,
    0 AS ticket_totaldescuento2,
    0 AS ticket_totaldescuento3,
    0 AS ticket_totaldescuento4,
    tablaventa.PROPINA AS ticket_propina,
    cancelado,
    CAST(numcheque AS VARCHAR) AS ticket_numcheque,
    numerotarjeta,
    puntosmonederogenerados,
    titulartarjetamonederodescuento AS titulartarjetamonedero,
    tarjetadescuento,
    descuentomonedero,
    e.idregimen_sat,
    tipopago.idformapago_SAT,
    tablaventa.idturno,
    nopersonas,
    tipodeservicio,
    idmesero,
    totalarticulos,
    LTRIM(RTRIM(estacion)) AS ticket_estacion,
    usuariodescuento,
    comentariodescuento,
    tablaventa.idtipodescuento,
    totalimpuestod2 AS TicketTotalIEPS,
    0 AS TicketTotalOtrosImpuestos,
    LEFT(CONVERT(VARCHAR, fecha + 15, 120), 10) + ' 23:59:59' AS ticket_fechavence,
    CONVERT(nvarchar(30), tablaventa.cierre, 120) AS ticket_fecha_cierre
FROM
    CHEQUES AS tablaventa
    INNER JOIN empresas AS e ON tablaventa.IDEMPRESA = e.IDEMPRESA
    LEFT JOIN chequespagos AS tablapago ON tablapago.folio = tablaventa.folio
    LEFT JOIN formasdepago AS tipopago ON tablapago.idformadepago = tipopago.idformadepago
WHERE
    fecha > (SELECT fecha_inicio_envio FROM configuracion_ws)
    AND (intentoEnvioAF < 20)
    AND (
        (enviado = 0) OR (enviado IS NULL)
    )
    AND (
        (pagado = 1 AND nofacturable = 0)
        OR cancelado = 1
    )
    AND codigo_unico_af IS NOT NULL
    AND codigo_unico_af <> ''
    AND tablaventa.IDEMPRESA = (SELECT TOP 1 idempresa FROM empresas)
ORDER BY
    numcheque;
"@
        "BackOffice Actualizar contraseña  administrador" = @"
UPDATE users
    SET Password = '08/Vqq0='
    OUTPUT inserted.UserName
    WHERE UserName = (SELECT TOP 1 UserName FROM users WHERE IsSuperAdmin = 1 and IsEnabled = 1);
"@
        "BackOffice Estaciones"                           = @"
SELECT
    t.Name,
    t.Ip,
    t.LastOnline,
    t.IsEnabled,
    u.UserName AS UltimoUsuario,
    t.AppVersion,
    t.IsMaximized,
    t.ForceAppUpdate,
    t.SkipDoPing
FROM Terminals t
LEFT JOIN Users u ON t.LastUserLogin = u.Id
ORDER BY t.IsEnabled DESC, t.Name;
"@
        "SR | Actualizar contraseña de administrador"     = @"
UPDATE usuarios
    SET contraseña = 'A9AE4E13D2A47998AC34'
    OUTPUT inserted.usuario
    WHERE usuario = (SELECT TOP 1 usuario FROM usuarios WHERE administrador = 1);
"@
        "SR | Revisar Pivot Table"                        = @"
SELECT app_id, field, COUNT(*)
    FROM app_settings
    GROUP BY app_id, field
    HAVING COUNT(*) > 1
"@
        "SR | Fecha Revisiones"                           = @"
WITH CTE AS (
        SELECT
            b.estacion,
            b.fecha       AS UltimoUso,
            ROW_NUMBER() OVER (PARTITION BY b.estacion ORDER BY b.fecha DESC) AS rn
        FROM bitacorasistema b
    )
    SELECT
        e.FECHAREV,
        c.estacion,
        c.UltimoUso
    FROM CTE c
    JOIN estaciones e
        ON c.estacion = e.idestacion
    WHERE c.rn = 1
    ORDER BY c.UltimoUso DESC;
"@
        "SR SYNC | nsplatformcontrol"                     = @"
BEGIN TRY
    BEGIN TRANSACTION;
    SELECT WorkspaceId, EntityType, OperationType, 0 AS IsSync, 0 AS Attempts, CreateDate
    INTO #tempcontroltaxes
    FROM nsplatformcontrol
    WHERE EntityType = 1;
    TRUNCATE TABLE nsplatformcontrol;
    INSERT INTO nsplatformcontrol (WorkspaceId, EntityType, OperationType, IsSync, Attempts, CreateDate)
    SELECT WorkspaceId, EntityType, OperationType, IsSync, Attempts, CreateDate
    FROM #tempcontroltaxes;
    DROP TABLE #tempcontroltaxes;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
"@
        "SR | Memoria Insuficiente"                       = @"
UPDATE empresas
        SET nombre='', razonsocial='',direccion='',sucursal='',
        rfc='',curp='', telefono='',giro='',contacto='',fax='',
        email='',idhardware='',web='',ciudad='',estado='',pais='',
        ciudadsucursal='',estadosucursal='',codigopostal='',a86ed5f9d02ec5b3='',
        codigopostalsucursal='',uid=newid();
GO
DELETE FROM registro_licencias;
"@
        "OTM | Eliminar Server en OTM"                    = @"
SELECT serie, ipserver, nombreservidor
    FROM configuracion;
"@
        "NSH | Eliminar Server en Hoteles"                = @"
SELECT serievalida, numserie, ipserver, nombreservidor, llave
    FROM configuracion;
"@
        "Restcard | Eliminar Server en Rest Card"         = @"
SELECT estacion, ipservidor FROM tabvariables;
"@
        "sql | Listar usuarios e idiomas"                 = @"
SELECT
    p.name AS Usuario,
    l.default_language_name AS Idioma
FROM
    sys.server_principals p
LEFT JOIN
    sys.sql_logins l ON p.principal_id = l.principal_id
WHERE
    p.type IN ('S', 'U')
"@
        "SR | Revisar Ultimo Folio de Producción"         = @"
        DECLARE @serie varchar(50)
        DECLARE @folio numeric(18, 0)
        DECLARE @nuevo numeric(18, 0)

        DECLARE cur CURSOR FOR
        SELECT serie, ultimofolioproduccion
        FROM folios

        OPEN cur
        FETCH NEXT FROM cur INTO @serie, @folio

        WHILE @@FETCH_STATUS = 0
        BEGIN
        IF @folio > 30000
        BEGIN
        SET @nuevo = @folio / 2

        UPDATE folios
        SET ultimofolioproduccion = @nuevo
        WHERE serie = @serie

        PRINT 'Serie ' + @serie + ': Se corrigió el folio de '
        + CAST(@folio AS varchar) + ' a '
        + CAST(@nuevo AS varchar)
        END
        ELSE
        BEGIN
        PRINT 'Serie ' + @serie + ': El folio de producción parece estar bien con '
        + CAST(@folio AS varchar)
        END

        FETCH NEXT FROM cur INTO @serie, @folio
        END

        CLOSE cur
        DEALLOCATE cur
"@
        "SR SYNC | Renovar NSPlatformControl"             = @"
/*  SE RECOMIENDA RESPALDAR LA BASE DE DATOS ANTES DE EJECUTAR ESTA CONSULTA
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */
DELETE FROM nsplatformcontrol;
UPDATE grupos                           SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE subgrupos                        SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE gruposmodificadores              SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE comentarios                      SET IdComentario = NEWID() WHERE 1=1;
UPDATE udsmedida                        SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE productos                        SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE modificadores                    SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE areasrestaurant                  SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE estaciones                       SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE formasdepago                     SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE usuarios                         SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE turnos                           SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE mesas                            SET WorkspaceId = NEWID() WHERE 1=1;
UPDATE gruposmodificadoresproductos     SET id          = NEWID() WHERE 1=1;
UPDATE gruposmodificadoresproductos     SET WorkspaceId = Id WHERE 1=1;
UPDATE dbo.declaracioncajero            SET WorkspaceId = NEWID() WHERE 1=1;
"@
    }
}
function Get-DzThemeBrush {
    param(
        [Parameter(Mandatory = $true)][string]$Hex,
        [Parameter(Mandatory = $true)][System.Windows.Media.Brush]$Fallback
    )
    if ([string]::IsNullOrWhiteSpace($Hex)) { return $Fallback }
    try {
        $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex)
        if ($brush -is [System.Windows.Freezable] -and $brush.CanFreeze) { $brush.Freeze() }
        return $brush
    } catch {
        return $Fallback
    }
}
function Get-TextPointerFromOffset {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.RichTextBox]$RichTextBox,
        [Parameter(Mandatory)][int]$Offset
    )
    if ($null -eq $RichTextBox.Document) { return $null }
    $pointer = $RichTextBox.Document.ContentStart
    $count = 0
    while ($pointer -ne $null) {
        $ctx = $pointer.GetPointerContext([System.Windows.Documents.LogicalDirection]::Forward)
        if ($ctx -eq [System.Windows.Documents.TextPointerContext]::Text) {
            $runText = $pointer.GetTextInRun([System.Windows.Documents.LogicalDirection]::Forward)
            $remaining = $Offset - $count
            if ($remaining -le $runText.Length) { return $pointer.GetPositionAtOffset($remaining) }
            $count += $runText.Length
            $pointer = $pointer.GetNextContextPosition([System.Windows.Documents.LogicalDirection]::Forward)
            continue
        }
        if ($ctx -eq [System.Windows.Documents.TextPointerContext]::ElementStart) {
            $el = $pointer.GetAdjacentElement([System.Windows.Documents.LogicalDirection]::Forward)
            if ($el -is [System.Windows.Documents.LineBreak]) {
                if ($count + 2 -ge $Offset) { return $pointer }
                $count += 2
            }
            $pointer = $pointer.GetNextContextPosition([System.Windows.Documents.LogicalDirection]::Forward)
            continue
        }
        if ($ctx -eq [System.Windows.Documents.TextPointerContext]::ElementEnd) {
            $parent = $pointer.Parent
            if ($parent -is [System.Windows.Documents.Paragraph]) {
                if ($count + 2 -ge $Offset) { return $pointer }
                $count += 2
            }
            $pointer = $pointer.GetNextContextPosition([System.Windows.Documents.LogicalDirection]::Forward)
            continue
        }
        $pointer = $pointer.GetNextContextPosition([System.Windows.Documents.LogicalDirection]::Forward)
    }
    return $RichTextBox.Document.ContentEnd
}
function Get-ResultTabHeaderText {
    param([System.Windows.Controls.TabItem]$TabItem)
    if (-not $TabItem) { return "Resultado" }
    $header = $TabItem.Header
    if ($header -is [System.Windows.Controls.TextBlock]) { return [string]$header.Text }
    if ($null -ne $header) { return [string]$header }
    return "Resultado"
}
function Get-ExportableResultTabs {
    param([System.Windows.Controls.TabControl]$TabControl)
    $exportable = @()
    if (-not $TabControl) { return $exportable }
    foreach ($item in $TabControl.Items) {
        if ($item -isnot [System.Windows.Controls.TabItem]) { continue }
        $dg = $item.Content
        if ($dg -isnot [System.Windows.Controls.DataGrid]) { continue }
        $dt = $null
        if ($dg.ItemsSource -is [System.Data.DataView]) {
            $dt = $dg.ItemsSource.Table
        } elseif ($dg.ItemsSource -is [System.Data.DataTable]) {
            $dt = $dg.ItemsSource
        } else {
            try { $dt = $dg.ItemsSource.Table } catch { $dt = $null }
        }
        if (-not $dt -or -not $dt.Rows -or $dt.Rows.Count -lt 1) { continue }
        $headerText = Get-ResultTabHeaderText -TabItem $item
        $exportable += [pscustomobject]@{
            Tab          = $item
            DataTable    = $dt
            RowCount     = $dt.Rows.Count
            Display      = "$headerText ($($dt.Rows.Count) filas)"
            DisplayShort = $headerText
        }
    }
    return $exportable
}
function Disconnect-DbCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Ctx
    )

    if ($Ctx.QueryRunning) {
        Write-DzDebug "`t[DEBUG][Disconnect] Cancelando query en ejecución..."
        try {
            if ($Ctx.CurrentQueryPowerShell) {
                $Ctx.CurrentQueryPowerShell.Stop()
                $Ctx.CurrentQueryPowerShell.Dispose()
            }
            if ($Ctx.CurrentQueryRunspace) {
                $Ctx.CurrentQueryRunspace.Close()
                $Ctx.CurrentQueryRunspace.Dispose()
            }
        } catch {
            Write-DzDebug "`t[DEBUG][Disconnect] Error cancelando query: $_"
        }
        $Ctx.CurrentQueryPowerShell = $null
        $Ctx.CurrentQueryRunspace = $null
        $Ctx.CurrentQueryAsync = $null
        $Ctx.QueryRunning = $false
        Write-DzDebug "`t[DEBUG][Disconnect] Query cancelada"
    }

    if ($Ctx.execUiTimer -and $Ctx.execUiTimer.IsEnabled) {
        Write-DzDebug "`t[DEBUG][Disconnect] Deteniendo execUiTimer..."
        $Ctx.execUiTimer.Stop()
    }

    if ($Ctx.QueryDoneTimer -and $Ctx.QueryDoneTimer.IsEnabled) {
        Write-DzDebug "`t[DEBUG][Disconnect] Deteniendo QueryDoneTimer..."
        $Ctx.QueryDoneTimer.Stop()
    }

    if ($Ctx.execStopwatch) {
        Write-DzDebug "`t[DEBUG][Disconnect] Deteniendo stopwatch..."
        $Ctx.execStopwatch.Stop()
        $Ctx.execStopwatch = $null
    }

    if ($Ctx.Connection) {
        Write-DzDebug "`t[DEBUG][Disconnect] Cerrando conexión SQL..."
        try {
            if ($Ctx.Connection.State -ne [System.Data.ConnectionState]::Closed) {
                $Ctx.Connection.Close()
            }
            $Ctx.Connection.Dispose()
        } catch {
            Write-DzDebug "`t[DEBUG][Disconnect] Error cerrando conexión: $_"
        }
        $Ctx.Connection = $null
    }

    Write-DzDebug "`t[DEBUG][Disconnect] Limpiando datos de conexión..."
    $Ctx.Server = $null
    $Ctx.User = $null
    $Ctx.Password = $null
    $Ctx.Database = $null
    $Ctx.DbCredential = $null

    if ($Ctx.tvDatabases) {
        Write-DzDebug "`t[DEBUG][Disconnect] Limpiando TreeView..."
        $Ctx.tvDatabases.Items.Clear()
    }

    if ($Ctx.cmbDatabases) {
        Write-DzDebug "`t[DEBUG][Disconnect] Limpiando ComboBox..."
        $Ctx.cmbDatabases.Items.Clear()
        $Ctx.cmbDatabases.IsEnabled = $false
    }

    if ($Ctx.lblConnectionStatus) {
        $Ctx.lblConnectionStatus.Text = "⚫ Desconectado"
    }

    Write-DzDebug "`t[DEBUG][Disconnect] Habilitando controles de conexión..."
    if ($Ctx.txtServer) { $Ctx.txtServer.IsEnabled = $true }
    if ($Ctx.txtUser) { $Ctx.txtUser.IsEnabled = $true }
    if ($Ctx.txtPassword) { $Ctx.txtPassword.IsEnabled = $true }
    if ($Ctx.btnConnectDb) { $Ctx.btnConnectDb.IsEnabled = $true }

    Write-DzDebug "`t[DEBUG][Disconnect] Deshabilitando controles de operaciones..."
    if ($Ctx.btnDisconnectDb) { $Ctx.btnDisconnectDb.IsEnabled = $false }
    if ($Ctx.btnExecute) { $Ctx.btnExecute.IsEnabled = $false }
    if ($Ctx.btnClearQuery) { $Ctx.btnClearQuery.IsEnabled = $false }
    if ($Ctx.btnExport) { $Ctx.btnExport.IsEnabled = $false }
    if ($Ctx.btnHistorial) { $Ctx.btnHistorial.IsEnabled = $false }
    if ($Ctx.cmbQueries) { $Ctx.cmbQueries.IsEnabled = $false }
    if ($Ctx.tcQueries) { $Ctx.tcQueries.IsEnabled = $false }
    if ($Ctx.tcResults) { $Ctx.tcResults.IsEnabled = $false }
    if ($Ctx.sqlEditor1) { $Ctx.sqlEditor1.IsEnabled = $false }
    if ($Ctx.dgResults) { $Ctx.dgResults.IsEnabled = $false }
    if ($Ctx.txtMessages) { $Ctx.txtMessages.IsEnabled = $false }

    if ($Ctx.txtMessages) {
        $Ctx.txtMessages.Text = "Desconectado de la base de datos."
    }

    if ($Ctx.txtServer) {
        try { $Ctx.txtServer.Focus() | Out-Null } catch {}
    }

    Write-DzDebug "`t[DEBUG][Disconnect] Desconexión completada exitosamente"
}
function Connect-DbCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Ctx)

    if ($null -eq $Ctx.txtServer -or $null -eq $Ctx.txtUser -or $null -eq $Ctx.txtPassword) {
        throw "Error interno: controles de conexión no inicializados."
    }

    $serverText = ([string]$Ctx.txtServer.Text).Trim()
    $userText = ([string]$Ctx.txtUser.Text).Trim()
    $passwordText = [string]$Ctx.txtPassword.Password

    Write-DzDebug "`t[DEBUG] | Server='$serverText' User='$userText' PasswordLen=$($passwordText.Length)"

    if ([string]::IsNullOrWhiteSpace($serverText) -or [string]::IsNullOrWhiteSpace($userText) -or [string]::IsNullOrWhiteSpace($passwordText)) {
        throw "Complete todos los campos de conexión"
    }

    $securePassword = (New-Object System.Net.NetworkCredential('', $passwordText)).SecurePassword
    $credential = New-Object System.Management.Automation.PSCredential($userText, $securePassword)

    $Ctx.Server = $serverText
    $Ctx.User = $userText
    $Ctx.Password = $passwordText
    $Ctx.DbCredential = $credential

    Write-DzDebug "`t[DEBUG] Obteniendo lista de bases de datos..."
    $databases = Get-SqlDatabases -Server $serverText -Credential $credential
    if (-not $databases -or $databases.Count -eq 0) {
        throw "Conexión correcta, pero no se encontraron bases de datos disponibles."
    }

    Write-DzDebug "`t[DEBUG] Se encontraron $($databases.Count) bases de datos"

    if ($Ctx.cmbDatabases) {
        $Ctx.cmbDatabases.Items.Clear()
        $Ctx.cmbDatabases.DisplayMemberPath = "Name"
        $Ctx.cmbDatabases.SelectedValuePath = "Name"

        foreach ($db in $databases) {
            $name = $null
            if ($db -is [string]) { $name = $db }
            elseif ($db.PSObject.Properties["Name"]) { $name = [string]$db.Name }
            elseif ($db.PSObject.Properties["Database"]) { $name = [string]$db.Database }
            else { $name = [string]$db }  # último recurso

            if (-not [string]::IsNullOrWhiteSpace($name)) {
                [void]$Ctx.cmbDatabases.Items.Add([pscustomobject]@{ Name = $name })
            }
        }

        $Ctx.cmbDatabases.IsEnabled = $true
        $Ctx.cmbDatabases.SelectedIndex = 0
        $Ctx.Database = [string]$Ctx.cmbDatabases.SelectedValue

    }

    if ($Ctx.lblConnectionStatus) {
        $Ctx.lblConnectionStatus.Text = "✓ Conectado a: $serverText | DB: $($Ctx.Database)"
    }

    if ($Ctx.txtServer) { $Ctx.txtServer.IsEnabled = $false }
    if ($Ctx.txtUser) { $Ctx.txtUser.IsEnabled = $false }
    if ($Ctx.txtPassword) { $Ctx.txtPassword.IsEnabled = $false }
    if ($Ctx.btnConnectDb) { $Ctx.btnConnectDb.IsEnabled = $false }

    if ($Ctx.btnDisconnectDb) { $Ctx.btnDisconnectDb.IsEnabled = $true }
    if ($Ctx.btnExecute) { $Ctx.btnExecute.IsEnabled = $true }
    if ($Ctx.btnClearQuery) { $Ctx.btnClearQuery.IsEnabled = $true }
    if ($Ctx.cmbQueries) { $Ctx.cmbQueries.IsEnabled = $true }
    if ($Ctx.btnExport) { $Ctx.btnExport.IsEnabled = $true }
    if ($Ctx.btnHistorial) { $Ctx.btnHistorial.IsEnabled = $true }
    if ($Ctx.tcQueries) { $Ctx.tcQueries.IsEnabled = $true }
    if ($Ctx.tcResults) { $Ctx.tcResults.IsEnabled = $true }
    if ($Ctx.sqlEditor1) { $Ctx.sqlEditor1.IsEnabled = $true }
    if ($Ctx.dgResults) { $Ctx.dgResults.IsEnabled = $true }
    if ($Ctx.txtMessages) { $Ctx.txtMessages.IsEnabled = $true }

    if ($Ctx.sqlEditor1) { try { $Ctx.sqlEditor1.Focus() | Out-Null } catch {} }
    if ($Ctx.tvDatabases) {
        Write-DzDebug "`t[DEBUG] Inicializando TreeView..."

        Initialize-SqlTreeView `
            -TreeView $Ctx.tvDatabases `
            -Server $serverText `
            -Credential $credential `
            -User $userText `
            -Password $passwordText `
            -GetCurrentDatabase ({ $Ctx.Database }.GetNewClosure()) `
            -AutoExpand $true `
            -OnDatabaseSelected ({
                param($dbName)

                if (-not $Ctx.cmbDatabases) { return }

                $dbName = [string]$dbName

                try {
                    if ($Ctx.cmbDatabases.SelectedValuePath -and $Ctx.cmbDatabases.SelectedValuePath.Trim().Length -gt 0) {
                        $Ctx.cmbDatabases.SelectedValue = $dbName
                    } else {
                        $Ctx.cmbDatabases.SelectedItem = $dbName
                    }

                    if (-not $Ctx.cmbDatabases.SelectedItem -and -not $Ctx.cmbDatabases.SelectedValue) {
                        for ($i = 0; $i -lt $Ctx.cmbDatabases.Items.Count; $i++) {
                            $item = $Ctx.cmbDatabases.Items[$i]
                            $n = $null
                            if ($item -is [string]) { $n = $item }
                            elseif ($item.PSObject.Properties["Name"]) { $n = [string]$item.Name }
                            elseif ($item.PSObject.Properties["Database"]) { $n = [string]$item.Database }
                            else { $n = [string]$item }

                            if ($n -eq $dbName) {
                                $Ctx.cmbDatabases.SelectedIndex = $i
                                break
                            }
                        }
                    }

                    if ($Ctx.cmbDatabases.SelectedValuePath -and $Ctx.cmbDatabases.SelectedValuePath.Trim().Length -gt 0) {
                        $Ctx.Database = [string]$Ctx.cmbDatabases.SelectedValue
                    } else {
                        $sel = $Ctx.cmbDatabases.SelectedItem
                        if ($sel -is [string]) { $Ctx.Database = $sel }
                        elseif ($sel -and $sel.PSObject.Properties["Name"]) { $Ctx.Database = [string]$sel.Name }
                        elseif ($sel -and $sel.PSObject.Properties["Database"]) { $Ctx.Database = [string]$sel.Database }
                        else { $Ctx.Database = [string]$sel }
                    }

                    if ($Ctx.lblConnectionStatus) {
                        $Ctx.lblConnectionStatus.Text = "✓ Conectado a: $($Ctx.Server) | DB: $($Ctx.Database)"
                    }

                    if ($Ctx.tvDatabases) {
                        Select-SqlTreeDatabase -TreeView $Ctx.tvDatabases -DatabaseName $Ctx.Database
                    }
                    if ($Ctx.tcQueries -and (Get-Command Set-QueryTabsDatabase -ErrorAction SilentlyContinue)) {
                        Set-QueryTabsDatabase -TabControl $Ctx.tcQueries -Database $Ctx.Database
                        Write-DzDebug "`t[DEBUG][TreeView] Pestañas actualizadas con BD: $($Ctx.Database)"
                    }
                    Write-DzDebug "`t[DEBUG][TreeView] BD seleccionada: $($Ctx.Database) (dbName='$dbName')"
                } catch {
                    Write-DzDebug "`t[DEBUG][OnDatabaseSelected] ERROR: $($_.Exception.Message)" -Color Red
                }
            }).GetNewClosure() `
            -OnDatabasesRefreshed ({
                try {
                    if (-not $Ctx.Server -or -not $Ctx.DbCredential) { return }

                    $dbs = Get-SqlDatabases -Server $Ctx.Server -Credential $Ctx.DbCredential
                    if (-not $dbs -or $dbs.Count -lt 1 -or -not $Ctx.cmbDatabases) { return }

                    $Ctx.cmbDatabases.Items.Clear()

                    if ($Ctx.cmbDatabases.DisplayMemberPath -and $Ctx.cmbDatabases.DisplayMemberPath.Trim().Length -gt 0) {
                        foreach ($db in $dbs) {
                            $name = $null
                            if ($db -is [string]) { $name = $db }
                            elseif ($db.PSObject.Properties["Name"]) { $name = [string]$db.Name }
                            elseif ($db.PSObject.Properties["Database"]) { $name = [string]$db.Database }
                            else { $name = [string]$db }

                            if (-not [string]::IsNullOrWhiteSpace($name)) {
                                [void]$Ctx.cmbDatabases.Items.Add([pscustomobject]@{ Name = $name })
                            }
                        }
                    } else {
                        foreach ($db in $dbs) { [void]$Ctx.cmbDatabases.Items.Add($db) }
                    }

                    if ($Ctx.Database) {
                        if ($Ctx.cmbDatabases.SelectedValuePath -and $Ctx.cmbDatabases.SelectedValuePath.Trim().Length -gt 0) {
                            $Ctx.cmbDatabases.SelectedValue = [string]$Ctx.Database
                        } else {
                            $Ctx.cmbDatabases.SelectedItem = $Ctx.Database
                        }
                    }

                    if (-not $Ctx.cmbDatabases.SelectedItem -and $Ctx.cmbDatabases.Items.Count -gt 0) {
                        $Ctx.cmbDatabases.SelectedIndex = 0
                    }

                    if ($Ctx.cmbDatabases.SelectedValuePath -and $Ctx.cmbDatabases.SelectedValuePath.Trim().Length -gt 0) {
                        $Ctx.Database = [string]$Ctx.cmbDatabases.SelectedValue
                    } else {
                        $sel = $Ctx.cmbDatabases.SelectedItem
                        if ($sel -is [string]) { $Ctx.Database = $sel }
                        elseif ($sel -and $sel.PSObject.Properties["Name"]) { $Ctx.Database = [string]$sel.Name }
                        elseif ($sel -and $sel.PSObject.Properties["Database"]) { $Ctx.Database = [string]$sel.Database }
                        else { $Ctx.Database = [string]$sel }
                    }

                    if ($Ctx.lblConnectionStatus) {
                        $Ctx.lblConnectionStatus.Text = "✓ Conectado a: $($Ctx.Server) | DB: $($Ctx.Database)"
                    }

                    if ($Ctx.tvDatabases -and $Ctx.Database) {
                        Select-SqlTreeDatabase -TreeView $Ctx.tvDatabases -DatabaseName $Ctx.Database
                    }

                    Write-DzDebug "`t[DEBUG][TreeView] ComboBox actualizado con $($dbs.Count) bases de datos"
                } catch {
                    Write-DzDebug "`t[DEBUG][OnDatabasesRefreshed] Error: $_"
                }
            }).GetNewClosure() `
            -InsertTextHandler ({
                param($text)
                if ($Ctx.tcQueries) {
                    Insert-TextIntoActiveQuery -TabControl $Ctx.tcQueries -Text $text
                }
            }).GetNewClosure()
    }

    Write-DzDebug "`t[DEBUG] Conexión establecida exitosamente"
    if ($Ctx.tvDatabases -and $Ctx.Database) {
        Select-SqlTreeDatabase -TreeView $Ctx.tvDatabases -DatabaseName $Ctx.Database
    }
}
function Export-ResultsCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Ctx)

    if (-not $Ctx.tcResults) {
        Ui-Warn "No existe un panel de resultados para exportar." "Atención" $Ctx.MainWindow
        return
    }

    $resultTabs = Get-ExportableResultTabs -TabControl $Ctx.tcResults
    if (-not $resultTabs -or $resultTabs.Count -eq 0) {
        Ui-Warn "No existe pestaña con resultados para exportar." "Atención" $Ctx.MainWindow
        return
    }

    $target = $null
    if ($resultTabs.Count -gt 1) {
        $items = $resultTabs | ForEach-Object {
            [pscustomobject]@{
                Path         = $_
                Display      = $_.Display
                DisplayShort = $_.DisplayShort
            }
        }
        $selected = Show-WpfPathSelectionDialog -Title "Exportar resultados" -Prompt "Seleccione la pestaña de resultados a exportar:" -Items $items -ExecuteButtonText "Exportar"
        if (-not $selected) { return }
        $target = $selected.Path
    } else {
        $target = $resultTabs[0]
    }

    $rowCount = [int]$target.RowCount
    $headerText = [string]$target.DisplayShort

    $safeName = ($headerText -replace '[\\/:*?"<>|]', '-')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "resultado" }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = "CSV (*.csv)|*.csv|Texto delimitado (*.txt)|*.txt"
    $saveDialog.FileName = "${timestamp}_${safeName}.csv"
    $saveDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($saveDialog.ShowDialog() -ne $true) { return }

    $filePath = $saveDialog.FileName
    $extension = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()

    if ($extension -eq ".txt" -or $saveDialog.FilterIndex -eq 2) {
        $separator = New-WpfInputDialog -Title "Separador de exportación" -Prompt "Ingrese el separador para el archivo de texto:" -DefaultValue "|"
        if ($null -eq $separator) { return }
        Export-ResultSetToDelimitedText -ResultSet $target.DataTable -Path $filePath -Separator $separator
    } else {
        Export-ResultSetToCsv -ResultSet ([pscustomobject]@{ DataTable = $target.DataTable }) -Path $filePath
    }

    Ui-Info "Exportación completada en:`n$filePath" "Exportación" $Ctx.MainWindow
}
function Get-DbNameFromComboSelection {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ComboBox)

    $selected = $ComboBox.SelectedItem
    if (-not $selected) { return $null }

    $db = $null
    if ($ComboBox.SelectedValuePath -and $ComboBox.SelectedValuePath.Trim().Length -gt 0) {
        $db = [string]$ComboBox.SelectedValue
    } else {
        if ($selected -is [string]) { $db = [string]$selected }
        elseif ($selected.PSObject.Properties["Name"]) { $db = [string]$selected.Name }
        elseif ($selected.PSObject.Properties["Database"]) { $db = [string]$selected.Database }
        else { $db = [string]$selected }
    }

    if ([string]::IsNullOrWhiteSpace($db)) { return $null }
    return $db
}
function Get-DbUiContext {
    [CmdletBinding()]
    param()

    @{
        QueryRunning           = $script:QueryRunning
        CurrentQueryPowerShell = $script:CurrentQueryPowerShell
        CurrentQueryRunspace   = $script:CurrentQueryRunspace
        CurrentQueryAsync      = $script:CurrentQueryAsync
        execUiTimer            = $script:execUiTimer
        QueryDoneTimer         = $script:QueryDoneTimer
        execStopwatch          = $script:execStopwatch

        Connection             = $global:connection
        Server                 = $global:server
        User                   = $global:user
        Password               = $global:password
        Database               = $global:database
        DbCredential           = $global:dbCredential

        tvDatabases            = $global:tvDatabases
        cmbDatabases           = $global:cmbDatabases
        lblConnectionStatus    = $global:lblConnectionStatus

        txtServer              = $global:txtServer
        txtUser                = $global:txtUser
        txtPassword            = $global:txtPassword
        btnConnectDb           = $global:btnConnectDb

        btnDisconnectDb        = $global:btnDisconnectDb
        btnExecute             = $global:btnExecute
        btnClearQuery          = $global:btnClearQuery
        btnExport              = $global:btnExport
        btnHistorial           = $global:btnHistorial
        cmbQueries             = $global:cmbQueries
        tcQueries              = $global:tcQueries
        tcResults              = $global:tcResults
        sqlEditor1             = $global:sqlEditor1
        dgResults              = $global:dgResults
        txtMessages            = $global:txtMessages
        lblRowCount            = $global:lblRowCount
        lblExecutionTimer      = $global:lblExecutionTimer

        MainWindow             = $global:MainWindow
    }
}
function Disconnect-DbUiSafe {
    [CmdletBinding()]
    param()

    try {
        $ctx = Get-DbUiContext
        Disconnect-DbCore -Ctx $ctx
        Save-DbUiContext -Ctx $ctx
        Write-Host "✓ Desconectado exitosamente" -ForegroundColor Green
    } catch {
        Write-DzDebug "`t[DEBUG][Disconnect] ERROR: $($_.Exception.Message)"
        Write-DzDebug "`t[DEBUG][Disconnect] Stack: $($_.ScriptStackTrace)"
        Write-Host "Error al desconectar: $($_.Exception.Message)" -ForegroundColor Red
        Ui-Error "Error al desconectar:`n`n$($_.Exception.Message)" $global:MainWindow
    }
}
function Connect-DbUiSafe {
    [CmdletBinding()]
    param()

    try {
        $ctx = Get-DbUiContext
        Connect-DbCore -Ctx $ctx
        Save-DbUiContext -Ctx $ctx
        if (Get-Command Save-DzSqlConnection -ErrorAction SilentlyContinue) {
            Save-DzSqlConnection -Server $ctx.Server -User $ctx.User -Password $ctx.Password
        }
        Write-Host "✓ Conectado exitosamente a: $($ctx.Server)" -ForegroundColor Green
    } catch {
        Write-DzDebug "`t[DEBUG][Connect] CATCH: $($_.Exception.Message)"
        Write-DzDebug "`t[DEBUG][Connect] Tipo: $($_.Exception.GetType().FullName)"
        Write-DzDebug "`t[DEBUG][Connect] Stack: $($_.ScriptStackTrace)"
        Ui-Error "Error de conexión: $($_.Exception.Message)" $global:MainWindow
        Write-Host "Error | Error de conexión: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Export-ModuleMember -Function @(
    'Invoke-SqlQuery', 'Invoke-SqlQueryMultiResultSet', 'Remove-SqlComments', 'Get-SqlDatabases', 'Get-SqlDatabasesInfo', 'Backup-Database', 'Connect-DbUiSafe', 'Disconnect-DbUiSafe', 'get-DbUiContext',
    'Execute-SqlQuery', 'Get-IniConnections', 'Load-IniConnectionsToComboBox',
    'Show-MultipleResultSets', 'Export-ResultSetToCsv', 'Export-ResultSetToDelimitedText',
    'Get-PredefinedQueries', 'Remove-SqlComments', 'Get-TextPointerFromOffset', 'Get-ResultTabHeaderText',
    'Get-ExportableResultTabs', 'Get-UseDatabaseFromQuery', 'Disconnect-DbCore', 'Connect-DbCore', 'Export-ResultsCore', 'Get-DbNameFromComboSelection'
)