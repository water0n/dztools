# tests/DzStorage.Tests.ps1

Describe "DzStorage - Migración de INIs a SQLite, DPAPI, Historial y Bitácora" {
    BeforeDiscovery {
        $script:ProjectRootDisc = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:LocalRuntimeZipDisc = Join-Path $script:ProjectRootDisc "sqlite-dll-win-x64-3530200.zip"
        $script:CanRunSqlite = [Environment]::Is64BitProcess -and (Test-Path -LiteralPath $script:LocalRuntimeZipDisc -PathType Leaf)
    }

    BeforeAll {
        $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:SrcPath = Join-Path $script:ProjectRoot "src"
        $script:ModulesPath = Join-Path $script:SrcPath "modules"
        $script:LocalRuntimeZip = Join-Path $script:ProjectRoot "sqlite-dll-win-x64-3530200.zip"
        $script:SharedRuntimeDir = Join-Path ([System.IO.Path]::GetTempPath()) "dztools_pester_sqlite_rt"

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
        Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

        Import-Module (Join-Path $script:ModulesPath "Utilities.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "GUI.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "SqliteOps.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "DzStorage.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "QueriesPad.psm1") -Force -DisableNameChecking

        $script:CanRunSqlite = [Environment]::Is64BitProcess -and (Test-Path -LiteralPath $script:LocalRuntimeZip -PathType Leaf)
    }

    AfterEach {
        Close-DzStorage
    }

    Context "Parsers puros de INI legado (sin DLL)" {
        It "Parsea dztools.ini completo con secciones desarrollo, UI y sql" {
            $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("Pass123!"))
            $lines = @(
                "; Comentario",
                "[desarrollo]",
                "debug=true",
                "",
                "[UI]",
                "mode=dark",
                "stacked_results=false",
                "",
                "[sql]",
                ("localhost\SQLEXPRESS=sa|" + $b64),
                "linea_corrupta_sin_igual",
                "srv_bad_b64=sa|@@@no_base64@@@"
            )
            $res = ConvertFrom-DzLegacyToolsIni -Lines $lines
            $res.Settings.Count | Should -Be 3
            ($res.Settings | Where-Object { $_.Section -eq 'dev' -and $_.Key -eq 'debug' }).Value | Should -Be 'true'
            ($res.Settings | Where-Object { $_.Section -eq 'ui' -and $_.Key -eq 'mode' }).Value | Should -Be 'dark'
            ($res.Settings | Where-Object { $_.Section -eq 'ui' -and $_.Key -eq 'stacked_results' }).Value | Should -Be 'false'
            $res.Connections.Count | Should -Be 1
            $res.Connections[0].Server | Should -Be 'localhost\SQLEXPRESS'
            $res.Connections[0].User | Should -Be 'sa'
            $res.Connections[0].Password | Should -Be 'Pass123!'
            $res.SkippedLines | Should -Be 2
        }

        It "Parsea Queries.ini con formatos de 6 y 7 columnas, QueriesOpen y líneas corruptas" {
            $q1B64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("SELECT 1"))
            $q2B64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("SELECT * FROM Clientes"))
            $tabB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("SELECT TOP 10 * FROM Ventas"))
            $lines = @(
                "[QueriesHistory]",
                "; comentario",
                "2026-01-10 08:30:00|TiendaDb|abc123|SELECT 1|OK (1 filas)|$q1B64",
                "2026-01-11 09:45:10|.\NS|TiendaDb|def456|SELECT * FROM Clientes|ERROR: Invalid object|$q2B64",
                "linea|invalida",
                "2026-01-11 10:00:00|.\NS|TiendaDb|bad|prev|OK|***NO_B64***",
                "[QueriesOpen]",
                "0|Query1|1|$tabB64",
                "bad|tab"
            )
            $res = ConvertFrom-DzLegacyQueriesIni -Lines $lines
            $res.History.Count | Should -Be 2
            $res.History[0].Server | Should -Be ''
            $res.History[0].RowsAffected | Should -Be 1
            $res.History[0].Success | Should -BeTrue
            $res.History[1].Server | Should -Be '.\NS'
            $res.History[1].Success | Should -BeFalse
            $res.History[1].ErrorMessage | Should -Be 'Invalid object'
            $res.SkippedHistoryLines | Should -Be 2
            $res.OpenTabs.Count | Should -Be 1
            $res.OpenTabs[0].IsDirty | Should -BeTrue
            $res.OpenTabs[0].QueryText | Should -Be 'SELECT TOP 10 * FROM Ventas'
            $res.SkippedTabLines | Should -Be 1
        }
    }

    Context "Cifrado DPAPI por servidor (sin DLL)" {
        It "Realiza round-trip correcto y falla cuando cambia el servidor (entropía)" {
            $cipher = Protect-DzSecretString -PlainText 'ClaveSuperSegura#2026' -Server '.\NationalSoft'
            $cipher | Should -BeOfType [byte]
            $ok = Unprotect-DzSecretBytes -CipherBytes $cipher -Server '.\nationalsoft' -Format 'dpapi-cu-v1'
            $ok.Success | Should -BeTrue
            $ok.PlainText | Should -Be 'ClaveSuperSegura#2026'

            $wrong = Unprotect-DzSecretBytes -CipherBytes $cipher -Server '.\OtroServidor' -Format 'dpapi-cu-v1'
            $wrong.Success | Should -BeFalse
            $wrong.PlainText | Should -Be ''
        }
    }

    Context "Núcleo SQLite, migración, historial, pestañas y bitácora" {
        It "Inicializa dztools.db nuevo con esquema v1, WAL, FTS5 y binding tipado" -Skip:(-not $script:CanRunSqlite) {
            $baseDir = Join-Path $TestDrive "core_db"
            $ok = Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $script:SharedRuntimeDir -LocalRuntimeZipPath $script:LocalRuntimeZip -ForceReinit
            $ok | Should -BeTrue
            Get-DzStorageMode | Should -Be 'sqlite'
            Test-Path (Join-Path $baseDir "dztools.db") | Should -BeTrue

            [int](Invoke-DzDbScalar -Sql "PRAGMA user_version;") | Should -Be 1
            [string](Invoke-DzDbScalar -Sql "PRAGMA journal_mode;") | Should -Be 'wal'
            [int](Invoke-DzDbScalar -Sql "PRAGMA foreign_keys;") | Should -Be 1

            $blob = [byte[]]@(1, 2, 3, 255)
            Invoke-DzDbNonQuery -Sql "INSERT INTO sql_connections (server, username, password_enc, password_format, last_database, created_at, updated_at) VALUES (@s, @u, @p, 'dpapi-cu-v1', @db, @n, @n);" -Parameters @{
                s  = 'srv_unicode_ñ_🚀'
                u  = 'sa'
                p  = $blob
                db = $null
                n  = '2026-01-01T00:00:00.000Z'
            } | Out-Null

            $row = @(Invoke-DzDbQuery -Sql "SELECT server, password_enc, last_database FROM sql_connections WHERE server = @s;" -Parameters @{ s = 'srv_unicode_ñ_🚀' })
            $row.Count | Should -Be 1
            $row[0].server | Should -Be 'srv_unicode_ñ_🚀'
            $row[0].last_database | Should -BeNullOrEmpty
            $row[0].password_enc.Length | Should -Be 4
            $row[0].password_enc[3] | Should -Be 255

            # Rollback en transacción
            {
                Invoke-DzDbTransaction {
                    Invoke-DzDbNonQuery -Sql "INSERT INTO app_meta(key, value, updated_at) VALUES ('tx_test', '1', '2026-01-01T00:00:00.000Z');" | Out-Null
                    throw "Fallo simulado"
                }
            } | Should -Throw
            (Invoke-DzDbScalar -Sql "SELECT value FROM app_meta WHERE key = 'tx_test';") | Should -BeNullOrEmpty
        }

        It "Detecta corrupción de sqlite3.dll y lo restaura desde el zip local" -Skip:(-not $script:CanRunSqlite) {
            $isolatedRt = Join-Path $TestDrive "rt_verify"
            $dll = Initialize-DzSqliteRuntime -RuntimeDir $isolatedRt -LocalZipPath $script:LocalRuntimeZip -NoDownload
            Test-Path -LiteralPath "$dll.sha256" | Should -BeTrue
            Test-DzSqliteRuntimeAvailable -RuntimeDir $isolatedRt | Should -BeTrue

            # Alterar sidecar .sha256 sin tocar el DLL bloqueado en memoria para probar detección
            Set-Content -LiteralPath "$dll.sha256" -Value ("0" * 64) -Encoding UTF8
            Test-DzSqliteRuntimeAvailable -RuntimeDir $isolatedRt | Should -BeFalse
        }

        It "Delega settings en Utilities.psm1 con alias desarrollo y dev, y marca needs_reentry ante ciphertext corrupto" -Skip:(-not $script:CanRunSqlite) {
            $baseDir = Join-Path $TestDrive "settings_dpapi"
            Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $script:SharedRuntimeDir -LocalRuntimeZipPath $script:LocalRuntimeZip -ForceReinit | Out-Null

            Set-DzUiMode -Mode 'dark'
            Get-DzUiMode | Should -Be 'dark'
            Set-DzDebugPreference -Enabled $true
            Get-DzDebugPreference | Should -BeTrue
            Set-DzStackedResults -Enabled $false
            Get-DzStackedResults | Should -BeFalse

            Update-DzIniSetting -Section 'desarrollo' -Key 'debug' -Value 'false'
            (Get-DzIniSectionMap -Section 'desarrollo')['debug'] | Should -Be 'false'

            Save-DzSqlConnection -Server '.\NS1' -User 'admin' -Password 'MiClave#1'
            $conn = Get-DzSavedSqlConnection -Server '.\ns1'
            $conn | Should -Not -BeNullOrEmpty
            $conn.User | Should -Be 'admin'
            $conn.Password | Should -Be 'MiClave#1'
            $conn.NeedsReentry | Should -BeFalse

            # Corromper ciphertext DPAPI y verificar manejo seguro + auditoría
            Invoke-DzDbNonQuery -Sql "UPDATE sql_connections SET password_enc = @bad WHERE server = '.\NS1';" -Parameters @{ bad = ([byte[]]@(9, 8, 7, 6, 5)) } | Out-Null
            $broken = Get-DzSavedSqlConnection -Server '.\NS1'
            $broken.Password | Should -Be ''
            $broken.NeedsReentry | Should -BeTrue
            $auditCred = @(Get-DzAuditLog -EventType 'CONFIG_CREDENTIAL_UNREADABLE')
            $auditCred.Count | Should -Be 1
        }

        It "Almacena > 100 queries, soporta paginación keyset, búsqueda FTS/LIKE, favoritos, duplicados y retención" -Skip:(-not $script:CanRunSqlite) {
            $baseDir = Join-Path $TestDrive "history_perf"
            Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $script:SharedRuntimeDir -LocalRuntimeZipPath $script:LocalRuntimeZip -ForceReinit | Out-Null

            Invoke-DzDbTransaction {
                for ($i = 1; $i -le 450; $i++) {
                    $db = if ($i % 2 -eq 0) { 'TiendaA' } else { 'TiendaB' }
                    $srv = if ($i % 3 -eq 0) { '.\SRV1' } else { '.\SRV2' }
                    $ok = ($i % 10 -ne 0)
                    $err = if ($ok) { '' } else { "Error detallado muy largo numero $i que supera cincuenta caracteres sin truncarse" }
                    $q = if ($i -eq 440) { "SELECT * FROM ClientesEspeciales WHERE Codigo = $i" } else { "SELECT TOP $i * FROM Ventas WHERE Folio = $i" }
                    Add-QueryToHistory -Query $q -Database $db -Server $srv -Success $ok -RowsAffected $i -ErrorMessage $err -DurationMs ($i * 2) | Out-Null
                }
            }

            (Get-QueryHistoryCount) | Should -Be 450

            $page1 = @(Get-QueryHistory -PageSize 200)
            $page1.Count | Should -Be 200
            $page2 = @(Get-QueryHistory -PageSize 200 -AfterId $page1[-1].Id)
            $page2.Count | Should -Be 200
            $page3 = @(Get-QueryHistory -PageSize 200 -AfterId $page2[-1].Id)
            $page3.Count | Should -Be 50
            ($page1[-1].Id -gt $page2[0].Id) | Should -BeTrue

            # Error completo sin truncar
            $errRows = @(Get-QueryHistory -Status 'Error' -PageSize 10)
            $errRows[0].ErrorMessage.Length | Should -BeGreaterThan 50

            # Búsqueda >= 3 chars (FTS5) y < 3 chars (LIKE)
            $ftsHits = @(Get-QueryHistory -Search 'ClientesEspeciales')
            $ftsHits.Count | Should -Be 1
            $ftsHits[0].DurationText | Should -Be '880 ms'

            $likeHits = @(Get-QueryHistory -Search '44')
            $likeHits.Count | Should -BeGreaterThan 0

            # Facetas y filtros
            $facets = Get-QueryHistoryFacets
            $facets.Servers | Should -Contain '.\SRV1'
            $facets.Databases | Should -Contain 'TiendaA'

            # Favoritos y eliminación de duplicados
            $dupId1 = Add-QueryToHistory -Query "SELECT   *  FROM   Productos" -Database 'TiendaA' -Server '.\SRV1' -Success $true -RowsAffected 3 -DurationMs 15
            $dupId2 = Add-QueryToHistory -Query "select * from productos" -Database 'TiendaA' -Server '.\SRV1' -Success $true -RowsAffected 4 -DurationMs 12
            Set-QueryFavorite -Id $dupId1 -IsFavorite $true | Should -BeTrue
            $deletedDups = Remove-QueryHistoryDuplicates
            $deletedDups | Should -Be 0
            # Agregamos un tercer duplicado no favorito para comprobar que solo borra duplicados no favoritos
            $dupId3 = Add-QueryToHistory -Query "SELECT * FROM Productos" -Database 'TiendaA' -Server '.\SRV1' -Success $true -RowsAffected 5 -DurationMs 10
            (Remove-QueryHistoryDuplicates) | Should -Be 1
            @(Get-QueryHistory -FavoritesOnly).Count | Should -Be 1

            # Clear manteniendo favoritas
            Clear-QueryHistory -KeepFavorites | Should -BeTrue
            (Get-QueryHistoryCount) | Should -Be 1

            # Retención por días conserva favoritas y elimina antiguas no favoritas
            $oldNonFav = Add-QueryToHistory -Query "SELECT 999" -Database 'TiendaA' -Server '.\SRV1'
            Invoke-DzDbNonQuery -Sql "UPDATE query_history SET executed_at = '2020-01-01T00:00:00.000Z' WHERE id = @id;" -Parameters @{ id = $oldNonFav } | Out-Null
            Set-DzSetting -Section 'history' -Key 'retention_days' -Value '30'
            (Invoke-QueryHistoryRetention) | Should -Be 1
            (Get-QueryHistoryCount) | Should -Be 1
        }

        It "Guarda y restaura pestañas abiertas conservando FilePath, Database e IsActive" -Skip:(-not $script:CanRunSqlite) {
            $baseDir = Join-Path $TestDrive "tabs_restore"
            Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $script:SharedRuntimeDir -LocalRuntimeZipPath $script:LocalRuntimeZip -ForceReinit | Out-Null

            $sqlFile = Join-Path $TestDrive "mi_script.sql"
            Set-Content -LiteralPath $sqlFile -Value "SELECT * FROM Facturas;" -Encoding UTF8

            $tc1 = New-Object System.Windows.Controls.TabControl
            $t1 = Open-SqlFileInTab -TabControl $tc1 -FilePath $sqlFile
            $t1.Tag.Database = 'VentasDb'
            $t2 = New-QueryTab -TabControl $tc1
            Set-SqlEditorText -Editor $t2.Tag.Editor -Text "SELECT GETDATE();"
            $t2.Tag.Database = 'MasterDb'
            $tc1.SelectedItem = $t1

            Save-OpenQueryTabs -TabControl $tc1 | Should -BeTrue

            $tc2 = New-Object System.Windows.Controls.TabControl
            $restored = Restore-OpenQueryTabs -TabControl $tc2
            $restored | Should -Be 2
            $tc2.SelectedItem.Tag.FilePath | Should -Be $sqlFile
            $tc2.SelectedItem.Tag.Database | Should -Be 'VentasDb'
            (Get-SqlEditorText -Editor $tc2.SelectedItem.Tag.Editor).Trim() | Should -Be 'SELECT * FROM Facturas;'
        }

        It "Audita eventos con redacción de secretos, filtra ruido y sincroniza audit-pending.jsonl tras fallback" -Skip:(-not $script:CanRunSqlite) {
            $baseDir = Join-Path $TestDrive "audit_fallback"
            # Simular primer arranque sin runtime (NoDownload en carpeta vacía) -> fallback
            $emptyRt = Join-Path $TestDrive "empty_rt"
            $okFallback = Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $emptyRt -NoDownload -ForceReinit
            $okFallback | Should -BeFalse
            Get-DzStorageMode | Should -Be 'fallback'

            Write-DzAuditEvent -EventType 'WIN_USER_CREATE' -Target 'soporte' -Status 'OK' -Details @{ password = 'Secret'; token = 'tk123'; group = 'Administradores' }
            $pendingPath = Join-Path $baseDir "audit-pending.jsonl"
            Test-Path -LiteralPath $pendingPath | Should -BeTrue
            $pendingRaw = Get-Content -LiteralPath $pendingPath -Raw
            $pendingRaw | Should -Not -Match 'Secret'
            $pendingRaw | Should -Not -Match 'tk123'
            $pendingRaw | Should -Match '\*\*\*REDACTED\*\*\*'

            # Siguiente arranque con runtime disponible -> importa audit-pending.jsonl
            $okSqlite = Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $script:SharedRuntimeDir -LocalRuntimeZipPath $script:LocalRuntimeZip -ForceReinit
            $okSqlite | Should -BeTrue
            Test-Path -LiteralPath $pendingPath | Should -BeFalse

            $logs = @(Get-DzAuditLog -EventType 'WIN_USER_CREATE')
            $logs.Count | Should -Be 1
            $logs[0].target | Should -Be 'soporte'
            $logs[0].details | Should -Match '\*\*\*REDACTED\*\*\*'

            # Filtro anti-ruido de clics WPF
            InModuleScope DzStorage {
                $noAuditWin = New-Object System.Windows.Window
                $noAuditWin.Tag = 'DzNoAudit'
                $btn1 = New-Object System.Windows.Controls.Button
                $btn1.Name = 'btnReal'
                $btn1.Content = 'Ejecutar'
                (Test-DzAuditShouldIgnoreClick -Control $btn1 -OwningWindow $noAuditWin -ControlName 'btnReal' -ActionLabel 'Ejecutar') | Should -BeTrue

                $normalWin = New-Object System.Windows.Window
                (Test-DzAuditShouldIgnoreClick -Control $btn1 -OwningWindow $normalWin -ControlName 'btnClose' -ActionLabel 'Cerrar') | Should -BeTrue
                (Test-DzAuditShouldIgnoreClick -Control $btn1 -OwningWindow $normalWin -ControlName '' -ActionLabel '×') | Should -BeTrue
                (Test-DzAuditShouldIgnoreClick -Control $btn1 -OwningWindow $normalWin -ControlName 'btnReal' -ActionLabel 'Ejecutar') | Should -BeFalse
            }
        }

        It "Migra dztools.ini y Queries.ini atómicamente, redacta contraseñas del backup y es idempotente" -Skip:(-not $script:CanRunSqlite) {
            $baseDir = Join-Path $TestDrive "full_migration"
            New-Item -ItemType Directory -Path $baseDir -Force | Out-Null

            $passB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('SqlSecret!'))
            @"
[desarrollo]
debug=true

[UI]
mode=dark
stacked_results=false

[sql]
.\NationalSoft=sa|$passB64
"@ | Set-Content -LiteralPath (Join-Path $baseDir "dztools.ini") -Encoding UTF8

            $qB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('SELECT COUNT(*) FROM Productos'))
            $tB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('SELECT 123'))
            @"
