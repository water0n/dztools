#requires -Version 5.0
#DzStorage.psm1 - Persistencia unificada SQLite (configuración, conexiones cifradas, historial, pestañas y bitácora)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Security

#region Estado del módulo

$script:DzStorageBaseDir = "C:\Temp\dztools"
$script:DzStorageDbPath = "C:\Temp\dztools\dztools.db"
$script:DzStorageBackupDir = "C:\Temp\dztools\backups\db"
$script:DzStoragePendingAuditPath = "C:\Temp\dztools\audit-pending.jsonl"
$script:DzLegacyToolsIniPath = "C:\Temp\dztools\dztools.ini"
$script:DzLegacyQueriesIniPath = "C:\Temp\dztools\Queries.ini"

$script:DzStorageMode = "uninitialized"  # 'uninitialized' | 'sqlite' | 'fallback'
$script:DzStorageLastError = $null
$script:DzDbInstance = $null
$script:DzSettingsCache = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
$script:DzFts5Enabled = $false
$script:DzSessionId = [guid]::NewGuid().ToString("N")
$script:DzLastAuditClickAt = New-Object 'System.Collections.Generic.Dictionary[string,datetime]' ([System.StringComparer]::OrdinalIgnoreCase)
$script:DzExcludedAuditControlsCache = $null
$script:DzTabsAutosaveTimer = $null
$script:DzLastSavedTabsSignature = $null

$script:DzDefaultExcludedAuditControls = @(
    'btnClose', 'btnCloseX', 'btnCloseFooter', 'btnCerrar',
    'btnCancel', 'btnCancelar', 'btnClearSearch', 'btnSsmsPanelToggle',
    'tabAddQuery', 'BtnFindNext', 'BtnFindPrev', 'btnFindNext', 'btnFindPrev', 'btnCloseSearch',
    'chkFilterFavorites', 'btnLoadMore'
)
$script:DzDefaultExcludedAuditLabels = @('×', 'x', 'cerrar', 'cancelar', '▼', '▲', 'ok', 'sí', 'si', 'no')
$script:DzDefaultSettings = [ordered]@{
    'dev.debug'               = 'false'
    'ui.mode'                 = 'light'
    'ui.stacked_results'      = 'true'
    'history.page_size'       = '200'
    'history.retention_days'  = '0'
    'audit.enabled'           = 'true'
    'audit.retention_days'    = '0'
    'audit.excluded_controls' = ($script:DzDefaultExcludedAuditControls -join ',')
    'storage.backup_keep'     = '5'
    'tabs.autosave_seconds'   = '60'
}

function Write-DzStorageDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    $text = "[Storage] $Message"
    if (Get-Command Write-DzDebug -ErrorAction SilentlyContinue) {
        try {
            Write-DzDebug -Message $text -Color $Color
            return
        } catch {
            Write-Verbose $text
        }
    }
    Write-Verbose $text
}

function Get-DzUtcTimestamp {
    [CmdletBinding()]
    param([datetime]$DateTime = [datetime]::UtcNow)
    $DateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-DzUtcTimestampToLocalText {
    [CmdletBinding()]
    param([string]$UtcText)
    if ([string]::IsNullOrWhiteSpace($UtcText)) { return "" }
    try {
        $dt = [datetime]::Parse($UtcText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dt.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
    } catch {
        return $UtcText
    }
}

function Get-DzGlobalAppVersion {
    [CmdletBinding()]
    param()
    $v = Get-Variable -Name version -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($v) { return [string]$v }
    return ""
}

function Get-DzIsAdministrator {
    [CmdletBinding()]
    param()
    if (Get-Command Test-Administrator -ErrorAction SilentlyContinue) {
        try { return [bool](Test-Administrator) } catch { return $false }
    }
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

#endregion

#region Wrapper nativo SQLite (DzTools.Storage.SqliteDb)

function Import-DzStorageNativeType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DllPath
    )

    if (-not [Environment]::Is64BitProcess) {
        throw "El runtime SQLite requiere PowerShell de 64 bits."
    }
    if (-not (Test-Path -LiteralPath $DllPath -PathType Leaf)) {
        throw "No se encontró sqlite3.dll en '$DllPath'."
    }

    if (-not ("DzTools.Storage.SqliteDb" -as [type])) {
        $source = @"
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace DzTools.Storage
{
    public sealed class QueryResult
    {
        public string[] Columns;
        public object[][] Rows;
    }

    public sealed class SqliteDb : IDisposable
    {
        private const int SQLITE_OK = 0;
        private const int SQLITE_ROW = 100;
        private const int SQLITE_DONE = 101;

        private const int SQLITE_INTEGER = 1;
        private const int SQLITE_FLOAT = 2;
        private const int SQLITE_TEXT = 3;
        private const int SQLITE_BLOB = 4;
        private const int SQLITE_NULL = 5;

        private const int SQLITE_OPEN_READWRITE = 0x00000002;
        private const int SQLITE_OPEN_CREATE = 0x00000004;
        private const int SQLITE_OPEN_FULLMUTEX = 0x00010000;

        private static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool SetDllDirectory(string lpPathName);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr LoadLibrary(string lpLibFileName);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "sqlite3_open_v2")]
        private static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_close_v2(IntPtr db);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_busy_timeout(IntPtr db, int ms);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "sqlite3_prepare_v2")]
        private static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int numBytes, out IntPtr stmt, IntPtr tail);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "sqlite3_prepare_v2")]
        private static extern int sqlite3_prepare_v2_ptr(IntPtr db, IntPtr sql, int numBytes, out IntPtr stmt, out IntPtr tail);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_step(IntPtr stmt);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_reset(IntPtr stmt);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_clear_bindings(IntPtr stmt);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_finalize(IntPtr stmt);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_extended_errcode(IntPtr db);

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
        private static extern int sqlite3_bind_null(IntPtr stmt, int index);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_bind_int64(IntPtr stmt, int index, long value);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_bind_double(IntPtr stmt, int index, double value);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] value, int byteCount, IntPtr destructor);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_bind_blob(IntPtr stmt, int index, byte[] value, int byteCount, IntPtr destructor);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_bind_parameter_index(IntPtr stmt, byte[] zName);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_changes(IntPtr db);

        [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern long sqlite3_last_insert_rowid(IntPtr db);

        private IntPtr _db;
        private readonly object _sync = new object();
        private readonly Dictionary<string, IntPtr> _stmtCache = new Dictionary<string, IntPtr>(StringComparer.Ordinal);
        private int _txDepth;

        public static void EnsureLibrary(string dllPath)
        {
            string dir = Path.GetDirectoryName(dllPath);
            if (!SetDllDirectory(dir))
            {
                throw new InvalidOperationException("No se pudo registrar directorio SQLite. Win32=" + Marshal.GetLastWin32Error());
            }
            if (GetModuleHandle("sqlite3.dll") == IntPtr.Zero)
            {
                IntPtr handle = LoadLibrary(dllPath);
                if (handle == IntPtr.Zero)
                {
                    throw new InvalidOperationException("No se pudo cargar sqlite3.dll desde '" + dllPath + "'. Win32=" + Marshal.GetLastWin32Error());
                }
            }
        }

        public SqliteDb(string dbPath)
        {
            string dir = Path.GetDirectoryName(dbPath);
            if (!String.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            IntPtr db;
            int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX;
            int rc = sqlite3_open_v2(ToUtf8Z(dbPath), out db, flags, IntPtr.Zero);
            if (rc != SQLITE_OK)
            {
                string msg = db != IntPtr.Zero ? GetError(db) : ("Codigo SQLite " + rc);
                if (db != IntPtr.Zero) { sqlite3_close_v2(db); }
                throw new InvalidOperationException(msg);
            }

            _db = db;
            sqlite3_busy_timeout(_db, 5000);
            ExecuteScript(
                "PRAGMA journal_mode = WAL;" +
                "PRAGMA synchronous = NORMAL;" +
                "PRAGMA foreign_keys = ON;" +
                "PRAGMA busy_timeout = 5000;" +
                "PRAGMA temp_store = MEMORY;"
            );
        }

        public bool IsOpen
        {
            get { return _db != IntPtr.Zero; }
        }

        public long LastInsertRowId
        {
            get
            {
                lock (_sync)
                {
                    EnsureOpen();
                    return sqlite3_last_insert_rowid(_db);
                }
            }
        }

        public void BeginImmediate()
        {
            lock (_sync)
            {
                EnsureOpen();
                if (_txDepth == 0)
                {
                    ExecuteInternal("BEGIN IMMEDIATE;", null, null, false);
                }
                else
                {
                    ExecuteInternal("SAVEPOINT dz_sp_" + _txDepth + ";", null, null, false);
                }
                _txDepth++;
            }
        }

        public void Commit()
        {
            lock (_sync)
            {
                EnsureOpen();
                if (_txDepth <= 0) { return; }
                _txDepth--;
                if (_txDepth == 0)
                {
                    ExecuteInternal("COMMIT;", null, null, false);
                }
                else
                {
                    ExecuteInternal("RELEASE SAVEPOINT dz_sp_" + _txDepth + ";", null, null, false);
                }
            }
        }

        public void Rollback()
        {
            lock (_sync)
            {
                EnsureOpen();
                if (_txDepth <= 0) { return; }
                _txDepth--;
                if (_txDepth == 0)
                {
                    ExecuteInternal("ROLLBACK;", null, null, false);
                }
                else
                {
                    ExecuteInternal("ROLLBACK TO SAVEPOINT dz_sp_" + _txDepth + "; RELEASE SAVEPOINT dz_sp_" + _txDepth + ";", null, null, false);
                }
            }
        }

        public int Execute(string sql, object[] parameters, bool cacheStatement)
        {
            lock (_sync)
            {
                EnsureOpen();
                return ExecuteInternal(sql, parameters, null, cacheStatement);
            }
        }

        public int ExecuteNamed(string sql, IDictionary parameters, bool cacheStatement)
        {
            lock (_sync)
            {
                EnsureOpen();
                return ExecuteInternal(sql, null, parameters, cacheStatement);
            }
        }

        public void ExecuteScript(string sqlScript)
        {
            if (String.IsNullOrWhiteSpace(sqlScript)) { return; }
            lock (_sync)
            {
                EnsureOpen();
                byte[] sqlBytes = ToUtf8Z(sqlScript);
                GCHandle handle = GCHandle.Alloc(sqlBytes, GCHandleType.Pinned);
                try
                {
                    IntPtr basePtr = handle.AddrOfPinnedObject();
                    int offset = 0;
                    int maxOffset = sqlBytes.Length - 1;
                    while (offset < maxOffset)
                    {
                        IntPtr currentPtr = new IntPtr(basePtr.ToInt64() + offset);
                        int remaining = sqlBytes.Length - offset;
                        IntPtr stmt;
                        IntPtr tail;
                        int rc = sqlite3_prepare_v2_ptr(_db, currentPtr, remaining, out stmt, out tail);
                        if (rc != SQLITE_OK)
                        {
                            ThrowSqlite(rc);
                        }
                        try
                        {
                            if (stmt != IntPtr.Zero)
                            {
                                while (true)
                                {
                                    int stepRc = sqlite3_step(stmt);
                                    if (stepRc == SQLITE_DONE) { break; }
                                    if (stepRc == SQLITE_ROW) { continue; }
                                    ThrowSqlite(stepRc);
                                }
                            }
                        }
                        finally
                        {
                            if (stmt != IntPtr.Zero) { sqlite3_finalize(stmt); }
                        }

                        if (tail == IntPtr.Zero) { break; }
                        int nextOffset = (int)(tail.ToInt64() - basePtr.ToInt64());
                        if (nextOffset <= offset) { break; }
                        offset = nextOffset;
                    }
                }
                finally
                {
                    handle.Free();
                }
            }
        }

        public QueryResult Query(string sql, object[] parameters, bool cacheStatement)
        {
            lock (_sync)
            {
                EnsureOpen();
                return QueryInternal(sql, parameters, null, cacheStatement);
            }
        }

        public QueryResult QueryNamed(string sql, IDictionary parameters, bool cacheStatement)
        {
            lock (_sync)
            {
                EnsureOpen();
                return QueryInternal(sql, null, parameters, cacheStatement);
            }
        }

        public object Scalar(string sql, object[] parameters)
        {
            QueryResult res = Query(sql, parameters, false);
            if (res.Rows == null || res.Rows.Length == 0 || res.Columns.Length == 0) { return null; }
            return res.Rows[0][0];
        }

        public object ScalarNamed(string sql, IDictionary parameters)
        {
            QueryResult res = QueryNamed(sql, parameters, false);
            if (res.Rows == null || res.Rows.Length == 0 || res.Columns.Length == 0) { return null; }
            return res.Rows[0][0];
        }

        public void Close()
        {
            lock (_sync)
            {
                foreach (IntPtr stmt in _stmtCache.Values)
                {
                    if (stmt != IntPtr.Zero) { sqlite3_finalize(stmt); }
                }
                _stmtCache.Clear();
                if (_db != IntPtr.Zero)
                {
                    sqlite3_close_v2(_db);
                    _db = IntPtr.Zero;
                }
                _txDepth = 0;
            }
        }

        public void Dispose()
        {
            Close();
        }

        private void EnsureOpen()
        {
            if (_db == IntPtr.Zero) { throw new InvalidOperationException("La conexion SQLite esta cerrada."); }
        }

        private IntPtr GetStatement(string sql, bool cacheStatement)
        {
            IntPtr stmt;
            if (cacheStatement && _stmtCache.TryGetValue(sql, out stmt))
            {
                sqlite3_reset(stmt);
                sqlite3_clear_bindings(stmt);
                return stmt;
            }
            byte[] sqlBytes = ToUtf8Z(sql);
            int rc = sqlite3_prepare_v2(_db, sqlBytes, sqlBytes.Length, out stmt, IntPtr.Zero);
            if (rc != SQLITE_OK) { ThrowSqlite(rc); }
            if (cacheStatement && stmt != IntPtr.Zero)
            {
                _stmtCache[sql] = stmt;
            }
            return stmt;
        }

        private void ReleaseStatement(IntPtr stmt, bool cached)
        {
            if (stmt == IntPtr.Zero) { return; }
            if (cached)
            {
                sqlite3_reset(stmt);
                sqlite3_clear_bindings(stmt);
            }
            else
            {
                sqlite3_finalize(stmt);
            }
        }

        private int ExecuteInternal(string sql, object[] posParams, IDictionary namedParams, bool cacheStatement)
        {
            IntPtr stmt = IntPtr.Zero;
            try
            {
                stmt = GetStatement(sql, cacheStatement);
                if (stmt == IntPtr.Zero) { return 0; }
                BindParameters(stmt, posParams, namedParams);
                while (true)
                {
                    int rc = sqlite3_step(stmt);
                    if (rc == SQLITE_DONE) { break; }
                    if (rc == SQLITE_ROW) { continue; }
                    ThrowSqlite(rc);
                }
                return sqlite3_changes(_db);
            }
            finally
            {
                ReleaseStatement(stmt, cacheStatement);
            }
        }

        private QueryResult QueryInternal(string sql, object[] posParams, IDictionary namedParams, bool cacheStatement)
        {
            IntPtr stmt = IntPtr.Zero;
            try
            {
                stmt = GetStatement(sql, cacheStatement);
                if (stmt == IntPtr.Zero)
                {
                    return new QueryResult { Columns = new string[0], Rows = new object[0][] };
                }
                BindParameters(stmt, posParams, namedParams);

                int colCount = sqlite3_column_count(stmt);
                List<string> columns = new List<string>(colCount);
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

                List<object[]> rows = new List<object[]>();
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
                    ThrowSqlite(rc);
                }

                return new QueryResult { Columns = columns.ToArray(), Rows = rows.ToArray() };
            }
            finally
            {
                ReleaseStatement(stmt, cacheStatement);
            }
        }

        private void BindParameters(IntPtr stmt, object[] posParams, IDictionary namedParams)
        {
            if (posParams != null)
            {
                for (int i = 0; i < posParams.Length; i++)
                {
                    BindValue(stmt, i + 1, posParams[i]);
                }
            }
            if (namedParams != null)
            {
                foreach (DictionaryEntry entry in namedParams)
                {
                    string key = Convert.ToString(entry.Key, CultureInfo.InvariantCulture);
                    if (String.IsNullOrEmpty(key)) { continue; }
                    string paramName = (key[0] == '@' || key[0] == ':' || key[0] == '$') ? key : ("@" + key);
                    int idx = sqlite3_bind_parameter_index(stmt, ToUtf8Z(paramName));
                    if (idx > 0)
                    {
                        BindValue(stmt, idx, entry.Value);
                    }
                }
            }
        }

        private void BindValue(IntPtr stmt, int index, object val)
        {
            int rc;
            if (val == null || val is DBNull)
            {
                rc = sqlite3_bind_null(stmt, index);
            }
            else if (val is byte[])
            {
                byte[] blob = (byte[])val;
                if (blob.Length == 0)
                {
                    rc = sqlite3_bind_blob(stmt, index, new byte[1], 0, SQLITE_TRANSIENT);
                }
                else
                {
                    rc = sqlite3_bind_blob(stmt, index, blob, blob.Length, SQLITE_TRANSIENT);
                }
            }
            else if (val is bool)
            {
                rc = sqlite3_bind_int64(stmt, index, ((bool)val) ? 1L : 0L);
            }
            else if (val is sbyte || val is byte || val is short || val is ushort || val is int || val is uint || val is long)
            {
                rc = sqlite3_bind_int64(stmt, index, Convert.ToInt64(val, CultureInfo.InvariantCulture));
            }
            else if (val is ulong)
            {
                unchecked
                {
                    rc = sqlite3_bind_int64(stmt, index, (long)((ulong)val));
                }
            }
            else if (val is float || val is double || val is decimal)
            {
                rc = sqlite3_bind_double(stmt, index, Convert.ToDouble(val, CultureInfo.InvariantCulture));
            }
            else if (val is DateTime)
            {
                string iso = ((DateTime)val).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", CultureInfo.InvariantCulture);
                byte[] raw = ToUtf8Z(iso);
                rc = sqlite3_bind_text(stmt, index, raw, raw.Length - 1, SQLITE_TRANSIENT);
            }
            else
            {
                string text = Convert.ToString(val, CultureInfo.InvariantCulture);
                byte[] raw = ToUtf8Z(text);
                rc = sqlite3_bind_text(stmt, index, raw, raw.Length - 1, SQLITE_TRANSIENT);
            }

            if (rc != SQLITE_OK) { ThrowSqlite(rc); }
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
                    int len = sqlite3_column_bytes(stmt, iCol);
                    if (len <= 0) { return new byte[0]; }
                    IntPtr ptr = sqlite3_column_blob(stmt, iCol);
                    byte[] data = new byte[len];
                    Marshal.Copy(ptr, data, 0, len);
                    return data;
                case SQLITE_NULL:
                default:
                    return DBNull.Value;
            }
        }

        private void ThrowSqlite(int rc)
        {
            int ext = _db != IntPtr.Zero ? sqlite3_extended_errcode(_db) : rc;
            string msg = _db != IntPtr.Zero ? GetError(_db) : ("Codigo SQLite " + rc);
            throw new InvalidOperationException(msg + " (SQLite " + ext + ")");
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

    [DzTools.Storage.SqliteDb]::EnsureLibrary($DllPath)
}

