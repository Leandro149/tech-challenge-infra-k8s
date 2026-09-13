[CmdletBinding()]
param(
  [ValidateNotNullOrEmpty()]
  [string]$Profile = 'tech-challenge',
  [string]$AdminPrincipalArn,
  [string]$PublicIp
)

$ErrorActionPreference = 'Stop'
$taskAccountId = '213284176265'
$taskRegion = 'us-east-1'
$taskRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
  throw 'Instale a AWS CLI v2 e configure um perfil antes de executar este script.'
}

# Credenciais de ambiente têm precedência sobre AWS_PROFILE no Terraform.
foreach ($taskCredentialName in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN')) {
  if (Test-Path "Env:$taskCredentialName") {
    throw "A variável $taskCredentialName está definida. Use um terminal sem credenciais de ambiente para selecionar o perfil AWS."
  }
}

function Invoke-AwsJson {
  param([string[]]$AwsArguments)

  $taskAwsResult = & aws @AwsArguments --profile $Profile --region $taskRegion --output json --no-cli-pager
  if ($LASTEXITCODE -ne 0) {
    throw 'A AWS CLI falhou. Confira o perfil, a validade da sessão e as permissões. Sessões temporárias exigem session token.'
  }
  return ($taskAwsResult | ConvertFrom-Json)
}

$taskIdentity = Invoke-AwsJson -AwsArguments @('sts', 'get-caller-identity')
if ($taskIdentity.Account -ne $taskAccountId) {
  throw "O perfil não pertence à conta esperada $taskAccountId. Nenhum parâmetro foi gerado."
}

if (-not $AdminPrincipalArn) {
  if ($taskIdentity.Arn -match '^arn:aws:iam::[0-9]{12}:user/.+$') {
    $AdminPrincipalArn = $taskIdentity.Arn
  } elseif ($taskIdentity.Arn -match '^arn:aws:sts::[0-9]{12}:assumed-role/([^/]+)/[^/]+$') {
    $taskRoleName = $Matches[1]
    # Consultar IAM preserva o path da role, ausente no ARN da sessão STS.
    $taskRole = Invoke-AwsJson -AwsArguments @('iam', 'get-role', '--role-name', $taskRoleName)
    $AdminPrincipalArn = $taskRole.Role.Arn
  } else {
    throw 'Use um user ou role IAM. Para uma sessão de role, informe -AdminPrincipalArn com o ARN IAM original.'
  }
}

if ($AdminPrincipalArn -notmatch "^arn:aws:iam::${taskAccountId}:(role|user)/.+$") {
  throw 'O administrador deve ser uma role ou user IAM da conta esperada. Não use ARN STS de sessão.'
}

if (-not $PublicIp) {
  $PublicIp = ([string](Invoke-RestMethod -Uri 'https://checkip.amazonaws.com' -TimeoutSec 30)).Trim()
}
$taskParsedIp = $null
if (-not [System.Net.IPAddress]::TryParse($PublicIp, [ref]$taskParsedIp) -or
    $taskParsedIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
    $taskParsedIp.ToString() -eq '0.0.0.0') {
  throw 'Informe um endereço IPv4 de saída válido com -PublicIp, sem /32. Nenhum parâmetro foi gerado.'
}
$taskAccessCidr = "$($taskParsedIp.ToString())/32"

# Somente dados não secretos. Os arquivos .auto.tfvars são ignorados pelo Git.
# Eles complementam terraform.tfvars sem sobrescrever customizações existentes.
$taskInfraValues = [ordered]@{
  aws_account_id = (ConvertTo-Json -InputObject $taskAccountId -Compress)
  aws_region = (ConvertTo-Json -InputObject $taskRegion -Compress)
  availability_zones = '["us-east-1a", "us-east-1b"]'
  cluster_admin_principal_arns = '[' + (ConvertTo-Json -InputObject $AdminPrincipalArn -Compress) + ']'
  cluster_endpoint_public_access_cidrs = '[' + (ConvertTo-Json -InputObject $taskAccessCidr -Compress) + ']'
}
$taskNameWidth = 'cluster_endpoint_public_access_cidrs'.Length
$taskInfraLines = foreach ($taskEntry in $taskInfraValues.GetEnumerator()) {
  $taskEntry.Key.PadRight($taskNameWidth) + ' = ' + $taskEntry.Value
}
$taskPlatformLine = 'demo_ingress_cidrs = [' + (ConvertTo-Json -InputObject $taskAccessCidr -Compress) + ']'
$taskUtf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $taskRepoRoot 'infra/access.auto.tfvars'), ($taskInfraLines -join "`n") + "`n", $taskUtf8)
[System.IO.File]::WriteAllText((Join-Path $taskRepoRoot 'platform/access.auto.tfvars'), $taskPlatformLine + "`n", $taskUtf8)

$env:AWS_PROFILE = $Profile
$env:AWS_REGION = $taskRegion
$env:AWS_DEFAULT_REGION = $taskRegion

Write-Host "Perfil validado na conta $taskAccountId, região $taskRegion."
Write-Host "Administrador Kubernetes: $AdminPrincipalArn"
Write-Host "CIDR autorizado para API EKS e demonstração: $taskAccessCidr"
Write-Host 'Parâmetros locais gerados. Nenhum recurso AWS foi provisionado.'
Write-Host 'Execute terraform -chdir=infra init e terraform -chdir=infra plan para revisar a infraestrutura.'
