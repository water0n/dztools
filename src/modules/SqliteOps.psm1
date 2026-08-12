#requires -Version 5.0
#SqliteOps.psm1 - SQLite runtime and cleaner tools for DzTools
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
try { Add-Type -AssemblyName System.Data -ErrorAction Stop } catch { try { Add-Type -AssemblyName System.Data.Common -ErrorAction SilentlyContinue } catch {} }

$script:DzSqliteResourceDir = "C:\temp\dztools\release\resources"
$script:DzSqliteZipName = "sqlite-dll-win-x64-3530200.zip"
$script:DzSqliteDllName = "sqlite3.dll"
$script:DzSqliteRawUrl = "https://raw.githubusercontent.com/water0n/dztools/main/sqlite-dll-win-x64-3530200.zip"
$script:DzSqliteZipSha256 = "5D40DE68DA94CEE0FBB01A7CAAE96C9226872549FB007E826F63CD7BB464B463"
$script:DzSqliteDefaultDbPath = "C:\NationalSoft\nspfmsync.db"

function Write-DzSqliteDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    $text = "[SQLite] $Message"
    if (Get-Command Write-DzDebug -ErrorAction SilentlyContinue) {
        try {
            Write-DzDebug -Message $text -Color $Color
            return
        } catch {}
    }

    Write-Host $text -ForegroundColor $Color
}

function Write-DzSqliteError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Context,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("[SQLite][ERROR] $Context")
    $lines.Add("Mensaje: $($ErrorRecord.Exception.Message)")
    $lines.Add("Tipo: $($ErrorRecord.Exception.GetType().FullName)")
    if ($ErrorRecord.FullyQualifiedErrorId) { $lines.Add("FullyQualifiedErrorId: $($ErrorRecord.FullyQualifiedErrorId)") }
    if ($ErrorRecord.CategoryInfo) { $lines.Add("CategoryInfo: $($ErrorRecord.CategoryInfo)") }
    if ($ErrorRecord.InvocationInfo) {
        if ($ErrorRecord.InvocationInfo.ScriptName) { $lines.Add("Archivo: $($ErrorRecord.InvocationInfo.ScriptName)") }
        if ($ErrorRecord.InvocationInfo.ScriptLineNumber) { $lines.Add("Linea: $($ErrorRecord.InvocationInfo.ScriptLineNumber)") }
        if ($ErrorRecord.InvocationInfo.OffsetInLine) { $lines.Add("Columna: $($ErrorRecord.InvocationInfo.OffsetInLine)") }
        if ($ErrorRecord.InvocationInfo.Line) { $lines.Add("Codigo: $($ErrorRecord.InvocationInfo.Line.Trim())") }
        if ($ErrorRecord.InvocationInfo.PositionMessage) { $lines.Add("Posicion: $($ErrorRecord.InvocationInfo.PositionMessage)") }
    }
    if ($ErrorRecord.ScriptStackTrace) { $lines.Add("ScriptStackTrace:`n$($ErrorRecord.ScriptStackTrace)") }
    if ($ErrorRecord.Exception.StackTrace) { $lines.Add("StackTrace .NET:`n$($ErrorRecord.Exception.StackTrace)") }

    $details = ($lines -join "`n")
    Write-Host $details -ForegroundColor Red
}

function Import-DzSqliteNativeClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DllPath
    )

    if (-not [Environment]::Is64BitProcess) {
        throw "El runtime SQLite incluido es x64. Ejecuta DzTools con PowerShell de 64 bits."
    }
    if (-not (Test-Path -LiteralPath $DllPath -PathType Leaf)) {
        throw "No se encontro sqlite3.dll en: $DllPath"
    }

    $dllDir = [System.IO.Path]::GetDirectoryName($DllPath)
    if (-not ("DzTools.Sqlite.NativeClient" -as [type])) {
        $source = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace DzTools.Sqlite
{
    public sealed class QueryResult
    {
        public string[] Columns;
        public object[][] Rows;
    }

    public static class NativeClient
    {
        private const int SQLITE_OK = 0;
        private const int SQLITE_ROW = 100;
        private const int SQLITE_DONE = 101;
        private const int SQLITE_INTEGER = 1;
        private const int SQLITE_FLOAT = 2;
        private const int SQLITE_TEXT = 3;
        private const int SQLITE_BLOB = 4;
        private const int SQLITE_NULL = 5;
        private const int SQLITE_OPEN_READONLY = 0x00000001;
        private const int SQLITE_OPEN_READWRITE = 0x00000002;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool SetDllDirectory(string lpPathName);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "sqlite3_open_v2")]
        private static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_close(IntPtr db);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "sqlite3_prepare_v2")]
        private static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int numBytes, out IntPtr stmt, IntPtr tail);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_step(IntPtr stmt);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_finalize(IntPtr stmt);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_errmsg(IntPtr db);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_column_count(IntPtr stmt);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_column_name(IntPtr stmt, int iCol);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_column_type(IntPtr stmt, int iCol);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern long sqlite3_column_int64(IntPtr stmt, int iCol);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern double sqlite3_column_double(IntPtr stmt, int iCol);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_column_text(IntPtr stmt, int iCol);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_column_blob(IntPtr stmt, int iCol);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_column_bytes(IntPtr stmt, int iCol);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] value, int byteCount, IntPtr destructor);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_changes(IntPtr db);

        public static void ConfigureNativePath(string directory)
        {
            if (!SetDllDirectory(directory))
            {
                throw new InvalidOperationException("No se pudo registrar el directorio SQLite. Win32=" + Marshal.GetLastWin32Error());
            }
        }

        public static QueryResult Query(string dbPath, string sql, string[] values)
        {
            IntPtr db = IntPtr.Zero;
            IntPtr stmt = IntPtr.Zero;
            try
            {
                db = Open(dbPath, true);
                stmt = Prepare(db, sql);
                BindAll(db, stmt, values);

                int colCount = sqlite3_column_count(stmt);
                List<string> columns = new List<string>();
                List<object[]> rows = new List<object[]>();
                HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                for (int i = 0; i < colCount; i++)
                {
                    string name = Utf8PtrToString(sqlite3_column_name(stmt, i), -1);
                    if (String.IsNullOrWhiteSpace(name)) { name = "Column" + (i + 1); }
                    string unique = name;
                    int suffix = 2;
                    while (names.Contains(unique))
                    {
                        unique = name + "_" + suffix;
                        suffix++;
                    }
                    names.Add(unique);
                    columns.Add(unique);
                }

                while (true)
                {
                    int rc = sqlite3_step(stmt);
                    if (rc == SQLITE_ROW)
                    {
                        object[] row = new object[colCount];
                        for (int i = 0; i < colCount; i++)
                        {
                            row[i] = GetColumnValue(stmt, i);
                        }
                        rows.Add(row);
                        continue;
                    }
                    if (rc == SQLITE_DONE) { break; }
                    throw new InvalidOperationException(GetError(db) + " (SQLite " + rc + ")");
                }

                return new QueryResult { Columns = columns.ToArray(), Rows = rows.ToArray() };
            }
            finally
            {
                if (stmt != IntPtr.Zero) { sqlite3_finalize(stmt); }
                if (db != IntPtr.Zero) { sqlite3_close(db); }
            }
        }

        public static long ExecuteNonQuery(string dbPath, string sql, string[] values)
        {
            IntPtr db = IntPtr.Zero;
            IntPtr stmt = IntPtr.Zero;
            try
            {
                db = Open(dbPath, false);
                stmt = Prepare(db, sql);
                BindAll(db, stmt, values);

                while (true)
                {
                    int rc = sqlite3_step(stmt);
                    if (rc == SQLITE_DONE) { break; }
                    if (rc == SQLITE_ROW) { continue; }
                    throw new InvalidOperationException(GetError(db) + " (SQLite " + rc + ")");
                }

                return sqlite3_changes(db);
            }
            finally
            {
                if (stmt != IntPtr.Zero) { sqlite3_finalize(stmt); }
                if (db != IntPtr.Zero) { sqlite3_close(db); }
            }
        }

        private static IntPtr Open(string dbPath, bool readOnly)
        {
            IntPtr db;
            int flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE;
            int rc = sqlite3_open_v2(ToUtf8Z(dbPath), out db, flags, IntPtr.Zero);
            if (rc != SQLITE_OK)
            {
                string msg = db != IntPtr.Zero ? GetError(db) : "Codigo SQLite " + rc;
                if (db != IntPtr.Zero) { sqlite3_close(db); }
                throw new InvalidOperationException(msg);
            }
            return db;
        }

        private static IntPtr Prepare(IntPtr db, string sql)
        {
            IntPtr stmt;
            byte[] sqlBytes = ToUtf8Z(sql);
            int rc = sqlite3_prepare_v2(db, sqlBytes, sqlBytes.Length, out stmt, IntPtr.Zero);
            if (rc != SQLITE_OK)
            {
                throw new InvalidOperationException(GetError(db) + " (SQLite " + rc + ")");
            }
            return stmt;
        }

        private static void BindAll(IntPtr db, IntPtr stmt, string[] values)
        {
            if (values == null) { return; }
            for (int i = 0; i < values.Length; i++)
            {
                byte[] raw = ToUtf8Z(values[i]);
                int rc = sqlite3_bind_text(stmt, i + 1, raw, raw.Length - 1, new IntPtr(-1));
                if (rc != SQLITE_OK)
                {
                    throw new InvalidOperationException(GetError(db) + " (SQLite " + rc + ")");
                }
            }
        }

        private static object GetColumnValue(IntPtr stmt, int iCol)
        {
            int type = sqlite3_column_type(stmt, iCol);
            switch (type)
            {
                case SQLITE_INTEGER:
                    return sqlite3_column_int64(stmt, iCol);
                case SQLITE_FLOAT:
                    return sqlite3_column_double(stmt, iCol);
                case SQLITE_TEXT:
                    return Utf8PtrToString(sqlite3_column_text(stmt, iCol), sqlite3_column_bytes(stmt, iCol));
                case SQLITE_BLOB:
                    return "(BLOB " + sqlite3_column_bytes(stmt, iCol) + " bytes)";
                case SQLITE_NULL:
                    return DBNull.Value;
                default:
                    return DBNull.Value;
            }
        }

        private static string GetError(IntPtr db)
        {
            return Utf8PtrToString(sqlite3_errmsg(db), -1);
        }

        private static byte[] ToUtf8Z(string value)
        {
            if (value == null) { value = String.Empty; }
            byte[] raw = Encoding.UTF8.GetBytes(value);
            byte[] output = new byte[raw.Length + 1];
            Buffer.BlockCopy(raw, 0, output, 0, raw.Length);
            output[output.Length - 1] = 0;
            return output;
        }

        private static string Utf8PtrToString(IntPtr ptr, int byteLen)
        {
            if (ptr == IntPtr.Zero) { return null; }
            if (byteLen < 0)
            {
                byteLen = 0;
                while (Marshal.ReadByte(ptr, byteLen) != 0) { byteLen++; }
            }
            if (byteLen == 0) { return String.Empty; }
            byte[] raw = new byte[byteLen];
            Marshal.Copy(ptr, raw, 0, byteLen);
            return Encoding.UTF8.GetString(raw);
        }
    }
}
"@
        Add-Type -TypeDefinition $source -ErrorAction Stop
    }

    [DzTools.Sqlite.NativeClient]::ConfigureNativePath($dllDir)
}