function ConvertTo-DzPlainParamDictionary {
    [CmdletBinding()]
    param([hashtable]$Parameters)
    if (-not $Parameters) { return $null }
    $clean = @{}
    foreach ($key in $Parameters.Keys) {
        $v = $Parameters[$key]
        if ($null -ne $v -and $v -is [psobject]) {
            $v = $v.PSObject.BaseObject
        }
        $clean[$key] = $v
    }
    return $clean
}

function ConvertFrom-DzSqliteQueryResult {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$QueryResult)

    $cols = @($QueryResult.Columns)
    $rows = $QueryResult.Rows
    if ($null -eq $rows -or $rows.Length -eq 0) {
        return @()
    }

    $list = New-Object System.Collections.Generic.List[object] ($rows.Length)
    for ($r = 0; $r -lt $rows.Length; $r++) {
        $sourceRow = $rows[$r]
        $obj = [ordered]@{}
        for ($c = 0; $c -lt $cols.Count; $c++) {
            $val = $sourceRow[$c]
            if ($val -is [System.DBNull]) { $val = $null }
            $obj[$cols[$c]] = $val
        }
        $list.Add([pscustomobject]$obj)
    }
    return $list.ToArray()
}

function Invoke-DzDbNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [hashtable]$Parameters = $null,
        [switch]$CacheStatement
    )

    if (-not $script:DzDbInstance -or -not $script:DzDbInstance.IsOpen) {
        throw "La base de datos de almacenamiento no está abierta."
    }
    $clean = ConvertTo-DzPlainParamDictionary -Parameters $Parameters
    return $script:DzDbInstance.ExecuteNamed($Sql, $clean, [bool]$CacheStatement)
}

function Invoke-DzDbQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [hashtable]$Parameters = $null,
        [switch]$CacheStatement
    )

    if (-not $script:DzDbInstance -or -not $script:DzDbInstance.IsOpen) {
        throw "La base de datos de almacenamiento no está abierta."
    }
    $clean = ConvertTo-DzPlainParamDictionary -Parameters $Parameters
    $res = $script:DzDbInstance.QueryNamed($Sql, $clean, [bool]$CacheStatement)
    return (ConvertFrom-DzSqliteQueryResult -QueryResult $res)
}

function Invoke-DzDbScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [hashtable]$Parameters = $null
    )

    if (-not $script:DzDbInstance -or -not $script:DzDbInstance.IsOpen) {
        throw "La base de datos de almacenamiento no está abierta."
    }
    $clean = ConvertTo-DzPlainParamDictionary -Parameters $Parameters
    $val = $script:DzDbInstance.ScalarNamed($Sql, $clean)
    if ($val -is [System.DBNull]) { return $null }
    return $val
}

function Invoke-DzDbTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    if (-not $script:DzDbInstance -or -not $script:DzDbInstance.IsOpen) {
        throw "La base de datos de almacenamiento no está abierta."
    }
    $script:DzDbInstance.BeginImmediate()
    try {
        $result = & $ScriptBlock
        $script:DzDbInstance.Commit()
        return $result
    } catch {
        try { $script:DzDbInstance.Rollback() } catch { Write-DzStorageDebug "Error en rollback: $($_.Exception.Message)" ([System.ConsoleColor]::Red) }
        throw
    }
}

#endregion

#region Esquema y migraciones de versión

