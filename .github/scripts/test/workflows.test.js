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

function fakeGithub({ comments = [], reviews = [], prs = {}, runs = [], statuses = [], openPrs = [], associated = [] } = {}) {
  const calls = { created: [], added: [], removed: [], graphql: [], dismissed: [] };
  return {
    calls,
    github: {
      paginate: async (fn) => ({ listComments: comments, listReviews: reviews, listOpen: openPrs })[fn] ?? [],
      graphql: async (query, vars) => { calls.graphql.push({ query, vars }); },
      rest: {
        issues: {
          listComments: 'listComments',
          createComment: async (a) => { calls.created.push(a); },
          addLabels: async (a) => { calls.added.push(a.labels); },
          removeLabel: async (a) => { calls.removed.push(a.name); },
        },
        pulls: {
          list: 'listOpen',
          listReviews: 'listReviews',
          get: async ({ pull_number: n }) => {
            if (!prs[n]) throw new Error(`no PR ${n}`);
            return { data: prs[n] };
          },
          dismissReview: async (a) => { calls.dismissed.push(a.review_id); },
        },
        checks: { listForRef: async () => ({ data: { check_runs: runs } }) },
        repos: {
          getCombinedStatusForRef: async () => ({ data: { statuses } }),
          listPullRequestsAssociatedWithCommit: async () => ({ data: associated }),
        },
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
  assert.match(f.calls.created[0].body, /status: automerge/);
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

const review = (login, state, id = 1) => ({ id, user: { login }, state });
const green = (name = 'validate') => ({ name, status: 'completed', conclusion: 'success' });
const running = (name = 'validate') => ({ name, status: 'in_progress', conclusion: null });
const failed = (name = 'validate', conclusion = 'failure') => ({ name, status: 'completed', conclusion });
const pr = (over = {}) => ({
  number: 7, node_id: 'PR_7', state: 'open', draft: false, labels: [], auto_merge: null,
  head: { sha: 'abc' }, ...over,
});
const prEvent = (action = 'opened', number = 7) => ({
  repo, eventName: 'pull_request_target', payload: { action, pull_request: { number } },
});
async function status(opts, context = prEvent()) {
  const f = fakeGithub({ prs: { 7: pr(opts.pr) }, ...opts });
  await run('pr-status.yml', { github: f.github, context });
  return f.calls;
}
const enabled = (calls) => calls.graphql.filter((g) => /enablePullRequestAutoMerge/.test(g.query));
const disabled = (calls) => calls.graphql.filter((g) => /disablePullRequestAutoMerge/.test(g.query));

test('pr-status: an unreviewed PR needs approval and never merges', async () => {
  const c = await status({ reviews: [], runs: [green()] });
  assert.deepEqual(c.added, [['status: needs approval']]);
  assert.equal(enabled(c).length, 0);
});

test('pr-status: approved with checks running waits for green', async () => {
  const c = await status({ reviews: [review('m', 'APPROVED')], runs: [green('pr-title'), running()] });
  assert.deepEqual(c.added, [['status: waiting for green']]);
  assert.equal(enabled(c).length, 0);
});

test('pr-status: approved with no checks yet also waits', async () => {
  const c = await status({ reviews: [review('m', 'APPROVED')], runs: [] });
  assert.deepEqual(c.added, [['status: waiting for green']]);
});

test('pr-status: approved with a failing check is ci failed and replaces the old status', async () => {
  const c = await status({
    pr: { labels: [{ name: 'status: waiting for green' }] },
    reviews: [review('m', 'APPROVED')], runs: [green('pr-title'), failed()],
  });
  assert.deepEqual(c.added, [['status: ci failed']]);
  assert.deepEqual(c.removed, ['status: waiting for green']);
  assert.equal(enabled(c).length, 0);
});

test('pr-status: approved and all green enables squash auto-merge', async () => {
  const c = await status({
    pr: { labels: [{ name: 'status: waiting for green' }] },
    reviews: [review('m', 'APPROVED')], runs: [green(), green('pr-title'), green('dependency-review')],
  });
  assert.deepEqual(c.added, [['status: automerge']]);
  assert.deepEqual(c.removed, ['status: waiting for green']);
  assert.equal(enabled(c).length, 1);
  assert.match(enabled(c)[0].query, /SQUASH/);
  assert.equal(enabled(c)[0].vars.id, 'PR_7');
});

test('pr-status: auto-merge is not enabled twice and labels are not re-added', async () => {
  const c = await status({
    pr: { labels: [{ name: 'status: automerge' }], auto_merge: { merge_method: 'squash' } },
    reviews: [review('m', 'APPROVED')], runs: [green()],
  });
  assert.deepEqual(c.added, []);
  assert.deepEqual(c.removed, []);
  assert.equal(c.graphql.length, 0);
});

test('pr-status: skipped and neutral count as passing, cancelled and timed out as failing', async () => {
  const ok = await status({
    reviews: [review('m', 'APPROVED')],
    runs: [green(), { name: 'a', status: 'completed', conclusion: 'skipped' }, { name: 'b', status: 'completed', conclusion: 'neutral' }],
  });
  assert.deepEqual(ok.added, [['status: automerge']]);
  for (const conclusion of ['cancelled', 'timed_out', 'action_required']) {
    const bad = await status({ reviews: [review('m', 'APPROVED')], runs: [green(), failed('x', conclusion)] });
    assert.deepEqual(bad.added, [['status: ci failed']], conclusion);
  }
});

test('pr-status: this job is ignored and legacy commit statuses count', async () => {
  const ignoring = await status({ reviews: [review('m', 'APPROVED')], runs: [green(), running('status')] });
  assert.deepEqual(ignoring.added, [['status: automerge']]);
  const pending = await status({ reviews: [review('m', 'APPROVED')], runs: [green()], statuses: [{ state: 'pending' }] });
  assert.deepEqual(pending.added, [['status: waiting for green']]);
  for (const state of ['failure', 'error']) {
    const bad = await status({ reviews: [review('m', 'APPROVED')], runs: [green()], statuses: [{ state }] });
    assert.deepEqual(bad.added, [['status: ci failed']], state);
  }
});

test('pr-status: requested changes and drafts need approval even when approved and green', async () => {
  const changes = await status({ reviews: [review('a', 'APPROVED'), review('b', 'CHANGES_REQUESTED', 2)], runs: [green()] });
  assert.deepEqual(changes.added, [['status: needs approval']]);
  assert.equal(enabled(changes).length, 0);
  const draft = await status({ pr: { draft: true }, reviews: [review('m', 'APPROVED')], runs: [green()] });
  assert.deepEqual(draft.added, [['status: needs approval']]);
  assert.equal(enabled(draft).length, 0);
});

test('pr-status: only a reviewer\'s latest verdict counts and comments are ignored', async () => {
  const fixed = await status({
    reviews: [review('b', 'CHANGES_REQUESTED', 1), review('b', 'APPROVED', 2), review('c', 'COMMENTED', 3)],
    runs: [green()],
  });
  assert.deepEqual(fixed.added, [['status: automerge']]);
  const onlyComments = await status({ reviews: [review('c', 'COMMENTED')], runs: [green()] });
  assert.deepEqual(onlyComments.added, [['status: needs approval']]);
});

test('pr-status: on hold clears managed labels and turns auto-merge off', async () => {
  const c = await status({
    pr: { labels: [{ name: 'status: on hold' }, { name: 'status: automerge' }], auto_merge: { merge_method: 'squash' } },
    reviews: [review('m', 'APPROVED')], runs: [green()],
  });
  assert.deepEqual(c.removed, ['status: automerge']);
  assert.deepEqual(c.added, []);
  assert.equal(enabled(c).length, 0);
  assert.equal(disabled(c).length, 1);
});

test('pr-status: a new push dismisses approvals so it cannot auto-merge unreviewed', async () => {
  const f = fakeGithub({
    prs: { 7: pr({ labels: [{ name: 'status: automerge' }], auto_merge: { merge_method: 'squash' } }) },
    reviews: [review('m', 'APPROVED', 41), review('n', 'APPROVED', 42)], runs: [green()],
  });
  await run('pr-status.yml', { github: f.github, context: prEvent('synchronize') });
  assert.deepEqual(f.calls.dismissed, [41, 42]);
  assert.deepEqual(f.calls.added, [['status: needs approval']]);
  assert.deepEqual(f.calls.removed, ['status: automerge']);
  assert.equal(enabled(f.calls).length, 0);
});

test('pr-status: approvals are only dismissed on synchronize', async () => {
  const f = fakeGithub({ prs: { 7: pr() }, reviews: [review('m', 'APPROVED', 41)], runs: [green()] });
  await run('pr-status.yml', { github: f.github, context: prEvent('labeled') });
  assert.deepEqual(f.calls.dismissed, []);
});

test('pr-status: closed pull requests are ignored', async () => {
  const c = await status({ pr: { state: 'closed' }, reviews: [review('m', 'APPROVED')], runs: [green()] });
  assert.deepEqual(c.added, []);
  assert.equal(c.graphql.length, 0);
});

test('pr-status: a finished CI run uses its PRs, else looks them up by commit', async () => {
  const direct = fakeGithub({ prs: { 7: pr() }, reviews: [review('m', 'APPROVED')], runs: [green()] });
  await run('pr-status.yml', {
    github: direct.github,
    context: { repo, eventName: 'workflow_run', payload: { workflow_run: { head_sha: 'abc', pull_requests: [{ number: 7 }] } } },
  });
  assert.deepEqual(direct.calls.added, [['status: automerge']]);

  const fork = fakeGithub({
    prs: { 7: pr() }, reviews: [review('m', 'APPROVED')], runs: [green()],
    associated: [{ number: 7, state: 'open' }, { number: 8, state: 'closed' }],
  });
  await run('pr-status.yml', {
    github: fork.github,
    context: { repo, eventName: 'workflow_run', payload: { workflow_run: { head_sha: 'abc', pull_requests: [] } } },
  });
  assert.deepEqual(fork.calls.added, [['status: automerge']]);
});

test('pr-status: the schedule sweeps every open PR and one failure does not stop the rest', async () => {
  const f = fakeGithub({
    prs: { 7: pr(), 9: pr({ number: 9, node_id: 'PR_9' }) },
    openPrs: [{ number: 5 }, { number: 7 }, { number: 9 }],
    reviews: [review('m', 'APPROVED')], runs: [green()],
  });
  await run('pr-status.yml', { github: f.github, context: { repo, eventName: 'schedule', payload: {} } });
  assert.deepEqual(f.calls.added, [['status: automerge'], ['status: automerge']]);
  assert.equal(enabled(f.calls).length, 2);
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