[QueriesHistory]
2026-02-01 12:00:00|.\NationalSoft|Tienda|h123|SELECT COUNT(*) FROM Productos|OK (1 filas)|$qB64

[QueriesOpen]
0|Query1|0|$tB64
"@ | Set-Content -LiteralPath (Join-Path $baseDir "Queries.ini") -Encoding UTF8

            $ok = Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $script:SharedRuntimeDir -LocalRuntimeZipPath $script:LocalRuntimeZip -ForceReinit
            $ok | Should -BeTrue

            (Get-DzUiMode) | Should -Be 'dark'
            (Get-DzDebugPreference) | Should -BeTrue
            (Get-DzStackedResults) | Should -BeFalse

            $c = Get-DzSavedSqlConnection -Server '.\NationalSoft'
            $c.User | Should -Be 'sa'
            $c.Password | Should -Be 'SqlSecret!'

            $h = @(Get-QueryHistory)
            $h.Count | Should -Be 1
            $h[0].FullQuery | Should -Be 'SELECT COUNT(*) FROM Productos'

            $tabs = @(Get-DzOpenQueryTabsData)
            $tabs.Count | Should -Be 1
            $tabs[0].QueryText | Should -Be 'SELECT 123'

            Test-Path -LiteralPath (Join-Path $baseDir "dztools.ini") | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $baseDir "Queries.ini") | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $baseDir "Queries.ini.migrated.bak") | Should -BeTrue
            $bakIni = Get-Content -LiteralPath (Join-Path $baseDir "dztools.ini.migrated.bak") -Raw
            $bakIni | Should -Match 'sa\|\*\*\*'
            $bakIni | Should -Not -Match ([regex]::Escape($passB64))

            # Idempotencia al reiniciar
            Close-DzStorage
            Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $script:SharedRuntimeDir -LocalRuntimeZipPath $script:LocalRuntimeZip -ForceReinit | Should -BeTrue
            (Get-QueryHistoryCount) | Should -Be 1
            @(Get-DzAuditLog -EventType 'MIGRATION_INI').Count | Should -Be 1
        }

        It "Mantiene los INIs intactos si ocurre un error durante la migración" -Skip:(-not $script:CanRunSqlite) {
            $baseDir = Join-Path $TestDrive "rollback_migration"
            New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
            @"
[desarrollo]
debug=true
"@ | Set-Content -LiteralPath (Join-Path $baseDir "dztools.ini") -Encoding UTF8

            InModuleScope DzStorage -Parameters @{ BaseDir = $baseDir; RtDir = $script:SharedRuntimeDir; ZipPath = $script:LocalRuntimeZip } {
                param($BaseDir, $RtDir, $ZipPath)
                Mock ConvertFrom-DzLegacyToolsIni { throw "Error simulado de migración" }
                $ok = Initialize-DzStorage -BaseDir $BaseDir -RuntimeDir $RtDir -LocalRuntimeZipPath $ZipPath -ForceReinit
                $ok | Should -BeFalse
                (Get-DzStorageMode) | Should -Be 'fallback'
            }

            Test-Path -LiteralPath (Join-Path $baseDir "dztools.ini") | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $baseDir "dztools.ini.migrated.bak") | Should -BeFalse
        }

        It "Crea respaldos rotativos con VACUUM INTO y expone runtime en C:\Temp\dztools\runtime" -Skip:(-not $script:CanRunSqlite) {
            (Get-DzSqliteRuntimePath) | Should -Be 'C:\Temp\dztools\runtime\sqlite3.dll'

            $baseDir = Join-Path $TestDrive "backup_vacuum"
            Initialize-DzStorage -BaseDir $baseDir -RuntimeDir $script:SharedRuntimeDir -LocalRuntimeZipPath $script:LocalRuntimeZip -ForceReinit | Out-Null
            $bak = New-DzStorageBackup
            $bak | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $bak -PathType Leaf | Should -BeTrue
        }

        It "Carga el XAML de Show-QueryHistoryWindow sin errores en Light y Dark" {
            $padContent = Get-Content (Join-Path $script:ModulesPath "QueriesPad.psm1") -Raw
            $m = [regex]::Match($padContent, '<Window xmlns="http://schemas\.microsoft\.com/winfx/2006/xaml/presentation"[\s\S]*?</Window>')
            $m.Success | Should -BeTrue
            $themesToTest = @(
                (InModuleScope GUI { Mock Get-DzUiMode { 'light' }; Get-DzUiTheme }),
                (InModuleScope GUI { Mock Get-DzUiMode { 'dark' }; Get-DzUiTheme })
            )
            foreach ($themeObj in $themesToTest) {
                $ui = New-WpfWindow -Xaml $m.Value -PassThru
                try {
                    $ui.Window | Should -Not -BeNullOrEmpty
                    { Set-DzWpfThemeResources -Window $ui.Window -Theme $themeObj } | Should -Not -Throw
                } finally {
                    $ui.Window.Close()
                }
            }
        }

        It "Mantiene compatibilidad de Write-DzDebug en jobs aislados sin DzStorage" {
            $utilPath = Join-Path $script:ModulesPath "Utilities.psm1"
            $job = Start-Job -ScriptBlock {
                param($Path)
                Import-Module $Path -Force -DisableNameChecking -ErrorAction Stop
                Write-DzDebug -Message "worker debug ok"
                Get-DzDebugPreference
            } -ArgumentList $utilPath
            try {
                Wait-Job -Job $job -Timeout 15 | Out-Null
                $job.State | Should -Be 'Completed'
                $out = Receive-Job -Job $job
                $out | Should -BeOfType [bool]
            } finally {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