function Get-DzSqliteRuntimePath {
    [CmdletBinding()]
    param()
    Join-Path $script:DzSqliteResourceDir $script:DzSqliteDllName
}

function Test-DzSqliteZipHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath
    )

    $hash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    if ($hash -ne $script:DzSqliteZipSha256) {
        throw "El hash SHA256 del runtime SQLite no coincide. Esperado: $script:DzSqliteZipSha256. Recibido: $hash"
    }
}

function Expand-DzSqliteRuntimeZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -notin @($script:DzSqliteDllName, "sqlite3.def")) { continue }
            $target = Join-Path $DestinationPath $entry.FullName
            $inStream = $null
            $outStream = $null
            try {
                $inStream = $entry.Open()
                $outStream = New-Object System.IO.FileStream($target, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $inStream.CopyTo($outStream)
            } finally {
                if ($outStream) { $outStream.Dispose() }
                if ($inStream) { $inStream.Dispose() }
            }
        }
    } finally {
        $zip.Dispose()
    }
}

function Save-DzSqliteRuntimeZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutFile,

        [System.Windows.Window]$ProgressWindow
    )

    $tmp = "$OutFile.download"
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    if (Get-Command Download-FileWithProgressWpfStream -ErrorAction SilentlyContinue) {
        Download-FileWithProgressWpfStream -Url $script:DzSqliteRawUrl -OutFile $tmp -Window $ProgressWindow | Out-Null
    } else {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
        Invoke-WebRequest -Uri $script:DzSqliteRawUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop
    }

    Test-DzSqliteZipHash -ZipPath $tmp
    Move-Item -LiteralPath $tmp -Destination $OutFile -Force
}

function Initialize-DzSqliteRuntime {
    [CmdletBinding()]
    param(
        [System.Windows.Window]$Owner,
        [System.Windows.Window]$ProgressWindow
    )

    if (-not [Environment]::Is64BitProcess) {
        throw "El runtime descargado es x64. Abre DzTools con PowerShell de 64 bits."
    }

    if (-not (Test-Path -LiteralPath $script:DzSqliteResourceDir)) {
        New-Item -ItemType Directory -Path $script:DzSqliteResourceDir -Force | Out-Null
    }

    $dllPath = Get-DzSqliteRuntimePath
    if (Test-Path -LiteralPath $dllPath -PathType Leaf) {
        if ($ProgressWindow) { Update-WpfProgressBar -Window $ProgressWindow -Percent 100 -Message "Runtime SQLite encontrado." }
        Import-DzSqliteNativeClient -DllPath $dllPath
        return $dllPath
    }

    $zipPath = Join-Path $script:DzSqliteResourceDir $script:DzSqliteZipName
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        if ($ProgressWindow) { Update-WpfProgressBar -Window $ProgressWindow -Percent 10 -Message "Descargando runtime SQLite..." }
        Save-DzSqliteRuntimeZip -OutFile $zipPath -ProgressWindow $ProgressWindow
    } else {
        if ($ProgressWindow) { Update-WpfProgressBar -Window $ProgressWindow -Percent 35 -Message "Validando runtime SQLite local..." }
        try {
            Test-DzSqliteZipHash -ZipPath $zipPath
        } catch {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            if ($ProgressWindow) { Update-WpfProgressBar -Window $ProgressWindow -Percent 10 -Message "Runtime local invalido. Descargando nuevamente..." }
            Save-DzSqliteRuntimeZip -OutFile $zipPath -ProgressWindow $ProgressWindow
        }
    }

    if ($ProgressWindow) { Update-WpfProgressBar -Window $ProgressWindow -Percent 80 -Message "Extrayendo sqlite3.dll..." }
    Expand-DzSqliteRuntimeZip -ZipPath $zipPath -DestinationPath $script:DzSqliteResourceDir

    if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
        throw "No se pudo extraer sqlite3.dll desde $zipPath"
    }

    if ($ProgressWindow) { Update-WpfProgressBar -Window $ProgressWindow -Percent 100 -Message "SQLite listo." }
    Import-DzSqliteNativeClient -DllPath $dllPath
    return $dllPath
}

function ConvertTo-DzSqliteDataTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QueryResult
    )

    $table = New-Object System.Data.DataTable
    foreach ($column in @($QueryResult.Columns)) {
        [void]$table.Columns.Add([string]$column, [object])
    }

    $rows = $QueryResult.Rows
    if ($null -eq $rows) {
        Write-Output -NoEnumerate $table
        return
    }

    for ($r = 0; $r -lt $rows.Length; $r++) {
        $sourceRow = $rows[$r]
        $row = $table.NewRow()
        for ($c = 0; $c -lt $table.Columns.Count; $c++) {
            $value = $sourceRow[$c]
            if ($null -eq $value) { $value = [DBNull]::Value }
            $row[$c] = $value
        }
        [void]$table.Rows.Add($row)
    }

    Write-Output -NoEnumerate $table
}

function Invoke-DzSqliteQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DbPath,

        [Parameter(Mandatory = $true)]
        [string]$Sql,

        [string[]]$Parameters = @(),

        [Parameter(Mandatory = $true)]
        [string]$DllPath
    )

    Import-DzSqliteNativeClient -DllPath $DllPath
    $result = [DzTools.Sqlite.NativeClient]::Query($DbPath, $Sql, $Parameters)
    ConvertTo-DzSqliteDataTable -QueryResult $result
}

function Invoke-DzSqliteNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DbPath,

        [Parameter(Mandatory = $true)]
        [string]$Sql,

        [string[]]$Parameters = @(),

        [Parameter(Mandatory = $true)]
        [string]$DllPath
    )

    Import-DzSqliteNativeClient -DllPath $DllPath
    [DzTools.Sqlite.NativeClient]::ExecuteNonQuery($DbPath, $Sql, $Parameters)
}

