# TC3-06 — Terraform do Kubernetes / EKS

Repositório de infraestrutura do Tech Challenge. Provisiona uma VPC, Amazon EKS com Managed Node Groups e IAM; configura namespaces, Load Balancer Controller, Metrics Server e HPA com Terraform.

## Atendimento aos requisitos

| Requisito | Entrega |
| --- | --- |
| VPC e Amazon EKS | VPC em duas AZs, duas subnets públicas, duas privadas, Internet Gateway e NAT Gateway; EKS Kubernetes 1.35 configurável |
| Node Groups | Managed Node Groups privados com AL2023, instâncias e capacidade mínima/desejada/máxima configuráveis |
| IAM | Roles do cluster e nodes, EKS Access Entries para administradores e IRSA exclusivo para VPC CNI e Load Balancer Controller |
| Load Balancer | AWS Load Balancer Controller via Helm; exemplo de Ingress que provisiona ALB público com targets IP e acesso restrito por CIDR |
| HPA e namespaces | Namespaces `tech-challenge` e `observability`, Metrics Server e HPA `autoscaling/v2` por CPU |

## Organização

```text
infra/                   # Recursos AWS e outputs para a plataforma
  policies/              # Política IAM oficial versionada do controller
  tests/                 # Planos simulados, sem acessar a AWS
  terraform.tfvars.example
platform/                # Recursos Kubernetes e charts Helm
  tests/                 # Planos simulados, sem acessar um cluster
  terraform.tfvars.example
docs/                    # Exemplo opcional de backend S3
.github/workflows/       # Validação automática de Terraform
.specs/                  # Requisitos e decisões da entrega
```

São dois projetos Terraform, com states independentes. Primeiro aplicar `infra/`; depois `platform/`. Essa separação permite que a API Kubernetes exista e esteja acessível antes da inicialização dos providers Kubernetes/Helm. Destruir na ordem inversa.

Os nodes e pods ficam nas subnets privadas. O ALB público ocupa as subnets públicas e encaminha tráfego aos IPs dos pods. O endpoint privado do EKS atende os nodes; o endpoint público permite administração somente pelos CIDRs informados. As subnets possuem tags para descoberta pelo controller.

## Pré-requisitos

- Terraform **>= 1.13 e < 2.0**; CI validada com **1.13.5**.
- AWS CLI **v2** instalada e credenciais válidas, por perfil, SSO ou variáveis de ambiente.
- `kubectl` compatível com a versão do cluster, para verificação.
- Permissões na conta para criar VPC, EC2, EKS, IAM, CloudWatch e passar as roles criadas ao EKS/EC2.
- Uma role ou user IAM existente para administrar o cluster, incluída em `cluster_admin_principal_arns`.
- Quota de EC2/EKS e disponibilidade dos tipos de instância nas AZs escolhidas.

Helm CLI é opcional: o provider Helm instala os charts. Não é necessário instalar Helm para executar o Terraform.

Verifique suas credenciais:

```powershell
$env:AWS_PROFILE = "seu-perfil"
aws sts get-caller-identity
```

Se a resposta retornar `arn:aws:sts::...:assumed-role/RoleName/session`, use o ARN IAM da role original em `cluster_admin_principal_arns`, por exemplo `arn:aws:iam::123456789012:role/RoleName`. Inclua o path completo se a role tiver um. Execute `platform/` usando uma identidade autorizada por essa lista.

## 1. Configurar os parâmetros

Na raiz do repositório:

```powershell
Copy-Item infra/terraform.tfvars.example infra/terraform.tfvars
Copy-Item platform/terraform.tfvars.example platform/terraform.tfvars
```

Edite os arquivos copiados:

- Em `infra/terraform.tfvars`, substitua o ARN de exemplo e `cluster_endpoint_public_access_cidrs` pelo IP público de saída do operador/runner, no formato `IP/32`, ou pelo CIDR da sua rede.
- Em `platform/terraform.tfvars`, substitua `demo_ingress_cidrs` pelo IP/CIDR autorizado a acessar a demonstração.
- Ao mudar `aws_region`, atualize também `availability_zones` para duas AZs da região escolhida.
- Ajuste nome, ambiente, instâncias e tamanhos dos Node Groups conforme necessário. Os tipos de instância devem ser compatíveis com a AMI **x86_64** configurada.

