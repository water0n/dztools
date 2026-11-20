#requires -Version 5.0

$script:DzAiSqlContextCache = $null

function Get-DzAiSqlContextPath {
    $moduleRoot = Split-Path -Parent $PSCommandPath
    return (Join-Path (Split-Path -Parent $moduleRoot) "resources\ai-sql-context.json")
}

function Get-DzAiSqlContext {
    [CmdletBinding()]
    param([switch]$Refresh)

    if ($script:DzAiSqlContextCache -and -not $Refresh) {
        return $script:DzAiSqlContextCache
    }

    $path = Get-DzAiSqlContextPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "No se encontro el contexto SQL para IA: $path"
    }

    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $script:DzAiSqlContextCache = $json | ConvertFrom-Json
    return $script:DzAiSqlContextCache
}

function Find-DzAiSqlIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        $Context = (Get-DzAiSqlContext)
    )

    $q = $Question.ToLowerInvariant()
    $matches = @()

    foreach ($domain in $Context.domains) {
        $score = 0
        foreach ($keyword in $domain.keywords) {
            $kw = ([string]$keyword).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($kw)) { continue }
            if ($q.Contains($kw)) { $score += [Math]::Max(1, $kw.Length) }
        }
        if ($score -gt 0) {
            $matches += [pscustomobject]@{
                Domain = $domain
                Score  = $score
            }
        }
    }

    $ordered = @($matches | Sort-Object -Property Score -Descending)
    if ($ordered.Count -eq 0) {
        $fallback = $Context.domains | Where-Object { $_.id -eq "ventas" } | Select-Object -First 1
        return [pscustomobject]@{
            PrimaryDomain = $fallback
            Domains       = @($fallback)
            Score         = 0
        }
    }

    $domains = @($ordered | Select-Object -First 2 | ForEach-Object { $_.Domain })
    return [pscustomobject]@{
        PrimaryDomain = $ordered[0].Domain
        Domains       = $domains
        Score         = $ordered[0].Score
    }
}

function ConvertTo-DzAiSqlContextText {
    param(
        [Parameter(Mandatory = $true)]$Intent,
        [Parameter(Mandatory = $true)]$Context
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add("Motor: $($Context.engine)")
    [void]$lines.Add("")
    [void]$lines.Add("Reglas globales:")
    foreach ($rule in $Context.globalRules) {
        [void]$lines.Add("- $rule")
    }

    foreach ($domain in $Intent.Domains) {
        if (-not $domain) { continue }
        [void]$lines.Add("")
        [void]$lines.Add("Dominio: $($domain.id) - $($domain.title)")
        if ($domain.tables) { [void]$lines.Add("Tablas: " + (($domain.tables | ForEach-Object { [string]$_ }) -join ", ")) }
        if ($domain.views) { [void]$lines.Add("Vistas: " + (($domain.views | ForEach-Object { [string]$_ }) -join ", ")) }
        if ($domain.columns) { [void]$lines.Add("Columnas: " + (($domain.columns | ForEach-Object { [string]$_ }) -join ", ")) }
        if ($domain.joins -and $domain.joins.Count -gt 0) {
            [void]$lines.Add("Joins:")
            foreach ($join in $domain.joins) { [void]$lines.Add("- $join") }
        }
        if ($domain.notes) {
            [void]$lines.Add("Notas:")
            foreach ($note in $domain.notes) { [void]$lines.Add("- $note") }
        }
        if ($domain.examples) {
            [void]$lines.Add("Ejemplos:")
            foreach ($example in $domain.examples) {
                [void]$lines.Add("-- $($example.name)")
                [void]$lines.Add([string]$example.sql)
            }
        }
    }

    return ($lines -join "`n")
}

function New-DzAiSqlPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        $Context = (Get-DzAiSqlContext)
    )

    $intent = Find-DzAiSqlIntent -Question $Question -Context $Context
    $contextText = ConvertTo-DzAiSqlContextText -Intent $intent -Context $Context

    $system = "Eres un asistente experto en SQL Server para soporte tecnico NationalSoft. Genera solamente una consulta SQL SELECT segura y ejecutable. No uses Markdown, no expliques, no inventes tablas fuera del contexto proporcionado."
    $prompt = @"
Genera una consulta SQL Server para responder la pregunta del usuario.

Pregunta:
$Question

Contexto permitido:
$contextText

Requisitos:
- Devuelve solamente SQL.
- La consulta debe empezar con SELECT o WITH y terminar con punto y coma.
- No uses instrucciones que modifiquen datos o estructura.
- Si necesitas fechas relativas, usa GETDATE().
"@

    return [pscustomobject]@{
        SystemInstruction = $system
        Prompt            = $prompt
        IntentId          = $intent.PrimaryDomain.id
        IntentTitle       = $intent.PrimaryDomain.title
    }
}

