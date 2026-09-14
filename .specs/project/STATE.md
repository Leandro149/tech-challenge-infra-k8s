# Estado da entrega

Atualizado em 2026-09-13.

## Entrega

- R01–R05 implementados em infra/ e platform/.
- Formatação e validação Terraform aprovadas nas duas etapas.
- Quinze testes com providers simulados aprovados: sete infra, seis platform e dois bootstrap; somente plans. Treze testes Node de CI/CD aprovados.
- Charts AWS Load Balancer Controller 3.5.0 e Metrics Server 3.14.0 passaram em helm lint e helm template com Kubernetes 1.35.
- Providers fixados em lockfiles; checksums de Windows/Linux amd64.
- README em português, exemplos tfvars, backend S3 opcional e CI de validação.

## Decisões

- Separar state AWS e state Kubernetes para evitar inicializar providers antes da existência da API do cluster.
- Não usar bootstrap de administrador implícito; exigir ARN IAM de administrador e CIDRs autorizados.
- Nodes AL2023 x86_64 privados; dois nodes t3.medium ON_DEMAND por padrão.
- IRSA separado para CNI e controller; política oficial do controller vendorizada na mesma versão do chart.
- Um NAT Gateway para a entrega acadêmica; saída concentra-se em uma AZ.
- Exemplo ALB/HPA habilitado por padrão; configuração de HPA para Deployment da aplicação disponível.
- HPA controla pods; Node Groups têm capacidade configurável sem autoscaler de nodes.

## Pendências do operador

- Instalar Terraform/AWS CLI no ambiente de execução; na validação local, Terraform e Helm foram usados de forma portátil no diretório temporário.
- Configurar um perfil AWS CLI com credenciais completas e válidas. Conta informada: 213284176265; região us-east-1. Credenciais temporárias recebidas sem session token, portanto não foi possível autenticar; nenhum segredo foi gravado no repositório.
- Executar scripts/Configure-AwsEnvironment.ps1 para validar identidade e gerar ARN IAM/CIDRs em arquivos access.auto.tfvars locais, ignorados pelo Git. O arquivo local infra/access.auto.tfvars já contém conta/região, sem administrador/CIDR até a autenticação.
- Ajustar capacidade, tags e opções de state para a conta.
- Executar plan/apply com credenciais próprias e verificar a entrega na AWS conforme README.
- Publicar os commits locais no remoto quando desejar; aplicar bootstrap e configurar os quatro GitHub Environments e runners Linux de IP fixo conforme docs/ci-cd.md.

## Limitações da validação

Nenhum recurso AWS foi criado. Testes simulados e validação sintática não comprovam quotas, permissões, disponibilidade regional, convergência dos controllers ou resposta HTTP. A CI foi criada; sua execução no GitHub depende da publicação do repositório.

## Configuração de acesso AWS

- Provider AWS com allowed_account_ids baseado em aws_account_id; exemplo atualizado para a conta informada.
- Script PowerShell validado por análise sintática e cinco cenários simulados: IAM user, role com path, conta errada, falha de sessão e IP inválido. Não usou credenciais reais nem acessou a conta AWS.
- Sessões STS resolvidas para role IAM via GetRole para preservar paths; o script também aceita ARN IAM explícito.
- Arquivos terraform.tfvars existentes preservados; conta, região, AZs, administrador e CIDRs gerados em access.auto.tfvars com precedência documentada.
- docs/aws-access.md descreve configuração do perfil fora do repositório e renovação das credenciais temporárias.
- Workflows TC3-09 implementadas; execução AWS depende de aplicar bootstrap OIDC/S3 e configurar Environments/runners. Nenhuma workflow AWS foi executada nesta validação local.

## TC3-09 — CI/CD

### Bootstrap manual pelo GitHub (2026-09-13)

