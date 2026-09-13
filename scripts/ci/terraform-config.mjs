import { appendFileSync, mkdirSync, readFileSync, readdirSync, copyFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isIPv4 } from 'node:net';
import { spawnSync } from 'node:child_process';

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const targets = { develop: 'homologacao', main: 'producao' };

export function routeEvent(eventName, event, context) {
  if (eventName === 'push') return null;
  if (eventName === 'workflow_dispatch') {
    const environment = event.inputs?.environment;
    if (targets[context.branch] !== environment) throw new Error('Plano manual: escolha develop/homologacao ou main/producao.');
    return { environment, mode: 'plan', ref: context.sha };
  }
  if (!['pull_request', 'pull_request_target'].includes(eventName)) return null;
  const pr = event.pull_request;
  const environment = targets[pr?.base?.ref];
  if (!environment) return null;
  if (event.action === 'closed') {
    if (eventName !== 'pull_request_target' || !pr.merged) return null;
    if (!pr.merge_commit_sha) throw new Error('Evento de merge sem commit identificado.');
    return { environment, mode: 'apply', ref: pr.merge_commit_sha };
  }
  if (eventName === 'pull_request_target') return null;
  if (!['opened', 'synchronize', 'reopened', 'ready_for_review'].includes(event.action)) return null;
  if (pr.head?.repo?.full_name !== context.repository) return null;
  return { environment, mode: 'plan', ref: context.sha };
}

function jsonArray(value, name, optional = false) {
  if (!value && optional) return [];
  let parsed;
  try { parsed = JSON.parse(value); } catch { throw new Error(`${name}: configure um array JSON.`); }
  if (!Array.isArray(parsed) || parsed.some(item => typeof item !== 'string' || !item.trim())) {
    throw new Error(`${name}: configure um array JSON de strings não vazias.`);
  }
  return parsed;
}

function validateCidrs(cidrs, name, required) {
  if (required && !cidrs.length) throw new Error(`${name}: informe ao menos um CIDR.`);
  for (const cidr of cidrs) {
    const parts = cidr.split('/');
    const prefix = Number(parts[1]);
    if (parts.length !== 2 || !isIPv4(parts[0]) || !/^\d+$/.test(parts[1]) || prefix < 1 || prefix > 32) {
      throw new Error(`${name}: use CIDRs IPv4 restritos, com prefixo entre 1 e 32.`);
    }
  }
}

function validateRunnerLabels(labels) {
  const selfHostedLinux = labels.includes('self-hosted') && labels.includes('linux');
  const githubHostedLinux = labels.length === 1 && labels[0] === 'ubuntu-latest';
  if (!selfHostedLinux && !githubHostedLinux) {
    throw new Error('TF_RUNNER_LABELS: use ["ubuntu-latest"] ou labels de um runner self-hosted Linux.');
  }
}

export function ipInCidr(ip, cidr) {
  if (!isIPv4(ip)) return false;
  const [network, prefix] = cidr.split('/');
  const toNumber = value => value.split('.').reduce((total, octet) => total * 256 + Number(octet), 0);
  const blockSize = 2 ** (32 - Number(prefix));
  return Math.floor(toNumber(ip) / blockSize) === Math.floor(toNumber(network) / blockSize);
}

