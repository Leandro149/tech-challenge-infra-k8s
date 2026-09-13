# Tarefas TC3-09

Execução sequencial, com ferramentas locais, Terraform e documentação oficial.

| Tarefa | Arquivos | Requisitos | Verificação |
| --- | --- | --- | --- |
| T1 — Isolamento e acesso de leitura | infra/{variables,eks,outputs}.tf; platform/{variables,providers,plan-access}.tf; tests | CI04, CI06 | fmt, validate, testes de namespace/ambiente e acesso |
| T2 — Bootstrap AWS | bootstrap/*.tf, lockfile, tests | CI01, CI06 | init, validate e planos simulados de buckets/trust/permissões |
| T3 — Configuração dos ambientes | environments/**; scripts/ci/terraform-config.mjs e tests | CI04, CI06 | node --test, isolamento de paths, IP, conta e configs |
| T4 — Workflow reutilizável | .github/workflows/terraform-environment.yml | CI01–CI05 | actionlint e testes de controle Terraform com CLI simulada |
| T5 — Eventos CI/CD | .github/workflows/terraform.yml | CI01–CI06 | actionlint; testes de merge/branch/fork/manual |
| T6 — Operação e memória | docs/ci-cd.md, README, docs/aws-access.md, .specs/project/* | CI01–CI06 | revisão de instruções/variáveis/limitações e git diff --check |

Status: T1–T6 implementadas e verificadas localmente. Quinze testes Terraform de planos simulados e treze testes Node aprovados; workflows aprovadas pelo actionlint. Provisionamento real e execução no GitHub dependem do bootstrap, runners e variáveis; não fazem parte da validação offline.
