# tests/Basic.Tests.ps1

Describe "Pruebas básicas del proyecto" {
    BeforeAll {
        $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:SrcPath = Join-Path $script:ProjectRoot "src"
        $script:ModulesPath = Join-Path $script:SrcPath "modules"
        $script:MainPath = Join-Path $script:SrcPath "main.ps1"
        $script:VersionPath = Join-Path $script:SrcPath "version.json"
    }

    Context "Verificación de archivos" {
        It "Debe existir el archivo main.ps1" {
            Test-Path $script:MainPath | Should -BeTrue
        }

        It "Debe existir la carpeta de módulos con archivos .psm1" {
            Test-Path $script:ModulesPath | Should -BeTrue
            (Get-ChildItem -Path $script:ModulesPath -Filter "*.psm1").Count | Should -BeGreaterThan 0
        }

        It "Debe existir el archivo version.json" {
            Test-Path $script:VersionPath | Should -BeTrue
        }
    }

    Context "Verificación de formato" {
        It "version.json debe ser JSON válido" {
            { Get-Content $script:VersionPath -Raw | ConvertFrom-Json } | Should -Not -Throw
        }

        It "version.json debe tener propiedad Version" {
            $json = Get-Content $script:VersionPath -Raw | ConvertFrom-Json
            $json.Version | Should -Not -BeNullOrEmpty
        }
    }

    Context "Módulos cargados en main.ps1" {
        It "Debe listar todos los módulos presentes en src/modules" {
            $mainContent = Get-Content $script:MainPath -Raw
            $moduleMatch = [regex]::Match($mainContent, '\$modules\s*=\s*@\((?<content>[\s\S]*?)\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $moduleMatch.Success | Should -BeTrue

            $declaredModules = [regex]::Matches($moduleMatch.Groups['content'].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
            $declaredModules = $declaredModules | Where-Object { $_ -ne "" }

            $moduleFiles = Get-ChildItem -Path $script:ModulesPath -Filter "*.psm1" | Select-Object -ExpandProperty Name

            $missingFromMain = Compare-Object -ReferenceObject $moduleFiles -DifferenceObject $declaredModules -PassThru | Where-Object { $_ -in $moduleFiles }
            $missingFromMain | Should -BeNullOrEmpty

            $unusedInMain = Compare-Object -ReferenceObject $declaredModules -DifferenceObject $moduleFiles -PassThru | Where-Object { $_ -in $declaredModules }
            $unusedInMain | Should -BeNullOrEmpty
        }
    }

    Context "Funciones exportadas en módulos" {
        It "Cada módulo debe exportar funciones definidas en el archivo" {
            $moduleFiles = Get-ChildItem -Path $script:ModulesPath -Filter "*.psm1"
            foreach ($moduleFile in $moduleFiles) {
                $content = Get-Content $moduleFile.FullName -Raw
                $exportMatch = [regex]::Match($content, 'Export-ModuleMember\s+-Function\s+@\((?<content>[\s\S]*?)\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                $exportMatch.Success | Should -BeTrue -Because "No se encontró Export-ModuleMember en $($moduleFile.Name)"

                $exportedFunctions = [regex]::Matches($exportMatch.Groups['content'].Value, "['""]([^'""]+)['""]") | ForEach-Object { $_.Groups[1].Value }
                $exportedFunctions = $exportedFunctions | Where-Object { $_ -ne "" }
                $exportedFunctions.Count | Should -BeGreaterThan 0

                foreach ($functionName in $exportedFunctions) {
                    $functionPattern = "function\s+$([regex]::Escape($functionName))\b"
                    [regex]::IsMatch($content, $functionPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | Should -BeTrue -Because "La función $functionName no está definida en $($moduleFile.Name)"
                }
            }
        }
    }

    Context "Compatibilidad PowerShell 5" {
        It "Los archivos no deben usar características de PS6+" {
            $matches = Get-ChildItem -Path $script:SrcPath -Recurse -Filter "*.ps*1" |
            Select-String -Pattern '#requires.*-Version.*([6-9]|\d{2,})'

            $matches | Should -BeNullOrEmpty
        }
    }

    Context "Reparación de base de datos" {
        BeforeAll {
            $script:SqlOpsPath = Join-Path $script:ModulesPath "SqlOps.psm1"
            $script:SqlOpsContent = Get-Content $script:SqlOpsPath -Raw
        }

        It "Debe limitar los pasos administrativos de reparación" {
            $script:SqlOpsContent.IndexOf('$adminTimeoutSeconds = 60') | Should -BeGreaterThan -1
            $script:SqlOpsContent | Should -Match 'CommandTimeoutSeconds\s+\$adminTimeoutSeconds\s+-StepName "cerrar conexiones existentes"'
            $script:SqlOpsContent | Should -Match 'CommandTimeoutSeconds\s+\$adminTimeoutSeconds\s+-StepName "configurar modo EMERGENCY"'
            $script:SqlOpsContent | Should -Match 'CommandTimeoutSeconds\s+\$adminTimeoutSeconds\s+-StepName "restaurar modo MULTI_USER"'
        }

        It "Debe dejar DBCC CHECKDB sin timeout automatico" {
            $script:SqlOpsContent | Should -Match 'CommandTimeoutSeconds\s+0\s+-StepName "ejecutar DBCC CHECKDB \(\$RepairOption\)"'
        }

        It "Debe usar SINGLE_USER automaticamente para reparar" {
            $script:SqlOpsContent.IndexOf('$requiresSingleUser = $RepairOption -ne "CHECK"') | Should -BeGreaterThan -1
            $script:SqlOpsContent.IndexOf('$useSingleUser = $CloseConnections -or $requiresSingleUser') | Should -BeGreaterThan -1
        }

        It "Debe reservar EMERGENCY para REPAIR_ALLOW_DATA_LOSS" {
            $script:SqlOpsContent.IndexOf('$useEmergency = $EmergencyMode -and $RepairOption -eq "REPAIR_ALLOW_DATA_LOSS"') | Should -BeGreaterThan -1
            $script:SqlOpsContent | Should -Match 'SQL Server solo permite reparar en EMERGENCY con REPAIR_ALLOW_DATA_LOSS'
        }

        It "Debe cerrar conexiones antes de configurar EMERGENCY" {
            $singleUserIndex = $script:SqlOpsContent.IndexOf('$closeQuery = "ALTER DATABASE [$safeName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE"')
            $emergencyIndex = $script:SqlOpsContent.IndexOf('$emergencyQuery = "ALTER DATABASE [$safeName] SET EMERGENCY"')

            $singleUserIndex | Should -BeGreaterThan -1
            $emergencyIndex | Should -BeGreaterThan -1
            $singleUserIndex | Should -BeLessThan $emergencyIndex
        }

        It "No debe mostrar marcadores internos en el log visible" {
            $script:SqlOpsContent | Should -Match '\(SUCCESS_RESULT\|ERROR_RESULT\|__DONE__\)'
        }
    }
}