export function loadConfiguration(environment, variables, root = repositoryRoot) {
  if (!Object.values(targets).includes(environment)) throw new Error('Ambiente inválido.');
  const infra = JSON.parse(readFileSync(join(root, 'environments', environment, 'infra.tfvars.json'), 'utf8'));
  const platform = JSON.parse(readFileSync(join(root, 'environments', environment, 'platform.tfvars.json'), 'utf8'));
  const expectedSuffix = environment === 'homologacao' ? 'hml' : 'prod';
  if (infra.environment !== expectedSuffix || infra.aws_account_id !== '213284176265' || infra.aws_region !== 'us-east-1') {
    throw new Error('Conta, região ou identificador do ambiente inconsistentes.');
  }
  const rolePattern = new RegExp(`^arn:aws:iam::${infra.aws_account_id}:role/.+$`);
  for (const key of ['AWS_ROLE_ARN', 'AWS_PLAN_ROLE_ARN']) {
    if (!rolePattern.test(variables[key] ?? '')) throw new Error(`${key}: configure uma role IAM da conta do projeto.`);
  }
  if (variables.AWS_ROLE_ARN === variables.AWS_PLAN_ROLE_ARN) throw new Error('Plan e apply precisam de roles distintas.');
  for (const [key, mode] of [['AWS_ROLE_ARN', 'apply'], ['AWS_PLAN_ROLE_ARN', 'plan']]) {
    if (variables[key] !== `arn:aws:iam::${infra.aws_account_id}:role/${infra.project_name}-${expectedSuffix}-terraform-${mode}`) {
      throw new Error(`${key}: a role não corresponde ao ambiente e ao bootstrap do projeto.`);
    }
  }
  if (!/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/.test(variables.TF_STATE_BUCKET ?? '')) {
    throw new Error('TF_STATE_BUCKET: configure o bucket S3 do ambiente.');
  }
  if (variables.TF_STATE_BUCKET !== `${infra.project_name}-tfstate-${infra.aws_account_id}-${expectedSuffix}`) {
    throw new Error('TF_STATE_BUCKET não corresponde ao ambiente. Use o bucket informado pelo bootstrap.');
  }
  const labels = jsonArray(variables.TF_RUNNER_LABELS, 'TF_RUNNER_LABELS');
  validateRunnerLabels(labels);
  const endpointCidrs = jsonArray(variables.EKS_PUBLIC_ACCESS_CIDRS, 'EKS_PUBLIC_ACCESS_CIDRS');
  validateCidrs(endpointCidrs, 'EKS_PUBLIC_ACCESS_CIDRS', true);
  const demoCidrs = jsonArray(variables.DEMO_INGRESS_CIDRS, 'DEMO_INGRESS_CIDRS', !platform.enable_demo);
  validateCidrs(demoCidrs, 'DEMO_INGRESS_CIDRS', platform.enable_demo);
  const extraAdmins = jsonArray(variables.TF_ADMIN_PRINCIPAL_ARNS, 'TF_ADMIN_PRINCIPAL_ARNS', true);
  const principalPattern = new RegExp(`^arn:aws:iam::${infra.aws_account_id}:(role|user)/.+$`);
  if (extraAdmins.some(arn => !principalPattern.test(arn) || arn === variables.AWS_PLAN_ROLE_ARN)) {
    throw new Error('TF_ADMIN_PRINCIPAL_ARNS: use administradores IAM da conta, sem a role de plan.');
  }
  return {
    environment, labels, bucket: variables.TF_STATE_BUCKET,
    infra: { ...infra, cluster_endpoint_public_access_cidrs: endpointCidrs,
      cluster_admin_principal_arns: [...new Set([variables.AWS_ROLE_ARN, ...extraAdmins])],
      cluster_readonly_principal_arns: [variables.AWS_PLAN_ROLE_ARN] },
    platform: { ...platform, demo_ingress_cidrs: demoCidrs, expected_environment: expectedSuffix,
      infra_state_backend: 's3', infra_state_config: {
        bucket: variables.TF_STATE_BUCKET, key: 'infra/terraform.tfstate', region: infra.aws_region,
      } },
  };
}

export function renderConfiguration(config, options) {
  if (!isIPv4(options.publicIp) || !config.infra.cluster_endpoint_public_access_cidrs.some(cidr => ipInCidr(options.publicIp, cidr))) {
    throw new Error('O IP de saída do runner não está autorizado em EKS_PUBLIC_ACCESS_CIDRS. Corrija o runner/CIDR antes de continuar.');
  }
  if (!/^\d+$/.test(options.runId) || !/^\d+$/.test(options.runAttempt)) throw new Error('Identificador da execução inválido.');
  const work = join(resolve(options.tempDir), `tc3-09-${options.runId}-${options.runAttempt}-${config.environment}`);
  const directories = {};
  for (const root of ['infra', 'platform']) {
    const source = join(options.repositoryRoot ?? repositoryRoot, root);
    const destination = join(work, root);
    mkdirSync(destination, { recursive: true });
    for (const entry of readdirSync(source, { withFileTypes: true })) {
      if (entry.isFile() && (entry.name.endsWith('.tf') || entry.name === '.terraform.lock.hcl')) {
        copyFileSync(join(source, entry.name), join(destination, entry.name));
      }
    }
    if (root === 'infra') {
      mkdirSync(join(destination, 'policies'), { recursive: true });
      for (const name of readdirSync(join(source, 'policies'))) {
        if (name.endsWith('.json')) copyFileSync(join(source, 'policies', name), join(destination, 'policies', name));
      }
    }
    writeFileSync(join(destination, 'backend.tf'), 'terraform {\n  backend "s3" {}\n}\n');
    writeFileSync(join(destination, 'backend.hcl'), [
      `bucket = ${JSON.stringify(config.bucket)}`, `key = "${root}/terraform.tfstate"`,
      `region = ${JSON.stringify(config.infra.aws_region)}`, 'encrypt = true', 'use_lockfile = true', '',
    ].join('\n'));
    writeFileSync(join(destination, 'terraform.tfvars.json'), JSON.stringify(config[root], null, 2) + '\n');
    directories[`${root}_dir`] = destination;
  }
  return directories;
}

