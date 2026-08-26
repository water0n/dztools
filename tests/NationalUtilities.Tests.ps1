$modulePath = Join-Path $PSScriptRoot "..\src\modules\NationalUtilities.psm1"

Add-Type -AssemblyName PresentationFramework
Import-Module $modulePath -Force

AfterAll {
    Remove-Module NationalUtilities -Force -ErrorAction SilentlyContinue
}

Describe "Permisos NationalSoft" {
    InModuleScope NationalUtilities {
        It "concede Full Control a Everyone con herencia para carpetas y archivos" {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) ("dztools-permissions-{0}" -f [Guid]::NewGuid())
            $job = $null
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null

            try {
                $job = Start-Job -ScriptBlock $script:SetNSEveryoneFullControlWorker -ArgumentList $testPath
                Wait-Job -Job $job -Timeout 15 | Out-Null
                $job.State | Should -Be "Completed"
                $result = Receive-Job -Job $job
                $result.Ok | Should -BeTrue

                $directoryInfo = New-Object System.IO.DirectoryInfo($testPath)
                $acl = $directoryInfo.GetAccessControl()
                $rules = $acl.GetAccessRules(
                    $true,
                    $true,
                    [System.Security.Principal.SecurityIdentifier]
                )
                $everyoneSid = New-Object System.Security.Principal.SecurityIdentifier(
                    [System.Security.Principal.WellKnownSidType]::WorldSid,
                    $null
                )
                $everyoneRules = @($rules | Where-Object {
                        $_.IdentityReference.Value -eq $everyoneSid.Value -and
                        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
                        ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -eq
                            [System.Security.AccessControl.FileSystemRights]::FullControl
                    })

                $everyoneRules.Count | Should -BeGreaterThan 0
                ($everyoneRules[0].InheritanceFlags -band [System.Security.AccessControl.InheritanceFlags]::ContainerInherit) |
                    Should -Be ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit)
                ($everyoneRules[0].InheritanceFlags -band [System.Security.AccessControl.InheritanceFlags]::ObjectInherit) |
                    Should -Be ([System.Security.AccessControl.InheritanceFlags]::ObjectInherit)
            } finally {
                if ($job) {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                }
                Remove-Item -LiteralPath $testPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "falla claramente cuando la carpeta no existe" {
            $missingPath = Join-Path ([System.IO.Path]::GetTempPath()) ("dztools-missing-{0}" -f [Guid]::NewGuid())
            $job = Start-Job -ScriptBlock $script:SetNSEveryoneFullControlWorker -ArgumentList $missingPath
            try {
                Wait-Job -Job $job -Timeout 15 | Out-Null
                $job.State | Should -Be "Completed"
                $result = Receive-Job -Job $job
                $result.Ok | Should -BeFalse
                $result.Error | Should -Match "no existe"
            } finally {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
