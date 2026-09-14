import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { routeEvent, loadConfiguration, renderConfiguration, runPlan, platformReady, assertCurrentMerge } from '../../scripts/ci/terraform-config.mjs';

const context = { branch: 'develop', sha: 'pr-sha', repository: 'Leandro149/tech-challenge-infra-k8s' };
const pullRequest = (base = 'develop', extra = {}) => ({
  action: 'opened', pull_request: { base: { ref: base }, head: { repo: { full_name: context.repository } }, ...extra },
});
const variables = (suffix = 'hml') => ({
  AWS_ROLE_ARN: `arn:aws:iam::213284176265:role/tech-challenge-${suffix}-terraform-apply`,
  AWS_PLAN_ROLE_ARN: `arn:aws:iam::213284176265:role/tech-challenge-${suffix}-terraform-plan`,
  TF_STATE_BUCKET: `tech-challenge-tfstate-213284176265-${suffix}`,
  TF_RUNNER_LABELS: '["self-hosted","linux","x64","terraform-test"]',
  EKS_PUBLIC_ACCESS_CIDRS: '["203.0.113.10/32"]',
  DEMO_INGRESS_CIDRS: '["203.0.113.20/32"]',
});

test('PRs route by target branch, never by feature branch', () => {
  assert.deepEqual(routeEvent('pull_request', pullRequest(), context), { environment: 'homologacao', mode: 'plan', ref: 'pr-sha' });
  assert.equal(routeEvent('pull_request', pullRequest('main'), context).environment, 'producao');
  assert.equal(routeEvent('pull_request', pullRequest('other'), context), null);
});

test('apply requires a merged PR and uses its merged commit', () => {
  const event = pullRequest('main', { merged: true, merge_commit_sha: 'merged-sha' });
  event.action = 'closed';
  assert.deepEqual(routeEvent('pull_request_target', event, context), { environment: 'producao', mode: 'apply', ref: 'merged-sha' });
  assert.equal(routeEvent('pull_request', event, context), null);
  event.pull_request.merged = false;
  assert.equal(routeEvent('pull_request_target', event, context), null);
  assert.equal(routeEvent('pull_request_target', pullRequest(), context), null);
  assert.equal(routeEvent('push', {}, context), null);
});

test('fork PRs receive no AWS plan, but approved merges deploy', () => {
  const event = pullRequest('develop', { head: { repo: { full_name: 'outside/fork' } } });
  assert.equal(routeEvent('pull_request', event, context), null);
  Object.assign(event, { action: 'closed' });
  Object.assign(event.pull_request, { merged: true, merge_commit_sha: 'merged-sha' });
  assert.equal(routeEvent('pull_request_target', event, context).mode, 'apply');
});

test('manual execution only plans the environment matching the selected branch', () => {
  assert.equal(routeEvent('workflow_dispatch', { inputs: { environment: 'homologacao' } }, context).mode, 'plan');
  assert.throws(() => routeEvent('workflow_dispatch', { inputs: { environment: 'producao' } }, context), /Plano manual/);
});

test('environments use distinct networks, buckets and roles', () => {
  const hml = loadConfiguration('homologacao', variables());
  const prod = loadConfiguration('producao', variables('prod'));
  assert.notEqual(hml.infra.vpc_cidr, prod.infra.vpc_cidr);
  assert.notEqual(hml.bucket, prod.bucket);
  assert.notDeepEqual(hml.infra.cluster_admin_principal_arns, prod.infra.cluster_admin_principal_arns);
  assert.equal(prod.platform.enable_demo, false);
  assert.equal(prod.platform.expected_environment, 'prod');
});

test('wrong account, reused bucket and environment roles fail before planning', () => {
  assert.throws(() => loadConfiguration('homologacao', { ...variables(), AWS_ROLE_ARN: 'arn:aws:iam::999999999999:role/Other' }), /AWS_ROLE_ARN/);
  assert.throws(() => loadConfiguration('homologacao', { ...variables(), TF_STATE_BUCKET: variables('prod').TF_STATE_BUCKET }), /não corresponde/);
  assert.throws(() => loadConfiguration('homologacao', variables('prod')), /não corresponde/);
});

