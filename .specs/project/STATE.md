# Estado da entrega

Atualizado em 2026-09-13.

## Entrega

- R01–R05 implementados em infra/ e platform/.
- Formatação e validação Terraform aprovadas nas duas etapas.
- Oito testes com providers simulados aprovados: quatro AWS e quatro Kubernetes/Helm; somente plans.
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
- Copiar os tfvars de exemplo e substituir ARN IAM e CIDRs; escolher região/AZs e capacidade adequadas à conta.
- Executar plan/apply com credenciais próprias e verificar a entrega na AWS conforme README.
- Publicar os commits locais no remoto quando desejar.

## Limitações da validação

Nenhum recurso AWS foi criado. Testes simulados e validação sintática não comprovam quotas, permissões, disponibilidade regional, convergência dos controllers ou resposta HTTP. A CI foi criada; sua execução no GitHub depende da publicação do repositório.
