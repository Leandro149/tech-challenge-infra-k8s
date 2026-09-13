# TC3-06 — Terraform do Kubernetes / EKS

| ID | Requisito | Implementação | Verificação |
| --- | --- | --- | --- |
| R01 | Provisionar VPC e EKS | infra/network.tf, infra/eks.tf | Terraform validate; após apply, cluster ACTIVE e nodes Ready |
| R02 | Configurar Node Groups | infra/eks.tf, infra/variables.tf | Managed Node Groups com mínimo, desejado e máximo configuráveis |
| R03 | Configurar IAM | infra/iam.tf | Roles do cluster/nodes, Access Entries e IRSA restrito por service account |
| R04 | Configurar Load Balancer | platform/controllers.tf, platform/demo.tf | Controller pronto; Ingress com hostname ALB e HTTP funcionando |
| R05 | Configurar HPA e namespaces | platform/namespaces.tf, platform/hpa.tf | Namespaces existentes, Metrics API disponível e HPA com métricas |

Critérios locais: terraform fmt -check -recursive e init -backend=false / validate / test em ambos os diretórios; exemplos sem credenciais; states ignorados pelo Git. Resultado: oito testes de plans simulados aprovados; charts validados com Helm para Kubernetes 1.35.

Critérios AWS: verificação manual documentada após provisionamento. Validar Terraform não comprova disponibilidade regional, quotas, permissões da conta ou funcionamento do cluster.
