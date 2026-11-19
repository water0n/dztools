# tests/RegistryUtilities.Tests.ps1

Describe "RegistryUtilities - Migración LZMA y Corrección NVMe 4KB" {
    BeforeAll {
        $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:SrcPath = Join-Path $script:ProjectRoot "src"
        $script:ModulesPath = Join-Path $script:SrcPath "modules"

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
        Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

        Import-Module (Join-Path $script:ModulesPath "Utilities.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "GUI.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "WindowsUtilities.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "RegistryUtilities.psm1") -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module RegistryUtilities -Force -ErrorAction SilentlyContinue
        Remove-Module WindowsUtilities -Force -ErrorAction SilentlyContinue
    }

    Context "Migración LZMA e integración en GUI principal" {
        It "Show-LZMADialog debe estar exportada desde RegistryUtilities y no desde WindowsUtilities" {
            $regMod = Get-Module RegistryUtilities
            $winMod = Get-Module WindowsUtilities

            $regMod.ExportedFunctions.Keys | Should -Contain 'Show-LZMADialog'
            $regMod.ExportedFunctions.Keys | Should -Contain 'Show-NvmeRegFixDialog'
            $winMod.ExportedFunctions.Keys | Should -Not -Contain 'Show-LZMADialog'
        }

        It "El XAML principal debe compartir la fila 50%/50% entre LZMAbtnBuscarCarpeta y btnNvmeRegFix" {
            $xaml = Get-MainWindowXaml -Theme @{ FormBackground = "#000000" }
            $xaml | Should -Match 'Name="LZMAbtnBuscarCarpeta"'
            $xaml | Should -Match 'Name="btnNvmeRegFix"'
            $xaml | Should -Match '<Grid Margin="0,0,0,10">\s*<Grid\.ColumnDefinitions>\s*<ColumnDefinition Width="\*"/>\s*<ColumnDefinition Width="6"/>\s*<ColumnDefinition Width="\*"/>'
        }
    }

    Context "Parser de fsutil (ConvertFrom-FsutilSectorInfo)" {
        It "Parsea sectores de 4096, 8192, 16384 y 32768 independientemente de separadores" {
            $sample8k = @"
LogicalBytesPerSector :                                 512
PhysicalBytesPerSectorForAtomicity :                      8192
PhysicalBytesPerSectorForPerformance :                    8192
FileSystemEffectivePhysicalBytesPerSectorForAtomicity :   4096
"@
            $res8k = ConvertFrom-FsutilSectorInfo -Output $sample8k -DriveLetter 'C'
            $res8k.Success | Should -BeTrue
            $res8k.RequiresElevation | Should -BeFalse
            $res8k.LogicalBytesPerSector | Should -Be 512
            $res8k.PhysicalBytesPerSectorForAtomicity | Should -Be 8192
            $res8k.PhysicalBytesPerSectorForPerformance | Should -Be 8192
            $res8k.FileSystemEffectivePhysicalBytesPerSectorForAtomicity | Should -Be 4096
            $res8k.MaxPhysicalSectorSize | Should -Be 8192

            $sample32k = @"
LogicalBytesPerSector :                                 512
PhysicalBytesPerSectorForAtomicity :                      16,384
PhysicalBytesPerSectorForPerformance :                    32 768
FileSystemEffectivePhysicalBytesPerSectorForAtomicity :   16.384
"@
            $res32k = ConvertFrom-FsutilSectorInfo -Output $sample32k -DriveLetter 'D'
            $res32k.Success | Should -BeTrue
            $res32k.PhysicalBytesPerSectorForAtomicity | Should -Be 16384
            $res32k.PhysicalBytesPerSectorForPerformance | Should -Be 32768
            $res32k.FileSystemEffectivePhysicalBytesPerSectorForAtomicity | Should -Be 16384
            $res32k.MaxPhysicalSectorSize | Should -Be 32768
        }

        It "Maneja salida vacía y errores de acceso denegado (inglés/español)" {
            $empty = ConvertFrom-FsutilSectorInfo -Output '' -DriveLetter 'C'
            $empty.Success | Should -BeFalse
            $empty.RequiresElevation | Should -BeFalse

            $deniedEs = ConvertFrom-FsutilSectorInfo -Output 'Error 5: Acceso denegado.' -DriveLetter 'C'
            $deniedEs.Success | Should -BeFalse
            $deniedEs.RequiresElevation | Should -BeTrue

            $deniedEn = ConvertFrom-FsutilSectorInfo -Output 'Error:  Access is denied.' -DriveLetter 'C'
            $deniedEn.Success | Should -BeFalse
            $deniedEn.RequiresElevation | Should -BeTrue
        }
    }

    Context "Matriz de elegibilidad (Test-NvmeSqlFixCandidate)" {
        BeforeEach {
            $script:baseOsWin11 = [PSCustomObject]@{ ProductName = 'Windows 11 Pro'; BuildNumber = 26100; IsWindows11 = $true; IsServer = $false }
            $script:baseOsServer2022 = [PSCustomObject]@{ ProductName = 'Windows Server 2022 Standard'; BuildNumber = 20348; IsWindows11 = $false; IsServer = $true }
            $script:baseDiskStornvme = [PSCustomObject]@{
                HasNvmeDisks              = $true
                HasStornvmeDisk           = $true
                HasUnsupportedDriverDisk  = $false
                AllDisksUnsupportedDriver = $false
                Disks                     = @(
                    [PSCustomObject]@{ DeviceId = '0'; FriendlyName = 'NVMe0'; BusType = 'NVMe'; PhysicalSectorSize = 16384; DriverService = 'stornvme'; IsStornvme = $true }
                )
            }
            $script:baseRegEmpty = [PSCustomObject]@{
                ValueExists      = $false
                ValueKind        = $null
                ValueData        = @()
                IsValueTypeValid = $true
                Has4095Rule      = $false
            }
            $script:baseRegApplied = [PSCustomObject]@{
                ValueExists      = $true
                ValueKind        = 'MultiString'
                ValueData        = @('* 4095')
                IsValueTypeValid = $true
                Has4095Rule      = $true
            }
            $script:baseSqlClean = [PSCustomObject]@{ Scanned = $true; HasFindings = $false; Findings = @(); Summary = 'Sin incidencias' }
        }

        It "Dictamina Candidate cuando NVMe stornvme tiene sector > 4096 sin * 4095" {
            $sec = [PSCustomObject]@{
                RequiresElevation = $false
                Volumes           = @(
                    [PSCustomObject]@{
                        DeviceID                   = 'C:'
                        IsNvmeVolume               = $true
                        DriverService              = 'stornvme'
                        IsStornvme                 = $true
                        FallbackPhysicalSectorSize = 16384
                        EffectiveMaxPhysicalSector = 16384
                        DataSource                 = 'fsutil'
                        Fsutil                     = (ConvertFrom-FsutilSectorInfo -Output "LogicalBytesPerSector : 512`nPhysicalBytesPerSectorForAtomicity : 16384`nPhysicalBytesPerSectorForPerformance : 16384`nFileSystemEffectivePhysicalBytesPerSectorForAtomicity : 16384")
                    }
                )
            }

            $v = Test-NvmeSqlFixCandidate -OsInfo $script:baseOsWin11 -DiskInfo $script:baseDiskStornvme -SectorDiagnostics $sec -RegistryState $script:baseRegEmpty -SqlLogResult $script:baseSqlClean
            $v.Status | Should -Be 'Candidate'
            $v.CanApplyByDefault | Should -BeTrue
            $v.RequiresReboot | Should -BeFalse
        }

        It "Dictamina Candidate en Windows Server (build < 22000) sin depender del build" {
            $sec = [PSCustomObject]@{
                RequiresElevation = $false
                Volumes           = @(
                    [PSCustomObject]@{
                        DeviceID                   = 'C:'
                        IsNvmeVolume               = $true
                        DriverService              = 'stornvme'
                        IsStornvme                 = $true
                        FallbackPhysicalSectorSize = 32768
                        EffectiveMaxPhysicalSector = 32768
                        DataSource                 = 'fsutil'
                        Fsutil                     = (ConvertFrom-FsutilSectorInfo -Output "PhysicalBytesPerSectorForAtomicity : 32768")
                    }
                )
            }

            $v = Test-NvmeSqlFixCandidate -OsInfo $script:baseOsServer2022 -DiskInfo $script:baseDiskStornvme -SectorDiagnostics $sec -RegistryState $script:baseRegEmpty -SqlLogResult $script:baseSqlClean
            $v.Status | Should -Be 'Candidate'
            $v.CanApplyByDefault | Should -BeTrue
        }

        It "Dictamina AlreadyAppliedPendingReboot cuando existe * 4095 pero sector sigue > 4096" {
            $sec = [PSCustomObject]@{
                RequiresElevation = $false
                Volumes           = @(
                    [PSCustomObject]@{
                        DeviceID                   = 'C:'
                        IsNvmeVolume               = $true
                        DriverService              = 'stornvme'
                        IsStornvme                 = $true
                        FallbackPhysicalSectorSize = 16384
                        EffectiveMaxPhysicalSector = 16384
                        DataSource                 = 'fsutil'
                        Fsutil                     = (ConvertFrom-FsutilSectorInfo -Output "PhysicalBytesPerSectorForAtomicity : 16384")
                    }
                )
            }

            $v = Test-NvmeSqlFixCandidate -OsInfo $script:baseOsWin11 -DiskInfo $script:baseDiskStornvme -SectorDiagnostics $sec -RegistryState $script:baseRegApplied -SqlLogResult $script:baseSqlClean
            $v.Status | Should -Be 'AlreadyAppliedPendingReboot'
            $v.CanApplyByDefault | Should -BeFalse
            $v.RequiresReboot | Should -BeTrue
        }

        It "Dictamina AlreadyFixed cuando existe * 4095 y todos los volúmenes NVMe son <= 4096" {
            $sec = [PSCustomObject]@{
                RequiresElevation = $false
                Volumes           = @(
                    [PSCustomObject]@{
                        DeviceID                   = 'C:'
                        IsNvmeVolume               = $true
                        DriverService              = 'stornvme'
                        IsStornvme                 = $true
                        FallbackPhysicalSectorSize = 4096
                        EffectiveMaxPhysicalSector = 4096
                        DataSource                 = 'fsutil'
                        Fsutil                     = (ConvertFrom-FsutilSectorInfo -Output "PhysicalBytesPerSectorForAtomicity : 4096`nPhysicalBytesPerSectorForPerformance : 4096`nFileSystemEffectivePhysicalBytesPerSectorForAtomicity : 4096")
                    }
                )
            }

            $v = Test-NvmeSqlFixCandidate -OsInfo $script:baseOsWin11 -DiskInfo $script:baseDiskStornvme -SectorDiagnostics $sec -RegistryState $script:baseRegApplied -SqlLogResult $script:baseSqlClean
            $v.Status | Should -Be 'AlreadyFixed'
            $v.CanApplyByDefault | Should -BeFalse
            $v.RequiresReboot | Should -BeFalse
        }

        It "Dictamina UnsupportedDriver cuando NVMe usa driver distinto de stornvme" {
            $diskIntel = [PSCustomObject]@{
                HasNvmeDisks              = $true
                HasStornvmeDisk           = $false
                HasUnsupportedDriverDisk  = $true
                AllDisksUnsupportedDriver = $true
                Disks                     = @(
                    [PSCustomObject]@{ DeviceId = '0'; FriendlyName = 'Intel Optane'; BusType = 'NVMe'; PhysicalSectorSize = 16384; DriverService = 'iaStorVD'; IsStornvme = $false }
                )
            }
            $sec = [PSCustomObject]@{
                RequiresElevation = $false
                Volumes           = @(
                    [PSCustomObject]@{
                        DeviceID                   = 'C:'
                        IsNvmeVolume               = $true
                        DriverService              = 'iaStorVD'
                        IsStornvme                 = $false
                        FallbackPhysicalSectorSize = 16384
                        EffectiveMaxPhysicalSector = 16384
                        DataSource                 = 'fsutil'
                        Fsutil                     = (ConvertFrom-FsutilSectorInfo -Output "PhysicalBytesPerSectorForAtomicity : 16384")
                    }
                )
            }

            $v = Test-NvmeSqlFixCandidate -OsInfo $script:baseOsWin11 -DiskInfo $diskIntel -SectorDiagnostics $sec -RegistryState $script:baseRegEmpty -SqlLogResult $script:baseSqlClean
            $v.Status | Should -Be 'UnsupportedDriver'
            $v.CanApplyByDefault | Should -BeFalse
            ($v.Reasons -join ' ') | Should -Match 'iaStorVD'
        }

        It "Ignora volúmenes no NVMe y solo evalúa volúmenes NVMe en discos mixtos" {
            $secMixed = [PSCustomObject]@{
                RequiresElevation = $false
                Volumes           = @(
                    [PSCustomObject]@{
                        DeviceID                   = 'C:'
                        IsNvmeVolume               = $true
                        DriverService              = 'stornvme'
                        IsStornvme                 = $true
                        FallbackPhysicalSectorSize = 4096
                        EffectiveMaxPhysicalSector = 4096
                        DataSource                 = 'fsutil'
                        Fsutil                     = (ConvertFrom-FsutilSectorInfo -Output "PhysicalBytesPerSectorForAtomicity : 4096")
                    },
                    [PSCustomObject]@{
                        DeviceID                   = 'E:'
                        IsNvmeVolume               = $false
                        DriverService              = ''
                        IsStornvme                 = $false
                        FallbackPhysicalSectorSize = 16384
                        EffectiveMaxPhysicalSector = 16384
                        DataSource                 = 'fsutil'
                        Fsutil                     = (ConvertFrom-FsutilSectorInfo -Output "PhysicalBytesPerSectorForAtomicity : 16384")
                    }
                )
            }

            $v = Test-NvmeSqlFixCandidate -OsInfo $script:baseOsWin11 -DiskInfo $script:baseDiskStornvme -SectorDiagnostics $secMixed -RegistryState $script:baseRegEmpty -SqlLogResult $script:baseSqlClean
            $v.Status | Should -Be 'NotCandidate'
            $v.CanApplyByDefault | Should -BeFalse
        }

        It "No habilita Aplicar por defecto si solo hay hallazgos en ERRORLOG con sectores <= 4096" {
            $secOk = [PSCustomObject]@{
                RequiresElevation = $false
                Volumes           = @(
                    [PSCustomObject]@{
                        DeviceID                   = 'C:'
                        IsNvmeVolume               = $true
                        DriverService              = 'stornvme'
                        IsStornvme                 = $true
                        FallbackPhysicalSectorSize = 4096
                        EffectiveMaxPhysicalSector = 4096
                        DataSource                 = 'fsutil'
                        Fsutil                     = (ConvertFrom-FsutilSectorInfo -Output "PhysicalBytesPerSectorForAtomicity : 4096")
                    }
                )
            }
            $sqlBad = [PSCustomObject]@{
                Scanned     = $true
                HasFindings = $true
                Findings    = @([PSCustomObject]@{ FilePath = 'ERRORLOG'; MatchType = 'MisalignedLogIO'; Line = 'misaligned log IOs' })
                Summary     = '1 coincidencia'
            }

            $v = Test-NvmeSqlFixCandidate -OsInfo $script:baseOsWin11 -DiskInfo $script:baseDiskStornvme -SectorDiagnostics $secOk -RegistryState $script:baseRegEmpty -SqlLogResult $sqlBad
            $v.Status | Should -Be 'NotCandidate'
            $v.CanApplyByDefault | Should -BeFalse
            ($v.Reasons -join ' ') | Should -Match 'ERRORLOG'
        }
    }

    Context "Lectura de SQL ERRORLOG (UTF-16 LE y archivo bloqueado)" {
        It "Lee ERRORLOG en UTF-16 LE abierto simultáneamente por otro stream y detecta errores clave" {
            $logDir = Join-Path $TestDrive 'SqlLogs'
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            $logFile = Join-Path $logDir 'ERRORLOG'

            $content = @(
                "2026-11-19 10:00:00.00 Server      Microsoft SQL Server 2022"
                "2026-11-19 10:00:01.00 spid7s      There have been 256 misaligned log IOs which required falling back to synchronous IO."
                "2026-11-19 10:00:02.00 spid7s      Error: 5178, Severity: 16, State: 1."
                "2026-11-19 10:00:03.00 spid7s      Exception c00000fd EXCEPTION_STACK_OVERFLOW"
            ) -join "`r`n"

            [System.IO.File]::WriteAllText($logFile, $content, [System.Text.Encoding]::Unicode)

            $lockStream = [System.IO.FileStream]::new(
                $logFile,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::ReadWrite
            )
            try {
                $res = Find-SqlMisalignedIoErrors -LogDirectories @($logDir)
                $res.HasFindings | Should -BeTrue
                $res.ScannedFiles | Should -Contain $logFile
                ($res.Findings | Select-Object -ExpandProperty MatchType) | Should -Contain 'MisalignedLogIO'
                ($res.Findings | Select-Object -ExpandProperty MatchType) | Should -Contain 'SectorError5178_5179'
                ($res.Findings | Select-Object -ExpandProperty MatchType) | Should -Contain 'ExceptionStackOverflow'
            } finally {
                $lockStream.Dispose()
            }
        }
    }

    Context "Respaldo, Aplicación, Preservación y Restauración en TestRegistry" {
        BeforeEach {
            $script:TestRootPath = "TestRegistry:\stornvme_$([Guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:TestRootPath -Force | Out-Null
            $script:TestBackupRoot = Join-Path $TestDrive ("backups_{0}" -f [Guid]::NewGuid().ToString('N'))
        }

        It "Crea respaldo .reg + .json, aplica * 4095 MultiString y al revertir limpia clave creada desde cero" {
            InModuleScope RegistryUtilities -Parameters @{ Root = $script:TestRootPath; Backups = $script:TestBackupRoot } {
                Mock Test-NvmeAdminPrivilege { return $true }

                $apply = Set-NvmePhysicalSectorFix -RootPath $Root -BackupRoot $Backups -DriverService 'stornvme' -Confirm:$false
                $apply.Success | Should -BeTrue
                Test-Path -LiteralPath $apply.JsonPath | Should -BeTrue
                Test-Path -LiteralPath $apply.RegPath | Should -BeTrue
                $apply.AppliedValues | Should -Contain '* 4095'

                $stateAfterApply = Get-NvmeRegistryState -RootPath $Root
                $stateAfterApply.Has4095Rule | Should -BeTrue
                $stateAfterApply.ValueKind | Should -Be 'MultiString'

                $listed = @(Get-NvmeRegistryBackups -BackupRoot $Backups)
                $listed.Count | Should -Be 1
                $listed[0].IsLatest | Should -BeTrue
                $listed[0].IsRestored | Should -BeFalse

                $restore = Restore-NvmeRegistryBackup -BackupJsonPath $apply.JsonPath -RootPath $Root -BackupRoot $Backups -Confirm:$false
                $restore.Success | Should -BeTrue

                $stateAfterRestore = Get-NvmeRegistryState -RootPath $Root
                $stateAfterRestore.ValueExists | Should -BeFalse
                $stateAfterRestore.DeviceKeyExists | Should -BeFalse
                $stateAfterRestore.ParametersKeyExists | Should -BeFalse

                $listedAfter = @(Get-NvmeRegistryBackups -BackupRoot $Backups)
                $listedAfter[0].IsRestored | Should -BeTrue
                $listedAfter[0].Display | Should -Match 'restaurado'

                $auditFile = Join-Path $Backups 'nvme_audit.log'
                Test-Path -LiteralPath $auditFile | Should -BeTrue
                $auditText = Get-Content -LiteralPath $auditFile -Raw
                $auditText | Should -Match 'Action=Apply'
                $auditText | Should -Match 'Action=Restore'
            }
        }

        It "Preserva entradas previas de REG_MULTI_SZ y restaura exactamente el valor anterior" {
            InModuleScope RegistryUtilities -Parameters @{ Root = $script:TestRootPath; Backups = $script:TestBackupRoot } {
                Mock Test-NvmeAdminPrivilege { return $true }

                $devPath = Join-Path (Join-Path $Root 'Parameters') 'Device'
                New-Item -Path $devPath -Force | Out-Null
                Set-ItemProperty -LiteralPath $devPath -Name 'ForcedPhysicalSectorSizeInBytes' -Value ([string[]]@('PCI\VEN_1234 4096')) -Type MultiString -Force

                $apply = Set-NvmePhysicalSectorFix -RootPath $Root -BackupRoot $Backups -Confirm:$false
                $apply.Success | Should -BeTrue
                $apply.AppliedValues | Should -Contain 'PCI\VEN_1234 4096'
                $apply.AppliedValues | Should -Contain '* 4095'

                $restore = Restore-NvmeRegistryBackup -BackupJsonPath $apply.JsonPath -RootPath $Root -BackupRoot $Backups -Confirm:$false
                $restore.Success | Should -BeTrue

                $stateRestored = Get-NvmeRegistryState -RootPath $Root
                $stateRestored.ValueExists | Should -BeTrue
                $stateRestored.ValueKind | Should -Be 'MultiString'
                $stateRestored.ValueData | Should -Contain 'PCI\VEN_1234 4096'
                $stateRestored.ValueData | Should -Not -Contain '* 4095'
            }
        }

        It "Aborta aplicación y restauración cuando no hay permisos de Administrador" {
            InModuleScope RegistryUtilities -Parameters @{ Root = $script:TestRootPath; Backups = $script:TestBackupRoot } {
                Mock Test-NvmeAdminPrivilege { return $false }

                $apply = Set-NvmePhysicalSectorFix -RootPath $Root -BackupRoot $Backups -Confirm:$false
                $apply.Success | Should -BeFalse
                $apply.Error | Should -Match 'Administrador'

                $restore = Restore-NvmeRegistryBackup -BackupJsonPath (Join-Path $Backups 'fake.json') -RootPath $Root -BackupRoot $Backups -Confirm:$false
                $restore.Success | Should -BeFalse
                $restore.Error | Should -Match 'Administrador'
            }
        }

        It "Aborta escritura sin modificar el Registro cuando falla el respaldo previo" {
            InModuleScope RegistryUtilities -Parameters @{ Root = $script:TestRootPath; Backups = $script:TestBackupRoot } {
                Mock Test-NvmeAdminPrivilege { return $true }

                $devPath = Join-Path (Join-Path $Root 'Parameters') 'Device'
                New-Item -Path $devPath -Force | Out-Null
                Set-ItemProperty -LiteralPath $devPath -Name 'ForcedPhysicalSectorSizeInBytes' -Value '4095' -Type String -Force

                Mock Backup-NvmeRegistryState {
                    return [PSCustomObject]@{ Success = $false; Error = 'Disco lleno simulado' }
                }

                $failedApply = Set-NvmePhysicalSectorFix -RootPath $Root -BackupRoot $Backups -Confirm:$false
                $failedApply.Success | Should -BeFalse
                $failedApply.Error | Should -Match 'respaldo'

                $unchanged = Get-NvmeRegistryState -RootPath $Root
                $unchanged.ValueKind | Should -Be 'String'
                $unchanged.Has4095Rule | Should -BeFalse
            }
        }

        It "Corrige valor de tipo incorrecto String a MultiString y restaura tipo String previo" {
            InModuleScope RegistryUtilities -Parameters @{ Root = $script:TestRootPath; Backups = $script:TestBackupRoot } {
                Mock Test-NvmeAdminPrivilege { return $true }

                $devPath = Join-Path (Join-Path $Root 'Parameters') 'Device'
                New-Item -Path $devPath -Force | Out-Null
                Set-ItemProperty -LiteralPath $devPath -Name 'ForcedPhysicalSectorSizeInBytes' -Value '4095' -Type String -Force

                $apply = Set-NvmePhysicalSectorFix -RootPath $Root -BackupRoot $Backups -Confirm:$false
                $apply.Success | Should -BeTrue

                $appliedState = Get-NvmeRegistryState -RootPath $Root
                $appliedState.ValueKind | Should -Be 'MultiString'
                $appliedState.Has4095Rule | Should -BeTrue

                $restore = Restore-NvmeRegistryBackup -BackupJsonPath $apply.JsonPath -RootPath $Root -BackupRoot $Backups -Confirm:$false
                $restore.Success | Should -BeTrue

                $restoredState = Get-NvmeRegistryState -RootPath $Root
                $restoredState.ValueKind | Should -Be 'String'
                $restoredState.ValueData | Should -Contain '4095'
            }
        }

        It "Ordena respaldos del más reciente al más antiguo y marca IsLatest correctamente" {
            InModuleScope RegistryUtilities -Parameters @{ Root = $script:TestRootPath; Backups = $script:TestBackupRoot } {
                $b1 = Backup-NvmeRegistryState -RootPath $Root -BackupRoot $Backups
                Start-Sleep -Milliseconds 50
                $b2 = Backup-NvmeRegistryState -RootPath $Root -BackupRoot $Backups

                $b1.Success | Should -BeTrue
                $b2.Success | Should -BeTrue

                $list = @(Get-NvmeRegistryBackups -BackupRoot $Backups)
                $list.Count | Should -Be 2
                $list[0].BackupId | Should -Be $b2.BackupId
                $list[0].IsLatest | Should -BeTrue
                $list[1].IsLatest | Should -BeFalse
            }
        }
    }

    Context "Diagnóstico simulado, trabajo asíncrono y XAML del modal WPF" {
        It "Get-NvmeSectorDiagnostics consume Invoke-Fsutil simulado para volúmenes NVMe" {
            InModuleScope RegistryUtilities {
                Mock Get-CimInstance {
                    return @([PSCustomObject]@{ DeviceID = 'C:'; DriveType = 3; VolumeName = 'OS' })
                } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }

                Mock Get-DriveToDiskMap {
                    return @{
                        'C' = @([PSCustomObject]@{ DiskNumber = '0'; BusType = 'NVMe'; FriendlyName = 'NVMe0'; PhysicalSectorSize = 16384; LogicalSectorSize = 512 })
                    }
                }

                Mock Invoke-Fsutil {
                    return [PSCustomObject]@{
                        ExitCode = 0
                        Output   = "LogicalBytesPerSector : 512`nPhysicalBytesPerSectorForAtomicity : 16384`nPhysicalBytesPerSectorForPerformance : 16384`nFileSystemEffectivePhysicalBytesPerSectorForAtomicity : 16384"
                    }
                }

                $diskInfo = [PSCustomObject]@{
                    HasNvmeDisks             = $true
                    HasStornvmeDisk          = $true
                    HasUnsupportedDriverDisk = $false
                    Disks                    = @([PSCustomObject]@{ DeviceId = '0'; DriverService = 'stornvme'; IsStornvme = $true; PhysicalSectorSize = 16384 })
                }

                $diag = Get-NvmeSectorDiagnostics -DiskInfo $diskInfo
                $diag.Volumes.Count | Should -Be 1
                $diag.Volumes[0].DataSource | Should -Be 'fsutil'
                $diag.Volumes[0].EffectiveMaxPhysicalSector | Should -Be 16384
                $diag.RequiresElevation | Should -BeFalse
            }
        }

        It "El análisis se ejecuta correctamente dentro de un Start-Job en segundo plano" {
            $modPath = Join-Path $script:ModulesPath "RegistryUtilities.psm1"
            $job = Start-Job -ScriptBlock {
                param($Path)
                Import-Module $Path -Force -DisableNameChecking -ErrorAction Stop
                Invoke-NvmeSystemAnalysis -IncludeSqlLogs -StreamJobProgress
            } -ArgumentList $modPath
            try {
                Wait-Job -Job $job -Timeout 25 | Out-Null
                $job.State | Should -Be 'Completed'
                $items = @(Receive-Job -Job $job)
                $progressItems = @($items | Where-Object { $_.Type -eq 'Progress' })
                $resultItem = $items | Where-Object { $_.Type -eq 'Result' } | Select-Object -Last 1

                $progressItems.Count | Should -BeGreaterOrEqual 5
                $resultItem | Should -Not -BeNullOrEmpty
                $resultItem.Ok | Should -BeTrue
                $res = $resultItem.Analysis
                $res.SqlLogs.HasFindings | Should -BeOfType [bool]
                $res.Verdict | Should -Not -BeNullOrEmpty
                $res.Verdict.Status | Should -BeIn @('Candidate', 'AlreadyAppliedPendingReboot', 'AlreadyFixed', 'UnsupportedDriver', 'NotCandidate')
            } finally {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }

        It "El XAML de Show-NvmeRegFixDialog y Show-NvmeBackupPickerDialog carga sin errores en modo Light y Dark" {
            $regContent = Get-Content (Join-Path $script:ModulesPath "RegistryUtilities.psm1") -Raw
            $xamlMatches = [regex]::Matches($regContent, '<Window xmlns="http://schemas\.microsoft\.com/winfx/2006/xaml/presentation"[\s\S]*?</Window>')
            $xamlMatches.Count | Should -Be 3

            $themesToTest = @(
                (InModuleScope GUI { Mock Get-DzUiMode { 'light' }; Get-DzUiTheme }),
                (InModuleScope GUI { Mock Get-DzUiMode { 'dark' }; Get-DzUiTheme })
            )
            foreach ($themeObj in $themesToTest) {
                foreach ($m in $xamlMatches) {
                    $ui = New-WpfWindow -Xaml $m.Value -PassThru
                    try {
                        $ui.Window | Should -Not -BeNullOrEmpty
                        { Set-DzWpfThemeResources -Window $ui.Window -Theme $themeObj } | Should -Not -Throw
                    } finally {
                        $ui.Window.Close()
                    }
                }
            }
        }
    }
}
