# TC3-09 — CI/CD da infraestrutura

| ID | Requisito | Critério |
| --- | --- | --- |
| CI01 | Pipelines Terraform | GitHub Actions valida os três roots e chama workflow reutilizável para AWS |
| CI02 | Executar fmt | terraform fmt -check -recursive em bootstrap, infra e platform |
| CI03 | Executar validate | init -backend=false e validate em CI; validate também antes do plano AWS |
| CI04 | Executar plan | PR interna para develop/main e execução manual produzem plano AWS; plataforma planeja quando seu state já existir |
| CI05 | Apply após merge | Somente pull_request_target closed com merged=true, contexto da base e checkout do commit já mesclado; novo plano e apply do arquivo salvo, infra antes de platform |
| CI06 | Separar ambientes | develop -> homologacao/hml, main -> producao/prod; CIDRs, clusters, buckets, roles e concorrência independentes |

Premissas: conta 213284176265, us-east-1, OIDC, buckets versionados com locking S3. Os runners Terraform usam Linux com IP público de saída fixo autorizado no EKS. PRs de forks executam validação sem credenciais; após merge executam deploy como as demais.

Bootstrap precisa ser aplicado uma vez por identidade AWS autorizada. Perfis locais e credenciais incompletas não são incorporados às workflows. Sem configuração AWS/GitHub, verificar código e testes localmente e documentar os passos pendentes.

No primeiro provisionamento, não há cluster/RBAC/state de platform para o plano em PR; registrar explicitamente o adiamento. Após merge: plan/apply AWS, depois plan/apply Kubernetes. Nos ambientes existentes, PR planeja ambas as etapas com acesso somente leitura (incluindo leitura de releases Helm).