test('network configuration rejects broad CIDRs and invalid runners', () => {
  assert.throws(() => loadConfiguration('homologacao', { ...variables(), EKS_PUBLIC_ACCESS_CIDRS: '["0.0.0.0/0"]' }), /restritos/);
  assert.throws(() => loadConfiguration('homologacao', { ...variables(), EKS_PUBLIC_ACCESS_CIDRS: 'invalid' }), /array JSON/);
  assert.throws(() => loadConfiguration('homologacao', { ...variables(), TF_RUNNER_LABELS: '["windows-latest"]' }), /TF_RUNNER_LABELS/);
});

test('network configuration allows GitHub hosted Ubuntu runners for academic environments', () => {
  const config = loadConfiguration('homologacao', {
    ...variables(),
    TF_RUNNER_LABELS: '["ubuntu-latest"]',
    EKS_PUBLIC_ACCESS_CIDRS: '["0.0.0.0/1","128.0.0.0/1"]',
  });
  assert.deepEqual(config.labels, ['ubuntu-latest']);
});

test('render excludes local tfvars, caches and credentials from temporary roots', () => {
  const root = mkdtempSync(join(tmpdir(), 'tc3-config-test-'));
  for (const name of ['infra', 'platform']) {
    mkdirSync(join(root, name));
    writeFileSync(join(root, name, 'versions.tf'), 'terraform {}\n');
    writeFileSync(join(root, name, '.terraform.lock.hcl'), '# test\n');
    writeFileSync(join(root, name, 'access.auto.tfvars'), 'environment = "dev"');
    writeFileSync(join(root, name, 'terraform.tfvars'), 'environment = "dev"');
    mkdirSync(join(root, name, '.terraform'));
  }
  mkdirSync(join(root, 'infra', 'policies'));
  writeFileSync(join(root, 'infra', 'policies', 'policy.json'), '{}');
  const config = loadConfiguration('homologacao', variables());
  const options = { repositoryRoot: root, tempDir: root, publicIp: '203.0.113.10', runId: '1', runAttempt: '1' };
  const dirs = renderConfiguration(config, options);
  assert.equal(existsSync(join(dirs.infra_dir, 'access.auto.tfvars')), false);
  assert.equal(existsSync(join(dirs.infra_dir, '.terraform')), false);
  assert.equal(existsSync(join(dirs.infra_dir, 'policies', 'policy.json')), true);
  assert.match(readFileSync(join(dirs.infra_dir, 'backend.hcl'), 'utf8'), /use_lockfile = true/);
  const values = JSON.parse(readFileSync(join(dirs.infra_dir, 'terraform.tfvars.json'), 'utf8'));
  assert.equal(values.environment, 'hml');
  assert.deepEqual(values.cluster_readonly_principal_arns, [variables().AWS_PLAN_ROLE_ARN]);
  const platform = JSON.parse(readFileSync(join(dirs.platform_dir, 'terraform.tfvars.json'), 'utf8'));
  assert.equal(platform.infra_state_config.key, 'infra/terraform.tfstate');
  assert.throws(() => renderConfiguration(config, { ...options, publicIp: '203.0.113.11' }), /não está autorizado/);
  assert.throws(() => renderConfiguration(config, { ...options, runId: '../escape' }), /inválido/);
});

test('plan accepts exit 2 as changes and propagates actual errors', () => {
  assert.equal(runPlan('/test', (command, args) => {
    assert.equal(command, 'terraform');
    assert.ok(args.includes('-detailed-exitcode') && args.includes('-out=tfplan'));
    return { status: 2 };
  }), true);
  assert.equal(runPlan('/test', () => ({ status: 0 })), false);
  assert.throws(() => runPlan('/test', () => ({ status: 1 })), /falhou/);
});

test('missing state postpones first platform PR plan, access denied fails', () => {
  const config = loadConfiguration('homologacao', variables());
  assert.equal(platformReady(config, () => ({ status: 0 })), true);
  assert.equal(platformReady(config, () => ({ status: 1, stderr: 'HeadObject (404) Not Found' })), false);
  assert.throws(() => platformReady(config, () => ({ status: 1, stderr: 'HeadObject (403) Forbidden' })), /Não foi possível/);
});

