'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const SYNODIC_MONTH_DAYS = 29.5305888531;
const REFERENCE_NEW_MOON_UTC = '2000-01-06T18:15:00.000Z';
const REFERENCE_NEW_MOON_MS = Date.parse(REFERENCE_NEW_MOON_UTC);
const DAY_MS = 24 * 60 * 60 * 1000;

// The major phases are astronomical instants, but the pet should let us live
// with each recognizable turning point. A 1/22-cycle margin on either side is
// about 1.34 days, so New, Quarter, and Full each remain visible for ~2.7 days.
const MAJOR_PHASE_HALF_WINDOW = 1 / 22;

const PHASES = Object.freeze([
  'new',
  'waxing-crescent',
  'first-quarter',
  'waxing-gibbous',
  'full',
  'waning-gibbous',
  'last-quarter',
  'waning-crescent',
]);

function normalizeCycle(value) {
  return ((value % 1) + 1) % 1;
}

function circularDistance(a, b) {
  const direct = Math.abs(a - b);
  return Math.min(direct, 1 - direct);
}

function classifyPhase(cycleFraction) {
  const f = normalizeCycle(cycleFraction);
  if (circularDistance(f, 0) <= MAJOR_PHASE_HALF_WINDOW) return 'new';
  if (Math.abs(f - 0.25) <= MAJOR_PHASE_HALF_WINDOW) return 'first-quarter';
  if (Math.abs(f - 0.5) <= MAJOR_PHASE_HALF_WINDOW) return 'full';
  if (Math.abs(f - 0.75) <= MAJOR_PHASE_HALF_WINDOW) return 'last-quarter';
  if (f < 0.25) return 'waxing-crescent';
  if (f < 0.5) return 'waxing-gibbous';
  if (f < 0.75) return 'waning-gibbous';
  return 'waning-crescent';
}

function phaseAt(input = new Date()) {
  const date = input instanceof Date ? input : new Date(input);
  if (!Number.isFinite(date.getTime())) throw new TypeError('A valid date is required');

  const elapsedDays = (date.getTime() - REFERENCE_NEW_MOON_MS) / DAY_MS;
  const cycleFraction = normalizeCycle(elapsedDays / SYNODIC_MONTH_DAYS);
  const phase = classifyPhase(cycleFraction);

  return {
    phase,
    cycleFraction,
    lunarAgeDays: cycleFraction * SYNODIC_MONTH_DAYS,
    illuminationFraction: (1 - Math.cos(2 * Math.PI * cycleFraction)) / 2,
    waxing: cycleFraction > 0 && cycleFraction < 0.5,
    calculatedAtUtc: date.toISOString(),
    referenceNewMoonUtc: REFERENCE_NEW_MOON_UTC,
    synodicMonthDays: SYNODIC_MONTH_DAYS,
    model: 'mean-synodic-month',
  };
}

function atomicCopy(source, destination) {
  const temporary = `${destination}.${process.pid}.tmp`;
  fs.copyFileSync(source, temporary);
  fs.renameSync(temporary, destination);
}

function selectPhaseAssets({ pluginRoot, dataRoot, at = new Date() }) {
  if (!pluginRoot) throw new TypeError('pluginRoot is required');
  if (!dataRoot) throw new TypeError('dataRoot is required');

  const result = phaseAt(at);
  const sourceDir = path.join(pluginRoot, 'phases', result.phase);
  fs.mkdirSync(dataRoot, { recursive: true });

  for (const filename of ['claude-idle.png', 'claude-blink.png', 'claude-happy.png']) {
    const source = path.join(sourceDir, filename);
    if (!fs.existsSync(source)) throw new Error(`Missing lunar phase asset: ${source}`);
    atomicCopy(source, path.join(dataRoot, filename));
  }

  const metadataPath = path.join(dataRoot, 'lunar-phase.json');
  const metadataTemporary = `${metadataPath}.${process.pid}.tmp`;
  fs.writeFileSync(metadataTemporary, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
  fs.renameSync(metadataTemporary, metadataPath);
  return result;
}

function main() {
  const pluginRoot = process.env.CLAUDE_PLUGIN_ROOT || __dirname;
  const dataRoot = process.env.CLAUDE_PET_DATA || path.join(os.homedir(), '.claude', 'pet-data');
  const at = process.env.CLAUDE_MOON_AT ? new Date(process.env.CLAUDE_MOON_AT) : new Date();
  const result = selectPhaseAssets({ pluginRoot, dataRoot, at });
  process.stdout.write(`${result.phase}\n`);
}

if (require.main === module) main();

module.exports = {
  MAJOR_PHASE_HALF_WINDOW,
  PHASES,
  REFERENCE_NEW_MOON_UTC,
  SYNODIC_MONTH_DAYS,
  classifyPhase,
  phaseAt,
  selectPhaseAssets,
};
