# Acesso à conta AWS do projeto

Conta configurada: **213284176265**. Região: **us-east-1**.

O Terraform usa as credenciais do ambiente/perfil AWS CLI; não há chaves nos arquivos Terraform. `aws_account_id` restringe o provider à conta informada. `infra/access.auto.tfvars` contém localmente essa conta e região; o script abaixo completa administrador e rede após uma autenticação válida.

## 1. Configurar autenticação local

Instale a [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html). Configure um perfil chamado `tech-challenge`, ou informe outro nome ao script.

Para credenciais temporárias, configure no arquivo **fora do repositório** `$env:USERPROFILE/.aws/credentials`:

```ini
[tech-challenge]
aws_access_key_id = NOVA_ACCESS_KEY
aws_secret_access_key = NOVA_SECRET_KEY
aws_session_token = NOVO_SESSION_TOKEN
```

Substitua os placeholders localmente por valores da mesma sessão. Preserve outros perfis existentes. Credenciais de sessão expiram e precisam ser renovadas juntas. Uma chave temporária exige o session token além da access key e secret key. [Documentação AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_use-resources.html).

Em `$env:USERPROFILE/.aws/config`, configure:

```ini
[profile tech-challenge]
region = us-east-1
output = json
```

Se a conta tiver IAM Identity Center, também é possível usar `aws configure sso --profile tech-challenge` e `aws sso login --profile tech-challenge`, sem adicionar chaves ao arquivo de credentials. [Configuração de perfis](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html).

As credenciais compartilhadas no chat devem ser substituídas e a sessão anterior revogada conforme seu método de emissão. Não copie essas credenciais para o repositório, tfvars, issues ou logs.

## 2. Validar identidade e gerar parâmetros

Em um terminal PowerShell sem `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` definidos no ambiente, execute na raiz do repositório:

```powershell
aws sts get-caller-identity --profile tech-challenge --region us-east-1
& ./scripts/Configure-AwsEnvironment.ps1 -Profile tech-challenge
```

O script faz apenas consultas: verifica a conta via STS, resolve o ARN IAM de uma sessão de role com `iam:GetRole`, consulta seu IPv4 público e gera `infra/access.auto.tfvars` e `platform/access.auto.tfvars`. Não executa plan/apply, não cria recursos AWS e não escreve credenciais. Os arquivos gerados são ignorados pelo Git.

O ARN de administrador deve corresponder à identidade usada para executar a plataforma. Se a sessão não permitir `iam:GetRole`, informe o ARN IAM original da role, incluindo o path:

```powershell
& ./scripts/Configure-AwsEnvironment.ps1 -Profile tech-challenge -AdminPrincipalArn 'arn:aws:iam::213284176265:role/seu-path/SuaRole'
```

Para informar o IP de saída manualmente:

```powershell
& ./scripts/Configure-AwsEnvironment.ps1 -Profile tech-challenge -PublicIp 'SEU_IPV4_PUBLICO'
```

Os arquivos `.auto.tfvars` têm precedência sobre `terraform.tfvars` para conta, região, AZs, ARN administrador e CIDRs. Instâncias, capacidade, tags, namespaces e opções de state continuam configuráveis normalmente. Execute o script novamente quando seu IP ou sua identidade mudar.

O script seleciona `AWS_PROFILE` no terminal atual. Se abrir outro terminal, configure `$env:AWS_PROFILE = 'tech-challenge'` antes de executar Terraform. Não use credenciais de ambiente simultaneamente ao perfil: o provider Terraform pode selecionar essas credenciais antes do perfil. [Precedência de configuração AWS](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html).

## 3. Conferir permissões e preparar o plano

A identidade precisa de permissões para VPC/EC2, EKS, criação e configuração de roles e políticas IAM, provider OIDC, `iam:PassRole` e logs CloudWatch. Identidade válida no STS não comprova essas permissões.

```powershell
terraform -chdir=infra init
terraform -chdir=infra plan -out=infra.tfplan
```

Depois de revisar o plano, seguir as etapas de apply e verificação no README. Sem credenciais completas e válidas, não é possível verificar a conta real nem configurar recursos nela.

## GitHub Actions

As workflows do TC3-09 executam validação offline, plan em PRs internas e apply após merge, com homologação e produção separadas. Para ativar os jobs AWS, aplicar o Terraform de bootstrap e configurar os Environments/runners conforme [CI/CD](ci-cd.md). Esses recursos ainda não foram criados na conta AWS. Chaves locais não são utilizadas pelo GitHub Actions; os jobs AWS autenticam por OIDC.
