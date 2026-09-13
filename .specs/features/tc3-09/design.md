# Design TC3-09

Workflow terraform.yml: push executa somente CI; pull_request aberta/atualizada executa CI e plan se interna; pull_request_target closed/merged usa contexto da base e commit já mesclado para CI e apply, inclusive merges aprovados de forks. Jobs de pull_request_target closed sem merge são ignorados. workflow_dispatch permite somente plan. Roteamento por base branch, sem deploy em branches arbitrárias.

Workflow reutilizável terraform-environment.yml: preflight em runner hospedado verifica as variáveis do GitHub Environment; job Terraform em runner Linux de IP fixo autentica com OIDC. Environments de leitura homologacao-plan/producao-plan usam roles read-only; homologacao/producao usam roles de apply. Configurações explícitas em environments/ são copiadas para diretórios temporários com apenas arquivos Terraform necessários, evitando parâmetros locais .auto.tfvars.

Bootstrap: provider OIDC GitHub único, dois buckets S3 privados/versionados/criptografados, duas roles de plan e duas de apply. Plan possui discovery/read AWS e state do próprio ambiente; escrita apenas no lock. Apply possui ações dos serviços usados e IAM restrito aos prefixes do ambiente/OIDC EKS, com PassRole e anexação de políticas limitados. Roles do bootstrap não são administradas pela pipeline dos clusters.

EKS: apply role na lista de administradores; plan role em Access Entry com grupo terraform-plan. Plataforma cria ClusterRole/Binding somente get/list/watch para o grupo. Leitura inclui secrets porque Helm usa secrets para guardar os releases.

State: keys infra/terraform.tfstate e platform/terraform.tfstate em buckets diferentes por ambiente; use_lockfile=true. Output environment em infra e postcondition em remote_state da plataforma evitam ler o ambiente errado.

Concurrency por ambiente/operação e cancel-in-progress=false para que planos não substituam applies pendentes; locking S3 com espera de dez minutos coordena states. Plano binário permanece no diretório temporário do job e não é publicado como artifact; resumo legível vai para logs/Job Summary. Após merge o plano é recriado, sem consumir artifacts de PR.