function Update-DzStorageSchema {
    [CmdletBinding()]
    param()

    $version = [int](Invoke-DzDbScalar -Sql "PRAGMA user_version;")
    if ($version -lt 1) {
        Invoke-DzDbTransaction {
            $v1Ddl = @"
CREATE TABLE IF NOT EXISTS app_meta (
    key         TEXT PRIMARY KEY,
    value       TEXT,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS app_settings (
    section     TEXT NOT NULL COLLATE NOCASE,
    key         TEXT NOT NULL COLLATE NOCASE,
    value       TEXT,
    updated_at  TEXT NOT NULL,
    PRIMARY KEY (section, key)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS sql_connections (
    id                 INTEGER PRIMARY KEY,
    server             TEXT NOT NULL UNIQUE COLLATE NOCASE,
    username           TEXT NOT NULL,
    password_enc       BLOB,
    password_format    TEXT NOT NULL,
    needs_reentry      INTEGER NOT NULL DEFAULT 0,
    last_database      TEXT,
    last_connected_at  TEXT,
    use_count          INTEGER NOT NULL DEFAULT 0,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS query_history (
    id              INTEGER PRIMARY KEY,
    executed_at     TEXT NOT NULL,
    server          TEXT,
    database_name   TEXT,
    query_hash      TEXT NOT NULL,
    preview         TEXT NOT NULL,
    full_query      TEXT NOT NULL,
    success         INTEGER NOT NULL,
    rows_affected   INTEGER,
    duration_ms     INTEGER,
    result_summary  TEXT,
    error_message   TEXT,
    is_favorite     INTEGER NOT NULL DEFAULT 0,
    windows_user    TEXT,
    machine_name    TEXT,
    source          TEXT NOT NULL DEFAULT 'app'
);
CREATE INDEX IF NOT EXISTS ix_qh_executed   ON query_history (executed_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS ix_qh_server_db  ON query_history (server, database_name, executed_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS ix_qh_hash       ON query_history (query_hash, executed_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS ix_qh_favorite   ON query_history (is_favorite, executed_at DESC, id DESC) WHERE is_favorite = 1;
CREATE INDEX IF NOT EXISTS ix_qh_success    ON query_history (success, executed_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS open_query_tabs (
    tab_index      INTEGER PRIMARY KEY,
    title          TEXT,
    query_text     TEXT NOT NULL,
    is_dirty       INTEGER NOT NULL DEFAULT 0,
    is_active      INTEGER NOT NULL DEFAULT 0,
    file_path      TEXT,
    database_name  TEXT,
    server         TEXT,
    updated_at     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audit_log (
    id            INTEGER PRIMARY KEY,
    created_at    TEXT NOT NULL,
    session_id    TEXT NOT NULL,
    event_type    TEXT NOT NULL,
    window_title  TEXT,
    control_name  TEXT,
    action_label  TEXT,
    target        TEXT,
    details       TEXT,
    status        TEXT,
    windows_user  TEXT NOT NULL,
    machine_name  TEXT NOT NULL,
    app_version   TEXT,
    is_admin      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_audit_created ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS ix_audit_type    ON audit_log (event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_audit_session ON audit_log (session_id);
"@
            $script:DzDbInstance.ExecuteScript($v1Ddl)
            $script:DzDbInstance.Execute("PRAGMA user_version = 1;", $null, $false) | Out-Null
        }
    }

    # Asegurar FTS5 trigram si el DLL lo soporta
    $ftsFlag = Invoke-DzDbScalar -Sql "SELECT value FROM app_meta WHERE key = 'fts5_enabled';"
    if ($null -eq $ftsFlag) {
        $ftsEnabled = $false
        try {
            Invoke-DzDbTransaction {
                $ftsSql = @"
CREATE VIRTUAL TABLE IF NOT EXISTS query_history_fts USING fts5(
    full_query, preview, server, database_name,
    content='query_history', content_rowid='id',
    tokenize='trigram'
);
CREATE TRIGGER IF NOT EXISTS tr_qh_ai AFTER INSERT ON query_history BEGIN
    INSERT INTO query_history_fts(rowid, full_query, preview, server, database_name)
    VALUES (new.id, new.full_query, new.preview, COALESCE(new.server, ''), COALESCE(new.database_name, ''));
END;
CREATE TRIGGER IF NOT EXISTS tr_qh_ad AFTER DELETE ON query_history BEGIN
    INSERT INTO query_history_fts(query_history_fts, rowid, full_query, preview, server, database_name)
    VALUES ('delete', old.id, old.full_query, old.preview, COALESCE(old.server, ''), COALESCE(old.database_name, ''));
END;
CREATE TRIGGER IF NOT EXISTS tr_qh_au AFTER UPDATE ON query_history BEGIN
    INSERT INTO query_history_fts(query_history_fts, rowid, full_query, preview, server, database_name)
    VALUES ('delete', old.id, old.full_query, old.preview, COALESCE(old.server, ''), COALESCE(old.database_name, ''));
    INSERT INTO query_history_fts(rowid, full_query, preview, server, database_name)
    VALUES (new.id, new.full_query, new.preview, COALESCE(new.server, ''), COALESCE(new.database_name, ''));
END;
"@
                $script:DzDbInstance.ExecuteScript($ftsSql)
                $now = Get-DzUtcTimestamp
                Invoke-DzDbNonQuery -Sql "INSERT OR REPLACE INTO app_meta(key, value, updated_at) VALUES ('fts5_enabled', '1', @now);" -Parameters @{ now = $now } | Out-Null
            }
            $ftsEnabled = $true
        } catch {
            Write-DzStorageDebug "FTS5 no disponible, usando búsqueda LIKE: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
            try {
                $now = Get-DzUtcTimestamp
                Invoke-DzDbNonQuery -Sql "INSERT OR REPLACE INTO app_meta(key, value, updated_at) VALUES ('fts5_enabled', '0', @now);" -Parameters @{ now = $now } | Out-Null
            } catch {
                Write-DzStorageDebug "No se pudo guardar bandera fts5_enabled: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
            }
        }
        $script:DzFts5Enabled = $ftsEnabled
    } else {
        $script:DzFts5Enabled = ([string]$ftsFlag -eq '1')
    }

    # Defaults iniciales en app_settings
    $nowDefaults = Get-DzUtcTimestamp
    Invoke-DzDbTransaction {
        foreach ($fullKey in $script:DzDefaultSettings.Keys) {
            $parts = $fullKey -split '\.', 2
            Invoke-DzDbNonQuery -CacheStatement `
                -Sql "INSERT OR IGNORE INTO app_settings(section, key, value, updated_at) VALUES (@section, @key, @value, @now);" `
                -Parameters @{
                    section = $parts[0]
                    key     = $parts[1]
                    value   = $script:DzDefaultSettings[$fullKey]
                    now     = $nowDefaults
                } | Out-Null
        }
    }
}

function Initialize-DzSettingsCache {
    [CmdletBinding()]
    param()
    $script:DzSettingsCache.Clear()
    $script:DzExcludedAuditControlsCache = $null
    $rows = Invoke-DzDbQuery -Sql "SELECT section, key, value FROM app_settings;"
    foreach ($row in $rows) {
        $cacheKey = "$($row.section).$($row.key)"
        $script:DzSettingsCache[$cacheKey] = if ($null -eq $row.value) { "" } else { [string]$row.value }
    }
}

#endregion

#region Parsers puros de INI legado

function ConvertFrom-DzLegacyToolsIni {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]]$Lines = @()
    )

    $settings = New-Object System.Collections.Generic.List[object]
    $connections = New-Object System.Collections.Generic.List[object]
    $skipped = 0
    $currentSection = ""

    foreach ($line in @($Lines)) {
        if ($null -eq $line) { continue }
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -match '^\s*;') { continue }

        if ($trimmed -match '^\[(.+)\]\s*$') {
            $currentSection = $matches[1].Trim()
            continue
        }

        $parts = $trimmed -split '=', 2
        if ($parts.Count -lt 2) {
            $skipped++
            continue
        }
        $key = $parts[0].Trim()
        $val = $parts[1].Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            $skipped++
            continue
        }

        switch -Regex ($currentSection.ToLowerInvariant()) {
            '^(desarrollo|dev)$' {
                $settings.Add([pscustomobject]@{ Section = 'dev'; Key = $key; Value = $val })
            }
            '^ui$' {
                $settings.Add([pscustomobject]@{ Section = 'ui'; Key = $key; Value = $val })
            }
            '^sql$' {
                $credParts = $val -split '\|', 2
                if ($credParts.Count -lt 2 -or [string]::IsNullOrWhiteSpace($credParts[0])) {
                    $skipped++
                    continue
                }
                $plainPassword = ""
                $decodeOk = $true
                try {
                    $bytes = [Convert]::FromBase64String($credParts[1])
                    $plainPassword = [System.Text.Encoding]::UTF8.GetString($bytes)
                } catch {
                    $decodeOk = $false
                }
                if (-not $decodeOk) {
                    $skipped++
                    continue
                }
                $connections.Add([pscustomobject]@{
                        Server   = $key
                        User     = $credParts[0]
                        Password = $plainPassword
                    })
            }
            default {
                if (-not [string]::IsNullOrWhiteSpace($currentSection)) {
                    $settings.Add([pscustomobject]@{ Section = $currentSection.ToLowerInvariant(); Key = $key; Value = $val })
                } else {
                    $skipped++
                }
            }
        }
    }

    return [pscustomobject]@{
        Settings     = $settings.ToArray()
        Connections  = $connections.ToArray()
        SkippedLines = $skipped
    }
}

function ConvertFrom-DzLegacyQueriesIni {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]]$Lines = @()
    )

    $history = New-Object System.Collections.Generic.List[object]
    $openTabs = New-Object System.Collections.Generic.List[object]
    $skippedHistory = 0
    $skippedTabs = 0
    $currentSection = ""

    foreach ($line in @($Lines)) {
        if ($null -eq $line) { continue }
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -match '^\s*;') { continue }

        if ($trimmed -match '^\[(.+)\]\s*$') {
            $currentSection = $matches[1].Trim()
            continue
        }

        if ($currentSection -eq 'QueriesHistory') {
            $parts = $trimmed -split '\|', 7
            $tsText = $null
            $server = ""
            $db = ""
            $preview = ""
            $resultInfo = ""
            $b64 = ""

            if ($parts.Count -eq 6) {
                $tsText = $parts[0]
                $db = $parts[1]
                $preview = $parts[3]
                $resultInfo = $parts[4]
                $b64 = $parts[5]
            } elseif ($parts.Count -ge 7) {
                $tsText = $parts[0]
                $server = $parts[1]
                $db = $parts[2]
                $preview = $parts[4]
                $resultInfo = $parts[5]
                $b64 = $parts[6]
            } else {
                $skippedHistory++
                continue
            }

            $fullQuery = $null
            try {
                $qBytes = [Convert]::FromBase64String($b64)
                $fullQuery = [System.Text.Encoding]::UTF8.GetString($qBytes)
            } catch {
                $skippedHistory++
                continue
            }
            if ([string]::IsNullOrWhiteSpace($fullQuery)) {
                $skippedHistory++
                continue
            }

            $utcStamp = Get-DzUtcTimestamp
            try {
                $parsedDt = [datetime]::ParseExact($tsText, "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                $localDt = [datetime]::SpecifyKind($parsedDt, [System.DateTimeKind]::Local)
                $utcStamp = Get-DzUtcTimestamp -DateTime $localDt
            } catch {
                try {
                    $parsedAny = [datetime]::Parse($tsText, [System.Globalization.CultureInfo]::InvariantCulture)
                    $utcStamp = Get-DzUtcTimestamp -DateTime $parsedAny
                } catch {
                    Write-DzStorageDebug "Fecha de historial inválida '$tsText', usando fecha actual." ([System.ConsoleColor]::Yellow)
                }
            }

            $success = ($resultInfo -match '^OK')
            $rowsAffected = $null
            if ($success -and $resultInfo -match 'OK\s*\((\d+)\s*filas?\)') {
                $rowsAffected = [int64]$Matches[1]
            }
            $errorMsg = ""
            if (-not $success -and $resultInfo -match '^ERROR:\s*(.*)$') {
                $errorMsg = $Matches[1]
            } elseif (-not $success) {
                $errorMsg = $resultInfo
            }

            $clean = ($fullQuery -replace '\s+', ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($preview)) {
                $preview = if ($clean.Length -gt 100) { $clean.Substring(0, 97) + "..." } else { $clean }
            }

            $history.Add([pscustomobject]@{
                    ExecutedAtUtc = $utcStamp
                    Server        = $server
                    Database      = $db
                    Hash          = (Get-DzQueryHash -Query $fullQuery)
                    Preview       = $preview
                    FullQuery     = $fullQuery
                    Success       = $success
                    RowsAffected  = $rowsAffected
                    ResultSummary = $resultInfo
                    ErrorMessage  = $errorMsg
                })
        } elseif ($currentSection -eq 'QueriesOpen') {
            $parts = $trimmed -split '\|', 4
            if ($parts.Count -lt 4) {
                $skippedTabs++
                continue
            }
            $tabIdx = 0
            if (-not [int]::TryParse($parts[0], [ref]$tabIdx)) {
                $skippedTabs++
                continue
            }
            $queryText = $null
            try {
                $tBytes = [Convert]::FromBase64String($parts[3])
                $queryText = [System.Text.Encoding]::UTF8.GetString($tBytes)
            } catch {
                $skippedTabs++
                continue
            }
            $openTabs.Add([pscustomobject]@{
                    TabIndex  = $tabIdx
                    Title     = $parts[1]
                    IsDirty   = ($parts[2] -eq '1')
                    QueryText = $queryText
                })
        }
    }

    return [pscustomobject]@{
        History             = $history.ToArray()
        OpenTabs            = $openTabs.ToArray()
        SkippedHistoryLines = $skippedHistory
        SkippedTabLines     = $skippedTabs
    }
}

#endregion

#region Cifrado DPAPI y Conexiones SQL

function Protect-DzSecretString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PlainText,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $entropy = [System.Text.Encoding]::UTF8.GetBytes("dztools|sql_connections|v1|" + $Server.Trim().ToLowerInvariant())
    try {
        return ,[System.Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
    } finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
}

function Unprotect-DzSecretBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][byte[]]$CipherBytes,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Format
    )

    if ($Format -eq 'none' -or $null -eq $CipherBytes -or $CipherBytes.Length -eq 0) {
        return [pscustomobject]@{ Success = $true; PlainText = "" }
    }
    if ($Format -ne 'dpapi-cu-v1') {
        return [pscustomobject]@{ Success = $false; PlainText = ""; Error = "Formato de cifrado no soportado: $Format" }
    }

    $entropy = [System.Text.Encoding]::UTF8.GetBytes("dztools|sql_connections|v1|" + $Server.Trim().ToLowerInvariant())
    $plainBytes = $null
    try {
        $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $CipherBytes,
            $entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $text = [System.Text.Encoding]::UTF8.GetString($plainBytes)
        return [pscustomobject]@{ Success = $true; PlainText = $text }
    } catch {
        return [pscustomobject]@{ Success = $false; PlainText = ""; Error = $_.Exception.Message }
    } finally {
        if ($plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    }
}

function Save-DzSqlConnectionRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Password
    )

    $serverClean = $Server.Trim()
    $userClean = $User.Trim()
    if ([string]::IsNullOrWhiteSpace($serverClean) -or [string]::IsNullOrWhiteSpace($userClean) -or [string]::IsNullOrWhiteSpace($Password)) {
        return
    }

    if ($script:DzStorageMode -ne 'sqlite') {
        Save-DzLegacyIniSqlConnection -Server $serverClean -User $userClean -Password $Password
        return
    }

    $cipher = Protect-DzSecretString -PlainText $Password -Server $serverClean
    $now = Get-DzUtcTimestamp
    $sql = @"
INSERT INTO sql_connections (server, username, password_enc, password_format, needs_reentry, use_count, created_at, updated_at)
VALUES (@server, @username, @password_enc, 'dpapi-cu-v1', 0, 0, @now, @now)
ON CONFLICT(server) DO UPDATE SET
    username        = excluded.username,
    password_enc    = excluded.password_enc,
    password_format = 'dpapi-cu-v1',
    needs_reentry   = 0,
    updated_at      = excluded.updated_at;
"@
    Invoke-DzDbNonQuery -CacheStatement -Sql $sql -Parameters @{
        server       = $serverClean
        username     = $userClean
        password_enc = $cipher
        now          = $now
    } | Out-Null
}

function Get-DzSqlConnectionRecords {
    [CmdletBinding()]
    param(
        [string]$Server = ""
    )

    if ($script:DzStorageMode -ne 'sqlite') {
        $legacy = @(Get-DzLegacyIniSqlConnections)
        if (-not [string]::IsNullOrWhiteSpace($Server)) {
            $target = $Server.Trim().ToLowerInvariant()
            return @($legacy | Where-Object { $_.Server -and $_.Server.Trim().ToLowerInvariant() -eq $target })
        }
        return $legacy
    }

    $sql = if ([string]::IsNullOrWhiteSpace($Server)) {
        "SELECT id, server, username, password_enc, password_format, needs_reentry, last_database, last_connected_at, use_count FROM sql_connections ORDER BY use_count DESC, COALESCE(last_connected_at, '') DESC, server ASC;"
    } else {
        "SELECT id, server, username, password_enc, password_format, needs_reentry, last_database, last_connected_at, use_count FROM sql_connections WHERE server = @server LIMIT 1;"
    }
    $params = if ([string]::IsNullOrWhiteSpace($Server)) { $null } else { @{ server = $Server.Trim() } }
    $rows = Invoke-DzDbQuery -Sql $sql -Parameters $params

    $list = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        $cipher = if ($row.password_enc -is [byte[]]) { [byte[]]$row.password_enc } else { $null }
        $fmt = if ($row.password_format) { [string]$row.password_format } else { 'none' }
        $needsReentry = ([int64]$row.needs_reentry -ne 0)

        $plainPass = ""
        if (-not $needsReentry -and $fmt -ne 'none' -and $null -ne $cipher -and $cipher.Length -gt 0) {
            $dec = Unprotect-DzSecretBytes -CipherBytes $cipher -Server ([string]$row.server) -Format $fmt
            if ($dec.Success) {
                $plainPass = $dec.PlainText
            } else {
                $needsReentry = $true
                $now = Get-DzUtcTimestamp
                try {
                    Invoke-DzDbNonQuery -Sql "UPDATE sql_connections SET needs_reentry = 1, updated_at = @now WHERE id = @id;" -Parameters @{ id = $row.id; now = $now } | Out-Null
                    Write-DzAuditEvent -EventType 'CONFIG_CREDENTIAL_UNREADABLE' -Target ([string]$row.server) -Status 'ERROR' -Details @{ reason = $dec.Error }
                } catch {
                    Write-DzStorageDebug "Error marcando needs_reentry: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
                }
            }
        }

        $list.Add([pscustomobject]@{
                Id              = [int64]$row.id
                Server          = [string]$row.server
                User            = [string]$row.username
                Password        = $plainPass
                NeedsReentry    = $needsReentry
                LastDatabase    = if ($row.last_database) { [string]$row.last_database } else { "" }
                LastConnectedAt = if ($row.last_connected_at) { [string]$row.last_connected_at } else { "" }
                UseCount        = [int64]$row.use_count
            })
    }

    return $list.ToArray()
}