function Get-DzSqliteLogEventsSummary {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath
    )

    $dt = Invoke-DzSqliteQuery -DbPath $DbPath -DllPath $DllPath -Sql @"
SELECT
  COUNT(*) AS Total,
  MIN("Timestamp") AS OldestTimestamp,
  MAX("Timestamp") AS NewestTimestamp
FROM LogEvents;
"@

    if ($dt.Rows.Count -eq 0) {
        return [pscustomobject]@{ Total = 0; OldestTimestamp = $null; NewestTimestamp = $null }
    }

    [pscustomobject]@{
        Total           = [int64]$dt.Rows[0]["Total"]
        OldestTimestamp = [string]$dt.Rows[0]["OldestTimestamp"]
        NewestTimestamp = [string]$dt.Rows[0]["NewestTimestamp"]
    }
}

function Get-DzSqliteLogEvents {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath,
        [ValidateRange(1, 1000)][int]$Limit = 200
    )

    Invoke-DzSqliteQuery -DbPath $DbPath -DllPath $DllPath -Parameters @([string]$Limit) -Sql @"
SELECT
  Id,
  "Timestamp",
  Level,
  Type,
  Source,
  Module,
  Catalog,
  Message,
  Exception
FROM LogEvents
ORDER BY Id DESC
LIMIT ?;
"@
}

function Get-DzSqliteLogEventsDeleteCount {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath,
        [Parameter(Mandatory = $true)][datetime]$BeforeDate
    )

    $cutoff = $BeforeDate.ToString("yyyy-MM-dd")
    $dt = Invoke-DzSqliteQuery -DbPath $DbPath -DllPath $DllPath -Parameters @($cutoff) -Sql 'SELECT COUNT(*) AS Total FROM LogEvents WHERE substr("Timestamp", 1, 10) < ?;'
    if ($dt.Rows.Count -eq 0) { return 0 }
    [int64]$dt.Rows[0]["Total"]
}

function Remove-DzSqliteLogEventsBefore {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath,
        [Parameter(Mandatory = $true)][datetime]$BeforeDate,
        [switch]$Vacuum
    )

    $cutoff = $BeforeDate.ToString("yyyy-MM-dd")
    $deleted = Invoke-DzSqliteNonQuery -DbPath $DbPath -DllPath $DllPath -Parameters @($cutoff) -Sql 'DELETE FROM LogEvents WHERE substr("Timestamp", 1, 10) < ?;'
    if ($Vacuum) {
        Invoke-DzSqliteNonQuery -DbPath $DbPath -DllPath $DllPath -Sql "VACUUM;" | Out-Null
    }
    [int64]$deleted
}

function ConvertTo-DzSqliteIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Identificador SQLite vacio."
    }
    '"' + $Name.Replace('"', '""') + '"'
}

function ConvertTo-DzSqliteStringLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    "'" + $Value.Replace("'", "''") + "'"
}

function Test-DzSqliteSelectLikeQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sql
    )

    $trimmed = $Sql.Trim()
    return ($trimmed -match '(?is)^\s*(SELECT|WITH|PRAGMA|EXPLAIN)\b')
}

function Get-DzSqliteTables {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath
    )

    $dt = Invoke-DzSqliteQuery -DbPath $DbPath -DllPath $DllPath -Sql @"
SELECT name
FROM sqlite_master
WHERE type = 'table'
  AND name NOT LIKE 'sqlite_%'
ORDER BY name;
"@
    @($dt.Rows | ForEach-Object { [string]$_["name"] })
}

function Get-DzSqliteTableColumns {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath,
        [Parameter(Mandatory = $true)][string]$TableName
    )

    $safeTable = ConvertTo-DzSqliteIdentifier -Name $TableName
    $dt = Invoke-DzSqliteQuery -DbPath $DbPath -DllPath $DllPath -Sql "PRAGMA table_info($safeTable);"
    @($dt.Rows | ForEach-Object {
            [pscustomobject]@{
                Name       = [string]$_["name"]
                Type       = [string]$_["type"]
                NotNull    = [bool]([int]$_["notnull"])
                PrimaryKey = [bool]([int]$_["pk"])
            }
        })
}

function Get-DzSqliteTableRowCount {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath,
        [Parameter(Mandatory = $true)][string]$TableName
    )

    $safeTable = ConvertTo-DzSqliteIdentifier -Name $TableName
    $dt = Invoke-DzSqliteQuery -DbPath $DbPath -DllPath $DllPath -Sql "SELECT COUNT(*) AS Total FROM $safeTable;"
    if ($dt.Rows.Count -eq 0) { return 0 }
    [int64]$dt.Rows[0]["Total"]
}

function Get-DzSqliteTableData {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath,
        [Parameter(Mandatory = $true)][string]$TableName,
        [ValidateRange(1, 5000)][int]$Limit = 500
    )

    $safeTable = ConvertTo-DzSqliteIdentifier -Name $TableName
    Invoke-DzSqliteQuery -DbPath $DbPath -DllPath $DllPath -Parameters @([string]$Limit) -Sql "SELECT * FROM $safeTable LIMIT ?;"
}

function New-DzSqliteFieldWhereClause {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ColumnName,
        [Parameter(Mandatory = $true)][ValidateSet("BeforeDate", "Equals", "Contains", "IsNullOrEmpty")][string]$Mode,
        [string]$Value
    )

    $safeColumn = ConvertTo-DzSqliteIdentifier -Name $ColumnName
    switch ($Mode) {
        "BeforeDate" {
            if ([string]::IsNullOrWhiteSpace($Value)) { throw "Selecciona una fecha limite." }
            return @{ Sql = "substr($safeColumn, 1, 10) < ?"; Parameters = @($Value) }
        }
        "Equals" {
            if ([string]::IsNullOrWhiteSpace($Value)) { throw "Captura un valor." }
            return @{ Sql = "$safeColumn = ?"; Parameters = @($Value) }
        }
        "Contains" {
            if ([string]::IsNullOrWhiteSpace($Value)) { throw "Captura un valor." }
            return @{ Sql = "$safeColumn LIKE ?"; Parameters = @("%$Value%") }
        }
        "IsNullOrEmpty" {
            return @{ Sql = "($safeColumn IS NULL OR $safeColumn = '')"; Parameters = @() }
        }
    }
}

function Get-DzSqliteDeletePreview {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath,
        [Parameter(Mandatory = $true)][string]$TableName,
        [Parameter(Mandatory = $true)][string]$ColumnName,
        [Parameter(Mandatory = $true)][ValidateSet("BeforeDate", "Equals", "Contains", "IsNullOrEmpty")][string]$Mode,
        [string]$Value
    )

    $safeTable = ConvertTo-DzSqliteIdentifier -Name $TableName
    $where = New-DzSqliteFieldWhereClause -ColumnName $ColumnName -Mode $Mode -Value $Value
    $dt = Invoke-DzSqliteQuery -DbPath $DbPath -DllPath $DllPath -Parameters $where.Parameters -Sql "SELECT COUNT(*) AS Total FROM $safeTable WHERE $($where.Sql);"
    if ($dt.Rows.Count -eq 0) { return 0 }
    [int64]$dt.Rows[0]["Total"]
}

function Remove-DzSqliteRowsByField {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath,
        [Parameter(Mandatory = $true)][string]$TableName,
        [Parameter(Mandatory = $true)][string]$ColumnName,
        [Parameter(Mandatory = $true)][ValidateSet("BeforeDate", "Equals", "Contains", "IsNullOrEmpty")][string]$Mode,
        [string]$Value,
        [switch]$Vacuum
    )

    $safeTable = ConvertTo-DzSqliteIdentifier -Name $TableName
    $where = New-DzSqliteFieldWhereClause -ColumnName $ColumnName -Mode $Mode -Value $Value
    $deleted = Invoke-DzSqliteNonQuery -DbPath $DbPath -DllPath $DllPath -Parameters $where.Parameters -Sql "DELETE FROM $safeTable WHERE $($where.Sql);"
    if ($Vacuum) {
        Invoke-DzSqliteNonQuery -DbPath $DbPath -DllPath $DllPath -Sql "VACUUM;" | Out-Null
    }
    [int64]$deleted
}

function Get-DzSqliteBackupDirectory {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath
    )

    $dbDir = [System.IO.Path]::GetDirectoryName($DbPath)
    if ([string]::IsNullOrWhiteSpace($dbDir)) {
        $dbDir = "C:\NationalSoft"
    }
    Join-Path $dbDir "Respaldos"
}

