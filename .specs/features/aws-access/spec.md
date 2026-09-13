# Configuração do acesso AWS

Conta informada pelo operador: 213284176265. Região: us-east-1.

1. Restringir o provider AWS à conta configurada e rejeitar IDs inválidos. Arquivos: infra/providers.tf, infra/variables.tf, infra/terraform.tfvars.example, infra/tests/infra.tftest.hcl. Verificar: fmt, validate e tests com provider simulado.
2. Preparar configuração local por perfil AWS CLI sem incorporar credenciais ao Terraform. Arquivos: scripts/Configure-AwsEnvironment.ps1, docs/aws-access.md, README.md. Verificar: análise sintática PowerShell e cenários simulados de identidade válida, conta errada, role com path e falha de autenticação.
3. Registrar a configuração e a limitação de acesso na memória do projeto. Arquivo: .specs/project/STATE.md.

O script deve verificar a conta antes de gerar arquivos, usar ARN IAM (não ARN STS de sessão), descobrir/aceitar IP público IPv4 e gravar apenas parâmetros não secretos em arquivos access.auto.tfvars ignorados pelo Git. Deve preservar terraform.tfvars existentes e não provisionar recursos.

Autenticação real depende de perfil AWS CLI válido. As credenciais temporárias fornecidas não incluem o session token. Não copiar credenciais compartilhadas no chat para arquivos ou logs. AWS CLI ainda não está disponível na máquina.
