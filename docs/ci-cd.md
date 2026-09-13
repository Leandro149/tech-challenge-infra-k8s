# TC3-09 — CI/CD da infraestrutura

Terraform CI/CD para a conta **213284176265**, região **us-east-1**. Autenticação no GitHub Actions por **OIDC**, sem access keys permanentes nos secrets.

## Fluxo

| Evento | Operação |
| --- | --- |
| Push em develop/main | fmt, init sem backend, validate e testes; nenhum apply |
| PR interna para develop | Validação e plan de homologação |
| PR interna para main | Validação e plan de produção |
| PR fechada sem merge | Validação, sem deploy |
| PR mesclada em develop | Validação do merge; plan/apply de infra, depois plan/apply de platform em homologação |
| PR mesclada em main | Mesmo fluxo em produção |
| PR de fork | Validação sem credenciais; merge aprovado aciona o deploy normalmente |
| Execução manual | Somente plan, escolhendo branch e ambiente correspondentes |

O `apply` depende de `pull_request_target.closed` com `merged=true`; não é acionado por push direto. Esse evento usa o contexto da branch base para permitir deploy de merges aprovados, inclusive de forks. Os jobs desse evento só executam após merge; código de PR aberta/fechada sem merge não é executado nesse contexto. O pipeline identifica o commit de merge e confere novamente evento/commit antes de autenticar. Para promover uma mudança, primeiro mesclar em `develop` e verificar homologação; depois abrir uma PR de `develop` para `main`.

### Separação

| Configuração | Homologação | Produção |
| --- | --- | --- |
| Branch | develop | main |
| Identificador Terraform | hml | prod |
| Cluster/VPC prefix | tech-challenge-hml | tech-challenge-prod |
| CIDR VPC | 10.40.0.0/16 | 10.50.0.0/16 |
| Bucket state | tech-challenge-tfstate-213284176265-hml | tech-challenge-tfstate-213284176265-prod |
| Environment de plan | homologacao-plan | producao-plan |
| Environment de apply | homologacao | producao |
| Demonstração ALB/HPA | Habilitada | Desabilitada |

Cada bucket usa as keys `infra/terraform.tfstate` e `platform/terraform.tfstate`. Não são utilizados Terraform Workspaces. Conta, bucket e roles são conferidos contra o ambiente; a plataforma verifica também o output `environment` do state AWS.

Os arquivos em `environments/` possuem somente configuração não secreta e são versionados. Ajuste instâncias, capacidade, tags e `hpa_workloads` nesses arquivos. O HPA da aplicação de produção deve apontar para um Deployment existente; esta pipeline não publica a aplicação de negócio.

## 1. Aplicar o bootstrap uma vez

### Pelo GitHub Actions

Para preparar S3/IAM sem instalar Terraform localmente, execute **Actions → Terraform bootstrap → Run workflow → main**. A workflow deve estar mesclada em `main`. Ela usa os Secrets AWS do Environment `producao`, com permissões de criação/configuração de S3 e IAM; a role de deploy dos clusters não possui as permissões necessárias ao bootstrap.

A execução prepara um bucket privado separado, `tech-challenge-tfstate-213284176265-bootstrap`, com criptografia, versionamento e TLS obrigatório, para guardar o state em `bootstrap/terraform.tfstate`. Também prepara os buckets de homologação/produção pela AWS CLI antes do Terraform, porque algumas contas acadêmicas bloqueiam leituras de Object Lock usadas pelo recurso `aws_s3_bucket` do provider. Depois executa init, fmt, validate, plan e apply de `bootstrap/`, criando ou atualizando as roles IAM. Reutiliza um provider GitHub OIDC existente e não aplica planos que contenham remoções. O bucket do próprio bootstrap é preparado via AWS CLI antes do Terraform e não é gerenciado pelo state dos clusters.

Confira as Variables no resumo da execução. Ao usar credenciais diretamente no deploy, copie também o `TF_ADMIN_PRINCIPAL_ARNS` sugerido para autorizar essa identidade no Kubernetes. Em seguida, reexecute o run do merge com evento `pull_request_target`; o run de push executa somente validações e o run de PR executa somente plan.

Se o primeiro plan do PR falhar com `NoSuchBucket`, falta executar o bootstrap. Após mesclar esta configuração, execute a workflow manual antes de reexecutar o deploy. Uma autenticação bem-sucedida não cria o bucket automaticamente.

Se já aplicou bootstrap localmente, preserve e migre seu state para esse backend antes de usar a workflow. Ela não importa automaticamente recursos existentes nem utiliza states locais. Não alterne entre bootstrap local e remoto sem migrar o state.