`203.0.113.10` e `123456789012` são placeholders. `0.0.0.0/0` é rejeitado para a API do EKS e para o ALB da demonstração. Se seu IP público mudar, atualize o CIDR do EKS em `infra/` antes de executar `platform/`.

Os arquivos `terraform.tfvars`, states e planos são ignorados pelo Git. Os arquivos `.terraform.lock.hcl` são versionados para fixar as versões dos providers.

## 2. Provisionar VPC, IAM e EKS

```powershell
terraform -chdir=infra init
terraform -chdir=infra validate
terraform -chdir=infra plan -out=infra.tfplan
terraform -chdir=infra apply infra.tfplan
```

O plano e o apply precisam de credenciais AWS e criam recursos cobrados. Revise o plano antes de aplicar. A criação do cluster e dos nodes pode levar vários minutos.

Configure o acesso local:

```powershell
$clusterName = terraform -chdir=infra output -raw cluster_name
$clusterRegion = terraform -chdir=infra output -raw aws_region
aws eks update-kubeconfig --region $clusterRegion --name $clusterName
kubectl get nodes
```

Todos os nodes devem estar `Ready`. Os add-ons VPC CNI, kube-proxy e CoreDNS são gerenciados pelo EKS. O Terraform seleciona a versão mais recente compatível no momento do plan; revise mudanças de versões nos próximos planos. O cluster envia logs do control plane ao CloudWatch com retenção de sete dias.

## 3. Configurar a plataforma Kubernetes

```powershell
terraform -chdir=platform init
terraform -chdir=platform validate
terraform -chdir=platform plan -out=platform.tfplan
terraform -chdir=platform apply platform.tfplan
```

Por padrão, a plataforma lê `../infra/terraform.tfstate`. A autenticação dos providers usa `aws eks get-token` com as credenciais atuais, renovando o token quando necessário.

Com `enable_demo = true`, cria o Deployment `tc3-demo`, Service ClusterIP, Ingress e HPA. O controller provisiona o ALB a partir do Ingress; não há um `aws_lb` separado. A URL é exibida após o apply:

```powershell
terraform -chdir=platform output -raw demo_url
```

A demonstração usa HTTP e a imagem oficial `registry.k8s.io/hpa-example:latest`, adequada para verificar HPA sob carga. Para aplicação real, utilize imagem versionada/digest e configure Ingress HTTPS com certificado ACM.

## Verificar a entrega na AWS

```powershell
kubectl get namespaces
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=600s
kubectl -n kube-system rollout status deployment/metrics-server --timeout=600s
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl -n tech-challenge get deployments,services,ingresses,hpa
kubectl -n tech-challenge describe hpa tc3-demo
$demoUrl = terraform -chdir=platform output -raw demo_url
Invoke-WebRequest -Uri $demoUrl
```

Esperado: controllers disponíveis, APIService com `AVAILABLE=True`, métricas de CPU/memória, Ingress com hostname e HTTP 200. O HPA pode precisar de alguns minutos para receber as primeiras métricas.

Para gerar carga dentro do cluster, execute em um terminal:

```powershell
kubectl -n tech-challenge run tc3-load --image=busybox:1.37.0 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://tc3-demo; done'
```

Em outro terminal:

```powershell
kubectl -n tech-challenge get hpa tc3-demo --watch
```

Observe a utilização de CPU e o número de réplicas. Se necessário, execute mais geradores com nomes diferentes. O exemplo escala entre dois e cinco pods, com alvo de 50% da CPU solicitada. Remova os geradores ao terminar:

```powershell
kubectl -n tech-challenge delete pod tc3-load
```

A redução tem janela de estabilização de 300 segundos. O HPA escala **pods**; configurar `max_size` no Node Group não instala autoscaling de **nodes**. Nesta entrega, ajuste `desired_size` e aplique `infra/` quando precisar de mais capacidade. Pods `Pending` podem indicar capacidade insuficiente.

## Integrar com o repositório da aplicação

Publique o Deployment e o Service da aplicação no namespace `tech-challenge`. Configure `resources.requests.cpu` em todos os containers do Deployment; o HPA por utilização depende desse valor. Evite outro HPA para o mesmo Deployment e configure o pipeline da aplicação para preservar o número de réplicas controlado pelo HPA.