function New-DzSqliteBackup {
    [CmdletBinding()]
    param(
        [string]$DbPath = $script:DzSqliteDefaultDbPath,
        [Parameter(Mandatory = $true)][string]$DllPath
    )

    if (-not (Test-Path -LiteralPath $DbPath -PathType Leaf)) {
        throw "No existe la base SQLite: $DbPath"
    }

    $backupDir = Get-DzSqliteBackupDirectory -DbPath $DbPath
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($DbPath)
    $ext = [System.IO.Path]::GetExtension($DbPath)
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".db" }
    $backupPath = Join-Path $backupDir ("{0}_{1}{2}" -f $name, (Get-Date -Format "yyyyMMdd_HHmmss"), $ext)

    $literal = ConvertTo-DzSqliteStringLiteral -Value $backupPath
    try {
        Invoke-DzSqliteNonQuery -DbPath $DbPath -DllPath $DllPath -Sql "VACUUM INTO $literal;" | Out-Null
    } catch {
        Copy-Item -LiteralPath $DbPath -Destination $backupPath -Force -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "No se pudo crear el respaldo: $backupPath"
    }
    return $backupPath
}

function Show-DzSqliteCleanerDialog {
    [CmdletBinding()]
    param(
        [System.Windows.Window]$Owner
    )

    $logDebug = ${function:Write-DzSqliteDebug}
    $logError = ${function:Write-DzSqliteError}
    $isSelectLikeQuery = ${function:Test-DzSqliteSelectLikeQuery}
    $progress = $null
    $dllPath = $null
    & $logDebug -Message "Click recibido. Iniciando Editor SQLite." -Color ([System.ConsoleColor]::Cyan)
    try {
        if (Get-Command Show-WpfProgressBar -ErrorAction SilentlyContinue) {
            $progress = Show-WpfProgressBar -Title "Preparando SQLite" -Message "Buscando runtime local..." -Owner $Owner -BlockOwner -ProgrammaticCloseOnly -HidePercent
        }
        $dllPath = Initialize-DzSqliteRuntime -Owner $Owner -ProgressWindow $progress
        & $logDebug -Message "Runtime listo: $dllPath" -Color ([System.ConsoleColor]::Green)
    } catch {
        & $logError -Context "Preparando runtime SQLite" -ErrorRecord $_
        if ($progress) { Close-WpfProgressBar -Window $progress }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) {
            Show-WpfMessageBox -Message "No se pudo preparar SQLite.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $Owner | Out-Null
        } else {
            Write-Host "No se pudo preparar SQLite: $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    } finally {
        if ($progress) { Close-WpfProgressBar -Window $progress }
    }

    $dbPath = $script:DzSqliteDefaultDbPath
    & $logDebug -Message "Base objetivo: $dbPath" -Color ([System.ConsoleColor]::Cyan)
    if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
        & $logDebug -Message "Base no encontrada: $dbPath" -Color ([System.ConsoleColor]::Yellow)
        Show-WpfMessageBox -Message "No se encontro la base SQLite:`n$dbPath" -Title "SQLite" -Buttons OK -Icon Warning -Owner $Owner | Out-Null
        return
    }

    $theme = Get-DzUiTheme
    $safeDbPath = [Security.SecurityElement]::Escape($dbPath)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Editor SQLite"
        Width="1120" Height="760"
        MinWidth="980" MinHeight="640"
        WindowStartupLocation="CenterOwner"
        WindowStyle="None"
        ResizeMode="CanResize"
        Background="{DynamicResource FormBg}"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type TextBlock}">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="{x:Type TextBox}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,4"/>
    </Style>
    <Style TargetType="{x:Type ComboBox}">
      <Setter Property="Height" Value="30"/>
    </Style>
    <Style TargetType="{x:Type DatePicker}">
      <Setter Property="Height" Value="30"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="{x:Type Button}">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentOrange}"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Button}">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentOrangeHover}"/>
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
    <Style x:Key="SecondaryButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style x:Key="DangerButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource AccentRed}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource SecondaryButtonStyle}">
      <Setter Property="Width" Value="30"/>
      <Setter Property="MinWidth" Value="30"/>
      <Setter Property="Height" Value="28"/>
      <Setter Property="Padding" Value="0"/>
    </Style>
    <Style TargetType="{x:Type DataGrid}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="AutoGenerateColumns" Value="True"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="CanUserDeleteRows" Value="False"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="RowHeight" Value="24"/>
      <Setter Property="ColumnHeaderHeight" Value="28"/>
    </Style>
  </Window.Resources>

  <Border BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" Background="{DynamicResource FormBg}">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="54"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Name="HeaderBar" Background="{DynamicResource FormBg}" Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0" Width="6" CornerRadius="3" Background="{DynamicResource AccentOrange}" Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1">
            <TextBlock Text="Editor SQLite" FontWeight="SemiBold" FontSize="13"/>
            <TextBlock Name="lblDbPath" Text="$safeDbPath" Foreground="{DynamicResource AccentMuted}" FontSize="10" Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2" Name="btnBackup" Content="Respaldar" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,8,0"/>
          <Button Grid.Column="3" Name="btnClose" Content="X" Style="{StaticResource IconButtonStyle}"/>
        </Grid>
      </Border>

      <Border Grid.Row="1" Margin="12,0,12,10" Padding="12" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.2*"/>
            <ColumnDefinition Width="8"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="8"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="8"/>
            <ColumnDefinition Width="2*"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock Text="Tabla" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <ComboBox Name="cmbTables"/>
          </StackPanel>
          <StackPanel Grid.Column="2">
            <TextBlock Text="Limite" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <TextBox Name="txtLimit" Text="500" Width="80" Height="30"/>
          </StackPanel>
          <StackPanel Grid.Column="4" VerticalAlignment="Bottom" Orientation="Horizontal">
            <Button Name="btnRefreshTable" Content="Actualizar" Style="{StaticResource SecondaryButtonStyle}" Margin="0,0,8,0"/>
            <Button Name="btnOpenBackupFolder" Content="Backups" Style="{StaticResource SecondaryButtonStyle}"/>
          </StackPanel>
          <StackPanel Grid.Column="6">
            <TextBlock Text="Estado" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <TextBlock Name="lblBackupStatus" Text="Sin respaldo. Solo navegacion habilitada." TextWrapping="Wrap" Foreground="{DynamicResource AccentMuted}"/>
          </StackPanel>
        </Grid>
      </Border>

      <TabControl Grid.Row="2" Name="tabEditor" Margin="12,0,12,10" Background="{DynamicResource ControlBg}">
        <TabItem Header="Navegar">
          <Grid Margin="8">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Name="lblTableSummary" Grid.Row="0" Text="Selecciona una tabla." Foreground="{DynamicResource AccentMuted}" Margin="0,0,0,8"/>
            <DataGrid Name="dgBrowse" Grid.Row="1"/>
          </Grid>
        </TabItem>

        <TabItem Header="Limpieza">
          <Grid Margin="8">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Padding="10" Margin="0,0,0,8" Background="{DynamicResource FormBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="1.1*"/>
                  <ColumnDefinition Width="8"/>
                  <ColumnDefinition Width="1.1*"/>
                  <ColumnDefinition Width="8"/>
                  <ColumnDefinition Width="1.1*"/>
                  <ColumnDefinition Width="8"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                  <TextBlock Text="Campo" FontWeight="SemiBold" Margin="0,0,0,4"/>
                  <ComboBox Name="cmbCleanColumn"/>
                </StackPanel>
                <StackPanel Grid.Column="2">
                  <TextBlock Text="Condicion" FontWeight="SemiBold" Margin="0,0,0,4"/>
                  <ComboBox Name="cmbCleanMode"/>
                </StackPanel>
                <StackPanel Grid.Column="4">
                  <TextBlock Text="Valor" FontWeight="SemiBold" Margin="0,0,0,4"/>
                  <Grid>
                    <DatePicker Name="dpCleanDate"/>
                    <TextBox Name="txtCleanValue" Visibility="Collapsed"/>
                  </Grid>
                </StackPanel>
                <StackPanel Grid.Column="6" Orientation="Horizontal" VerticalAlignment="Bottom">
                  <Button Name="btnPreviewDelete" Content="Previsualizar" Style="{StaticResource SecondaryButtonStyle}" Margin="0,0,8,0" IsEnabled="False"/>
                  <Button Name="btnCleanRows" Content="Limpiar" Style="{StaticResource DangerButtonStyle}" IsEnabled="False"/>
                </StackPanel>
              </Grid>
            </Border>
            <TextBox Grid.Row="1" Name="txtCleanPreview" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"/>
          </Grid>
        </TabItem>

        <TabItem Header="Query">
          <Grid Margin="8">
            <Grid.RowDefinitions>
              <RowDefinition Height="150"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="90"/>
            </Grid.RowDefinitions>
            <TextBox Name="txtSql" Grid.Row="0" IsEnabled="False" AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="{DynamicResource CodeFontFamily}" FontSize="{DynamicResource CodeFontSize}"/>
            <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,8">
              <Button Name="btnExecuteSql" Content="Ejecutar query" Style="{StaticResource PrimaryButtonStyle}" IsEnabled="False" Margin="0,0,8,0"/>
              <Button Name="btnClearSql" Content="Limpiar query" Style="{StaticResource SecondaryButtonStyle}" IsEnabled="False"/>
            </StackPanel>
            <DataGrid Name="dgQueryResults" Grid.Row="2"/>
            <TextBox Name="txtQueryMessages" Grid.Row="3" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontFamily="{DynamicResource CodeFontFamily}" FontSize="11" Margin="0,8,0,0"/>
          </Grid>
        </TabItem>
      </TabControl>

      <Border Grid.Row="3" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1,1,0,0" Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Name="lblStatus" Text="Listo." VerticalAlignment="Center" Foreground="{DynamicResource AccentMuted}"/>
          <Button Grid.Column="1" Name="btnCloseFooter" Content="Cerrar" Style="{StaticResource SecondaryButtonStyle}" IsCancel="True"/>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