function Get-DzAiSchemaSearchTerms {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Question)

    $q = $Question.ToLowerInvariant()
    $schemaWords = @('tabla', 'tablas', 'columna', 'columnas', 'campo', 'campos', 'schema', 'esquema')
    $hasSchemaIntent = $false
    foreach ($word in $schemaWords) {
        if ($q.Contains($word)) {
            $hasSchemaIntent = $true
            break
        }
    }
    if (-not $hasSchemaIntent) { return @() }

    $terms = New-Object 'System.Collections.Generic.List[string]'
    $patterns = @(
        '(?i)(?:con|tengan|tiene|tienen|contengan|contiene)\s+(?:la\s+)?(?:columna|campo)?\s*([a-zA-Z_][a-zA-Z0-9_]*)',
        '(?i)(?:columna|campo)\s+([a-zA-Z_][a-zA-Z0-9_]*)'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Question, $pattern)
        if ($match.Success) {
            [void]$terms.Add($match.Groups[1].Value)
        }
    }

    if ($terms.Count -eq 0) { return @() }

    $expanded = New-Object 'System.Collections.Generic.List[string]'
    foreach ($term in $terms) {
        $clean = ([string]$term).Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        if (-not $expanded.Contains($clean)) { [void]$expanded.Add($clean) }
        switch -Regex ($clean.ToLowerInvariant()) {
            '^(companyid|company|empresa)$' {
                if (-not $expanded.Contains('idempresa')) { [void]$expanded.Add('idempresa') }
            }
            '^(workspace|tenant|tenantid)$' {
                if (-not $expanded.Contains('WorkspaceId')) { [void]$expanded.Add('WorkspaceId') }
            }
        }
    }

    return @($expanded)
}

function New-DzAiSchemaDiscoverySql {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Question)

    $terms = @(Get-DzAiSchemaSearchTerms -Question $Question)
    if ($terms.Count -eq 0) { return "" }

    $termSelects = @()
    foreach ($term in $terms) {
        $safe = ([string]$term).Replace("'", "''")
        $termSelects += "SELECT '$safe' AS term"
    }
    $termSql = $termSelects -join "`n    UNION ALL`n    "

    return @"
WITH search_terms AS (
    $termSql
)
SELECT
    c.TABLE_SCHEMA,
    c.TABLE_NAME,
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.IS_NULLABLE,
    c.ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE EXISTS (
    SELECT 1
    FROM search_terms st
    WHERE c.COLUMN_NAME COLLATE Latin1_General_CI_AI LIKE '%' + st.term + '%'
)
ORDER BY
    c.TABLE_SCHEMA,
    c.TABLE_NAME,
    c.ORDINAL_POSITION;
"@
}

function Get-DzAiSqlFromText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Text)

    $candidate = ([string]$Text).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) { return "" }

    $block = [regex]::Match($candidate, '(?is)```(?:sql)?\s*(.*?)\s*```')
    if ($block.Success) {
        $candidate = $block.Groups[1].Value.Trim()
    }

    $candidate = $candidate -replace '^\s*SQL\s*:\s*', ''
    $candidate = $candidate.Trim()

    $startMatch = [regex]::Match($candidate, "(?is)\b(WITH|SELECT)\b")
    if ($startMatch.Success -and $startMatch.Index -gt 0) {
        $candidate = $candidate.Substring($startMatch.Index).Trim()
    }

    if (-not $candidate.EndsWith(";")) {
        $candidate = "$candidate;"
    }
    return $candidate
}

function Test-DzAiGeneratedSqlSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Sql)

    $clean = Get-DzAiSqlFromText -Text $Sql
    if ([string]::IsNullOrWhiteSpace($clean)) { return $false }

    $withoutComments = [regex]::Replace($clean, "(?is)/\*.*?\*/", " ")
    $withoutComments = [regex]::Replace($withoutComments, "(?m)--.*$", " ")
    $normalized = $withoutComments.Trim()

    if ($normalized -notmatch '^(?is)\s*(SELECT|WITH)\b') { return $false }

    $blocked = '(?is)\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|TRUNCATE|EXEC|EXECUTE|CREATE|BACKUP|RESTORE|GRANT|REVOKE|DENY|DBCC|BULK)\b'
    if ($normalized -match $blocked) { return $false }

    return $true
}

Export-ModuleMember -Function @(
    'Get-DzAiSqlContext',
    'Find-DzAiSqlIntent',
    'New-DzAiSqlPrompt',
    'New-DzAiSchemaDiscoverySql',
    'Get-DzAiSchemaSearchTerms',
    'Test-DzAiGeneratedSqlSafe',
    'Get-DzAiSqlFromText'
)