- Run de bootstrap 34790992720 autenticou e avançou até o apply, mas a conta negou `s3:GetBucketObjectLockConfiguration` por Service Control Policy ao ler `aws_s3_bucket.state["homologacao"]`.
- Bootstrap ajustado para preparar os buckets de state hml/prod pela AWS CLI da workflow e deixar o Terraform gerenciar somente OIDC/IAM, evitando a leitura de Object Lock bloqueada pelo provider. Outputs e policies usam nomes/ARNs calculados.
- Run de bootstrap 34791395026 ainda encontrou endereços `aws_s3_bucket*.state[...]` herdados no state remoto e falhou antes do apply. A workflow agora remove somente esses endereços legados do state remoto antes do plan; os buckets AWS permanecem existentes e configurados pela AWS CLI.

- Correção do primeiro bootstrap: state list pode retornar "No state file was found!" antes do primeiro apply. Esse caso segue com lista vazia; falhas de acesso ou state inválido continuam interrompendo o job. Teste executa a etapa Bash com cinco cenários simulados, sem chamadas AWS.

- Run de PR 34788543879 autenticou com secrets, mas falhou no init por NoSuchBucket no bucket de produção.
- Workflow Terraform bootstrap adicionada: execução manual em main com Environment producao, armazenamento remoto separado e persistente, reutilização de provider OIDC e plan/apply de S3/IAM antes do deploy.
- Operador deve executar bootstrap com credenciais S3/IAM autorizadas, configurar Variables do resumo e reexecutar o run de merge. Nenhum bucket foi criado nesta sessão local.
- State local anterior precisa ser migrado antes de usar bootstrap remoto; não há importação automática de recursos existentes.
- Verificação local: actionlint aprovado, seis scripts Bash com sintaxe válida, quatro cenários de credenciais e HCL do backend verificados, 14 testes Node aprovados. Não foram feitas chamadas AWS nesses testes.

### Correção de autenticação do deploy (2026-09-13)

- Run de merge 34788252271 iniciou apply em ubuntu-latest, mas falhou no OIDC antes de executar Terraform.
- Secrets STATIC_AWS_* estavam somente no job prepare; movidos para o job terraform que autentica e executa plan/apply. Caller passa secrets com inherit.
- Credenciais parciais e chaves temporárias sem session token agora falham com mensagem específica, sem exibir valores secretos.
- Apply não é cancelado por uma nova execução concorrente; somente planos podem ser substituídos.
- Verificação local: 14 testes Node aprovados e actionlint sem erros. Publicação AWS ainda depende da autenticação válida e do bootstrap existente.

- develop -> homologacao/hml; main -> producao/prod. Buckets, VPCs, clusters, roles e configurações diferentes.
- Push executa somente CI. PR interna executa plan; closed/merged executa novo plan/apply no commit de merge. Forks sem plan AWS antes do merge; manual somente plan.
- Reusable workflow com preflight, OIDC plan/apply, diretórios temporários sem tfvars locais, locking S3 e grupos de concorrência por ambiente/operação.
- Bootstrap com provider GitHub OIDC reutilizável, buckets privados/versionados/SSE-S3/TLS e roles específicas. Policies de EC2/EKS da role apply são amplas nesses serviços da conta; separação lógica não equivale a contas AWS separadas.
- EKS Access Entry readonly e RBAC get/list/watch para plan; inclui secrets para leitura de releases Helm. Admin de apply e operadores opcionais configurados pela pipeline.
- Primeiro plan de plataforma em PR adiado se states infra/platform não existirem; merge cria AWS antes do plano/apply Kubernetes. Falha S3 de acesso não é tratada como state inexistente.
- Output environment e postcondition da leitura do state evitam cruzar ambientes. Produção sem aplicação demonstrativa não exige CIDR de ALB.
- actionlint local aprovou as duas workflows; testes Node verificaram roteamento/merge/fork, roles/buckets, IP e isolamento de parâmetros, códigos do plan e state inicial.
- Check de commit atual da branch antes do apply impede que jobs antigos na fila apliquem código anterior a um merge mais recente.
