# tech-challenge-infra-k8s

Entregar o TC3-06: infraestrutura AWS e configuração do Kubernetes declaradas em Terraform.

Objetivos: VPC em duas AZs, Amazon EKS com Managed Node Groups privados, IAM com acesso explícito ao cluster e IRSA, ALB via Ingress, namespaces e HPA com Metrics Server.

Stack: Terraform >= 1.13, providers AWS 6.x, Kubernetes 3.x, Helm 3.x e TLS 4.x; Kubernetes 1.35 configurável.

Escopo: código de infraestrutura, configuração de plataforma, exemplo demonstrável e documentação. Aplicação de negócio, banco de dados, DNS e pipeline de deploy de aplicações pertencem aos respectivos repositórios.

Premissas: região us-east-1; duas AZs; um NAT Gateway para ambiente acadêmico; credenciais AWS fornecidas pelo operador. Gerar código e validar localmente; provisionamento real requer execução pelo operador.