export function runPlan(directory, execute = spawnSync) {
  const result = execute('terraform', [`-chdir=${directory}`, 'plan', '-input=false', '-no-color', '-lock-timeout=10m', '-detailed-exitcode', '-out=tfplan'], { stdio: 'inherit' });
  if (result.error) throw result.error;
  if (![0, 2].includes(result.status)) throw new Error(`terraform plan falhou (código ${result.status}).`);
  return result.status === 2;
}

export function platformReady(config, execute = spawnSync) {
  for (const root of ['infra', 'platform']) {
    const result = execute('aws', ['s3api', 'head-object', '--bucket', config.bucket, '--key', `${root}/terraform.tfstate`,
      '--region', config.infra.aws_region, '--query', 'ContentLength', '--output', 'text', '--no-cli-pager'], { encoding: 'utf8' });
    if (result.error) throw result.error;
    if (result.status === 0) continue;
    if (/\b404\b|NoSuchKey|Not Found/.test(result.stderr ?? '')) return false;
    throw new Error('Não foi possível verificar o state S3. Confira acesso e existência do bucket; erro não tratado como primeiro deploy.');
  }
  return true;
}

export async function assertCurrentMerge(context, request = fetch) {
  if (!targets[context.branch]) throw new Error('Branch de deploy inválida.');
  const response = await request(`${context.apiUrl}/repos/${context.repository}/git/ref/heads/${context.branch}`, {
    headers: { Authorization: `Bearer ${context.token}`, Accept: 'application/vnd.github+json' },
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw new Error('Não foi possível conferir o commit atual da branch no GitHub.');
  const reference = await response.json();
  if (reference.object?.sha !== context.ref) {
    throw new Error('Este merge foi substituído por um commit mais recente. Execute o run do merge atual; este job não fará apply de código antigo.');
  }
}

function output(values) {
  const content = Object.entries(values).map(([key, value]) => `${key}=${value}`).join('\n') + '\n';
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, content);
  else process.stdout.write(content);
}

function summary(message) {
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, message + '\n');
}

async function main() {
  const command = process.argv[2];
  if (command === 'assert-current-merge') {
    const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    return assertCurrentMerge({
      branch: event.pull_request?.base?.ref, repository: process.env.GITHUB_REPOSITORY,
      ref: process.env.CI_CHECKOUT_REF, token: process.env.GH_TOKEN, apiUrl: process.env.GITHUB_API_URL,
    });
  }
  if (command === 'route' || command === 'prepare') {
    const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    const route = routeEvent(process.env.GITHUB_EVENT_NAME, event, {
      branch: process.env.GITHUB_REF_NAME, sha: process.env.GITHUB_SHA, repository: process.env.GITHUB_REPOSITORY,
    });
    if (command === 'route') return output(route ? { enabled: true, ...route } : { enabled: false });
    if (!route || route.environment !== process.env.CI_ENVIRONMENT || route.mode !== process.env.CI_MODE || route.ref !== process.env.CI_CHECKOUT_REF) {
      throw new Error('Evento, ambiente ou commit não autorizado para esta execução Terraform.');
    }
    const config = loadConfiguration(route.environment, process.env);
    return output({ runner_labels: JSON.stringify(config.labels) });
  }
  const config = loadConfiguration(process.env.CI_ENVIRONMENT, process.env);
  if (command === 'render') {
    const response = await fetch('https://checkip.amazonaws.com', { signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error('Falha ao consultar IP de saída do runner.');
    const directories = renderConfiguration(config, {
      publicIp: (await response.text()).trim(), tempDir: process.env.RUNNER_TEMP,
      runId: process.env.GITHUB_RUN_ID, runAttempt: process.env.GITHUB_RUN_ATTEMPT,
    });
    output(directories);
    summary(`### ${config.environment}\nConta: ${config.infra.aws_account_id}. Região: ${config.infra.aws_region}. Runner autorizado por CIDR.`);
  } else if (command === 'platform-ready') {
    const ready = platformReady(config);
    output({ ready });
    if (!ready) summary('Plataforma: plano de PR adiado porque os states de infra/platform ainda não existem. O primeiro merge executará infra e plataforma em sequência.');
  } else if (command === 'plan') {
    const root = process.argv[3];
    if (!['infra', 'platform'].includes(root)) throw new Error('Root Terraform inválido.');
    const directory = process.env[`${root.toUpperCase()}_DIR`];
    if (!directory || !existsSync(join(directory, 'terraform.tfvars.json'))) throw new Error('Diretório Terraform não foi preparado.');
    const changes = runPlan(directory);
    summary(`${root}: plano concluído ${changes ? 'com alterações' : 'sem alterações'}. Consulte os logs Terraform para os detalhes.`);
  } else {
    throw new Error('Comando inválido: route, prepare, assert-current-merge, render, platform-ready ou plan.');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