function Remove-DzSqlConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server
    )

    if ($script:DzStorageMode -ne 'sqlite') { return $false }
    $changes = Invoke-DzDbNonQuery -Sql "DELETE FROM sql_connections WHERE server = @server;" -Parameters @{ server = $Server.Trim() }
    return ($changes -gt 0)
}

function Update-DzSqlConnectionUsage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [string]$Database = ""
    )

    if ($script:DzStorageMode -ne 'sqlite') { return }
    $serverClean = $Server.Trim()
    if ([string]::IsNullOrWhiteSpace($serverClean)) { return }
    $now = Get-DzUtcTimestamp
    Invoke-DzDbNonQuery -CacheStatement -Sql @"
UPDATE sql_connections
SET last_database = CASE WHEN @db <> '' THEN @db ELSE last_database END,
    last_connected_at = @now,
    use_count = use_count + 1,
    updated_at = @now
WHERE server = @server;
"@ -Parameters @{
        server = $serverClean
        db     = if ($Database) { $Database.Trim() } else { "" }
        now    = $now
    } | Out-Null
}

#endregion

#region Settings y compatibilidad con Utilities.psm1

function Resolve-DzSettingsSectionName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Section)
    $s = $Section.Trim().ToLowerInvariant()
    if ($s -eq 'desarrollo') { return 'dev' }
    return $s
}

function Get-DzSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Default = ""
    )

    $sec = Resolve-DzSettingsSectionName -Section $Section
    $k = $Key.Trim().ToLowerInvariant()
    $cacheKey = "$sec.$k"

    if ($script:DzStorageMode -eq 'sqlite') {
        if ($script:DzSettingsCache.ContainsKey($cacheKey)) {
            return $script:DzSettingsCache[$cacheKey]
        }
        $val = Invoke-DzDbScalar -Sql "SELECT value FROM app_settings WHERE section = @sec AND key = @k;" -Parameters @{ sec = $sec; k = $k }
        if ($null -ne $val) {
            $strVal = [string]$val
            $script:DzSettingsCache[$cacheKey] = $strVal
            return $strVal
        }
        return $Default
    }

    if ($script:DzStorageMode -eq 'fallback') {
        $map = Get-DzLegacyIniSectionMap -Section $Section
        if ($map -and $map.ContainsKey($Key)) { return [string]$map[$Key] }
    }
    return $Default
}

function Set-DzSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    $sec = Resolve-DzSettingsSectionName -Section $Section
    $k = $Key.Trim().ToLowerInvariant()
    $cacheKey = "$sec.$k"

    if ($script:DzStorageMode -eq 'sqlite') {
        $oldValue = $null
        if ($script:DzSettingsCache.ContainsKey($cacheKey)) {
            $oldValue = $script:DzSettingsCache[$cacheKey]
        }
        $now = Get-DzUtcTimestamp
        Invoke-DzDbNonQuery -CacheStatement -Sql @"
INSERT INTO app_settings(section, key, value, updated_at)
VALUES (@sec, @k, @val, @now)
ON CONFLICT(section, key) DO UPDATE SET
    value      = excluded.value,
    updated_at = excluded.updated_at;
"@ -Parameters @{
            sec = $sec
            k   = $k
            val = $Value
            now = $now
        } | Out-Null

        $script:DzSettingsCache[$cacheKey] = $Value
        if ($cacheKey -eq 'audit.excluded_controls') {
            $script:DzExcludedAuditControlsCache = $null
        }
        if ($oldValue -ne $Value) {
            Write-DzAuditEvent -EventType 'CONFIG_CHANGE' -Target "$sec.$k" -Status 'OK' -Details @{
                section   = $sec
                key       = $k
                old_value = $oldValue
                new_value = $Value
            }
        }
        return
    }

    Update-DzLegacyIniSetting -Section $Section -Key $Key -Value $Value
}

function Get-DzSettingsSection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Section)

    $sec = Resolve-DzSettingsSectionName -Section $Section
    if ($script:DzStorageMode -eq 'sqlite') {
        $map = @{}
        $rows = Invoke-DzDbQuery -Sql "SELECT key, value FROM app_settings WHERE section = @sec;" -Parameters @{ sec = $sec }
        foreach ($row in $rows) {
            $map[[string]$row.key] = if ($null -eq $row.value) { "" } else { [string]$row.value }
        }
        return $map
    }
    return (Get-DzLegacyIniSectionMap -Section $Section)
}

#endregion

#region Modo Legacy INI (para fallback y migración)

function Initialize-DzLegacyIniFiles {
    [CmdletBinding()]
    param()
    $dir = Split-Path -Path $script:DzLegacyToolsIniPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:DzLegacyToolsIniPath)) {
        "[desarrollo]`ndebug=false`n`n[UI]`nmode=light`nstacked_results=true`n`n[sql]`n; server=user|password" | Out-File -FilePath $script:DzLegacyToolsIniPath -Encoding UTF8 -Force
    }
    if (-not (Test-Path -LiteralPath $script:DzLegacyQueriesIniPath)) {
        $initialQueries = @"
[QueriesHistory]
; Historial de queries ejecutadas
; Formato: timestamp|server|database|query_hash|query_preview|result|query_base64

[QueriesOpen]
; Estado de pestañas abiertas al cerrar
; Formato: tab_index|tab_title|is_dirty|query_content_base64
"@
        Set-Content -LiteralPath $script:DzLegacyQueriesIniPath -Value $initialQueries -Encoding UTF8
    }
}

function Get-DzLegacyIniSectionMap {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Section)

    if (-not (Test-Path -LiteralPath $script:DzLegacyToolsIniPath)) { return @{} }
    $content = Get-Content -LiteralPath $script:DzLegacyToolsIniPath -ErrorAction SilentlyContinue
    if ($null -eq $content) { return @{} }

    $map = @{}
    $inSection = $false
    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*;') { continue }
        if ($trimmed -match '^\[(.+)\]\s*$') {
            $current = $matches[1].Trim()
            $inSection = ($current.ToLowerInvariant() -eq $Section.ToLowerInvariant())
            continue
        }
        if (-not $inSection) { continue }
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $parts = $trimmed -split '=', 2
        if ($parts.Count -lt 2) { continue }
        $k = $parts[0].Trim()
        $v = $parts[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($k)) { $map[$k] = $v }
    }
    return $map
}

function Update-DzLegacyIniSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    Initialize-DzLegacyIniFiles
    $content = Get-Content -LiteralPath $script:DzLegacyToolsIniPath -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = @() }

    $lines = New-Object System.Collections.Generic.List[string]
    $sectionFound = $false
    $keyUpdated = $false
    $inTargetSection = $false
    $escapedKey = [regex]::Escape($Key)

    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*;') { $lines.Add($line); continue }
        if ($trimmed -match '^\[(.+)\]\s*$') {
            if ($inTargetSection -and -not $keyUpdated) {
                $lines.Add("$Key=$Value")
                $keyUpdated = $true
            }
            $currentSection = $matches[1].Trim()
            $inTargetSection = ($currentSection.ToLowerInvariant() -eq $Section.ToLowerInvariant())
            if ($inTargetSection) { $sectionFound = $true }
            $lines.Add($line)
            continue
        }
        if ($inTargetSection -and $trimmed -match "^\s*${escapedKey}\s*=") {
            $lines.Add("$Key=$Value")
            $keyUpdated = $true
            continue
        }
        $lines.Add($line)
    }

    if ($sectionFound) {
        if (-not $keyUpdated) { $lines.Add("$Key=$Value") }
    } else {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne "") { $lines.Add("") }
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
    }

    Set-Content -LiteralPath $script:DzLegacyToolsIniPath -Value $lines -Encoding UTF8
}

function Get-DzLegacyIniSqlConnections {
    [CmdletBinding()]
    param()
    $entries = Get-DzLegacyIniSectionMap -Section "sql"
    $list = @()
    foreach ($srv in $entries.Keys) {
        $val = [string]$entries[$srv]
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        $parts = $val -split '\|', 2
        if ($parts.Count -lt 2) { continue }
        $pass = ""
        try {
            $pass = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[1]))
        } catch {
            $pass = ""
        }
        $list += [pscustomobject]@{
            Server       = $srv
            User         = $parts[0]
            Password     = $pass
            NeedsReentry = $false
        }
    }
    return $list
}

function Save-DzLegacyIniSqlConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Password))
    Update-DzLegacyIniSetting -Section "sql" -Key $Server -Value "$User|$encoded"
}

function Add-DzLegacyIniQueryToHistory {
    [CmdletBinding()]
    param(
        [string]$Query,
        [string]$Database,
        [string]$Server = "",
        [bool]$Success = $true,
        [int]$RowsAffected = 0,
        [string]$ErrorMessage = ""
    )

    Initialize-DzLegacyIniFiles
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $cleanQuery = ($Query -replace '\s+', ' ').Trim()
    $preview = if ($cleanQuery.Length -gt 100) { $cleanQuery.Substring(0, 97) + "..." } else { $cleanQuery }
    $hash = (Get-DzQueryHash -Query $Query).Substring(0, 16)
    $resultInfo = if ($Success) { if ($RowsAffected -gt 0) { "OK ($RowsAffected filas)" } else { "OK" } } else { "ERROR: $($ErrorMessage.Substring(0, [Math]::Min(50, $ErrorMessage.Length)))" }
    $queryBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Query))
    $historyLine = "$timestamp|$Server|$Database|$hash|$preview|$resultInfo|$queryBase64"

    $content = Get-Content -LiteralPath $script:DzLegacyQueriesIniPath -ErrorAction Stop
    $lines = New-Object System.Collections.Generic.List[string]
    $historyLines = New-Object System.Collections.Generic.List[string]
    $inHistorySection = $false
    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "[QueriesHistory]") {
            $inHistorySection = $true
            $lines.Add($line)
            continue
        }
        if ($trimmed -eq "[QueriesOpen]") {
            if ($inHistorySection) {
                $historyLines.Add($historyLine)
                $startIdx = [Math]::Max(0, $historyLines.Count - 100)
                for ($i = $startIdx; $i -lt $historyLines.Count; $i++) { $lines.Add($historyLines[$i]) }
            }
            $inHistorySection = $false
            $lines.Add($line)
            continue
        }
        if ($inHistorySection -and -not ($trimmed -match '^\s*;')) {
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) { $historyLines.Add($line) }
            continue
        }
        $lines.Add($line)
    }
    if ($inHistorySection) {
        $historyLines.Add($historyLine)
        $startIdx = [Math]::Max(0, $historyLines.Count - 100)
        for ($i = $startIdx; $i -lt $historyLines.Count; $i++) { $lines.Add($historyLines[$i]) }
    }
    Set-Content -LiteralPath $script:DzLegacyQueriesIniPath -Value $lines -Encoding UTF8
}

function Get-DzLegacyIniQueryHistory {
    [CmdletBinding()]
    param([int]$MaxItems = 100)
    if (-not (Test-Path -LiteralPath $script:DzLegacyQueriesIniPath)) { return @() }
    $lines = Get-Content -LiteralPath $script:DzLegacyQueriesIniPath -ErrorAction SilentlyContinue
    $parsed = ConvertFrom-DzLegacyQueriesIni -Lines $lines
    $items = New-Object System.Collections.Generic.List[object]
    $idx = $parsed.History.Count
    for ($i = $parsed.History.Count - 1; $i -ge 0; $i--) {
        $h = $parsed.History[$i]
        $items.Add([pscustomobject]@{
                Id           = [int64]$idx
                Timestamp    = ConvertFrom-DzUtcTimestampToLocalText -UtcText $h.ExecutedAtUtc
                ExecutedAtUtc = $h.ExecutedAtUtc
                Server       = $h.Server
                Database     = $h.Database
                Hash         = $h.Hash
                Preview      = $h.Preview
                Result       = $h.ResultSummary
                FullQuery    = $h.FullQuery
                Success      = $h.Success
                RowsAffected = $h.RowsAffected
                DurationMs   = $null
                DurationText = "--"
                ErrorMessage = $h.ErrorMessage
                IsFavorite   = $false
                FavoriteIcon = "☆"
            })
        $idx--
        if ($MaxItems -gt 0 -and $items.Count -ge $MaxItems) { break }
    }
    return $items.ToArray()
}

#endregion

#region Historial de queries y pestañas abiertas

function Get-DzQueryHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query
    )

    $normalized = ($Query -replace '\s+', ' ').Trim().ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hashBytes = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes, 0, 16).Replace('-', '').ToLowerInvariant())
    } finally {
        $sha.Dispose()
    }
}

function Format-DzDurationMs {
    [CmdletBinding()]
    param([AllowNull()]$DurationMs)

    if ($null -eq $DurationMs) { return "--" }
    $ms = [int64]$DurationMs
    if ($ms -lt 0) { return "--" }
    if ($ms -lt 1000) { return "$ms ms" }
    return ("{0:N2} s" -f ($ms / 1000.0))
}

