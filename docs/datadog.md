# TC3-10: Datadog no EKS

## Componentes

- `platform/datadog.tf`: Agent por node, Cluster Agent, receptor OTLP gRPC (4317), coleta de logs por anotacao e metricas de infraestrutura.
- `monitoring/`: root Terraform independente que cria sete monitores e um SLO de disponibilidade interna de 99% em sete dias.
- Repositorio `tech_challenge`: Serilog/OTel, Correlation ID, healthchecks e anotacoes do Deployment.

O Agent envia dados para a conta Datadog. Serilog grava JSON em stdout; OpenTelemetry envia traces/metricas para o Agent **do mesmo node**. Nao instalar uma segunda instrumentacao automatica .NET nem outro Agent pelo assistente do Datadog.

## 1. Conta e Secret

No assistente Datadog, a plataforma e **Kubernetes / AWS EKS**, com infraestrutura, APM e logs. Use a instalacao deste repositorio para habilitar OTLP. Esta conta usa US1 (`https://app.datadoghq.com/`), portanto `datadog_site = "datadoghq.com"`; os arquivos dos dois ambientes ja registram esse site.

O assistente pode mostrar `helm install datadog-operator` e um Secret no namespace `datadog`. Esse caminho exige aplicar tambem um recurso `DatadogAgent`. Aqui o Terraform gerencia diretamente o chart `datadog` em `observability`; use a esteira ou o script de Secret deste repositorio, em vez de misturar comandos do Operator com o chart. Se uma API Key aparecer em chat, issue ou comando compartilhado, revogue-a em Organization Settings > API Keys e crie outra antes de continuar.

Para deploy pela esteira, configure uma nova chave como **Environment secret** `DATADOG_API_KEY` em GitHub > repositorio da infra > Settings > Environments > `homologacao` > Add secret. O job `apply homologacao` autentica no EKS, cria ou atualiza `datadog-secret` em `observability` e instala o Agent no mesmo deploy. Para producao, configure um secret separado com o mesmo nome no Environment `producao`. A chave nao entra no Git nem no state Terraform. Se o Secret ja existir no cluster, a esteira aceita a instalacao mesmo sem esse Environment secret; com ele configurado, a chave armazenada no GitHub atualiza o Secret em cada apply.

Os clusters configurados sao `tech-challenge-hml` e `tech-challenge-prod`, ambos em `us-east-1` na conta `213284176265`. A AWS CLI foi instalada neste computador para o usuario atual; abra um novo terminal PowerShell para atualizar o PATH, ou execute `aws.exe` de `%LOCALAPPDATA%\Programs\Amazon\AWSCLIV2`. O perfil local `[default]` continha credenciais temporarias expiradas em 2026-09-15; renove a sessao AWS pelo metodo da sua conta antes de consultar o EKS. Confira primeiro:

```powershell
aws sts get-caller-identity --region us-east-1
```

Com identidade valida na conta `213284176265`, gere o contexto do cluster desejado. Para comecar em homologacao:

```powershell
aws eks update-kubeconfig --region us-east-1 --name tech-challenge-hml
kubectl config current-context
kubectl get nodes
./scripts/Configure-DatadogSecret.ps1 -ClusterName tech-challenge-hml
```

Para producao, substitua `tech-challenge-hml` por `tech-challenge-prod`. O script verifica o ARN exato do contexto EKS antes de solicitar a API Key, para evitar gravar o Secret em outro cluster. Ele solicita a chave sem mostra-la e envia o Secret pelo stdin do kubectl. Nao passe a chave para Terraform, Git, appsettings ou para o Deployment da API. O chart requer a chave `api-key` dentro do Secret `datadog-secret`.

## 2. Agent

No arquivo de variaveis usado para aplicar `platform/`, configure:

```hcl
enable_datadog         = true
datadog_site           = "datadoghq.com"
datadog_api_key_secret = "datadog-secret"
```

Para CI/CD, adicione esses campos ao JSON do ambiente em `environments/producao/platform.tfvars.json` ou `environments/homologacao/platform.tfvars.json`. O pipeline existente preserva esses campos. Para execucao local, use seu arquivo de variaveis/backend ja configurado, revise o plano e aplique:

```powershell
terraform -chdir=platform init
terraform -chdir=platform plan -out=datadog.tfplan
terraform -chdir=platform apply datadog.tfplan
kubectl get pods -n observability
```

Em ambientes que usam S3, mantenha a configuracao do backend e `infra_state_config` daquele ambiente. Nao inicialize um state local paralelo ao state da pipeline. O Secret precisa existir ANTES de habilitar o chart. `enable_datadog` fica `false` por padrao ate essa configuracao ser feita.