"@

    $ui = New-WpfWindow -Xaml $xaml -PassThru
    $w = $ui.Window
    $c = $ui.Controls
    Set-DzWpfThemeResources -Window $w -Theme $theme
    if ($Owner) { $w.Owner = $Owner }

    if ($c["HeaderBar"]) {
        $c["HeaderBar"].Add_MouseLeftButtonDown({
                if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                    try { $w.DragMove() } catch {}
                }
            }.GetNewClosure())
    }

    $state = @{
        BackupReady = $false
        BackupPath  = $null
        TableName   = $null
    }

    $cmbTables = $c["cmbTables"]
    $txtLimit = $c["txtLimit"]
    $lblTableSummary = $c["lblTableSummary"]
    $lblBackupStatus = $c["lblBackupStatus"]
    $lblStatus = $c["lblStatus"]
    $dgBrowse = $c["dgBrowse"]
    $cmbCleanColumn = $c["cmbCleanColumn"]
    $cmbCleanMode = $c["cmbCleanMode"]
    $dpCleanDate = $c["dpCleanDate"]
    $txtCleanValue = $c["txtCleanValue"]
    $txtCleanPreview = $c["txtCleanPreview"]
    $txtSql = $c["txtSql"]
    $btnExecuteSql = $c["btnExecuteSql"]
    $btnClearSql = $c["btnClearSql"]
    $btnPreviewDelete = $c["btnPreviewDelete"]
    $btnCleanRows = $c["btnCleanRows"]
    $dgQueryResults = $c["dgQueryResults"]
    $txtQueryMessages = $c["txtQueryMessages"]

    $null = $cmbCleanMode.Items.Add("Anterior a fecha")
    $null = $cmbCleanMode.Items.Add("Igual a")
    $null = $cmbCleanMode.Items.Add("Contiene")
    $null = $cmbCleanMode.Items.Add("Nulo o vacio")
    $cmbCleanMode.SelectedIndex = 0
    $dpCleanDate.SelectedDate = [datetime]::Today
    $txtSql.Text = "SELECT * FROM LogEvents LIMIT 100;"

    $setStatus = {
        param([string]$Message, [string]$Kind = "Info")
        if (-not $lblStatus) { return }
        $lblStatus.Text = $Message
        try {
            switch ($Kind) {
                "Ok" { $lblStatus.Foreground = $w.FindResource("AccentSecondary") }
                "Warn" { $lblStatus.Foreground = $w.FindResource("AccentOrange") }
                "Error" { $lblStatus.Foreground = $w.FindResource("AccentRed") }
                default { $lblStatus.Foreground = $w.FindResource("AccentMuted") }
            }
        } catch {}
    }.GetNewClosure()

    $setBackupControls = {
        param([bool]$Enabled)
        foreach ($control in @($txtSql, $btnExecuteSql, $btnClearSql, $btnPreviewDelete, $btnCleanRows, $cmbCleanColumn, $cmbCleanMode, $dpCleanDate, $txtCleanValue)) {
            try { $control.IsEnabled = $Enabled } catch {}
        }
        try { if ($Enabled -and $updateCleanModeUi) { & $updateCleanModeUi } } catch { & $logError -Context "Actualizando controles de respaldo" -ErrorRecord $_ }
        if ($Enabled) {
            $lblBackupStatus.Text = "Respaldo activo: $($state.BackupPath)"
            try { $lblBackupStatus.Foreground = $w.FindResource("AccentSecondary") } catch {}
        } else {
            $lblBackupStatus.Text = "Sin respaldo. Solo navegacion habilitada."
            try { $lblBackupStatus.Foreground = $w.FindResource("AccentMuted") } catch {}
        }
    }.GetNewClosure()

    $requireBackup = {
        if ($state.BackupReady) { return $true }
        Show-WpfMessageBox -Message "Primero crea un respaldo de la base SQLite." -Title "Respaldo requerido" -Buttons OK -Icon Warning -Owner $w | Out-Null
        return $false
    }.GetNewClosure()

    $getLimit = {
        $limit = 500
        if ([int]::TryParse([string]$txtLimit.Text, [ref]$limit) -and $limit -gt 0) {
            return [int]([Math]::Min($limit, 5000))
        }
        return [int]500
    }.GetNewClosure()

    $getCleanMode = {
        switch ([string]$cmbCleanMode.SelectedItem) {
            "Anterior a fecha" { return "BeforeDate" }
            "Igual a" { return "Equals" }
            "Contiene" { return "Contains" }
            "Nulo o vacio" { return "IsNullOrEmpty" }
            default { return "BeforeDate" }
        }
    }.GetNewClosure()

    $getCleanValue = {
        $mode = & $getCleanMode
        if ($mode -eq "BeforeDate") {
            if (-not $dpCleanDate.SelectedDate) { throw "Selecciona una fecha limite." }
            return ([datetime]$dpCleanDate.SelectedDate).ToString("yyyy-MM-dd")
        }
        if ($mode -eq "IsNullOrEmpty") { return "" }
        return [string]$txtCleanValue.Text
    }.GetNewClosure()

    $loadColumns = {
        param([string]$TableName)
        & $logDebug -Message "Cargando columnas. Tabla='$TableName'" -Color ([System.ConsoleColor]::DarkCyan)
        $cmbCleanColumn.Items.Clear()
        if ([string]::IsNullOrWhiteSpace($TableName)) { return }
        $columns = Get-DzSqliteTableColumns -DbPath $dbPath -DllPath $dllPath -TableName $TableName
        foreach ($column in $columns) {
            $label = if ([string]::IsNullOrWhiteSpace($column.Type)) { $column.Name } else { "$($column.Name) ($($column.Type))" }
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $label
            $item.Tag = $column.Name
            $null = $cmbCleanColumn.Items.Add($item)
        }
        if ($cmbCleanColumn.Items.Count -gt 0) {
            $timestampItem = $cmbCleanColumn.Items | Where-Object { $_.Tag -match '^(Timestamp|Fecha|Date|CreatedAt|UpdatedAt)$' } | Select-Object -First 1
            if ($timestampItem) { $cmbCleanColumn.SelectedItem = $timestampItem } else { $cmbCleanColumn.SelectedIndex = 0 }
        }
        & $logDebug -Message "Columnas cargadas para '$TableName': $($columns.Count)" -Color ([System.ConsoleColor]::DarkCyan)
    }.GetNewClosure()

    $loadTable = {
        $tableName = [string]$cmbTables.SelectedItem
        if ([string]::IsNullOrWhiteSpace($tableName)) { return }
        $state.TableName = $tableName
        try {
            $limit = [int](& $getLimit)
            & $logDebug -Message "Leyendo tabla '$tableName'. Limite=$limit" -Color ([System.ConsoleColor]::Cyan)
            $setStatus.Invoke("Leyendo tabla $tableName...")
            $total = Get-DzSqliteTableRowCount -DbPath $dbPath -DllPath $dllPath -TableName $tableName
            $dt = Get-DzSqliteTableData -DbPath $dbPath -DllPath $dllPath -TableName $tableName -Limit $limit
            $dgBrowse.ItemsSource = $dt.DefaultView
            $lblTableSummary.Text = "Tabla: $tableName | Filas: $total | Mostrando: $($dt.Rows.Count)"
            & $loadColumns $tableName
            $setStatus.Invoke("Tabla cargada: $tableName", "Ok")
            & $logDebug -Message "Tabla '$tableName' cargada. Total=$total Mostrando=$($dt.Rows.Count) Columnas=$($dt.Columns.Count)" -Color ([System.ConsoleColor]::Green)
        } catch {
            & $logError -Context "Leyendo tabla '$tableName'" -ErrorRecord $_
            $setStatus.Invoke("No se pudo leer la tabla: $($_.Exception.Message)", "Error")
            Show-WpfMessageBox -Message "No se pudo leer la tabla.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
        }
    }.GetNewClosure()

    $loadTables = {
        try {
            & $logDebug -Message "Listando tablas SQLite..." -Color ([System.ConsoleColor]::Cyan)
            $cmbTables.Items.Clear()
            $tables = Get-DzSqliteTables -DbPath $dbPath -DllPath $dllPath
            & $logDebug -Message "Tablas encontradas: $($tables.Count) [$($tables -join ', ')]" -Color ([System.ConsoleColor]::Green)
            foreach ($table in $tables) { $null = $cmbTables.Items.Add($table) }
            if ($cmbTables.Items.Count -eq 0) {
                $setStatus.Invoke("No se encontraron tablas.", "Warn")
                return
            }
            if ($tables -contains "LogEvents") { $cmbTables.SelectedItem = "LogEvents" } else { $cmbTables.SelectedIndex = 0 }
            & $loadTable
        } catch {
            & $logError -Context "Listando tablas SQLite" -ErrorRecord $_
            $setStatus.Invoke("No se pudieron listar tablas: $($_.Exception.Message)", "Error")
            Show-WpfMessageBox -Message "No se pudieron listar tablas.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
        }
    }.GetNewClosure()

    $updateCleanModeUi = {
        $mode = & $getCleanMode
        if ($mode -eq "BeforeDate") {
            $dpCleanDate.Visibility = "Visible"
            $txtCleanValue.Visibility = "Collapsed"
        } elseif ($mode -eq "IsNullOrEmpty") {
            $dpCleanDate.Visibility = "Collapsed"
            $txtCleanValue.Visibility = "Visible"
            $txtCleanValue.Text = ""
        } else {
            $dpCleanDate.Visibility = "Collapsed"
            $txtCleanValue.Visibility = "Visible"
        }
        $dpCleanDate.IsEnabled = [bool]$state.BackupReady
        if ($mode -eq "IsNullOrEmpty") {
            $txtCleanValue.IsEnabled = $false
        } else {
            $txtCleanValue.IsEnabled = [bool]$state.BackupReady
        }
    }.GetNewClosure()

    $previewDelete = {
        if (-not (& $requireBackup)) { return }
        $tableName = [string]$cmbTables.SelectedItem
        $columnItem = $cmbCleanColumn.SelectedItem
        if (-not $columnItem) {
            Show-WpfMessageBox -Message "Selecciona un campo." -Title "SQLite" -Buttons OK -Icon Warning -Owner $w | Out-Null
            return
        }
        try {
            $mode = & $getCleanMode
            $value = & $getCleanValue
            & $logDebug -Message "Previsualizando limpieza. Tabla='$tableName' Campo='$($columnItem.Tag)' Modo='$mode' Valor='$value'" -Color ([System.ConsoleColor]::Cyan)
            $count = Get-DzSqliteDeletePreview -DbPath $dbPath -DllPath $dllPath -TableName $tableName -ColumnName ([string]$columnItem.Tag) -Mode $mode -Value $value
            $txtCleanPreview.Text = "Tabla: $tableName`r`nCampo: $($columnItem.Tag)`r`nCondicion: $($cmbCleanMode.SelectedItem)`r`nCoincidencias: $count"
            $setStatus.Invoke("Previsualizacion lista. Coincidencias: $count", "Warn")
            & $logDebug -Message "Previsualizacion lista. Coincidencias=$count" -Color ([System.ConsoleColor]::Yellow)
        } catch {
            & $logError -Context "Previsualizando limpieza" -ErrorRecord $_
            $setStatus.Invoke("No se pudo previsualizar: $($_.Exception.Message)", "Error")
            Show-WpfMessageBox -Message "No se pudo previsualizar.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
        }
    }.GetNewClosure()

    $cleanRows = {
        if (-not (& $requireBackup)) { return }
        $tableName = [string]$cmbTables.SelectedItem
        $columnItem = $cmbCleanColumn.SelectedItem
        if (-not $columnItem) {
            Show-WpfMessageBox -Message "Selecciona un campo." -Title "SQLite" -Buttons OK -Icon Warning -Owner $w | Out-Null
            return
        }
        try {
            $mode = & $getCleanMode
            $value = & $getCleanValue
            & $logDebug -Message "Calculando limpieza. Tabla='$tableName' Campo='$($columnItem.Tag)' Modo='$mode' Valor='$value' Backup='$($state.BackupPath)'" -Color ([System.ConsoleColor]::Cyan)
            $count = Get-DzSqliteDeletePreview -DbPath $dbPath -DllPath $dllPath -TableName $tableName -ColumnName ([string]$columnItem.Tag) -Mode $mode -Value $value
            if ($count -le 0) {
                $setStatus.Invoke("No hay registros para limpiar.", "Ok")
                & $logDebug -Message "Limpieza cancelada: 0 coincidencias." -Color ([System.ConsoleColor]::Yellow)
                return
            }
            $message = "Se borraran $count registro(s).`nTabla: $tableName`nCampo: $($columnItem.Tag)`nCondicion: $($cmbCleanMode.SelectedItem)`n`nRespaldo:`n$($state.BackupPath)`n`nDeseas continuar?"
            $confirm = Show-WpfMessageBox -Message $message -Title "Confirmar limpieza SQLite" -Buttons YesNo -Icon Warning -Owner $w
            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

            $opProgress = $null
            try {
                $opProgress = Show-WpfProgressBar -Title "Limpiando SQLite" -Message "Eliminando registros..." -Owner $w -BlockOwner -ProgrammaticCloseOnly -HidePercent
                & $logDebug -Message "Ejecutando DELETE. Coincidencias esperadas=$count" -Color ([System.ConsoleColor]::Yellow)
                $deleted = Remove-DzSqliteRowsByField -DbPath $dbPath -DllPath $dllPath -TableName $tableName -ColumnName ([string]$columnItem.Tag) -Mode $mode -Value $value -Vacuum
                if ($opProgress) { Update-WpfProgressBar -Window $opProgress -Percent 100 -Message "Limpieza completada." }
            } finally {
                if ($opProgress) { Close-WpfProgressBar -Window $opProgress }
            }

            $txtCleanPreview.Text = "Registros eliminados: $deleted`r`nRespaldo: $($state.BackupPath)"
            & $loadTable
            $setStatus.Invoke("Limpieza completada. Registros eliminados: $deleted", "Ok")
            & $logDebug -Message "Limpieza completada. Eliminados=$deleted" -Color ([System.ConsoleColor]::Green)
        } catch {
            & $logError -Context "Limpiando registros SQLite" -ErrorRecord $_
            $setStatus.Invoke("Error durante la limpieza: $($_.Exception.Message)", "Error")
            Show-WpfMessageBox -Message "No se pudo limpiar.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
        }
    }.GetNewClosure()

    $backupDatabase = {
        $opProgress = $null
        try {
            & $logDebug -Message "Creando respaldo de '$dbPath'..." -Color ([System.ConsoleColor]::Cyan)
            $opProgress = Show-WpfProgressBar -Title "Respaldando SQLite" -Message "Creando respaldo..." -Owner $w -BlockOwner -ProgrammaticCloseOnly -HidePercent
            $backupPath = New-DzSqliteBackup -DbPath $dbPath -DllPath $dllPath
            if ($opProgress) { Update-WpfProgressBar -Window $opProgress -Percent 100 -Message "Respaldo creado." }
            $state.BackupReady = $true
            $state.BackupPath = $backupPath
            & $setBackupControls $true
            $setStatus.Invoke("Respaldo creado: $backupPath", "Ok")
            & $logDebug -Message "Respaldo creado: $backupPath" -Color ([System.ConsoleColor]::Green)
            Show-WpfMessageBox -Message "Respaldo creado:`n$backupPath" -Title "SQLite" -Buttons OK -Icon Information -Owner $w | Out-Null
        } catch {
            & $logError -Context "Creando respaldo SQLite" -ErrorRecord $_
            $setStatus.Invoke("No se pudo crear respaldo: $($_.Exception.Message)", "Error")
            Show-WpfMessageBox -Message "No se pudo crear el respaldo.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
        } finally {
            if ($opProgress) { Close-WpfProgressBar -Window $opProgress }
        }
    }.GetNewClosure()

    $executeSql = {
        if (-not (& $requireBackup)) { return }
        $sql = [string]$txtSql.Text
        if ([string]::IsNullOrWhiteSpace($sql)) {
            Show-WpfMessageBox -Message "Escribe un query." -Title "SQLite" -Buttons OK -Icon Warning -Owner $w | Out-Null
            return
        }
        try {
            & $logDebug -Message "Ejecutando query. SQL=`n$sql" -Color ([System.ConsoleColor]::Cyan)
            if (& $isSelectLikeQuery -Sql $sql) {
                $dt = Invoke-DzSqliteQuery -DbPath $dbPath -DllPath $dllPath -Sql $sql
                $dgQueryResults.ItemsSource = $dt.DefaultView
                $txtQueryMessages.Text = "Filas devueltas: $($dt.Rows.Count)"
                $setStatus.Invoke("Query ejecutado.", "Ok")
                & $logDebug -Message "Query SELECT finalizado. Filas=$($dt.Rows.Count) Columnas=$($dt.Columns.Count)" -Color ([System.ConsoleColor]::Green)
            } else {
                $confirm = Show-WpfMessageBox -Message "Este query puede modificar la base.`n`nRespaldo:`n$($state.BackupPath)`n`nDeseas ejecutarlo?" -Title "Confirmar query" -Buttons YesNo -Icon Warning -Owner $w
                if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
                $affected = Invoke-DzSqliteNonQuery -DbPath $dbPath -DllPath $dllPath -Sql $sql
                $dgQueryResults.ItemsSource = $null
                $txtQueryMessages.Text = "Query ejecutado. Cambios reportados por SQLite: $affected"
                & $loadTable
                $setStatus.Invoke("Query de escritura ejecutado.", "Ok")
                & $logDebug -Message "Query escritura finalizado. Cambios=$affected" -Color ([System.ConsoleColor]::Green)
            }
        } catch {
            & $logError -Context "Ejecutando query SQLite" -ErrorRecord $_
            $txtQueryMessages.Text = $_.Exception.Message
            $setStatus.Invoke("Error en query: $($_.Exception.Message)", "Error")
        }
    }.GetNewClosure()

    $c["btnClose"].Add_Click({ $w.Close() })
    $c["btnCloseFooter"].Add_Click({ $w.Close() })
    $c["btnBackup"].Add_Click({ & $backupDatabase })
    $c["btnRefreshTable"].Add_Click({ & $loadTable })
    $c["btnPreviewDelete"].Add_Click({ & $previewDelete })
    $c["btnCleanRows"].Add_Click({ & $cleanRows })
    $c["btnExecuteSql"].Add_Click({ & $executeSql })
    $c["btnClearSql"].Add_Click({
            $txtSql.Clear()
            $dgQueryResults.ItemsSource = $null
            $txtQueryMessages.Clear()
        })
    $c["btnOpenBackupFolder"].Add_Click({
            $backupDir = Get-DzSqliteBackupDirectory -DbPath $dbPath
            if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            Start-Process -FilePath "explorer.exe" -ArgumentList "`"$backupDir`""
        })
    $cmbTables.Add_SelectionChanged({
            if ($cmbTables.SelectedItem) { & $loadTable }
        })
    $cmbCleanMode.Add_SelectionChanged({ & $updateCleanModeUi })

    $w.Add_Loaded({
            & $logDebug -Message "Ventana Editor SQLite cargada." -Color ([System.ConsoleColor]::Cyan)
            & $setBackupControls $false
            & $updateCleanModeUi
            & $loadTables
        }.GetNewClosure())

    $null = $w.ShowDialog()
}

function Show-DzSqliteLogEventsCleanerDialog {
    [CmdletBinding()]
    param(
        [System.Windows.Window]$Owner
    )

    $progress = $null
    $dllPath = $null
    try {
        if (Get-Command Show-WpfProgressBar -ErrorAction SilentlyContinue) {
            $progress = Show-WpfProgressBar -Title "Preparando SQLite" -Message "Buscando runtime local..." -Owner $Owner -BlockOwner -ProgrammaticCloseOnly -HidePercent
        }
        $dllPath = Initialize-DzSqliteRuntime -Owner $Owner -ProgressWindow $progress
    } catch {
        if ($progress) { Close-WpfProgressBar -Window $progress }
        if (Get-Command Show-WpfMessageBox -ErrorAction SilentlyContinue) {
            Show-WpfMessageBox -Message "No se pudo preparar SQLite.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $Owner | Out-Null
        } else {
            Write-Host "No se pudo preparar SQLite: $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    } finally {
        if ($progress) { Close-WpfProgressBar -Window $progress }
    }

    $dbPath = $script:DzSqliteDefaultDbPath
    if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
        Show-WpfMessageBox -Message "No se encontro la base SQLite:`n$dbPath" -Title "SQLite" -Buttons OK -Icon Warning -Owner $Owner | Out-Null
        return
    }

    $theme = Get-DzUiTheme
    $safeDbPath = [Security.SecurityElement]::Escape($dbPath)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Limpiar SQLite"
        Width="980" Height="650"
        MinWidth="900" MinHeight="560"
        WindowStartupLocation="CenterOwner"
        WindowStyle="None"
        ResizeMode="CanResize"
        Background="{DynamicResource FormBg}"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type TextBlock}">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="{x:Type TextBox}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,4"/>
    </Style>
    <Style TargetType="{x:Type DatePicker}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style TargetType="{x:Type ComboBox}">
      <Setter Property="Height" Value="30"/>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="{x:Type Button}">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentOrange}"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Button}">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentOrangeHover}"/>
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
    <Style x:Key="SecondaryButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style x:Key="DangerButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource AccentRed}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="{x:Type Button}" BasedOn="{StaticResource SecondaryButtonStyle}">
      <Setter Property="Width" Value="30"/>
      <Setter Property="MinWidth" Value="30"/>
      <Setter Property="Height" Value="28"/>
      <Setter Property="Padding" Value="0"/>
    </Style>
    <Style TargetType="{x:Type DataGrid}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="AutoGenerateColumns" Value="True"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="CanUserDeleteRows" Value="False"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="RowHeight" Value="24"/>
      <Setter Property="ColumnHeaderHeight" Value="28"/>
    </Style>
  </Window.Resources>

  <Border BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" Background="{DynamicResource FormBg}">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Name="HeaderBar" Background="{DynamicResource FormBg}" Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0" Width="6" CornerRadius="3" Background="{DynamicResource AccentOrange}" Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1">
            <TextBlock Text="Limpiar SQLite" FontWeight="SemiBold" FontSize="13"/>
            <TextBlock Name="lblRuntime" Text="$safeDbPath" Foreground="{DynamicResource AccentMuted}" FontSize="10" Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2" Name="btnClose" Content="X" Style="{StaticResource IconButtonStyle}"/>
        </Grid>
      </Border>

      <Border Grid.Row="1" Margin="12,0,12,10" Padding="12" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.2*"/>
            <ColumnDefinition Width="10"/>
            <ColumnDefinition Width="1.2*"/>
            <ColumnDefinition Width="10"/>
            <ColumnDefinition Width="1.2*"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock Text="Tabla" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <ComboBox Name="cmbTables" IsReadOnly="True"/>
          </StackPanel>
          <StackPanel Grid.Column="2">
            <TextBlock Text="Resumen" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <TextBlock Name="lblSummary" Text="Sin cargar" TextWrapping="Wrap" Foreground="{DynamicResource AccentMuted}"/>
          </StackPanel>
          <StackPanel Grid.Column="4">
            <TextBlock Text="Fecha limite" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <DatePicker Name="dpCutoffDate" Height="30"/>
          </StackPanel>
        </Grid>
      </Border>

      <Grid Grid.Row="2" Margin="12,0,12,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
          <Button Name="btnViewLogEvents" Content="Ver LogEvents" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,8,0"/>
          <Button Name="btnPreviewDelete" Content="Previsualizar limpieza" Style="{StaticResource SecondaryButtonStyle}" Margin="0,0,8,0"/>
          <Button Name="btnClean" Content="Limpiar" Style="{StaticResource DangerButtonStyle}" Margin="0,0,8,0"/>
          <CheckBox Name="chkVacuum" Content="Compactar despues de borrar" IsChecked="True" VerticalAlignment="Center" Foreground="{DynamicResource FormFg}" Margin="4,0,0,0"/>
        </StackPanel>
        <DataGrid Name="dgLogEvents" Grid.Row="1"/>
      </Grid>

      <Border Grid.Row="3" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1,1,0,0" Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Name="lblStatus" Text="Listo." VerticalAlignment="Center" Foreground="{DynamicResource AccentMuted}"/>
          <Button Grid.Column="1" Name="btnCloseFooter" Content="Cerrar" Style="{StaticResource SecondaryButtonStyle}" IsCancel="True"/>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