Em `platform/terraform.tfvars`:

```hcl
enable_demo = false

hpa_workloads = {
  api = {
    namespace       = "tech-challenge"
    deployment_name = "api"
    min_replicas    = 2
    max_replicas    = 5
    cpu_utilization = 70
  }
}
```

O Deployment `api` precisa existir para o HPA operar. O repositório da aplicação pode publicar seu Ingress com `ingressClassName: alb` e anotações de scheme, target-type e listeners, seguindo o exemplo em `platform/demo.tf`.

O namespace `observability` fica disponível para ferramentas futuras; Metrics Server atende o HPA, mas não substitui uma plataforma de monitoramento.

## State remoto opcional com S3

Para trabalho em equipe, use um bucket S3 existente com versionamento, criptografia e acesso restrito. Cada etapa precisa de uma key diferente.

Na raiz:

```powershell
Copy-Item docs/backend.tf.example infra/backend.tf
Copy-Item docs/backend.tf.example platform/backend.tf
Copy-Item infra/s3.backend.hcl.example infra/backend.hcl
Copy-Item platform/s3.backend.hcl.example platform/backend.hcl
```

Edite bucket/região nos dois arquivos `backend.hcl`. Se já existir state local, migre-o:

```powershell
terraform -chdir=infra init -migrate-state -backend-config=backend.hcl
terraform -chdir=platform init -migrate-state -backend-config=backend.hcl
```

Se for a primeira inicialização, execute `init -backend-config=backend.hcl` sem `-migrate-state`. O bucket não é criado por esta entrega.

Atualize também a leitura do state em `platform/terraform.tfvars`:

```hcl
infra_state_backend = "s3"
infra_state_config = {
  bucket = "seu-bucket-terraform-state"
  key    = "tech-challenge/dev/eks/terraform.tfstate"
  region = "us-east-1"
}
```

O backend da própria plataforma usa `tech-challenge/dev/platform/terraform.tfstate`; a leitura de outputs aponta para a key de **infra**. O locking utiliza `use_lockfile = true` no backend S3, sem tabela DynamoDB. A identidade que executa `platform/` precisa ler o state de infraestrutura.

## Validação local e CI

Sem credenciais AWS e sem cluster:

```powershell
terraform fmt -check -recursive
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
terraform -chdir=infra test
terraform -chdir=platform init -backend=false -input=false
terraform -chdir=platform validate
terraform -chdir=platform test
```

Os testes usam providers simulados e executam apenas planos. Verificam rede privada, acesso administrativo, restrições de CIDR, IRSA, HPA e desativação do exemplo. Não comprovam permissões, quotas ou funcionamento na AWS; essa etapa é verificada pelos comandos acima após o apply.

O GitHub Actions executa formatação, init, validate e os testes a cada push/PR. Não executa apply nem precisa de secrets AWS. Ao habilitar backend S3 localmente, mantenha a configuração do backend fora dos testes e informe `-backend=false` na CI.

## Remover os recursos

Remova antes as aplicações, Ingresses e Services `LoadBalancer` publicados por outros repositórios. Eles podem manter recursos AWS associados ao cluster.

```powershell
terraform -chdir=platform plan -destroy -out=destroy.tfplan
terraform -chdir=platform apply destroy.tfplan
```

Confirme no console AWS que o ALB e seus recursos associados foram removidos pelo controller antes de destruir a base:

```powershell
terraform -chdir=infra plan -destroy -out=destroy.tfplan
terraform -chdir=infra apply destroy.tfplan
```

EKS, EC2, NAT Gateway, ALB, IPv4 público, tráfego e logs geram custos enquanto existirem. A configuração usa um único NAT Gateway para o ambiente acadêmico, concentrando a saída em uma AZ e podendo gerar tráfego entre AZs. Para produção, revisar saída por AZ, requisitos de disponibilidade, logs, HTTPS e políticas de acesso.

## Referências

- [Versões Kubernetes suportadas no EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Instalação oficial do AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/)
- [Backend S3 do Terraform](https://developer.hashicorp.com/terraform/language/backend/s3)