function Add-DzQueryHistoryRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][string]$Database,
        [string]$Server = "",
        [bool]$Success = $true,
        [int64]$RowsAffected = 0,
        [string]$ErrorMessage = "",
        [AllowNull()][Nullable[int64]]$DurationMs = $null,
        [string]$ResultSummary = "",
        [string]$Source = "app"
    )

    if ($script:DzStorageMode -ne 'sqlite') {
        Add-DzLegacyIniQueryToHistory -Query $Query -Database $Database -Server $Server -Success $Success -RowsAffected ([int]$RowsAffected) -ErrorMessage $ErrorMessage
        return $null
    }

    $cleanQuery = ($Query -replace '\s+', ' ').Trim()
    $preview = if ($cleanQuery.Length -gt 120) { $cleanQuery.Substring(0, 117) + "..." } else { $cleanQuery }
    $hash = Get-DzQueryHash -Query $Query
    $summary = if (-not [string]::IsNullOrWhiteSpace($ResultSummary)) {
        $ResultSummary
    } elseif ($Success) {
        if ($RowsAffected -gt 0) { "OK ($RowsAffected filas)" } else { "OK" }
    } else {
        $shortErr = if ($ErrorMessage) { $ErrorMessage.Substring(0, [Math]::Min(50, $ErrorMessage.Length)) } else { "Error" }
        "ERROR: $shortErr"
    }

    $now = Get-DzUtcTimestamp
    $sql = @"
INSERT INTO query_history (
    executed_at, server, database_name, query_hash, preview, full_query,
    success, rows_affected, duration_ms, result_summary, error_message,
    is_favorite, windows_user, machine_name, source
) VALUES (
    @executed_at, @server, @database_name, @query_hash, @preview, @full_query,
    @success, @rows_affected, @duration_ms, @result_summary, @error_message,
    0, @windows_user, @machine_name, @source
);
"@
    Invoke-DzDbNonQuery -CacheStatement -Sql $sql -Parameters @{
        executed_at    = $now
        server         = $Server
        database_name  = $Database
        query_hash     = $hash
        preview        = $preview
        full_query     = $Query
        success        = $(if ($Success) { 1 } else { 0 })
        rows_affected  = $RowsAffected
        duration_ms    = $DurationMs
        result_summary = $summary
        error_message  = $ErrorMessage
        windows_user   = $env:USERNAME
        machine_name   = $env:COMPUTERNAME
        source         = $Source
    } | Out-Null

    return [int64]$script:DzDbInstance.LastInsertRowId
}

function Build-DzQueryHistoryWhereClause {
    [CmdletBinding()]
    param(
        [string]$Search = "",
        [string]$Server = "",
        [string]$Database = "",
        [string]$Status = "All",
        [AllowNull()][Nullable[datetime]]$From = $null,
        [AllowNull()][Nullable[datetime]]$To = $null,
        [bool]$FavoritesOnly = $false,
        [string]$AfterExecutedAt = "",
        [int64]$AfterId = 0
    )

    $clauses = New-Object System.Collections.Generic.List[string]
    $params = @{}

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $clauses.Add("qh.server = @server")
        $params['server'] = $Server
    }
    if (-not [string]::IsNullOrWhiteSpace($Database)) {
        $clauses.Add("qh.database_name = @database")
        $params['database'] = $Database
    }
    if ($Status -eq 'Ok') {
        $clauses.Add("qh.success = 1")
    } elseif ($Status -eq 'Error') {
        $clauses.Add("qh.success = 0")
    }
    if ($FavoritesOnly) {
        $clauses.Add("qh.is_favorite = 1")
    }
    if ($null -ne $From) {
        $clauses.Add("qh.executed_at >= @from_utc")
        $params['from_utc'] = Get-DzUtcTimestamp -DateTime $From
    }
    if ($null -ne $To) {
        $clauses.Add("qh.executed_at <= @to_utc")
        $params['to_utc'] = Get-DzUtcTimestamp -DateTime $To
    }

    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $tokens = @($Search.Trim() -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $canUseFts = $script:DzFts5Enabled -and ($tokens.Count -gt 0) -and (($tokens | Where-Object { $_.Length -lt 3 }).Count -eq 0)
        if ($canUseFts) {
            $ftsParts = foreach ($tok in $tokens) { '"' + $tok.Replace('"', '""') + '"' }
            $clauses.Add("qh.id IN (SELECT rowid FROM query_history_fts WHERE query_history_fts MATCH @fts_query)")
            $params['fts_query'] = ($ftsParts -join ' AND ')
        } else {
            $i = 0
            foreach ($tok in $tokens) {
                $pName = "like_$i"
                $escaped = $tok.Replace('\', '\\').Replace('%', '\%').Replace('_', '\_')
                $clauses.Add("(qh.full_query LIKE @$pName ESCAPE '\' OR qh.preview LIKE @$pName ESCAPE '\' OR COALESCE(qh.server,'') LIKE @$pName ESCAPE '\' OR COALESCE(qh.database_name,'') LIKE @$pName ESCAPE '\')")
                $params[$pName] = "%$escaped%"
                $i++
            }
        }
    }

    if ($AfterId -gt 0) {
        $cursorTs = $AfterExecutedAt
        if ([string]::IsNullOrWhiteSpace($cursorTs)) {
            $cursorTs = [string](Invoke-DzDbScalar -Sql "SELECT executed_at FROM query_history WHERE id = @aid;" -Parameters @{ aid = $AfterId })
        }
        if (-not [string]::IsNullOrWhiteSpace($cursorTs)) {
            $clauses.Add("(qh.executed_at < @after_ts OR (qh.executed_at = @after_ts AND qh.id < @after_id))")
            $params['after_ts'] = $cursorTs
            $params['after_id'] = $AfterId
        } else {
            $clauses.Add("qh.id < @after_id")
            $params['after_id'] = $AfterId
        }
    }

    $whereSql = if ($clauses.Count -gt 0) { "WHERE " + ($clauses -join " AND ") } else { "" }
    return [pscustomobject]@{
        WhereSql   = $whereSql
        Parameters = $params
    }
}

function Get-DzQueryHistoryRecords {
    [CmdletBinding()]
    param(
        [int]$MaxItems = 0,
        [int]$PageSize = 0,
        [string]$Search = "",
        [string]$Server = "",
        [string]$Database = "",
        [ValidateSet('All', 'Ok', 'Error')][string]$Status = 'All',
        [AllowNull()][Nullable[datetime]]$From = $null,
        [AllowNull()][Nullable[datetime]]$To = $null,
        [switch]$FavoritesOnly,
        [string]$AfterExecutedAt = "",
        [int64]$AfterId = 0
    )

    if ($script:DzStorageMode -ne 'sqlite') {
        $limitLegacy = if ($MaxItems -gt 0) { $MaxItems } elseif ($PageSize -gt 0) { $PageSize } else { 100 }
        return (Get-DzLegacyIniQueryHistory -MaxItems $limitLegacy)
    }

    $limit = if ($PageSize -gt 0) {
        $PageSize
    } elseif ($MaxItems -gt 0) {
        $MaxItems
    } else {
        $cfgSize = 200
        [void][int]::TryParse((Get-DzSetting -Section 'history' -Key 'page_size' -Default '200'), [ref]$cfgSize)
        if ($cfgSize -lt 1) { 200 } else { $cfgSize }
    }

    $filter = Build-DzQueryHistoryWhereClause -Search $Search -Server $Server -Database $Database -Status $Status -From $From -To $To -FavoritesOnly ([bool]$FavoritesOnly) -AfterExecutedAt $AfterExecutedAt -AfterId $AfterId
    $filter.Parameters['limit_rows'] = [int64]$limit

    $sql = @"
SELECT
    qh.id, qh.executed_at, qh.server, qh.database_name, qh.query_hash,
    qh.preview, qh.full_query, qh.success, qh.rows_affected, qh.duration_ms,
    qh.result_summary, qh.error_message, qh.is_favorite
FROM query_history qh
$($filter.WhereSql)
ORDER BY qh.executed_at DESC, qh.id DESC
LIMIT @limit_rows;
"@
    $rows = @(Invoke-DzDbQuery -Sql $sql -Parameters $filter.Parameters)
    $list = New-Object System.Collections.Generic.List[object] ($rows.Count)
    foreach ($row in $rows) {
        $isFav = ([int64]$row.is_favorite -ne 0)
        $dur = if ($null -ne $row.duration_ms) { [int64]$row.duration_ms } else { $null }
        $list.Add([pscustomobject]@{
                Id            = [int64]$row.id
                ExecutedAtUtc = [string]$row.executed_at
                Timestamp     = ConvertFrom-DzUtcTimestampToLocalText -UtcText ([string]$row.executed_at)
                Server        = if ($row.server) { [string]$row.server } else { "" }
                Database      = if ($row.database_name) { [string]$row.database_name } else { "" }
                Hash          = [string]$row.query_hash
                Preview       = [string]$row.preview
                Result        = if ($row.result_summary) { [string]$row.result_summary } else { "" }
                FullQuery     = [string]$row.full_query
                Success       = ([int64]$row.success -ne 0)
                RowsAffected  = if ($null -ne $row.rows_affected) { [int64]$row.rows_affected } else { $null }
                DurationMs    = $dur
                DurationText  = Format-DzDurationMs -DurationMs $dur
                ErrorMessage  = if ($row.error_message) { [string]$row.error_message } else { "" }
                IsFavorite    = $isFav
                FavoriteIcon  = if ($isFav) { "★" } else { "☆" }
            })
    }
    return $list.ToArray()
}

function Get-QueryHistoryCount {
    [CmdletBinding()]
    param(
        [string]$Search = "",
        [string]$Server = "",
        [string]$Database = "",
        [ValidateSet('All', 'Ok', 'Error')][string]$Status = 'All',
        [AllowNull()][Nullable[datetime]]$From = $null,
        [AllowNull()][Nullable[datetime]]$To = $null,
        [switch]$FavoritesOnly
    )

    if ($script:DzStorageMode -ne 'sqlite') {
        return @(Get-DzLegacyIniQueryHistory -MaxItems 0).Count
    }

    $filter = Build-DzQueryHistoryWhereClause -Search $Search -Server $Server -Database $Database -Status $Status -From $From -To $To -FavoritesOnly ([bool]$FavoritesOnly)
    $val = Invoke-DzDbScalar -Sql "SELECT COUNT(*) FROM query_history qh $($filter.WhereSql);" -Parameters $filter.Parameters
    return [int64]$val
}

function Get-QueryHistoryFacets {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite') {
        $items = @(Get-DzLegacyIniQueryHistory -MaxItems 0)
        return [pscustomobject]@{
            Servers   = @($items | ForEach-Object { $_.Server } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            Databases = @($items | ForEach-Object { $_.Database } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        }
    }

    $srvRows = Invoke-DzDbQuery -Sql "SELECT DISTINCT server FROM query_history WHERE server IS NOT NULL AND server <> '' ORDER BY server COLLATE NOCASE;"
    $dbRows = Invoke-DzDbQuery -Sql "SELECT DISTINCT database_name FROM query_history WHERE database_name IS NOT NULL AND database_name <> '' ORDER BY database_name COLLATE NOCASE;"

    return [pscustomobject]@{
        Servers   = @($srvRows | ForEach-Object { [string]$_.server })
        Databases = @($dbRows | ForEach-Object { [string]$_.database_name })
    }
}

function Remove-DzQueryHistoryRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Items
    )

    if (-not $Items -or $Items.Count -eq 0) { return $true }
    if ($script:DzStorageMode -ne 'sqlite') { return $false }

    $ids = New-Object System.Collections.Generic.List[int64]
    foreach ($it in $Items) {
        if ($null -ne $it.Id -and [int64]$it.Id -gt 0) {
            $ids.Add([int64]$it.Id)
        }
    }

    Invoke-DzDbTransaction {
        if ($ids.Count -gt 0) {
            $batchSize = 400
            for ($i = 0; $i -lt $ids.Count; $i += $batchSize) {
                $chunk = @()
                $params = @{}
                $end = [Math]::Min($ids.Count, $i + $batchSize)
                for ($j = $i; $j -lt $end; $j++) {
                    $p = "id_$j"
                    $chunk += "@$p"
                    $params[$p] = $ids[$j]
                }
                $inList = $chunk -join ','
                Invoke-DzDbNonQuery -Sql "DELETE FROM query_history WHERE id IN ($inList);" -Parameters $params | Out-Null
            }
        } else {
            foreach ($it in $Items) {
                if ($it.Hash -and $it.ExecutedAtUtc) {
                    Invoke-DzDbNonQuery -Sql "DELETE FROM query_history WHERE executed_at = @ts AND query_hash = @h;" -Parameters @{
                        ts = [string]$it.ExecutedAtUtc
                        h  = [string]$it.Hash
                    } | Out-Null
                }
            }
        }
    }
    return $true
}

function Clear-DzQueryHistoryRecords {
    [CmdletBinding()]
    param([switch]$KeepFavorites)

    if ($script:DzStorageMode -ne 'sqlite') { return $false }
    if ($KeepFavorites) {
        Invoke-DzDbNonQuery -Sql "DELETE FROM query_history WHERE is_favorite = 0;" | Out-Null
    } else {
        Invoke-DzDbNonQuery -Sql "DELETE FROM query_history;" | Out-Null
    }
    return $true
}

function Remove-QueryHistoryDuplicates {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite') { return 0 }
    $sql = @"
DELETE FROM query_history
WHERE is_favorite = 0
  AND id NOT IN (
      SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (PARTITION BY query_hash ORDER BY executed_at DESC, id DESC) AS rn
          FROM query_history
      )
      WHERE rn = 1
  );
"@
    $deleted = Invoke-DzDbNonQuery -Sql $sql
    return [int64]$deleted
}

function Set-QueryFavorite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int64]$Id,
        [Parameter(Mandatory = $true)][bool]$IsFavorite
    )

    if ($script:DzStorageMode -ne 'sqlite') { return $false }
    $changes = Invoke-DzDbNonQuery -CacheStatement -Sql "UPDATE query_history SET is_favorite = @fav WHERE id = @id;" -Parameters @{
        id  = $Id
        fav = $(if ($IsFavorite) { 1 } else { 0 })
    }
    return ($changes -gt 0)
}