"@

    $ui = New-WpfWindow -Xaml $xaml -PassThru
    $w = $ui.Window
    $c = $ui.Controls
    Set-DzWpfThemeResources -Window $w -Theme $theme
    if ($Owner) { $w.Owner = $Owner }

    if ($c["HeaderBar"]) {
        $c["HeaderBar"].Add_MouseLeftButtonDown({
                if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                    try { $w.DragMove() } catch {}
                }
            }.GetNewClosure())
    }

    $cmbTables = $c["cmbTables"]
    $dpCutoffDate = $c["dpCutoffDate"]
    $lblSummary = $c["lblSummary"]
    $lblStatus = $c["lblStatus"]
    $dgLogEvents = $c["dgLogEvents"]
    $chkVacuum = $c["chkVacuum"]
    $buttons = @($c["btnViewLogEvents"], $c["btnPreviewDelete"], $c["btnClean"], $c["btnClose"], $c["btnCloseFooter"]) | Where-Object { $_ }

    $null = $cmbTables.Items.Add("LogEvents")
    $cmbTables.SelectedIndex = 0
    $dpCutoffDate.SelectedDate = [datetime]::Today

    $setStatus = {
        param([string]$Message, [string]$Kind = "Info")
        if (-not $lblStatus) { return }
        $lblStatus.Text = $Message
        try {
            switch ($Kind) {
                "Ok" { $lblStatus.Foreground = $w.FindResource("AccentSecondary") }
                "Warn" { $lblStatus.Foreground = $w.FindResource("AccentOrange") }
                "Error" { $lblStatus.Foreground = $w.FindResource("AccentRed") }
                default { $lblStatus.Foreground = $w.FindResource("AccentMuted") }
            }
        } catch {}
    }.GetNewClosure()

    $setBusy = {
        param([bool]$IsBusy)
        foreach ($button in $buttons) {
            try { $button.IsEnabled = -not $IsBusy } catch {}
        }
    }.GetNewClosure()

    $refreshSummary = {
        try {
            $summary = Get-DzSqliteLogEventsSummary -DbPath $dbPath -DllPath $dllPath
            $old = if ([string]::IsNullOrWhiteSpace($summary.OldestTimestamp)) { "-" } else { $summary.OldestTimestamp }
            $new = if ([string]::IsNullOrWhiteSpace($summary.NewestTimestamp)) { "-" } else { $summary.NewestTimestamp }
            $lblSummary.Text = "Filas: $($summary.Total)`nDesde: $old`nHasta: $new"
            return $summary
        } catch {
            $setStatus.Invoke("No se pudo leer LogEvents: $($_.Exception.Message)", "Error")
            return $null
        }
    }.GetNewClosure()

    $loadLogEvents = {
        $setBusy.Invoke($true)
        try {
            $setStatus.Invoke("Leyendo ultimos registros de LogEvents...")
            $dt = Get-DzSqliteLogEvents -DbPath $dbPath -DllPath $dllPath -Limit 200
            $dgLogEvents.ItemsSource = $dt.DefaultView
            $summary = $refreshSummary.Invoke()
            $setStatus.Invoke("LogEvents cargado. Mostrando hasta 200 registros recientes.", "Ok")
        } catch {
            $setStatus.Invoke("Error cargando LogEvents: $($_.Exception.Message)", "Error")
            Show-WpfMessageBox -Message "No se pudo leer LogEvents.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
        } finally {
            $setBusy.Invoke($false)
        }
    }.GetNewClosure()

    $previewDelete = {
        if (-not $dpCutoffDate.SelectedDate) {
            Show-WpfMessageBox -Message "Selecciona una fecha limite." -Title "SQLite" -Buttons OK -Icon Warning -Owner $w | Out-Null
            return
        }
        try {
            $date = [datetime]$dpCutoffDate.SelectedDate
            $count = Get-DzSqliteLogEventsDeleteCount -DbPath $dbPath -DllPath $dllPath -BeforeDate $date
            $setStatus.Invoke(("Se borrarian {0} registro(s) anteriores a {1:dd/MM/yyyy}." -f $count, $date), "Warn")
        } catch {
            $setStatus.Invoke("No se pudo calcular la limpieza: $($_.Exception.Message)", "Error")
            Show-WpfMessageBox -Message "No se pudo calcular la limpieza.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
        }
    }.GetNewClosure()

    $cleanLogEvents = {
        if (-not $dpCutoffDate.SelectedDate) {
            Show-WpfMessageBox -Message "Selecciona una fecha limite." -Title "SQLite" -Buttons OK -Icon Warning -Owner $w | Out-Null
            return
        }

        $date = [datetime]$dpCutoffDate.SelectedDate
        try {
            $count = Get-DzSqliteLogEventsDeleteCount -DbPath $dbPath -DllPath $dllPath -BeforeDate $date
        } catch {
            Show-WpfMessageBox -Message "No se pudo calcular la limpieza.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
            return
        }

        if ($count -le 0) {
            $setStatus.Invoke(("No hay registros anteriores a {0:dd/MM/yyyy}." -f $date), "Ok")
            return
        }

        $msg = "Se borraran $count registro(s) de LogEvents anteriores a $($date.ToString('dd/MM/yyyy')).`n`nEsta accion no se puede deshacer. Deseas continuar?"
        $confirm = Show-WpfMessageBox -Message $msg -Title "Confirmar limpieza SQLite" -Buttons YesNo -Icon Warning -Owner $w
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        $opProgress = $null
        $setBusy.Invoke($true)
        try {
            if (Get-Command Show-WpfProgressBar -ErrorAction SilentlyContinue) {
                $opProgress = Show-WpfProgressBar -Title "Limpiando SQLite" -Message "Eliminando LogEvents..." -Owner $w -BlockOwner -ProgrammaticCloseOnly -HidePercent
            }
            if ($opProgress) { Update-WpfProgressBar -Window $opProgress -Percent 25 -Message "Eliminando registros..." }
            $deleted = Remove-DzSqliteLogEventsBefore -DbPath $dbPath -DllPath $dllPath -BeforeDate $date -Vacuum:([bool]$chkVacuum.IsChecked)
            if ($opProgress) { Update-WpfProgressBar -Window $opProgress -Percent 100 -Message "Limpieza completada." }
            $refreshSummary.Invoke() | Out-Null
            $dt = Get-DzSqliteLogEvents -DbPath $dbPath -DllPath $dllPath -Limit 200
            $dgLogEvents.ItemsSource = $dt.DefaultView
            $setStatus.Invoke("Limpieza completada. Registros eliminados: $deleted.", "Ok")
            Show-WpfMessageBox -Message "Limpieza completada.`nRegistros eliminados: $deleted" -Title "SQLite" -Buttons OK -Icon Information -Owner $w | Out-Null
        } catch {
            $setStatus.Invoke("Error durante la limpieza: $($_.Exception.Message)", "Error")
            Show-WpfMessageBox -Message "No se pudo limpiar LogEvents.`n`n$($_.Exception.Message)" -Title "SQLite" -Buttons OK -Icon Error -Owner $w | Out-Null
        } finally {
            if ($opProgress) { Close-WpfProgressBar -Window $opProgress }
            $setBusy.Invoke($false)
        }
    }.GetNewClosure()

    $c["btnClose"].Add_Click({ $w.Close() })
    $c["btnCloseFooter"].Add_Click({ $w.Close() })
    $c["btnViewLogEvents"].Add_Click({ $loadLogEvents.Invoke() })
    $c["btnPreviewDelete"].Add_Click({ $previewDelete.Invoke() })
    $c["btnClean"].Add_Click({ $cleanLogEvents.Invoke() })

    $w.Add_Loaded({
            $refreshSummary.Invoke() | Out-Null
            $loadLogEvents.Invoke()
        }.GetNewClosure())

    $null = $w.ShowDialog()
}

Export-ModuleMember -Function @(
    'Initialize-DzSqliteRuntime',
    'Invoke-DzSqliteQuery',
    'Invoke-DzSqliteNonQuery',
    'Get-DzSqliteLogEventsSummary',
    'Get-DzSqliteLogEvents',
    'Get-DzSqliteLogEventsDeleteCount',
    'Remove-DzSqliteLogEventsBefore',
    'Get-DzSqliteTables',
    'Get-DzSqliteTableColumns',
    'Get-DzSqliteTableRowCount',
    'Get-DzSqliteTableData',
    'Get-DzSqliteDeletePreview',
    'Remove-DzSqliteRowsByField',
    'Get-DzSqliteBackupDirectory',
    'New-DzSqliteBackup',
    'Show-DzSqliteCleanerDialog'
)
