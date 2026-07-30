# Real lunar phases

The Moon pet follows the real lunar cycle without making any network requests. At every Claude `SessionStart`, `pet/lunar-phase.js` calculates the lunar age, selects one of eight illustrated phase sets, and atomically copies its idle, blink, and happy frames into `~/.claude/pet-data`.

The resident watches `lunar-phase.json`, which is deliberately written only after all three images are in place. A metadata timestamp change triggers a safe in-process reload; the old bitmaps are disposed after the new set has loaded. The pet therefore changes phase without a restart and cannot show a blink from one phase with a smile from another.

## Visual convention

The sprites use the Northern Hemisphere orientation:

- waxing illumination grows from the right;
- waning illumination remains on the left;
- New, First Quarter, Full, and Last Quarter each remain visible for about 2.7 days;
- the Crescent and Gibbous phases between them each remain visible for about 4.7 days.

That display timing is intentionally experiential rather than pretending the four turning points last for literal days. Astronomically they are instants, but a desktop character needs enough time in each iconic state for a person to actually encounter it.

The face is part of the lunar disk. Any facial area in shadow is redrawn in soft blue-white with muted lavender cheeks, while the pupils stay near-black. Lit and unlit regions both retain subtle crater texture.

## Calculation

The selector uses a deterministic mean-month model:

- reference new Moon: `2000-01-06T18:15:00Z`;
- mean synodic month: `29.5305888531` days;
- cycle fraction: elapsed UTC days modulo the mean synodic month;
- illumination estimate: `(1 - cos(2 * pi * cycleFraction)) / 2`.

The reference epoch comes from [NASA GSFC's phase table](https://eclipse.gsfc.nasa.gov/TYPE/moonphase.html), the phase order and visual meaning follow [NASA's Moon Phases guide](https://science.nasa.gov/moon/moon-phases/), and official date comparisons use the [U.S. Naval Observatory Moon phase tables](https://aa.usno.navy.mil/data/MoonPhases).

This is an ambient reminder, not an ephemeris. The real synodic month varies, and the USNO notes individual cycles can differ from the mean by several hours. The display can therefore cross a phase margin a few hours earlier or later than a high-precision astronomical calculation. Runtime privacy remains simple: no location, session content, or network access is used.

## Development

Regenerate all 24 phase/expression assets and the three top-level fallback frames:

```powershell
pwsh -NoProfile -File tools/claude-draw.ps1
```

Build the eight-phase visual review sheet:

```powershell
pwsh -NoProfile -File tools/moon-phase-preview.ps1
```

Run the selector tests:

```powershell
node --test --test-isolation=none pet/lunar-phase.test.js
```

For a deterministic manual check, set `CLAUDE_MOON_AT` to an ISO UTC timestamp before invoking the selector. `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PET_DATA` can redirect its source and destination roots during tests.
