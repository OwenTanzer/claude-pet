'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  MAJOR_PHASE_HALF_WINDOW,
  PHASES,
  classifyPhase,
  phaseAt,
  selectPhaseAssets,
} = require('./lunar-phase');

test('classifies all eight phases and wraps around new moon', () => {
  const epsilon = 0.001;
  assert.equal(classifyPhase(0), 'new');
  assert.equal(classifyPhase(1 - epsilon), 'new');
  assert.equal(classifyPhase(MAJOR_PHASE_HALF_WINDOW + epsilon), 'waxing-crescent');
  assert.equal(classifyPhase(0.25), 'first-quarter');
  assert.equal(classifyPhase(0.25 + MAJOR_PHASE_HALF_WINDOW + epsilon), 'waxing-gibbous');
  assert.equal(classifyPhase(0.5), 'full');
  assert.equal(classifyPhase(0.5 + MAJOR_PHASE_HALF_WINDOW + epsilon), 'waning-gibbous');
  assert.equal(classifyPhase(0.75), 'last-quarter');
  assert.equal(classifyPhase(0.75 + MAJOR_PHASE_HALF_WINDOW + epsilon), 'waning-crescent');
});

test('reference epoch is a new moon', () => {
  const result = phaseAt('2000-01-06T18:15:00Z');
  assert.equal(result.phase, 'new');
  assert.ok(result.lunarAgeDays < 1e-9);
});

test('full moon lingers into the day after the 2026-07-29 astronomical full moon', () => {
  const result = phaseAt('2026-07-30T19:00:00Z');
  assert.equal(result.phase, 'full');
  assert.ok(result.cycleFraction > 0.5);
  assert.ok(result.illuminationFraction > 0.97);
});

test('selects one coherent expression set and writes metadata atomically', (t) => {
  const testRoot = path.join(__dirname, '.tmp');
  fs.mkdirSync(testRoot, { recursive: true });
  const temporary = fs.mkdtempSync(path.join(testRoot, 'claude-moon-test-'));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const pluginRoot = path.join(temporary, 'plugin');
  const dataRoot = path.join(temporary, 'data');

  for (const phase of PHASES) {
    const phaseDir = path.join(pluginRoot, 'phases', phase);
    fs.mkdirSync(phaseDir, { recursive: true });
    for (const frame of ['idle', 'blink', 'happy']) {
      fs.writeFileSync(path.join(phaseDir, `claude-${frame}.png`), `${phase}:${frame}`);
    }
  }

  const result = selectPhaseAssets({ pluginRoot, dataRoot, at: '2026-07-30T19:00:00Z' });
  assert.equal(result.phase, 'full');
  assert.equal(fs.readFileSync(path.join(dataRoot, 'claude-idle.png'), 'utf8'), 'full:idle');
  assert.equal(JSON.parse(fs.readFileSync(path.join(dataRoot, 'lunar-phase.json'), 'utf8')).phase, 'full');
  assert.deepEqual(fs.readdirSync(dataRoot).filter((name) => name.endsWith('.tmp')), []);
});
