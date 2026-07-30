'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const adapter = require(path.resolve(__dirname, '..', 'scripts', 'saturn-hook.js'));

function invoke(dataRoot, eventName, payload) {
  return adapter.handle(eventName, payload, {
    dataRoot,
    host: { hookParentPid: 123, hostPid: 456, terminalPid: 789, terminalKey: '0123456789' },
  });
}

test('hook contracts and normalized state records stay privacy-safe', (t) => {
  const dataRoot = fs.mkdtempSync(path.join(__dirname, '.tmp-saturn-hook-'));
  t.after(() => fs.rmSync(dataRoot, { recursive: true, force: true }));
  const common = {
    conversationId: 'the-real-conversation-id',
    workspacePaths: ['C:\\secret-project'],
    transcriptPath: 'C:\\private\\transcript.jsonl',
    artifactDirectoryPath: 'C:\\private\\artifacts',
    prompt: 'DO NOT STORE THIS PROMPT',
  };

  assert.deepEqual(invoke(dataRoot, 'PreInvocation', { ...common, invocationNum: 1 }), {});
  assert.deepEqual(invoke(dataRoot, 'PreToolUse', {
    ...common,
    stepIdx: 2,
    toolCall: { name: 'run_command', args: { CommandLine: 'SECRET COMMAND' } },
  }), { decision: 'allow' });
  assert.deepEqual(invoke(dataRoot, 'PostToolUse', { ...common, stepIdx: 2, error: '' }), {});
  assert.deepEqual(invoke(dataRoot, 'PostInvocation', { ...common, invocationNum: 1 }), {});
  assert.deepEqual(invoke(dataRoot, 'Stop', {
    ...common,
    executionNum: 1,
    terminationReason: 'model_stop',
    fullyIdle: true,
  }), { decision: '' });

  const eventDir = path.join(dataRoot, 'events');
  const files = fs.readdirSync(eventDir).filter((name) => name.endsWith('.json')).sort();
  assert.equal(files.length, 5);
  const records = files.map((name) => JSON.parse(fs.readFileSync(path.join(eventDir, name), 'utf8')));
  assert.deepEqual(records.map((record) => record.state), ['working', 'working', 'working', 'working', 'done']);
  assert.equal(new Set(records.map((record) => record.conversationKey)).size, 1);
  assert.equal(records.every((record) => Number.isInteger(record.hookParentPid) && record.hookParentPid > 0), true);
  assert.equal(records.every((record) => record.hostPid === 456 && record.terminalPid === 789 && record.terminalKey === '0123456789'), true);
  const persisted = JSON.stringify(records);
  for (const secret of ['the-real-conversation-id', 'secret-project', 'transcript.jsonl', 'DO NOT STORE THIS PROMPT', 'SECRET COMMAND']) {
    assert.equal(persisted.includes(secret), false, `persisted secret: ${secret}`);
  }
});

test('terminal identity is session-specific and the marker bypasses hook stdout', () => {
  const key = adapter.terminalKey({ WT_SESSION: '{2fd244e0-a33f-4ebe-8b67-b6e88f6f4270}' });
  assert.match(key, /^[0-9a-f]{10}$/);
  assert.equal(adapter.terminalKey({}), '');
  assert.equal(adapter.terminalTitle(key), `Saturn - Antigravity CLI [${key}]`);

  let marker = '';
  assert.equal(adapter.markTerminalTab(adapter.terminalTitle(key), (sequence) => { marker = sequence; }), true);
  assert.equal(marker, `\u001b]0;Saturn - Antigravity CLI [${key}]\u0007`);
});

test('reliable errors surface attention and background stops remain working', (t) => {
  const dataRoot = fs.mkdtempSync(path.join(__dirname, '.tmp-saturn-hook-'));
  t.after(() => fs.rmSync(dataRoot, { recursive: true, force: true }));
  invoke(dataRoot, 'PostToolUse', { conversationId: 'a', error: 'failed' });
  invoke(dataRoot, 'Stop', { conversationId: 'a', fullyIdle: false, terminationReason: 'model_stop' });
  const records = fs.readdirSync(path.join(dataRoot, 'events')).sort()
    .map((name) => JSON.parse(fs.readFileSync(path.join(dataRoot, 'events', name), 'utf8')));
  assert.equal(records[0].state, 'attention');
  assert.equal(records[1].state, 'working');
});