function Invoke-QueryHistoryRetention {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite') { return 0 }
    $days = 0
    [void][int]::TryParse((Get-DzSetting -Section 'history' -Key 'retention_days' -Default '0'), [ref]$days)
    if ($days -le 0) { return 0 }

    $cutoff = Get-DzUtcTimestamp -DateTime ([datetime]::UtcNow.AddDays(-$days))
    $deleted = Invoke-DzDbNonQuery -Sql "DELETE FROM query_history WHERE is_favorite = 0 AND executed_at < @cutoff;" -Parameters @{ cutoff = $cutoff }
    return [int64]$deleted
}

function Save-DzOpenQueryTabsData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][array]$Tabs = @()
    )

    if ($script:DzStorageMode -ne 'sqlite') { return $false }

    $tabList = @($Tabs)
    $now = Get-DzUtcTimestamp
    Invoke-DzDbTransaction {
        Invoke-DzDbNonQuery -Sql "DELETE FROM open_query_tabs;" | Out-Null
        $sql = @"
INSERT INTO open_query_tabs (tab_index, title, query_text, is_dirty, is_active, file_path, database_name, server, updated_at)
VALUES (@tab_index, @title, @query_text, @is_dirty, @is_active, @file_path, @database_name, @server, @updated_at);
"@
        foreach ($tab in $tabList) {
            Invoke-DzDbNonQuery -CacheStatement -Sql $sql -Parameters @{
                tab_index     = [int]$tab.TabIndex
                title         = if ($tab.Title) { [string]$tab.Title } else { "Query$([int]$tab.TabIndex + 1)" }
                query_text    = [string]$tab.QueryText
                is_dirty      = $(if ($tab.IsDirty) { 1 } else { 0 })
                is_active     = $(if ($tab.IsActive) { 1 } else { 0 })
                file_path     = if ($tab.FilePath) { [string]$tab.FilePath } else { $null }
                database_name = if ($tab.Database) { [string]$tab.Database } else { $null }
                server        = if ($tab.Server) { [string]$tab.Server } else { $null }
                updated_at    = $now
            } | Out-Null
        }
    }
    return $true
}

function Get-DzOpenQueryTabsData {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite') { return @() }
    $rows = @(Invoke-DzDbQuery -Sql "SELECT tab_index, title, query_text, is_dirty, is_active, file_path, database_name, server FROM open_query_tabs ORDER BY tab_index ASC;")
    $list = New-Object System.Collections.Generic.List[object] ($rows.Count)
    foreach ($row in $rows) {
        $list.Add([pscustomobject]@{
                TabIndex  = [int]$row.tab_index
                Title     = if ($row.title) { [string]$row.title } else { "" }
                QueryText = [string]$row.query_text
                IsDirty   = ([int64]$row.is_dirty -ne 0)
                IsActive  = ([int64]$row.is_active -ne 0)
                FilePath  = if ($row.file_path) { [string]$row.file_path } else { "" }
                Database  = if ($row.database_name) { [string]$row.database_name } else { "" }
                Server    = if ($row.server) { [string]$row.server } else { "" }
            })
    }
    return $list.ToArray()
}

function Start-DzOpenTabsAutosaveTimer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Controls.TabControl]$TabControl,
        [Parameter(Mandatory = $true)][scriptblock]$SaveHandler
    )

    Stop-DzOpenTabsAutosaveTimer
    if ($script:DzStorageMode -ne 'sqlite') { return }

    $seconds = 60
    [void][int]::TryParse((Get-DzSetting -Section 'tabs' -Key 'autosave_seconds' -Default '60'), [ref]$seconds)
    if ($seconds -le 0) { return }

    $script:DzLastSavedTabsSignature = $null
    $tcRef = $TabControl
    $handlerRef = $SaveHandler
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($seconds)
    $timer.Add_Tick({
            try {
                if ($script:DzStorageMode -ne 'sqlite') { return }
                $hasDirty = $false
                $sigBuilder = New-Object System.Text.StringBuilder
                $idx = 0
                foreach ($it in $tcRef.Items) {
                    if ($it -isnot [System.Windows.Controls.TabItem]) { continue }
                    if (-not $it.Tag -or $it.Tag.Type -ne 'QueryTab' -or -not $it.Tag.Editor) { continue }
                    if ($it.Tag.IsDirty) { $hasDirty = $true }
                    $txt = [string]$it.Tag.Editor.Text
                    $isSel = if ($it -eq $tcRef.SelectedItem) { "1" } else { "0" }
                    [void]$sigBuilder.Append("$idx|$($it.Tag.Title)|$isSel|$($txt.Length)|$($txt.GetHashCode());")
                    $idx++
                }
                if (-not $hasDirty) { return }
                $sig = $sigBuilder.ToString()
                if ($sig -eq $script:DzLastSavedTabsSignature) { return }
                if (& $handlerRef -TabControl $tcRef) {
                    $script:DzLastSavedTabsSignature = $sig
                }
            } catch {
                Write-DzStorageDebug "Error en autoguardado de pestañas: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
            }
        }.GetNewClosure())
    $timer.Start()
    $script:DzTabsAutosaveTimer = $timer
}

function Stop-DzOpenTabsAutosaveTimer {
    [CmdletBinding()]
    param()
    if ($script:DzTabsAutosaveTimer) {
        try { $script:DzTabsAutosaveTimer.Stop() } catch { Write-DzStorageDebug "Error deteniendo timer autosave: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow) }
        $script:DzTabsAutosaveTimer = $null
    }
}

#endregion

#region Bitácora de auditoría (audit_log)

function ConvertTo-DzRedactedAuditValue {
    [CmdletBinding()]
    param([AllowNull()]$Value, [int]$Depth = 0)

    if ($null -eq $Value) { return $null }
    if ($Depth -gt 6) { return [string]$Value }

    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $kStr = [string]$key
            if ($kStr -match '(?i)(password|passwd|pwd|token|secret|apikey|api_key|credential|connectionstring)') {
                $out[$kStr] = '***REDACTED***'
            } else {
                $out[$kStr] = ConvertTo-DzRedactedAuditValue -Value $Value[$key] -Depth ($Depth + 1)
            }
        }
        return $out
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [byte[]])) {
        $arr = @()
        foreach ($item in $Value) {
            $arr += ,(ConvertTo-DzRedactedAuditValue -Value $item -Depth ($Depth + 1))
        }
        return $arr
    }

    return $Value
}

function ConvertTo-DzRedactedAuditDetailsJson {
    [CmdletBinding()]
    param([AllowNull()]$Details)

    if ($null -eq $Details) { return $null }
    if ($Details -is [hashtable] -and $Details.Count -eq 0) { return $null }
    try {
        $sanitized = ConvertTo-DzRedactedAuditValue -Value $Details
        return ($sanitized | ConvertTo-Json -Depth 6 -Compress)
    } catch {
        return '{"error":"failed_to_serialize_details"}'
    }
}

function Write-DzAuditEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [string]$Target = "",
        [string]$Status = "INFO",
        [hashtable]$Details = $null,
        [string]$ActionLabel = "",
        [string]$WindowTitle = "",
        [string]$ControlName = ""
    )

    try {
        if ($script:DzStorageMode -eq 'uninitialized') { return }
        $enabled = (Get-DzSetting -Section 'audit' -Key 'enabled' -Default 'true')
        if ($enabled -eq 'false' -or $enabled -eq '0') { return }

        $now = Get-DzUtcTimestamp
        $detailsJson = ConvertTo-DzRedactedAuditDetailsJson -Details $Details
        $winUser = if ($env:USERNAME) { [string]$env:USERNAME } else { [Environment]::UserName }
        $machine = if ($env:COMPUTERNAME) { [string]$env:COMPUTERNAME } else { [Environment]::MachineName }
        $appVer = Get-DzGlobalAppVersion
        $isAdmin = if (Get-DzIsAdministrator) { 1 } else { 0 }

        if ($script:DzStorageMode -eq 'sqlite' -and $script:DzDbInstance -and $script:DzDbInstance.IsOpen) {
            $sql = @"
INSERT INTO audit_log (
    created_at, session_id, event_type, window_title, control_name,
    action_label, target, details, status, windows_user, machine_name,
    app_version, is_admin
) VALUES (
    @created_at, @session_id, @event_type, @window_title, @control_name,
    @action_label, @target, @details, @status, @windows_user, @machine_name,
    @app_version, @is_admin
);
"@
            Invoke-DzDbNonQuery -CacheStatement -Sql $sql -Parameters @{
                created_at   = $now
                session_id   = $script:DzSessionId
                event_type   = $EventType
                window_title = if ($WindowTitle) { $WindowTitle } else { $null }
                control_name = if ($ControlName) { $ControlName } else { $null }
                action_label = if ($ActionLabel) { $ActionLabel } else { $null }
                target       = if ($Target) { $Target } else { $null }
                details      = $detailsJson
                status       = $Status
                windows_user = $winUser
                machine_name = $machine
                app_version  = if ($appVer) { $appVer } else { $null }
                is_admin     = $isAdmin
            } | Out-Null
            return
        }

        # Fallback: acumular en audit-pending.jsonl para sincronizar luego
        $dir = Split-Path -Path $script:DzStoragePendingAuditPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $record = [ordered]@{
            created_at   = $now
            session_id   = $script:DzSessionId
            event_type   = $EventType
            window_title = $WindowTitle
            control_name = $ControlName
            action_label = $ActionLabel
            target       = $Target
            details      = $detailsJson
            status       = $Status
            windows_user = $winUser
            machine_name = $machine
            app_version  = $appVer
            is_admin     = $isAdmin
        }
        $line = ($record | ConvertTo-Json -Compress) + [Environment]::NewLine
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($script:DzStoragePendingAuditPath, $line, $utf8NoBom)
    } catch {
        Write-DzStorageDebug "Error escribiendo bitácora ($EventType): $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
    }
}

function Import-DzPendingAuditFile {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite') { return 0 }
    if (-not (Test-Path -LiteralPath $script:DzStoragePendingAuditPath -PathType Leaf)) { return 0 }

    $lines = Get-Content -LiteralPath $script:DzStoragePendingAuditPath -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines -or $lines.Count -eq 0) {
        Remove-Item -LiteralPath $script:DzStoragePendingAuditPath -Force -ErrorAction SilentlyContinue
        return 0
    }

    $imported = 0
    $sql = @"
INSERT INTO audit_log (
    created_at, session_id, event_type, window_title, control_name,
    action_label, target, details, status, windows_user, machine_name,
    app_version, is_admin
) VALUES (
    @created_at, @session_id, @event_type, @window_title, @control_name,
    @action_label, @target, @details, @status, @windows_user, @machine_name,
    @app_version, @is_admin
);
"@
    Invoke-DzDbTransaction {
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json
                if (-not $obj -or -not $obj.event_type) { continue }
                Invoke-DzDbNonQuery -CacheStatement -Sql $sql -Parameters @{
                    created_at   = if ($obj.created_at) { [string]$obj.created_at } else { Get-DzUtcTimestamp }
                    session_id   = if ($obj.session_id) { [string]$obj.session_id } else { $script:DzSessionId }
                    event_type   = [string]$obj.event_type
                    window_title = if ($obj.window_title) { [string]$obj.window_title } else { $null }
                    control_name = if ($obj.control_name) { [string]$obj.control_name } else { $null }
                    action_label = if ($obj.action_label) { [string]$obj.action_label } else { $null }
                    target       = if ($obj.target) { [string]$obj.target } else { $null }
                    details      = if ($obj.details) { [string]$obj.details } else { $null }
                    status       = if ($obj.status) { [string]$obj.status } else { 'INFO' }
                    windows_user = if ($obj.windows_user) { [string]$obj.windows_user } else { [string]$env:USERNAME }
                    machine_name = if ($obj.machine_name) { [string]$obj.machine_name } else { [string]$env:COMPUTERNAME }
                    app_version  = if ($obj.app_version) { [string]$obj.app_version } else { $null }
                    is_admin     = if ($null -ne $obj.is_admin) { [int]$obj.is_admin } else { 0 }
                } | Out-Null
                $imported++
            } catch {
                Write-DzStorageDebug "Línea audit-pending omitida: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
            }
        }
    }
    Remove-Item -LiteralPath $script:DzStoragePendingAuditPath -Force -ErrorAction SilentlyContinue
    return $imported
}

function Invoke-DzAuditRetention {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite') { return 0 }
    $days = 0
    [void][int]::TryParse((Get-DzSetting -Section 'audit' -Key 'retention_days' -Default '0'), [ref]$days)
    if ($days -le 0) { return 0 }

    $cutoff = Get-DzUtcTimestamp -DateTime ([datetime]::UtcNow.AddDays(-$days))
    $deleted = Invoke-DzDbNonQuery -Sql "DELETE FROM audit_log WHERE created_at < @cutoff;" -Parameters @{ cutoff = $cutoff }
    return [int64]$deleted
}

function Get-DzAuditLog {
    [CmdletBinding()]
    param(
        [int]$Limit = 200,
        [string]$EventType = "",
        [string]$SessionId = ""
    )

    if ($script:DzStorageMode -ne 'sqlite') { return @() }
    $clauses = New-Object System.Collections.Generic.List[string]
    $params = @{ limit_rows = [int64]$Limit }
    if (-not [string]::IsNullOrWhiteSpace($EventType)) {
        $clauses.Add("event_type = @etype")
        $params['etype'] = $EventType
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $clauses.Add("session_id = @sid")
        $params['sid'] = $SessionId
    }
    $whereSql = if ($clauses.Count -gt 0) { "WHERE " + ($clauses -join " AND ") } else { "" }
    $rows = Invoke-DzDbQuery -Sql "SELECT id, created_at, session_id, event_type, window_title, control_name, action_label, target, details, status, windows_user, machine_name, app_version, is_admin FROM audit_log $whereSql ORDER BY id DESC LIMIT @limit_rows;" -Parameters $params
    return $rows
}