### Pelo computador

Use uma identidade AWS autorizada a criar buckets, provider OIDC, roles e políticas IAM. Configure antes a AWS CLI conforme [Acesso AWS](aws-access.md).

```powershell
$env:AWS_PROFILE = 'tech-challenge'
aws sts get-caller-identity
terraform -chdir=bootstrap init
terraform -chdir=bootstrap plan -out=bootstrap.tfplan
terraform -chdir=bootstrap apply bootstrap.tfplan
terraform -chdir=bootstrap output -json github_environment_variables
```

No fluxo local, crie e configure previamente os buckets `tech-challenge-tfstate-213284176265-hml` e `tech-challenge-tfstate-213284176265-prod` com versionamento, SSE-S3, bloqueio de acesso público e política que exige TLS. O Terraform de `bootstrap/` cria ou reutiliza o provider OIDC GitHub e cria quatro roles com sessões de até duas horas. O state do bootstrap começa local: preserve-o fora do Git e em backup seguro. Se desejar migrá-lo, use um backend dedicado ao bootstrap, com uma identidade operadora autorizada; as roles dos clusters não acessam esse state.

Se já existir o provider `token.actions.githubusercontent.com` na conta, informe o ARN para reutilizá-lo:

```powershell
terraform -chdir=bootstrap plan -var='existing_github_oidc_provider_arn=arn:aws:iam::213284176265:oidc-provider/token.actions.githubusercontent.com' -out=bootstrap.tfplan
terraform -chdir=bootstrap apply bootstrap.tfplan
```

A role de plan possui ações de descoberta/leitura AWS e acesso ao state do seu ambiente. Pode escrever/excluir apenas os objetos `.tflock` usados pelo locking, sem gravar o state. A role de apply possui as ações dos serviços usadas pelo Terraform, com IAM limitado às roles/política da aplicação. Não recebe `AdministratorAccess` nem permissão de alterar as roles do bootstrap.

Nesta configuração acadêmica, as permissões de EC2/EKS da role de apply abrangem esses serviços na conta. Os ambientes ficam separados por recursos, buckets e roles; essa separação não constitui uma fronteira de segurança entre contas AWS.

## 2. Preparar os runners

Os jobs AWS podem rodar em `ubuntu-latest` para o ambiente acadêmico ou em **runners self-hosted Linux com IP público de saída fixo** para uma configuração mais controlada. Terraform 1.13.5 e Node 22 são instalados pelas actions. O runner precisa acessar GitHub, AWS APIs, Terraform Registry, repositórios Helm e a API pública do EKS por HTTPS.

Para evitar configurar uma máquina self-hosted, use:

```json
["ubuntu-latest"]
```

Nesse modo, o IP de saída do GitHub Actions pode variar. Configure `EKS_PUBLIC_ACCESS_CIDRS` com os dois blocos abaixo para permitir que a checagem de IP e o acesso inicial ao EKS funcionem:

```json
["0.0.0.0/1", "128.0.0.0/1"]
```

Sugestão de labels:

```json
["self-hosted", "linux", "x64", "terraform-hml"]
```

```json
["self-hosted", "linux", "x64", "terraform-prod"]
```

Se optar por self-hosted, o runner de provisionamento deve existir fora do cluster EKS que ele cria. O runner pode usar saída por NAT com Elastic IP. Seu IP de saída precisa constar em `EKS_PUBLIC_ACCESS_CIDRS`; inclua também o IP/rede dos operadores que administrarão o Kubernetes.

O pipeline confere o IP real via `checkip.amazonaws.com` e falha se ele não estiver autorizado. Não adiciona IPs à VPC/EKS durante um plano de PR.

## 3. Configurar os GitHub Environments

Em **Settings → Environments**, crie:

- `homologacao-plan`
- `homologacao`
- `producao-plan`
- `producao`

Configure as seguintes **Variables**, usando os valores do output do bootstrap. Repita a configuração de homologação nos dois Environments de homologação e a de produção nos dois Environments de produção.

| Variable | Valor |
| --- | --- |
| AWS_ROLE_ARN | Role de apply do ambiente, conforme output |
| AWS_PLAN_ROLE_ARN | Role de plan do ambiente, conforme output |
| TF_STATE_BUCKET | Bucket do ambiente, conforme output |
| TF_RUNNER_LABELS | Array JSON das labels do runner correspondente |
| EKS_PUBLIC_ACCESS_CIDRS | Array JSON com CIDRs autorizados no EKS, incluindo o runner |
| DEMO_INGRESS_CIDRS | Array JSON dos CIDRs autorizados no ALB; obrigatório em homologação; em produção pode ser `[]` |
| TF_ADMIN_PRINCIPAL_ARNS | Opcional: array JSON das roles/users IAM de operadores do Kubernetes |

