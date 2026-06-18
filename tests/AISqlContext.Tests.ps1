$modulePath = Join-Path $PSScriptRoot "..\src\modules\AISqlContext.psm1"
Import-Module $modulePath -Force

Describe "AISqlContext" {
    It "detecta ventas de hoy" {
        $intent = Find-DzAiSqlIntent -Question "ventas de hoy"
        $intent.PrimaryDomain.id | Should -Be "ventas"
    }

    It "detecta clientes con mas ventas" {
        $intent = Find-DzAiSqlIntent -Question "clientes con mas ventas del ultimo mes"
        $intent.PrimaryDomain.id | Should -Be "clientes_ventas"
    }

    It "detecta productos mas vendidos" {
        $intent = Find-DzAiSqlIntent -Question "productos mas vendidos"
        $intent.PrimaryDomain.id | Should -Be "productos_ventas"
    }

    It "genera SQL deterministico para tablas con companyid" {
        $sql = New-DzAiSchemaDiscoverySql -Question "dame las tablas con companyid"
        $sql | Should -Match "INFORMATION_SCHEMA.COLUMNS"
        $sql | Should -Match "companyid"
        $sql | Should -Match "idempresa"
        Test-DzAiGeneratedSqlSafe -Sql $sql | Should -BeTrue
    }

    It "permite SELECT" {
        Test-DzAiGeneratedSqlSafe -Sql "SELECT TOP (10) * FROM dbo.cheques;" | Should -BeTrue
    }

    It "permite WITH con SELECT" {
        Test-DzAiGeneratedSqlSafe -Sql "WITH x AS (SELECT 1 AS n) SELECT n FROM x;" | Should -BeTrue
    }

    It "rechaza SQL destructivo" {
        Test-DzAiGeneratedSqlSafe -Sql "UPDATE dbo.cheques SET total = 0;" | Should -BeFalse
        Test-DzAiGeneratedSqlSafe -Sql "DELETE FROM dbo.cheques;" | Should -BeFalse
        Test-DzAiGeneratedSqlSafe -Sql "DROP TABLE dbo.cheques;" | Should -BeFalse
        Test-DzAiGeneratedSqlSafe -Sql "INSERT INTO dbo.cheques(total) VALUES (0);" | Should -BeFalse
        Test-DzAiGeneratedSqlSafe -Sql "ALTER TABLE dbo.cheques ADD x int;" | Should -BeFalse
        Test-DzAiGeneratedSqlSafe -Sql "EXEC dbo.Reproceso;" | Should -BeFalse
    }

    It "extrae bloque SQL de una respuesta con Markdown" {
        $response = @'
Aqui esta:
```sql
SELECT 1 AS ok
```
'@
        $sql = Get-DzAiSqlFromText -Text $response
        $sql | Should -Be "SELECT 1 AS ok;"
    }
}