function Get-DzWpfElementText {
    [CmdletBinding()]
    param([AllowNull()]$Element, [int]$Depth = 0)

    if ($null -eq $Element -or $Depth -gt 5) { return "" }
    if ($Element -is [string]) { return $Element.Trim() }
    if ($Element -is [System.Windows.Controls.TextBlock]) { return ([string]$Element.Text).Trim() }
    if ($Element -is [System.Windows.Controls.AccessText]) { return ([string]$Element.Text).Replace('_', '').Trim() }
    if ($Element -is [System.Windows.Controls.Panel]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($child in $Element.Children) {
            $t = Get-DzWpfElementText -Element $child -Depth ($Depth + 1)
            if (-not [string]::IsNullOrWhiteSpace($t)) { $parts.Add($t) }
        }
        return ($parts -join ' ').Trim()
    }
    if ($Element -is [System.Windows.Controls.Decorator] -and $Element.Child) {
        return (Get-DzWpfElementText -Element $Element.Child -Depth ($Depth + 1))
    }
    if ($Element -is [System.Windows.Controls.ContentControl] -and $Element.Content) {
        return (Get-DzWpfElementText -Element $Element.Content -Depth ($Depth + 1))
    }
    if ($Element -is [System.Windows.Controls.HeaderedItemsControl] -and $Element.Header) {
        return (Get-DzWpfElementText -Element $Element.Header -Depth ($Depth + 1))
    }
    return ([string]$Element).Trim()
}

function Get-DzExcludedAuditControlSet {
    [CmdletBinding()]
    param()

    if ($null -ne $script:DzExcludedAuditControlsCache) {
        return $script:DzExcludedAuditControlsCache
    }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $raw = Get-DzSetting -Section 'audit' -Key 'excluded_controls' -Default ($script:DzDefaultExcludedAuditControls -join ',')
    foreach ($entry in ($raw -split '[,;]')) {
        $clean = $entry.Trim()
        if (-not [string]::IsNullOrWhiteSpace($clean)) { [void]$set.Add($clean) }
    }
    $script:DzExcludedAuditControlsCache = $set
    return $set
}

function Resolve-DzAuditOwningWindow {
    [CmdletBinding()]
    param([AllowNull()]$Control)

    if ($null -eq $Control) { return $null }
    try {
        $win = [System.Windows.Window]::GetWindow($Control)
        if ($win) { return $win }
    } catch {
        Write-DzStorageDebug "No se pudo obtener ventana directa: $($_.Exception.Message)" ([System.ConsoleColor]::DarkGray)
    }

    if ($Control -is [System.Windows.Controls.MenuItem]) {
        try {
            $curr = $Control
            while ($curr -and -not ($curr -is [System.Windows.Controls.ContextMenu])) {
                $curr = $curr.Parent
            }
            if ($curr -is [System.Windows.Controls.ContextMenu] -and $curr.PlacementTarget) {
                $w2 = [System.Windows.Window]::GetWindow($curr.PlacementTarget)
                if ($w2) { return $w2 }
            }
        } catch {
            Write-DzStorageDebug "Error resolviendo ventana desde ContextMenu: $($_.Exception.Message)" ([System.ConsoleColor]::DarkGray)
        }
    }

    $mainWin = Get-Variable -Name MainWindow -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($mainWin -is [System.Windows.Window]) { return $mainWin }
    return $null
}

function Test-DzAuditShouldIgnoreClick {
    [CmdletBinding()]
    param(
        [AllowNull()]$Control,
        [AllowNull()]$OwningWindow,
        [string]$ControlName = "",
        [string]$ActionLabel = ""
    )

    if ($null -eq $Control) { return $true }

    # Ignorar controles internos de plantillas WPF (scrollbars, flechas de ComboBox/DatePicker, headers de DataGrid, expandir TreeView)
    if ($Control -is [System.Windows.Controls.Primitives.RepeatButton] -or
        $Control -is [System.Windows.Controls.Primitives.DataGridColumnHeader] -or
        $Control -is [System.Windows.Controls.Primitives.Thumb]) {
        return $true
    }
    try {
        $tp = $Control.TemplatedParent
        if ($null -ne $tp) {
            if ($tp -is [System.Windows.Controls.ComboBox] -or
                $tp -is [System.Windows.Controls.DatePicker] -or
                $tp -is [System.Windows.Controls.Primitives.ScrollBar] -or
                $tp -is [System.Windows.Controls.TabControl] -or
                $tp -is [System.Windows.Controls.Expander] -or
                $tp -is [System.Windows.Controls.TreeViewItem] -or
                $tp -is [System.Windows.Controls.Slider]) {
                return $true
            }
        }
    } catch {
        Write-DzStorageDebug "Error verificando TemplatedParent: $($_.Exception.Message)" ([System.ConsoleColor]::DarkGray)
    }

    if ($Control -is [System.Windows.Controls.MenuItem] -and $Control.HasItems) {
        return $true
    }

    if ($OwningWindow) {
        if ($OwningWindow.Tag -eq 'DzNoAudit') { return $true }
        if ($OwningWindow.Tag -is [hashtable] -and $OwningWindow.Tag.NoAudit) { return $true }
    }

    $excludedSet = Get-DzExcludedAuditControlSet
    if (-not [string]::IsNullOrWhiteSpace($ControlName) -and $excludedSet.Contains($ControlName)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($ControlName)) {
        if ($Control -is [System.Windows.Controls.CheckBox] -or $Control -is [System.Windows.Controls.RadioButton]) {
            return $true
        }
        $normLabel = $ActionLabel.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($normLabel) -or ($normLabel -in $script:DzDefaultExcludedAuditLabels)) {
            return $true
        }
    }

    return $false
}

function Invoke-DzAuditUiClickCapture {
    [CmdletBinding()]
    param(
        [AllowNull()]$Control,
        [Parameter(Mandatory = $true)][ValidateSet('UI_CLICK', 'UI_MENU')][string]$EventType
    )

    try {
        $win = Resolve-DzAuditOwningWindow -Control $Control
        $winTitle = if ($win -and $win.Title) { [string]$win.Title } else { "" }
        $ctrlName = if ($Control.Name) { [string]$Control.Name } else { "" }

        $label = ""
        if ($EventType -eq 'UI_MENU') {
            $label = Get-DzWpfElementText -Element $Control.Header
        } else {
            $label = Get-DzWpfElementText -Element $Control.Content
        }
        if ([string]::IsNullOrWhiteSpace($label) -and $Control.ToolTip) {
            $label = Get-DzWpfElementText -Element $Control.ToolTip
        }

        if (Test-DzAuditShouldIgnoreClick -Control $Control -OwningWindow $win -ControlName $ctrlName -ActionLabel $label) {
            return
        }

        $nowUtc = [datetime]::UtcNow
        $debounceKey = "$winTitle|$ctrlName|$label"
        if ($script:DzLastAuditClickAt.ContainsKey($debounceKey)) {
            $elapsedMs = ($nowUtc - $script:DzLastAuditClickAt[$debounceKey]).TotalMilliseconds
            if ($elapsedMs -lt 500) { return }
        }
        $script:DzLastAuditClickAt[$debounceKey] = $nowUtc

        Write-DzAuditEvent -EventType $EventType -WindowTitle $winTitle -ControlName $ctrlName -ActionLabel $label -Status 'INFO'
    } catch {
        Write-DzStorageDebug "Error capturando clic de auditoría: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
    }
}

function Initialize-DzAudit {
    [CmdletBinding()]
    param()

    if ([AppDomain]::CurrentDomain.GetData('DzTools.AuditRegistered')) {
        return
    }
    [AppDomain]::CurrentDomain.SetData('DzTools.AuditRegistered', $true)

    $buttonHandler = [System.Windows.RoutedEventHandler] {
        param($srcControl, $routedArgs)
        $null = $routedArgs
        Invoke-DzAuditUiClickCapture -Control $srcControl -EventType 'UI_CLICK'
    }
    $menuHandler = [System.Windows.RoutedEventHandler] {
        param($srcControl, $routedArgs)
        $null = $routedArgs
        Invoke-DzAuditUiClickCapture -Control $srcControl -EventType 'UI_MENU'
    }

    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.Primitives.ButtonBase],
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        $buttonHandler,
        $true
    )
    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.MenuItem],
        [System.Windows.Controls.MenuItem]::ClickEvent,
        $menuHandler,
        $true
    )
}

#endregion

#region Migración de INIs, respaldos e integridad

function Get-DzUniqueBackupPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PreferredPath)

    if (-not (Test-Path -LiteralPath $PreferredPath)) { return $PreferredPath }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    return "$PreferredPath.$stamp"
}

function Write-DzRedactedToolsIniBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$BackupPath
    )

    $rawLines = Get-Content -LiteralPath $SourcePath -ErrorAction Stop
    $outLines = New-Object System.Collections.Generic.List[string]
    $inSql = $false
    foreach ($line in @($rawLines)) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]\s*$') {
            $inSql = ($matches[1].Trim().ToLowerInvariant() -eq 'sql')
            $outLines.Add($line)
            continue
        }
        if ($inSql -and -not ($trimmed -match '^\s*;') -and $trimmed -match '^([^=]+)=([^|]+)\|(.+)$') {
            $srv = $matches[1].Trim()
            $usr = $matches[2].Trim()
            $outLines.Add("$srv=$usr|***")
            continue
        }
        $outLines.Add($line)
    }

    $tmp = "$BackupPath.tmp"
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($tmp, $outLines, $utf8Bom)
    Move-Item -LiteralPath $tmp -Destination $BackupPath -Force -ErrorAction Stop
}

function Invoke-DzLegacyIniMigration {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite') { return $false }

    $alreadyDone = Invoke-DzDbScalar -Sql "SELECT value FROM app_meta WHERE key = 'migration.ini_completed_at';"
    if (-not [string]::IsNullOrWhiteSpace([string]$alreadyDone)) { return $false }

    $hasToolsIni = Test-Path -LiteralPath $script:DzLegacyToolsIniPath -PathType Leaf
    $hasQueriesIni = Test-Path -LiteralPath $script:DzLegacyQueriesIniPath -PathType Leaf

    $now = Get-DzUtcTimestamp
    if (-not $hasToolsIni -and -not $hasQueriesIni) {
        Invoke-DzDbNonQuery -Sql "INSERT OR REPLACE INTO app_meta(key, value, updated_at) VALUES ('migration.ini_completed_at', @now, @now);" -Parameters @{ now = $now } | Out-Null
        return $false
    }

    $toolsParsed = if ($hasToolsIni) {
        ConvertFrom-DzLegacyToolsIni -Lines (Get-Content -LiteralPath $script:DzLegacyToolsIniPath -ErrorAction Stop)
    } else {
        [pscustomobject]@{ Settings = @(); Connections = @(); SkippedLines = 0 }
    }
    $queriesParsed = if ($hasQueriesIni) {
        ConvertFrom-DzLegacyQueriesIni -Lines (Get-Content -LiteralPath $script:DzLegacyQueriesIniPath -ErrorAction Stop)
    } else {
        [pscustomobject]@{ History = @(); OpenTabs = @(); SkippedHistoryLines = 0; SkippedTabLines = 0 }
    }

    $migratedSettings = 0
    $migratedConns = 0
    $migratedHistory = 0
    $migratedTabs = 0

    Invoke-DzDbTransaction {
        foreach ($s in $toolsParsed.Settings) {
            Invoke-DzDbNonQuery -CacheStatement -Sql @"
INSERT INTO app_settings(section, key, value, updated_at)
VALUES (@sec, @k, @val, @now)
ON CONFLICT(section, key) DO UPDATE SET
    value      = excluded.value,
    updated_at = excluded.updated_at;
"@ -Parameters @{ sec = $s.Section; k = $s.Key; val = $s.Value; now = $now } | Out-Null
            $migratedSettings++
        }

        foreach ($c in $toolsParsed.Connections) {
            Save-DzSqlConnectionRecord -Server $c.Server -User $c.User -Password $c.Password
            $migratedConns++
        }

        foreach ($h in $queriesParsed.History) {
            Invoke-DzDbNonQuery -CacheStatement -Sql @"
INSERT INTO query_history (
    executed_at, server, database_name, query_hash, preview, full_query,
    success, rows_affected, duration_ms, result_summary, error_message,
    is_favorite, windows_user, machine_name, source
) VALUES (
    @executed_at, @server, @database_name, @query_hash, @preview, @full_query,
    @success, @rows_affected, NULL, @result_summary, @error_message,
    0, @windows_user, @machine_name, 'ini-migration'
);
"@ -Parameters @{
                executed_at    = $h.ExecutedAtUtc
                server         = $h.Server
                database_name  = $h.Database
                query_hash     = $h.Hash
                preview        = $h.Preview
                full_query     = $h.FullQuery
                success        = $(if ($h.Success) { 1 } else { 0 })
                rows_affected  = $h.RowsAffected
                result_summary = $h.ResultSummary
                error_message  = $h.ErrorMessage
                windows_user   = $env:USERNAME
                machine_name   = $env:COMPUTERNAME
            } | Out-Null
            $migratedHistory++
        }

        foreach ($t in $queriesParsed.OpenTabs) {
            Invoke-DzDbNonQuery -CacheStatement -Sql @"
INSERT OR REPLACE INTO open_query_tabs (tab_index, title, query_text, is_dirty, is_active, file_path, database_name, server, updated_at)
VALUES (@tab_index, @title, @query_text, @is_dirty, 0, NULL, NULL, NULL, @updated_at);
"@ -Parameters @{
                tab_index  = [int]$t.TabIndex
                title      = $t.Title
                query_text = $t.QueryText
                is_dirty   = $(if ($t.IsDirty) { 1 } else { 0 })
                updated_at = $now
            } | Out-Null
            $migratedTabs++
        }

        $stats = [ordered]@{
            settings        = $migratedSettings
            connections     = $migratedConns
            history         = $migratedHistory
            open_tabs       = $migratedTabs
            skipped_tools   = $toolsParsed.SkippedLines
            skipped_history = $queriesParsed.SkippedHistoryLines
            skipped_tabs    = $queriesParsed.SkippedTabLines
        }
        $statsJson = $stats | ConvertTo-Json -Compress
        Invoke-DzDbNonQuery -Sql "INSERT OR REPLACE INTO app_meta(key, value, updated_at) VALUES ('migration.ini_completed_at', @now, @now);" -Parameters @{ now = $now } | Out-Null
        Invoke-DzDbNonQuery -Sql "INSERT OR REPLACE INTO app_meta(key, value, updated_at) VALUES ('migration.ini_stats', @stats, @now);" -Parameters @{ stats = $statsJson; now = $now } | Out-Null
    }

    # Si la transacción fue exitosa, respaldar y retirar los INIs
    if ($hasQueriesIni) {
        $qBak = Get-DzUniqueBackupPath -PreferredPath "$($script:DzLegacyQueriesIniPath).migrated.bak"
        Move-Item -LiteralPath $script:DzLegacyQueriesIniPath -Destination $qBak -Force -ErrorAction Stop
    }
    if ($hasToolsIni) {
        $tBak = Get-DzUniqueBackupPath -PreferredPath "$($script:DzLegacyToolsIniPath).migrated.bak"
        Write-DzRedactedToolsIniBackup -SourcePath $script:DzLegacyToolsIniPath -BackupPath $tBak
        Remove-Item -LiteralPath $script:DzLegacyToolsIniPath -Force -ErrorAction Stop
    }

    Initialize-DzSettingsCache
    Write-DzAuditEvent -EventType 'MIGRATION_INI' -Target $script:DzStorageDbPath -Status 'OK' -Details @{
        settings        = $migratedSettings
        connections     = $migratedConns
        history         = $migratedHistory
        open_tabs       = $migratedTabs
        skipped_tools   = $toolsParsed.SkippedLines
        skipped_history = $queriesParsed.SkippedHistoryLines
        skipped_tabs    = $queriesParsed.SkippedTabLines
    }
    return $true
}