Formato dos CIDRs, substituindo os endereços de documentação pelos IPs reais:

```json
["203.0.113.10/32", "198.51.100.20/32"]
```

Exemplo de operador adicional:

```json
["arn:aws:iam::213284176265:role/SuaRoleDeOperacao"]
```

Para a configuração acadêmica, também é possível cadastrar `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e, quando a credencial for temporária, `AWS_SESSION_TOKEN` como **Secrets** do Environment. Quando esses secrets existem, a action usa essas credenciais diretamente. Se eles não existirem, a action usa OIDC com `id-token: write`, role por Environment e account ID autorizado.

Restrinja as branches de deploy: `homologacao` somente `develop`, `producao` somente `main`. Os Environments `*-plan` precisam aceitar `refs/pull/*/merge` para PRs e a branch correspondente para planos manuais. Proteja `develop` e `main` exigindo PR e os checks de CI antes do merge. As workflows não adicionam uma aprovação manual ao apply após merge.

O subject OIDC corresponde ao Environment, por exemplo `repo:Leandro149/tech-challenge-infra-k8s:environment:producao`; as regras de branch dos Environments completam a restrição do acesso. [Documentação GitHub/AWS OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

## 4. Primeiro merge e ambientes existentes

Na primeira PR, não existem states do cluster/plataforma nem o RBAC Kubernetes da role de plan. O pipeline executa plan de infra e registra no Job Summary que o plan da plataforma foi adiado. Depois do merge, a role de apply provisiona o EKS e faz plan/apply da plataforma, incluindo o RBAC de leitura.

Nas próximas PRs, são planejadas as duas etapas. A role de plan entra no EKS pelo grupo `terraform-plan`, com `get/list/watch`. Essa leitura inclui secrets porque Helm guarda os releases em secrets; não há permissões de escrita Kubernetes para essa role. Um erro 403 ao consultar S3 falha a pipeline, em vez de ser interpretado como ausência de state.

States locais do ambiente `dev` não são usados automaticamente em homologação/produção. Se houver infraestrutura existente a preservar, migrar/importar explicitamente seus states antes de aplicar; do contrário, estes ambientes criam recursos novos.

## Operação

Os comandos são executados em diretórios temporários montados com código Terraform e configuração do ambiente. Arquivos locais `access.auto.tfvars`, `terraform.tfvars`, caches e credenciais não são copiados. O locking S3 utiliza `use_lockfile=true` e espera até dez minutos por locks.

Cada ambiente/operação possui grupo de concorrência, com `cancel-in-progress=false`; um plano de PR não substitui um apply pendente. O GitHub mantém o run corrente e o mais recente pendente de cada grupo. Os locks dos backends coordenam o acesso aos states entre plan e apply.

Antes de autenticar para apply, o job confere se o commit de merge ainda é o commit atual da branch base. Se um job antigo sair da fila depois de um merge mais recente, ele falha sem aplicar código antigo; use o run do merge atual. O token GitHub desse check possui apenas leitura e fica restrito a essa etapa.

O plano binário permanece no diretório temporário do job e o apply utiliza esse arquivo na mesma execução. Não há publicação de artifacts binários de planos/states nem consumo de planos de PR para aplicar merges. Detalhes ficam nos logs Terraform e o resultado vai para o Job Summary.

Se falhar após aplicar infra, corrija o problema e reexecute o run do merge; o Terraform reconcilia infra e depois tenta a plataforma. Não há rollback automático. Para remoção, seguir a ordem plataforma → infra no README, configurando os backends/configurações do ambiente correto; não executar destroy com o state local `dev` esperando remover homologação/produção.

Cada ambiente provisionado mantém seu próprio EKS, dois nodes, NAT e demais recursos cobrados. Esta entrega não executa automaticamente destroy de homologação/produção.

## Verificação local

```powershell
terraform fmt -check -recursive
terraform -chdir=bootstrap init -backend=false -input=false
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap test
terraform -chdir=infra validate
terraform -chdir=infra test
terraform -chdir=platform validate
terraform -chdir=platform test
node --test tests/ci/terraform-config.test.mjs
```

Se ainda não tiver inicializado infra/platform, executar `init -backend=false` nesses diretórios antes de validate/test. A CI executa init nos três roots. Os testes usam providers simulados e nenhum recurso AWS é criado.

Referência do state/locking: [Backend S3 do Terraform](https://developer.hashicorp.com/terraform/language/backend/s3).
