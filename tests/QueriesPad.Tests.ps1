# tests/QueriesPad.Tests.ps1

Describe "Pruebas de QueriesPad y Botón Abrir" {
    BeforeAll {
        $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:SrcPath = Join-Path $script:ProjectRoot "src"
        $script:ModulesPath = Join-Path $script:SrcPath "modules"

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
        Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

        Import-Module (Join-Path $script:ModulesPath "Utilities.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "GUI.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $script:ModulesPath "QueriesPad.psm1") -Force -DisableNameChecking
    }

    Context "Verificación de interfaz XAML" {
        It "El XAML principal debe contener el botón btnOpenFile" {
            $xaml = Get-MainWindowXaml -Theme @{ FormBackground = "#000000" }
            $xaml | Should -Match 'Name="btnOpenFile"'
            $xaml | Should -Match 'Content="📁 Abrir"'
            $xaml | Should -Match 'btnExecute'
        }

        It "btnExecute y btnOpenFile deben compartir una grilla de 2 columnas" {
            $xaml = Get-MainWindowXaml -Theme @{ FormBackground = "#000000" }
            $xaml | Should -Match '<Grid Margin="0,0,0,8">\s*<Grid.ColumnDefinitions>\s*<ColumnDefinition Width="\*"/>\s*<ColumnDefinition Width="\*"/>'
        }
    }

    Context "Función Open-SqlFileInTab" {
        It "Open-SqlFileInTab debe estar disponible y exportada" {
            Get-Command Open-SqlFileInTab -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Debe arrojar error si el archivo no existe" {
            $tc = New-Object System.Windows.Controls.TabControl
            { Open-SqlFileInTab -TabControl $tc -FilePath "C:\Ruta\Inexistente\test.sql" } | Should -Throw
        }

        It "Debe cargar un archivo SQL en una pestaña con su contenido y nombre" {
            $tempFile = [System.IO.Path]::GetTempFileName() + ".sql"
            try {
                $sqlContent = "SELECT * FROM Clientes WHERE Activo = 1;"
                [System.IO.File]::WriteAllText($tempFile, $sqlContent, [System.Text.Encoding]::UTF8)

                $tc = New-Object System.Windows.Controls.TabControl
                $tab = Open-SqlFileInTab -TabControl $tc -FilePath $tempFile

                $tab | Should -Not -BeNullOrEmpty
                $tab.Tag | Should -Not -BeNullOrEmpty
                $tab.Tag.FilePath | Should -Be $tempFile
                $tab.Tag.IsDirty | Should -BeFalse
                (Get-SqlEditorText -Editor $tab.Tag.Editor).Trim() | Should -Be $sqlContent.Trim()
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}