function New-DzStorageBackup {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite' -or -not $script:DzDbInstance -or -not $script:DzDbInstance.IsOpen) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $script:DzStorageBackupDir)) {
        New-Item -ItemType Directory -Path $script:DzStorageBackupDir -Force | Out-Null
    }
    $stamp = Get-Date -Format "yyyyMMdd"
    $dest = Join-Path $script:DzStorageBackupDir "dztools_$stamp.db"
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    }
    $escaped = "'" + $dest.Replace("'", "''") + "'"
    $script:DzDbInstance.Execute("VACUUM INTO $escaped;", $null, $false) | Out-Null

    $keep = 5
    [void][int]::TryParse((Get-DzSetting -Section 'storage' -Key 'backup_keep' -Default '5'), [ref]$keep)
    if ($keep -gt 0) {
        $all = @(Get-ChildItem -LiteralPath $script:DzStorageBackupDir -Filter "dztools_*.db" -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if ($all.Count -gt $keep) {
            foreach ($old in ($all | Select-Object -Skip $keep)) {
                Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
    return $dest
}

function Invoke-DzStorageWeeklyBackupIfDue {
    [CmdletBinding()]
    param()

    if ($script:DzStorageMode -ne 'sqlite') { return }
    try {
        $lastStr = Invoke-DzDbScalar -Sql "SELECT value FROM app_meta WHERE key = 'storage.last_backup_at';"
        $due = $true
        if (-not [string]::IsNullOrWhiteSpace([string]$lastStr)) {
            try {
                $lastDt = [datetime]::Parse([string]$lastStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                if (([datetime]::UtcNow - $lastDt).TotalDays -lt 7) { $due = $false }
            } catch {
                $due = $true
            }
        }
        if ($due) {
            $path = New-DzStorageBackup
            if ($path) {
                $now = Get-DzUtcTimestamp
                Invoke-DzDbNonQuery -Sql "INSERT OR REPLACE INTO app_meta(key, value, updated_at) VALUES ('storage.last_backup_at', @now, @now);" -Parameters @{ now = $now } | Out-Null
            }
        }
    } catch {
        Write-DzStorageDebug "Respaldo periódico omitido: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
    }
}

function Move-DzCorruptDatabaseAndRecover {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DbPath)

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $corruptTarget = "$DbPath.corrupt-$stamp"
    foreach ($suffix in @("", "-wal", "-shm")) {
        $src = "$DbPath$suffix"
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Move-Item -LiteralPath $src -Destination "$corruptTarget$suffix" -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path -LiteralPath $script:DzStorageBackupDir -PathType Container) {
        $backups = @(Get-ChildItem -LiteralPath $script:DzStorageBackupDir -Filter "dztools_*.db" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        foreach ($bak in $backups) {
            try {
                $candidate = New-Object DzTools.Storage.SqliteDb($bak.FullName)
                try {
                    $chk = [string]($candidate.Scalar("PRAGMA quick_check;", $null))
                    if ($chk -eq 'ok') {
                        $candidate.Close()
                        Copy-Item -LiteralPath $bak.FullName -Destination $DbPath -Force -ErrorAction Stop
                        Write-DzStorageDebug "Base corrupta recuperada desde respaldo: $($bak.Name)" ([System.ConsoleColor]::Yellow)
                        return $true
                    }
                } finally {
                    $candidate.Dispose()
                }
            } catch {
                Write-DzStorageDebug "Respaldo $($bak.Name) inválido: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
            }
        }
    }
    return $false
}

function Set-DzDatabaseRestrictedAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DbPath)

    if (-not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { return }
    try {
        $acl = Get-Acl -LiteralPath $DbPath -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $false)
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $adminsSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $full = [System.Security.AccessControl.FileSystemRights]::FullControl
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        foreach ($sid in @($currentUser, $adminsSid, $systemSid)) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, $full, $allow)
            $acl.SetAccessRule($rule)
        }
        Set-Acl -LiteralPath $DbPath -AclObject $acl -ErrorAction Stop
    } catch {
        Write-DzStorageDebug "No se pudo ajustar ACL de ${DbPath}: $($_.Exception.Message)" ([System.ConsoleColor]::DarkGray)
    }
}

#endregion

#region Inicialización y cierre

function Get-DzStorageMode {
    [CmdletBinding()]
    param()
    return $script:DzStorageMode
}

function Get-DzStorageLastError {
    [CmdletBinding()]
    param()
    return $script:DzStorageLastError
}

function Get-DzStorageDbPath {
    [CmdletBinding()]
    param()
    return $script:DzStorageDbPath
}

function Initialize-DzStorage {
    [CmdletBinding()]
    param(
        [string]$BaseDir = "C:\Temp\dztools",
        [string]$RuntimeDir = "",
        [string]$LocalRuntimeZipPath = "",
        [switch]$NoDownload,
        [switch]$ForceReinit
    )

    if ($ForceReinit) {
        Close-DzStorage
    } elseif ($script:DzStorageMode -eq 'sqlite' -and $script:DzDbInstance -and $script:DzDbInstance.IsOpen) {
        return $true
    }

    $script:DzStorageBaseDir = $BaseDir
    $script:DzStorageDbPath = Join-Path $BaseDir "dztools.db"
    $script:DzStorageBackupDir = Join-Path $BaseDir "backups\db"
    $script:DzStoragePendingAuditPath = Join-Path $BaseDir "audit-pending.jsonl"
    $script:DzLegacyToolsIniPath = Join-Path $BaseDir "dztools.ini"
    $script:DzLegacyQueriesIniPath = Join-Path $BaseDir "Queries.ini"
    $script:DzStorageLastError = $null

    if (-not (Test-Path -LiteralPath $BaseDir)) {
        New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
    }

    try {
        if (-not [Environment]::Is64BitProcess) {
            throw "El runtime SQLite requiere PowerShell de 64 bits."
        }
        if (-not (Get-Command Initialize-DzSqliteRuntime -ErrorAction SilentlyContinue)) {
            throw "El módulo SqliteOps no está disponible."
        }

        $initParams = @{}
        if (-not [string]::IsNullOrWhiteSpace($RuntimeDir)) { $initParams['RuntimeDir'] = $RuntimeDir }
        if (-not [string]::IsNullOrWhiteSpace($LocalRuntimeZipPath)) { $initParams['LocalZipPath'] = $LocalRuntimeZipPath }
        if ($NoDownload) { $initParams['NoDownload'] = $true }

        $dllPath = Initialize-DzSqliteRuntime @initParams
        Import-DzStorageNativeType -DllPath $dllPath

        $dbAlreadyExisted = (Test-Path -LiteralPath $script:DzStorageDbPath -PathType Leaf) -and ((Get-Item -LiteralPath $script:DzStorageDbPath).Length -gt 0)
        $db = New-Object DzTools.Storage.SqliteDb($script:DzStorageDbPath)
        if ($dbAlreadyExisted) {
            $check = ""
            try { $check = [string]($db.Scalar("PRAGMA quick_check;", $null)) } catch { $check = "error" }
            if ($check -ne 'ok') {
                $db.Close()
                $db.Dispose()
                [void](Move-DzCorruptDatabaseAndRecover -DbPath $script:DzStorageDbPath)
                $db = New-Object DzTools.Storage.SqliteDb($script:DzStorageDbPath)
            }
        }

        $script:DzDbInstance = $db
        $script:DzStorageMode = 'sqlite'

        Update-DzStorageSchema
        Initialize-DzSettingsCache
        [void](Invoke-DzLegacyIniMigration)
        [void](Import-DzPendingAuditFile)
        [void](Invoke-QueryHistoryRetention)
        [void](Invoke-DzAuditRetention)
        Invoke-DzStorageWeeklyBackupIfDue
        Set-DzDatabaseRestrictedAcl -DbPath $script:DzStorageDbPath

        return $true
    } catch {
        $script:DzStorageLastError = $_.Exception.Message
        Write-DzStorageDebug "Iniciando en modo fallback INI. Motivo: $($script:DzStorageLastError)" ([System.ConsoleColor]::Yellow)
        if ($script:DzDbInstance) {
            try { $script:DzDbInstance.Close(); $script:DzDbInstance.Dispose() } catch { Write-DzStorageDebug "Error cerrando instancia fallida: $($_.Exception.Message)" ([System.ConsoleColor]::DarkGray) }
            $script:DzDbInstance = $null
        }
        $script:DzStorageMode = 'fallback'
        Initialize-DzLegacyIniFiles
        return $false
    }
}

function Close-DzStorage {
    [CmdletBinding()]
    param()

    Stop-DzOpenTabsAutosaveTimer
    if ($script:DzDbInstance) {
        try {
            if ($script:DzDbInstance.IsOpen) {
                try { $script:DzDbInstance.Execute("PRAGMA wal_checkpoint(TRUNCATE);", $null, $false) | Out-Null } catch { Write-DzStorageDebug "Checkpoint al cerrar omitido: $($_.Exception.Message)" ([System.ConsoleColor]::DarkGray) }
                try { $script:DzDbInstance.Execute("PRAGMA optimize;", $null, $false) | Out-Null } catch { Write-DzStorageDebug "Optimize al cerrar omitido: $($_.Exception.Message)" ([System.ConsoleColor]::DarkGray) }
                $script:DzDbInstance.Close()
            }
            $script:DzDbInstance.Dispose()
        } catch {
            Write-DzStorageDebug "Error cerrando DzStorage: $($_.Exception.Message)" ([System.ConsoleColor]::Yellow)
        } finally {
            $script:DzDbInstance = $null
        }
    }
    $script:DzSettingsCache.Clear()
    $script:DzExcludedAuditControlsCache = $null
    $script:DzStorageMode = 'uninitialized'
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-DzStorage',
    'Close-DzStorage',
    'Get-DzStorageMode',
    'Get-DzStorageLastError',
    'Get-DzStorageDbPath',
    'Get-DzSetting',
    'Set-DzSetting',
    'Get-DzSettingsSection',
    'Get-DzLegacyIniSectionMap',
    'Update-DzLegacyIniSetting',
    'Protect-DzSecretString',
    'Unprotect-DzSecretBytes',
    'Save-DzSqlConnectionRecord',
    'Get-DzSqlConnectionRecords',
    'Remove-DzSqlConnection',
    'Update-DzSqlConnectionUsage',
    'Get-DzQueryHash',
    'Format-DzDurationMs',
    'Add-DzQueryHistoryRecord',
    'Get-DzQueryHistoryRecords',
    'Get-QueryHistoryCount',
    'Get-QueryHistoryFacets',
    'Remove-DzQueryHistoryRecords',
    'Clear-DzQueryHistoryRecords',
    'Remove-QueryHistoryDuplicates',
    'Set-QueryFavorite',
    'Invoke-QueryHistoryRetention',
    'Save-DzOpenQueryTabsData',
    'Get-DzOpenQueryTabsData',
    'Start-DzOpenTabsAutosaveTimer',
    'Stop-DzOpenTabsAutosaveTimer',
    'Initialize-DzAudit',
    'Write-DzAuditEvent',
    'Get-DzAuditLog',
    'Invoke-DzAuditRetention',
    'ConvertFrom-DzLegacyToolsIni',
    'ConvertFrom-DzLegacyQueriesIni',
    'Invoke-DzLegacyIniMigration',
    'New-DzStorageBackup',
    'Invoke-DzDbQuery',
    'Invoke-DzDbNonQuery',
    'Invoke-DzDbScalar',
    'Invoke-DzDbTransaction'
)