test('reusable workflow preflight rejects apply before merge and a different checkout', () => {
  const root = mkdtempSync(join(tmpdir(), 'tc3-event-test-'));
  const eventPath = join(root, 'event.json');
  writeFileSync(eventPath, JSON.stringify(pullRequest()));
  const env = { ...process.env, ...variables(), GITHUB_EVENT_PATH: eventPath, GITHUB_EVENT_NAME: 'pull_request',
    GITHUB_REPOSITORY: context.repository, GITHUB_SHA: context.sha, GITHUB_REF_NAME: 'feature',
    CI_ENVIRONMENT: 'homologacao', CI_MODE: 'apply', CI_CHECKOUT_REF: context.sha, GITHUB_OUTPUT: '' };
  const execute = overrides => spawnSync(process.execPath, ['scripts/ci/terraform-config.mjs', 'prepare'], { env: { ...env, ...overrides }, encoding: 'utf8' });
  assert.equal(execute({}).status, 1);
  assert.equal(execute({ CI_MODE: 'plan', CI_CHECKOUT_REF: 'different-sha' }).status, 1);
  const result = execute({ CI_MODE: 'plan' });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /runner_labels=/);
});

test('reusable workflow allows apply on the exact merged commit', () => {
  const root = mkdtempSync(join(tmpdir(), 'tc3-merge-test-'));
  const eventPath = join(root, 'event.json');
  const event = pullRequest('main', { merged: true, merge_commit_sha: 'merged-sha' });
  event.action = 'closed';
  writeFileSync(eventPath, JSON.stringify(event));
  const result = spawnSync(process.execPath, ['scripts/ci/terraform-config.mjs', 'prepare'], { encoding: 'utf8', env: {
    ...process.env, ...variables('prod'), GITHUB_OUTPUT: '', GITHUB_EVENT_PATH: eventPath, GITHUB_EVENT_NAME: 'pull_request_target',
    GITHUB_REPOSITORY: context.repository, GITHUB_SHA: 'merged-sha', GITHUB_REF_NAME: 'main',
    CI_ENVIRONMENT: 'producao', CI_MODE: 'apply', CI_CHECKOUT_REF: 'merged-sha',
  } });
  assert.equal(result.status, 0, result.stderr);
});

test('queued old merges cannot overwrite a newer deployment', async () => {
  const context = { branch: 'main', repository: 'example/repo', ref: 'current-sha', token: 'test-token', apiUrl: 'https://api.github.com' };
  const response = sha => async () => ({ ok: true, json: async () => ({ object: { sha } }) });
  await assertCurrentMerge(context, response('current-sha'));
  await assert.rejects(assertCurrentMerge(context, response('newer-sha')), /substituído/);
  await assert.rejects(assertCurrentMerge(context, async () => ({ ok: false })), /Não foi possível/);
});

