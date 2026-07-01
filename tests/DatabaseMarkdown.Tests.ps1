$modulePath = Join-Path $PSScriptRoot "..\src\modules\Database.psm1"

Add-Type -AssemblyName PresentationFramework
Import-Module $modulePath -Force

AfterAll {
    Remove-Module Database -Force -ErrorAction SilentlyContinue
}

Describe "Database Markdown copy" {
    InModuleScope Database {
        It "genera una tabla Markdown como Supabase" {
            $headers = @("id", "auth_user_id")
            $rows = @(
                ,@("97e15bb5-2466-4326-bcfe-9dc9c47ccfe5", "1cc8a024-dd53-480b-81b3-31864502b72e")
                ,@("9b9095bf-6913-44be-ba5a-ddf0820d7a41", "041cb1ad-304b-4969-9f1f-94b08016229a")
                ,@("9c7dead1-f49f-45d8-9af7-7f203545a2fa", "9849ed67-5f67-4b99-99e7-40bc972cf759")
                ,@("ef250278-354e-46ca-8464-536774006f4d", "6866834f-e75d-4469-94ac-f8ff4bd2e096")
                ,@("35077165-2846-4bb0-b5f1-74e345de5507", "1cb2385f-ab6a-485f-b24c-99565b48362c")
            )

            $markdown = New-DzMarkdownTableText -Headers $headers -Rows $rows
            $expected = @'
| id                                   | auth_user_id                         |
| ------------------------------------ | ------------------------------------ |
| 97e15bb5-2466-4326-bcfe-9dc9c47ccfe5 | 1cc8a024-dd53-480b-81b3-31864502b72e |
| 9b9095bf-6913-44be-ba5a-ddf0820d7a41 | 041cb1ad-304b-4969-9f1f-94b08016229a |
| 9c7dead1-f49f-45d8-9af7-7f203545a2fa | 9849ed67-5f67-4b99-99e7-40bc972cf759 |
| ef250278-354e-46ca-8464-536774006f4d | 6866834f-e75d-4469-94ac-f8ff4bd2e096 |
| 35077165-2846-4bb0-b5f1-74e345de5507 | 1cb2385f-ab6a-485f-b24c-99565b48362c |
'@

            ($markdown -replace "`r`n", "`n") | Should -Be ($expected -replace "`r`n", "`n")
        }

        It "alinea columnas con separador minimo valido" {
            $markdown = New-DzMarkdownTableText -Headers @("a", "longer") -Rows @(
                ,@("one", "x")
                ,@("two", "three")
            )
            $lines = ($markdown -replace "`r`n", "`n").Split("`n")

            $lines[0] | Should -Be "| a   | longer |"
            $lines[1] | Should -Be "| --- | ------ |"
            $lines[2] | Should -Be "| one | x      |"
            $lines[3] | Should -Be "| two | three  |"
        }

        It "normaliza valores especiales para Markdown" {
            $date = [datetime]"2026-06-05T07:08:09.123"
            $markdown = New-DzMarkdownTableText -Headers @("n", "date", "ok", "pipe", "multi") -Rows @(
                ,@([System.DBNull]::Value, $date, $true, "a|b", "line`nnext`tend")
            )
            $lines = ($markdown -replace "`r`n", "`n").Split("`n")

            $lines[0] | Should -Be "| n    | date                    | ok   | pipe | multi         |"
            $lines[1] | Should -Be "| ---- | ----------------------- | ---- | ---- | ------------- |"
            $lines[2] | Should -Be "| NULL | 2026-06-05 07:08:09.123 | True | a\|b | line next end |"
        }
    }

    It "expone la opcion en el menu contextual del DataGrid" {
        $databasePath = Join-Path $PSScriptRoot "..\src\modules\Database.psm1"
        $content = Get-Content $databasePath -Raw

        $content | Should -Match "Copiar como Markdown"
        $content | Should -Match "New-DzMarkdownTableText"
        $content | Should -Match '\& \$module \{ param\(\$grid\) Get-DzDataGridSelectionTable'
    }
}
