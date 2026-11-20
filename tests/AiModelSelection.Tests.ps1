Import-Module (Join-Path $PSScriptRoot '..\src\modules\AI.psm1') -Force -DisableNameChecking

Describe 'Seleccion de modelos Gemini' {
    InModuleScope AI {
        It 'ordena Flash estable y excluye 3.7, preview y otros tipos' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{
                    models = @(
                        @{ name = 'models/gemini-3.6-flash'; supportedGenerationMethods = @('generateContent') },
                        @{ name = 'models/gemini-3.7-flash'; supportedGenerationMethods = @('generateContent') },
                        @{ name = 'models/gemini-3.8-flash'; supportedGenerationMethods = @('generateContent') },
                        @{ name = 'models/gemini-3.9-flash'; supportedGenerationMethods = @('generateContent') },
                        @{ name = 'models/gemini-3.9-flash-preview'; supportedGenerationMethods = @('generateContent') },
                        @{ name = 'models/gemini-3.9-flash-tts'; supportedGenerationMethods = @('generateContent') },
                        @{ name = 'models/gemini-4-flash'; supportedGenerationMethods = @('countTokens') }
                    )
                }
            } -ParameterFilter { $Method -eq 'Get' }

            @(Get-DzAiFlashModelCandidates -ApiKey 'test-key') |
                Should -Be @('models/gemini-3.9-flash', 'models/gemini-3.8-flash', 'models/gemini-3.6-flash')
        }

        It 'usa el respaldo fijo cuando falla models.list' {
            Mock Invoke-RestMethod { throw 'Sin conexion' } -ParameterFilter { $Method -eq 'Get' }

            @(Get-DzAiFlashModelCandidates -ApiKey 'test-key') |
                Should -Be @('models/gemini-3.8-flash', 'models/gemini-3.6-flash', 'models/gemini-3.5-flash')
        }

        It 'revisa las paginas siguientes del catalogo' {
            Mock Invoke-RestMethod {
                if ($Uri -match 'pageToken=') {
                    return [pscustomobject]@{
                        models = @(@{ name = 'models/gemini-3.9-flash'; supportedGenerationMethods = @('generateContent') })
                    }
                }
                [pscustomobject]@{
                    models = @(@{ name = 'models/gemini-3.8-flash'; supportedGenerationMethods = @('generateContent') })
                    nextPageToken = 'next-page'
                }
            } -ParameterFilter { $Method -eq 'Get' }

            @(Get-DzAiFlashModelCandidates -ApiKey 'test-key') |
                Should -Be @('models/gemini-3.9-flash', 'models/gemini-3.8-flash')
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly
        }

        It 'reintenta con el siguiente Flash tras un 503 y conserva la configuracion compatible' {
            $script:requestBodies = @()
            Mock Invoke-RestMethod {
                [pscustomobject]@{
                    models = @(
                        @{ name = 'models/gemini-3.8-flash'; supportedGenerationMethods = @('generateContent') },
                        @{ name = 'models/gemini-3.6-flash'; supportedGenerationMethods = @('generateContent') }
                    )
                }
            } -ParameterFilter { $Method -eq 'Get' }
            Mock Invoke-RestMethod {
                $script:requestBodies += [pscustomobject]@{ Uri = $Uri; Body = ($Body | ConvertFrom-Json) }
                if ($Uri -match '3\.8-flash') { throw '503 Service Unavailable' }
                [pscustomobject]@{
                    candidates = @(@{ content = @{ parts = @(@{ text = 'Respuesta de prueba' }) } })
                }
            } -ParameterFilter { $Method -eq 'Post' }

            $result = Invoke-DzGeminiGenerateContent -Prompt 'SELECT 1' -ApiKey 'test-key' -IncludeMetadata

            $result.Model | Should -Be 'models/gemini-3.6-flash'
            $result.Text | Should -Be 'Respuesta de prueba'
            $script:requestBodies.Count | Should -Be 2
            $script:requestBodies[0].Body.generationConfig.thinkingConfig | Should -BeNullOrEmpty
            $script:requestBodies[1].Body.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'minimal'
        }

        It 'no consume otros modelos cuando la clave es invalida' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{
                    models = @(
                        @{ name = 'models/gemini-3.8-flash'; supportedGenerationMethods = @('generateContent') },
                        @{ name = 'models/gemini-3.6-flash'; supportedGenerationMethods = @('generateContent') }
                    )
                }
            } -ParameterFilter { $Method -eq 'Get' }
            Mock Invoke-RestMethod { throw '401 API_KEY_INVALID' } -ParameterFilter { $Method -eq 'Post' }

            { Invoke-DzGeminiGenerateContent -Prompt 'SELECT 1' -ApiKey 'invalid-key' } |
                Should -Throw '*API_KEY_INVALID*'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'Post' }
        }
    }
}