test('bootstrap handles first execution and preserves errors and managed OIDC providers', t => {
  const bash = process.platform === 'win32' ? join(process.env.ProgramFiles ?? 'C:/Program Files', 'Git/bin/bash.exe') : 'bash';
  if (process.platform === 'win32' && !existsSync(bash)) return t.skip('Git Bash não está instalado.');
  const workflow = readFileSync('.github/workflows/terraform-bootstrap.yml', 'utf8');
  const block = workflow.match(/- name: Reuse an existing GitHub OIDC provider\r?\n        run: \|\r?\n([\s\S]*?)(?=      - name:)/);
  assert.ok(block, 'Etapa de reutilização de OIDC deve existir.');
  const script = block[1].split(/\r?\n/).map(line => line.startsWith('          ') ? line.slice(10) : line).join('\n');
  const scenarios = [
    { name: 'first-run', exit: '1', error: 'No state file was found!', expected: 0, discover: true },
    { name: 'access-denied', exit: '1', error: 'AccessDenied: S3 returned 403', expected: 1, discover: false },
    { name: 'invalid-state', exit: '1', error: 'Error: invalid state JSON', expected: 1, discover: false },
    { name: 'managed-provider', exit: '0', output: 'aws_iam_openid_connect_provider.github[0]', expected: 0, discover: false },
    { name: 'reuse-provider', exit: '0', expected: 0, discover: true, existingProvider: true },
    { name: 'static-credentials-mode', exit: '0', expected: 0, discover: false, manageOidc: 'false' },
  ];
  for (const scenario of scenarios) {
    const root = mkdtempSync(join(tmpdir(), 'tc3-bootstrap-test-'));
    const portable = value => value.replaceAll('\\', '/');
    const calls = join(root, 'aws-calls');
    const terraformCalls = join(root, 'terraform-calls');
    const githubEnv = join(root, 'github-env');
    const scriptPath = join(root, 'verify.sh');
    writeFileSync(scriptPath, `
terraform() {
  printf '%s\\n' "$*" >> "$MOCK_TERRAFORM_CALLS"
  printf '%s\\n' "$MOCK_STATE_OUTPUT"
  printf '%s\\n' "$MOCK_STATE_ERROR" >&2
  return "$MOCK_STATE_EXIT"
}
aws() { printf 'called\\n' >> "$MOCK_CALLS"; printf '{}\\n'; }
jq() { return "$MOCK_PROVIDER_EXIT"; }
${script}`);
    const result = spawnSync(bash, ['-e', portable(scriptPath)], { encoding: 'utf8', env: {
      ...process.env, RUNNER_TEMP: portable(root), BOOTSTRAP_DIR: portable(root),
      GITHUB_ENV: portable(githubEnv), AWS_ACCOUNT_ID: '213284176265', MOCK_CALLS: portable(calls),
      MOCK_TERRAFORM_CALLS: portable(terraformCalls),
      MOCK_STATE_OUTPUT: scenario.output ?? '', MOCK_STATE_ERROR: scenario.error ?? '',
      MOCK_STATE_EXIT: scenario.exit, MOCK_PROVIDER_EXIT: scenario.existingProvider ? '0' : '1',
      TF_VAR_manage_github_oidc_roles: scenario.manageOidc ?? 'true',
    } });
    assert.equal(result.status, scenario.expected, `${scenario.name}: ${result.stderr}`);
    assert.equal(existsSync(calls), scenario.discover, scenario.name);
    if (scenario.existingProvider) assert.match(readFileSync(githubEnv, 'utf8'), /TF_VAR_existing_github_oidc_provider_arn=/);
    if (scenario.expected === 1) assert.match(result.stderr, new RegExp(scenario.error));
  }
});

test('bootstrap removes legacy bucket resources from remote state before planning', () => {
  const bash = process.platform === 'win32' ? join(process.env.ProgramFiles ?? 'C:/Program Files', 'Git/bin/bash.exe') : 'bash';
  if (process.platform === 'win32' && !existsSync(bash)) return;
  const workflow = readFileSync('.github/workflows/terraform-bootstrap.yml', 'utf8');
  const block = workflow.match(/- name: Reuse an existing GitHub OIDC provider\r?\n        run: \|\r?\n([\s\S]*?)(?=      - name:)/);
  assert.ok(block, 'Etapa de reutilização de OIDC deve existir.');
  const script = block[1].split(/\r?\n/).map(line => line.startsWith('          ') ? line.slice(10) : line).join('\n');
  const root = mkdtempSync(join(tmpdir(), 'tc3-bootstrap-legacy-state-'));
  const portable = value => value.replaceAll('\\', '/');
  const terraformCalls = join(root, 'terraform-calls');
  const scriptPath = join(root, 'verify.sh');
  writeFileSync(scriptPath, `
terraform() {
  printf '%s\\n' "$*" >> "$MOCK_TERRAFORM_CALLS"
  if [[ "$*" == *' state list' ]]; then
    printf '%s\\n' 'aws_s3_bucket.state["homologacao"]' 'aws_s3_bucket_public_access_block.state["producao"]' 'aws_iam_role.terraform["producao-plan"]'
  fi
}
aws() { printf '{}\\n'; }
jq() { return 1; }
${script}`);
  const result = spawnSync(bash, ['-e', portable(scriptPath)], { encoding: 'utf8', env: {
    ...process.env, RUNNER_TEMP: portable(root), BOOTSTRAP_DIR: portable(root), GITHUB_ENV: portable(join(root, 'github-env')),
    AWS_ACCOUNT_ID: '213284176265', MOCK_TERRAFORM_CALLS: portable(terraformCalls),
  } });
  assert.equal(result.status, 0, result.stderr);
  const calls = readFileSync(terraformCalls, 'utf8');
  assert.match(calls, /state rm aws_s3_bucket\.state\["homologacao"\] aws_s3_bucket_public_access_block\.state\["producao"\]/);
  assert.doesNotMatch(calls, /aws_iam_role\.terraform/);
});
