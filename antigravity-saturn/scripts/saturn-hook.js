'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const MAX_INPUT_BYTES = 1024 * 1024;
const MAX_EVENT_FILES = 500;
const KEEP_EVENT_FILES = 400;
const KNOWN_EVENTS = new Set([
  'PreInvocation',
  'PostInvocation',
  'PreToolUse',
  'PostToolUse',
  'Stop',
]);
const EVENT_RANK = {
  PreInvocation: 1,
  PreToolUse: 2,
  PostToolUse: 3,
  PostInvocation: 4,
  Stop: 9,
};
const TERMINATION_REASONS = new Set(['model_stop', 'max_steps_exceeded', 'error']);

function getDataRoot(env = process.env) {
  return env.SATURN_DATA_DIR || path.join(os.homedir(), '.gemini', 'antigravity-saturn');
}

function responseFor(eventName) {
  if (eventName === 'PreToolUse') return { decision: 'allow' };
  if (eventName === 'Stop') return { decision: '' };
  return {};
}

function mapState(eventName, payload) {
  if (eventName === 'Stop') {
    if (payload.error || payload.terminationReason === 'error' || payload.terminationReason === 'max_steps_exceeded') {
      return { state: 'attention', reason: 'execution-error' };
    }
    if (payload.fullyIdle === false) return { state: 'working', reason: 'background-active' };
    return { state: 'done', reason: 'execution-stopped' };
  }
  if (eventName === 'PostToolUse' && payload.error) {
    return { state: 'attention', reason: 'tool-error' };
  }
  if (eventName === 'PreToolUse') return { state: 'working', reason: 'tool-started' };
  if (eventName === 'PostToolUse') return { state: 'working', reason: 'tool-finished' };
  if (eventName === 'PreInvocation') return { state: 'working', reason: 'model-started' };
  return { state: 'working', reason: 'model-finished' };
}

function conversationKey(value) {
  const raw = typeof value === 'string' && value ? value : 'unknown';
  return crypto.createHash('sha256').update(raw).digest('hex').slice(0, 20);
}

function normalizeEvent(eventName, payload, now = Date.now()) {
  const mapped = mapState(eventName, payload);
  const record = {
    version: 1,
    source: 'antigravity',
    event: eventName,
    state: mapped.state,
    reason: mapped.reason,
    conversationKey: conversationKey(payload.conversationId),
    timestampMs: now,
  };

  if (Number.isInteger(payload.stepIdx)) record.stepIdx = payload.stepIdx;
  if (Number.isInteger(payload.invocationNum)) record.invocationNum = payload.invocationNum;
  if (Number.isInteger(payload.executionNum)) record.executionNum = payload.executionNum;
  if (Array.isArray(payload.workspacePaths)) record.workspaceCount = payload.workspacePaths.length;
  if (eventName === 'Stop' && typeof payload.fullyIdle === 'boolean') record.fullyIdle = payload.fullyIdle;
  if (eventName === 'Stop' && typeof payload.terminationReason === 'string') {
    record.terminationReason = TERMINATION_REASONS.has(payload.terminationReason) ? payload.terminationReason : 'other';
  }
  return record;
}

function pruneEvents(eventsDir) {
  let files;
  try {
    files = fs.readdirSync(eventsDir)
      .filter((name) => name.endsWith('.json'))
      .sort();
  } catch {
    return;
  }
  if (files.length <= MAX_EVENT_FILES) return;
  for (const name of files.slice(0, files.length - KEEP_EVENT_FILES)) {
    try { fs.unlinkSync(path.join(eventsDir, name)); } catch { /* best effort */ }
  }
}

function writeEvent(record, dataRoot = getDataRoot()) {
  const eventsDir = path.join(dataRoot, 'events');
  fs.mkdirSync(eventsDir, { recursive: true, mode: 0o700 });
  const nonce = crypto.randomBytes(5).toString('hex');
  const rank = EVENT_RANK[record.event] || 0;
  const stem = `${String(record.timestampMs).padStart(13, '0')}-${rank}-${process.pid}-${nonce}`;
  const temporary = path.join(eventsDir, `.${stem}.tmp`);
  const destination = path.join(eventsDir, `${stem}.json`);
  fs.writeFileSync(temporary, `${JSON.stringify(record)}\n`, { encoding: 'utf8', mode: 0o600, flag: 'wx' });
  fs.renameSync(temporary, destination);
  pruneEvents(eventsDir);
  return destination;
}

function parseInput(text) {
  if (!text || text.length > MAX_INPUT_BYTES) return {};
  try {
    const value = JSON.parse(text);
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  } catch {
    return {};
  }
}

function handle(eventName, payload, options = {}) {
  const response = responseFor(eventName);
  if (!KNOWN_EVENTS.has(eventName)) return response;
  const record = normalizeEvent(eventName, payload, options.now);
  writeEvent(record, options.dataRoot);
  return response;
}

function main() {
  const eventName = process.argv[2] || '';
  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => {
    if (input.length <= MAX_INPUT_BYTES) input += chunk;
  });
  process.stdin.on('end', () => {
    let response = responseFor(eventName);
    try { response = handle(eventName, parseInput(input)); } catch { /* hooks must remain non-blocking */ }
    process.stdout.write(`${JSON.stringify(response)}\n`);
  });
}

if (require.main === module) main();

module.exports = {
  conversationKey,
  getDataRoot,
  handle,
  mapState,
  normalizeEvent,
  parseInput,
  responseFor,
  writeEvent,
};
