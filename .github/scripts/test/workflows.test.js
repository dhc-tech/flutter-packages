// Tests the actions/github-script bodies of the label/bot workflows against a
// fake GitHub API. Run: node --test .github/scripts/test/
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const workflows = path.join(__dirname, '..', '..', 'workflows');

// Pulls the `script: |` block out of a workflow file and dedents it.
function scriptOf(file) {
  const lines = fs.readFileSync(path.join(workflows, file), 'utf8').split('\n');
  const start = lines.findIndex((l) => /^\s*script: \|\s*$/.test(l));
  assert.notEqual(start, -1, `no script block in ${file}`);
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== '' && line.search(/\S/) <= keyIndent) break;
    body.push(line.slice(keyIndent + 2));
  }
  return body.join('\n');
}

function fakeGithub({ comments = [], permission = 'write' } = {}) {
  const calls = { created: [], added: [], removed: [], graphql: [] };
  const issues = {
    listComments: 'listComments',
    createComment: async (a) => { calls.created.push(a); },
    addLabels: async (a) => { calls.added.push(a.labels); },
    removeLabel: async (a) => { calls.removed.push(a.name); },
  };
  return {
    calls,
    github: {
      paginate: async () => comments,
      graphql: async (query, vars) => { calls.graphql.push({ query, vars }); },
      rest: {
        issues,
        repos: { getCollaboratorPermissionLevel: async () => ({ data: { permission } }) },
      },
    },
  };
}

async function run(file, { github, context }) {
  const core = { info() {}, warning() {}, setFailed(m) { throw new Error(m); } };
  const fn = new AsyncFunction('github', 'context', 'core', scriptOf(file));
  await fn(github, context, core);
}

const repo = { owner: 'dhc-tech', repo: 'flutter-packages' };
const label = (name) => ({ name });

test('bot: welcomes a new issue once', async () => {
  const f = fakeGithub();
  const context = { repo, eventName: 'issues', payload: { action: 'opened', issue: { number: 1, labels: [] } } };
  await run('bot.yml', { github: f.github, context });
  assert.equal(f.calls.created.length, 1);
  assert.match(f.calls.created[0].body, /repo-bot:welcome-issue/);

  const again = fakeGithub({ comments: [{ body: '<!-- repo-bot:welcome-issue -->\nhi' }] });
  await run('bot.yml', { github: again.github, context });
  assert.equal(again.calls.created.length, 0, 'must not comment twice');
});

test('bot: welcomes a new pull request with the checklist', async () => {
  const f = fakeGithub();
  const context = { repo, eventName: 'pull_request_target', payload: { action: 'opened', pull_request: { number: 5 } } };
  await run('bot.yml', { github: f.github, context });
  assert.equal(f.calls.created.length, 1);
  assert.match(f.calls.created[0].body, /Conventional Commit/);
  assert.match(f.calls.created[0].body, /autosubmit/);
});

test('bot: asks for details when needs: info is added', async () => {
  const f = fakeGithub();
  const context = { repo, eventName: 'issues', payload: { action: 'labeled', label: label('needs: info'), issue: { number: 2, labels: [label('needs: info')] } } };
  await run('bot.yml', { github: f.github, context });
  assert.match(f.calls.created[0].body, /flutter doctor -v/);
});

test('bot: invites contributors for good first issue and help wanted only', async () => {
  for (const name of ['good first issue', 'help wanted']) {
    const f = fakeGithub();
    const context = { repo, eventName: 'issues', payload: { action: 'labeled', label: label(name), issue: { number: 3, labels: [label(name)] } } };
    await run('bot.yml', { github: f.github, context });
    assert.equal(f.calls.created.length, 1, name);
  }
  const f = fakeGithub();
  const context = { repo, eventName: 'issues', payload: { action: 'labeled', label: label('question'), issue: { number: 3, labels: [] } } };
  await run('bot.yml', { github: f.github, context });
  assert.equal(f.calls.created.length, 0);
});

test('bot: reporter reply swaps needs: info for needs: triage', async () => {
  const f = fakeGithub();
  const context = {
    repo, eventName: 'issue_comment',
    payload: {
      action: 'created',
      issue: { number: 4, user: { login: 'reporter' }, labels: [label('needs: info')] },
      comment: { user: { login: 'reporter', type: 'User' } },
    },
  };
  await run('bot.yml', { github: f.github, context });
  assert.deepEqual(f.calls.removed, ['needs: info']);
  assert.deepEqual(f.calls.added, [['needs: triage']]);
});

test('bot: ignores replies from others, bots, other labels and pull requests', async () => {
  const base = { number: 4, user: { login: 'reporter' }, labels: [label('needs: info')] };
  const cases = [
    { issue: base, comment: { user: { login: 'maintainer', type: 'User' } } },
    { issue: base, comment: { user: { login: 'reporter', type: 'Bot' } } },
    { issue: { ...base, labels: [label('question')] }, comment: { user: { login: 'reporter', type: 'User' } } },
    { issue: { ...base, pull_request: {} }, comment: { user: { login: 'reporter', type: 'User' } } },
  ];
  for (const payload of cases) {
    const f = fakeGithub();
    await run('bot.yml', { github: f.github, context: { repo, eventName: 'issue_comment', payload: { action: 'created', ...payload } } });
    assert.deepEqual(f.calls.removed, []);
    assert.deepEqual(f.calls.added, []);
  }
});