O deploy do chart pode levar mais de dez minutos na primeira execucao, especialmente enquanto o EKS baixa imagens e cria DaemonSet/Cluster Agent. O Terraform aguarda ate 20 minutos. Se ainda falhar por timeout, verifique os eventos antes de reexecutar a pipeline:

```powershell
kubectl get pods -n observability -o wide
kubectl get events -n observability --sort-by=.lastTimestamp
kubectl describe pods -n observability
```

O receptor usa hostPort 4317 na rede privada dos nodes. Nao exponha essa porta em LoadBalancer/Ingress nem a internet. A API usa `status.hostIP`. Esta configuracao e para Managed Node Groups Linux; Fargate exige outra estrategia.

## 3. Publicar API

Publique as alteracoes do repositorio `tech_challenge` pela pipeline. O manifesto usa `IMAGE_TAG` com o SHA do commit tanto na imagem quanto no label de versao. `DD_ENV`/label sao `prod`; em homologacao, use `hml`, igual ao ambiente do Agent e dos monitores.

Verifique:

```powershell
kubectl rollout status deployment/api -n tech-challenge
kubectl logs deployment/api -n tech-challenge --tail=20
kubectl get pods -n observability -l app.kubernetes.io/component=agent
# Escolha um pod Agent da lista:
kubectl exec -n observability <agent-pod> -c agent -- agent status
kubectl exec -n observability <agent-pod> -c agent -- agent configcheck
```

No status/configcheck, verificar OTLP e `http_check`, e ausencia de falhas de autenticacao. No Datadog: Infrastructure/Kubernetes, APM com `service:tech-challenge-api`, Logs com `service:tech-challenge-api env:prod`, Metrics Explorer com `techchallenge.os.*` depois de executar operacoes de OS.

## 4. Monitores e uptime

O root `monitoring/` e validado no CI, mas seu apply e separado do deploy AWS. Requer **API Key + Application Key** com permissoes de monitores e SLO; o Agent requer somente API Key. O provider le `DD_API_KEY` e `DD_APP_KEY`. Use um gerenciador de segredos ou entrada protegida na sessao para definir essas variaveis, sem escrever as chaves nos comandos versionados.

Crie `monitoring/terraform.tfvars` (ignorado pelo Git):

```hcl
cluster_name            = "NOME-EXATO-DO-EKS"
environment             = "prod"
datadog_api_url          = "https://api.datadoghq.com/"
notification_recipients = "@seu-email"
```

Para EU, use `https://api.datadoghq.eu/`; para outros sites, consulte a API URL oficial. Os filtros devem corresponder aos dados ingeridos. Guarde o state de `monitoring/` com o mesmo cuidado dos outros roots; para uso compartilhado, configure backend remoto separado.

```powershell
terraform -chdir=monitoring init
terraform -chdir=monitoring plan -out=monitoring.tfplan
terraform -chdir=monitoring apply monitoring.tfplan
```

Monitores: CPU de usuario dos nodes >80%, memoria utilizavel <15%, nenhuma replica disponivel, falhas tecnicas de OS, liveness, readiness e logs de erro. Ausencia de dados alerta para disponibilidade; nao alerta para ausencia de erros de OS. Limiares sao iniciais para a demonstracao e podem ser ajustados em `monitoring/main.tf`. Com destinatarios vazios, alertas ficam apenas na interface.

O SLO usa readiness e replicas para acompanhar disponibilidade interna em sete dias. Ele precisa acumular historico; nao e correto apresentar 99% como resultado medido logo apos instalar. Para disponibilidade vista pelo cliente (DNS/ALB/TLS), adicione um teste Synthetic HTTP para a URL real quando ela estiver definida.

CPU/memoria dos containers tambem ficam no Kubernetes Explorer. Para um dashboard da banca, selecione: CPU e memoria da API, replicas disponiveis, `network.http.can_connect`, contagem de `techchallenge.os.operations`, `techchallenge.os.failures` por operacao e latencia no APM.

## Verificacao sem credenciais

```powershell
terraform -chdir=platform init -backend=false
terraform -chdir=platform test
terraform -chdir=monitoring init -backend=false
terraform -chdir=monitoring test
node --test tests/ci/terraform-config.test.mjs
```

Testes usam providers simulados. Eles nao confirmam ingestao na conta, consultas validadas pela API Datadog, autorizacao AWS nem conectividade real entre pods/nodes.

## Referencias

- [OTLP no Datadog Agent](https://docs.datadoghq.com/opentelemetry/interoperability/otlp_ingest_in_the_agent/)
- [Chart oficial](https://github.com/DataDog/helm-charts/tree/main/charts/datadog)
- [Correlacao OTel/logs](https://docs.datadoghq.com/opentelemetry/correlate/logs_and_traces/)
- [Monitores Terraform](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/monitor)
