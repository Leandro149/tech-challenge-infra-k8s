[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$')]
    [string]$SecretName = 'datadog-secret'
)

$ErrorActionPreference = 'Stop'
& kubectl get namespace observability -o name
if ($LASTEXITCODE -ne 0) { throw 'Provisione o namespace observability em platform/ antes de continuar.' }

$secureKey = Read-Host 'Datadog API Key' -AsSecureString
try {
    $apiKey = [System.Net.NetworkCredential]::new('', $secureKey).Password
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'API Key obrigatoria.' }
    $secret = @{
        apiVersion = 'v1'
        kind = 'Secret'
        metadata = @{ name = $SecretName; namespace = 'observability' }
        type = 'Opaque'
        stringData = @{ 'api-key' = $apiKey }
    }
    $secret | ConvertTo-Json -Depth 5 -Compress | & kubectl apply --server-side --field-manager=tc3-datadog-secret -f -
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar o Secret Datadog.' }
}
finally {
    $apiKey = $null
    $secret = $null
    $secureKey.Dispose()
}