function prContext(title, body = '', labels = []) {
  return { repo, eventName: 'pull_request_target', payload: { action: 'opened', pull_request: { number: 9, title, body, labels } } };
}

test('pr-labels: adds the type from a Conventional Commit title', async () => {
  const f = fakeGithub();
  await run('pr-labels.yml', { github: f.github, context: prContext('feat(dig_cli): add flag') });
  assert.deepEqual(f.calls.added, [['type: feat']]);
});

test('pr-labels: replaces a stale type and marks breaking changes', async () => {
  const f = fakeGithub();
  await run('pr-labels.yml', { github: f.github, context: prContext('fix(white_label_kit)!: drop api', '', [label('type: feat'), label('p: dig_cli')]) });
  assert.deepEqual(f.calls.added.flat().sort(), ['breaking-change', 'type: fix']);
  assert.deepEqual(f.calls.removed, ['type: feat']);
});

test('pr-labels: BREAKING CHANGE footer counts and unrelated labels are kept', async () => {
  const f = fakeGithub();
  await run('pr-labels.yml', { github: f.github, context: prContext('refactor: tidy', 'x\n\nBREAKING CHANGE: y', [label('platform: web')]) });
  assert.deepEqual(f.calls.added.flat().sort(), ['breaking-change', 'type: refactor']);
  assert.deepEqual(f.calls.removed, []);
});

test('pr-labels: an unknown or missing prefix adds no type and clears a stale one', async () => {
  for (const title of ['Update stuff', 'wip(x): y', 'feat add thing']) {
    const f = fakeGithub();
    await run('pr-labels.yml', { github: f.github, context: prContext(title, '', [label('type: fix')]) });
    assert.deepEqual(f.calls.added, [], title);
    assert.deepEqual(f.calls.removed, ['type: fix'], title);
  }
});

function labelContext(action, actor = 'maintainer') {
  return { repo, actor, payload: { action, label: label('autosubmit'), pull_request: { number: 7, node_id: 'PR_node' } } };
}

test('autosubmit: a maintainer enables squash auto-merge', async () => {
  for (const permission of ['admin', 'maintain', 'write']) {
    const f = fakeGithub({ permission });
    await run('autosubmit.yml', { github: f.github, context: labelContext('labeled') });
    assert.equal(f.calls.graphql.length, 1, permission);
    assert.match(f.calls.graphql[0].query, /enablePullRequestAutoMerge/);
    assert.match(f.calls.graphql[0].query, /SQUASH/);
    assert.equal(f.calls.graphql[0].vars.id, 'PR_node');
  }
});

test('autosubmit: removing the label disables auto-merge', async () => {
  const f = fakeGithub();
  await run('autosubmit.yml', { github: f.github, context: labelContext('unlabeled') });
  assert.match(f.calls.graphql[0].query, /disablePullRequestAutoMerge/);
});

test('autosubmit: users without write access cannot use it', async () => {
  for (const permission of ['read', 'triage', 'none']) {
    const f = fakeGithub({ permission });
    await run('autosubmit.yml', { github: f.github, context: labelContext('labeled', 'stranger') });
    assert.equal(f.calls.graphql.length, 0, permission);
    assert.deepEqual(f.calls.removed, ['autosubmit'], permission);
  }
});

function issueContext(title, body, labels = []) {
  return { repo, payload: { action: 'opened', issue: { number: 11, title, body, labels } } };
}

test('issue-labeler: adds package, platform and type labels from the text', async () => {
  const f = fakeGithub();
  await run('issue-labeler.yml', { github: f.github, context: issueContext('[Bug]: dig_cli crashes', 'Happens on Android and iOS') });
  assert.deepEqual(f.calls.added.flat().sort(), ['p: dig_cli', 'platform: android', 'platform: ios', 'type: fix']);
});

test('issue-labeler: never re-adds existing labels and tolerates an empty body', async () => {
  const f = fakeGithub();
  await run('issue-labeler.yml', { github: f.github, context: issueContext('apple sign in feature request', null, [label('p: apple_sign_in_plugin')]) });
  assert.deepEqual(f.calls.added.flat().sort(), ['type: feat']);

  const none = fakeGithub();
  await run('issue-labeler.yml', { github: none.github, context: issueContext('hello', '') });
  assert.deepEqual(none.calls.added, []);
});

test('issue-labeler: matches package names with separators and breaking-change', async () => {
  const f = fakeGithub();
  await run('issue-labeler.yml', { github: f.github, context: issueContext('white label kit', 'this is a breaking change for attachment-engine') });
  assert.deepEqual(f.calls.added.flat().sort(), ['breaking-change', 'p: attachment_engine', 'p: white_label_kit']);
});
