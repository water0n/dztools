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
}
