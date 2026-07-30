'use strict';

const crypto = require('node:crypto');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const MAX_INPUT_BYTES = 1024 * 1024;
const MAX_EVENT_FILES = 500;
const KEEP_EVENT_FILES = 400;
const TAB_TITLE_PREFIX = 'Saturn - Antigravity CLI';
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

function terminalKey(env = process.env) {
  const session = typeof env.WT_SESSION === 'string' ? env.WT_SESSION.trim() : '';
  if (!session) return '';
  return crypto.createHash('sha256').update(session).digest('hex').slice(0, 10);
}

function terminalTitle(key = '') {
  return key ? `${TAB_TITLE_PREFIX} [${key}]` : TAB_TITLE_PREFIX;
}

function markTerminalTab(title, writer) {
  const sequence = `\u001b]0;${title}\u0007`;
  if (writer) {
    try { writer(sequence); return true; } catch { return false; }
  }
  let marked = false;
  try {
    const fd = fs.openSync('\\\\.\\CONOUT$', 'w');
    try { fs.writeSync(fd, sequence, null, 'utf8'); } finally { fs.closeSync(fd); }
    marked = true;
  } catch { /* fall through to the console-title command */ }
  try {
    const result = childProcess.spawnSync('cmd.exe', ['/d', '/c', 'title', title], {
      stdio: 'ignore', timeout: 1000, windowsHide: true,
    });
    if (result.status === 0) marked = true;
  } catch { /* hooks remain non-blocking */ }
  return marked;
}

function discoverHostProcess(parentPid = process.ppid) {
  const safeParentPid = Number.isInteger(parentPid) && parentPid > 0 ? parentPid : process.ppid;
  const fallback = { hookParentPid: safeParentPid, hostPid: safeParentPid, terminalPid: 0 };
  const script = [
    "$all=@{}",
    "Get-CimInstance -Query 'SELECT ProcessId,ParentProcessId,Name,CreationDate FROM Win32_Process' -ErrorAction SilentlyContinue | ForEach-Object { $all[[int]$_.ProcessId]=$_ }",
    `$cur=${safeParentPid}`,
    "$agy=0",
    "$terminal=0",
    "for($i=0;$i -lt 12 -and $cur -gt 0;$i++){ if(-not $all.ContainsKey($cur)){break}; $p=$all[$cur]; if($p.Name -ieq 'agy.exe'){$agy=$cur}; if($p.Name -ieq 'WindowsTerminal.exe'){$terminal=$cur}; $cur=[int]$p.ParentProcessId }",
    "Write-Output ($agy.ToString() + ',' + $terminal.ToString())",
  ].join('; ');
  try {
    const result = childProcess.spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script,
    ], { encoding: 'utf8', timeout: 2000, windowsHide: true });
    if (result.status !== 0) return fallback;
    const match = String(result.stdout || '').trim().match(/(\d+),(\d+)\s*$/);
    if (!match) return fallback;
    const agyPid = Number(match[1]);
    const terminalPid = Number(match[2]);
    return {
      hookParentPid: safeParentPid,
      hostPid: agyPid > 0 ? agyPid : safeParentPid,
      terminalPid: terminalPid > 0 ? terminalPid : 0,
    };
  } catch {
    return fallback;
  }
}

function normalizeEvent(eventName, payload, now = Date.now(), host = discoverHostProcess()) {
  const mapped = mapState(eventName, payload);
  const record = {
    version: 1,
    source: 'antigravity',
    event: eventName,
    state: mapped.state,
    reason: mapped.reason,
    conversationKey: conversationKey(payload.conversationId),
    hookParentPid: host.hookParentPid,
    hostPid: host.hostPid,
    terminalPid: host.terminalPid,
    timestampMs: now,
  };
  if (typeof host.terminalKey === 'string' && /^[0-9a-f]{10}$/.test(host.terminalKey)) {
    record.terminalKey = host.terminalKey;
  }

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
  const record = normalizeEvent(eventName, payload, options.now, options.host);
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
    try {
      const host = discoverHostProcess();
      host.terminalKey = terminalKey();
      const title = terminalTitle(host.terminalKey);
      markTerminalTab(title);
      response = handle(eventName, parseInput(input), { host });
      markTerminalTab(title);
    } catch { /* hooks must remain non-blocking */ }
    process.stdout.write(`${JSON.stringify(response)}\n`);
  });
}

if (require.main === module) main();

module.exports = {
  conversationKey,
  discoverHostProcess,
  getDataRoot,
  handle,
  markTerminalTab,
  mapState,
  normalizeEvent,
  parseInput,
  responseFor,
  terminalKey,
  terminalTitle,
  writeEvent,
};
