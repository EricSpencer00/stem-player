const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

function assertRegex(re, msg) {
  if (!re.test(html)) {
    throw new Error(msg);
  }
}

function countMatches(re, text) {
  const m = text.match(re);
  return m ? m.length : 0;
}

function check(label, fn) {
  try {
    fn();
    console.log(`✔ ${label}`);
  } catch (err) {
    failures.push({ label, error: err.message || String(err) });
    console.log(`✖ ${label}: ${err.message}`);
  }
}

const failures = [];

check('Transport controls are centered', () => {
  assertRegex(/\.transport\s*\{[^}]*justify-content:\s*center[^}]*\}/m, 'transport is not centered.');
});

check('Sample buttons are rendered after stem controls', () => {
  const samplePos = html.indexOf('id="sampleRows"');
  const wavePos = html.indexOf('id="waveRow"');
  const playbarPos = html.indexOf('id="playbar"');
  const stemsPos = html.indexOf('id="stems-panel"');

  if (samplePos === -1 || wavePos === -1 || playbarPos === -1 || stemsPos === -1) {
    throw new Error('Missing required layout DOM anchors.');
  }
  if (!(samplePos > stemsPos && samplePos > playbarPos && samplePos > wavePos)) {
    throw new Error('sampleRows is not placed after player controls.');
  }
});

check('Loop snapping exists and is used by loop setter', () => {
  if (!/function\s+snapLoopStart\s*\(/.test(html)) {
    throw new Error('snapLoopStart missing.');
  }
  const setLoopMatch = html.match(/function\s+setLoop\s*\([^)]*\)\s*\{[\s\S]*?\n\}/);
  if (!setLoopMatch || !/snapLoopStart/.test(setLoopMatch[0])) {
    throw new Error('setLoop does not call snapLoopStart anymore.');
  }
});

check('Separator mode architecture exists with fast/fallback path', () => {
  assertRegex(/const\s+MODEL_PRESETS\s*=\s*\{[\s\S]*?fast:[\s\S]*?better:/m, 'MODEL_PRESETS missing both fast and better modes.');
  assertRegex(/const\s+runSeparation\s*=\s*async\s*\(mode\)\s*=>/m, 'runSeparation helper missing.');
  assertRegex(/const\s+runMode\s*=\s*requestedMode\s*===\s*['\"]better['\"]\s*&&\s*!isBetterModelReady\(\)\s*\?\s*['\"]fast['\"]/m,
    'No explicit fallback fast path from better when model unavailable.');
});

check('Model failure fallback path is present', () => {
  assertRegex(/ensureModelReady\(\s*['\"]better['\"],\s*\(p,m\)\s*=>\s*prog\(p,m\)\);/m,
    'Better mode load guard path missing.');
  assertRegex(/ML model failed to load; using fast mode/, 'Model load fallback user-facing message missing.');
  assertRegex(/Better mode failed, using fast mode:/m, 'Runtime fallback-from-better-to-fast catch branch missing.');
});

check('Error handling is normalized with getErrorMessage', () => {
  assertRegex(/function\s+getErrorMessage\s*\(/m, 'getErrorMessage helper missing.');
  assertRegex(/alert\('Unable to load sample track: '\+getErrorMessage\(e\)\)/m, 'Sample error path not using getErrorMessage.');
  assertRegex(/alert\('Error processing file: '\+getErrorMessage\(e\)\)/m, 'HandleFile error path not using getErrorMessage.');
});

check('File input and upload branch exist', () => {
  assertRegex(/<input\s+type="file"\s+id="fileInput"/m, 'fileInput missing.');
  assertRegex(/Please drop an audio file \(mp3, wav, flac, etc\.\)/m, 'Invalid file guard/alert not present.');
  assertRegex(/document\.getElementById\('center'\)\.addEventListener\('click',\(\)=>\{/m, 'center click handler missing.');
  assertRegex(/document\.getElementById\('btnPlay'\)\.click\(\);.*document\.getElementById\('fileInput'\)\.click\(\);/ms,
    'center click upload/play branch missing.');
});

check('Loop controls exist for each stem with 4 buttons each', () => {
  const stems = ['drums', 'bass', 'vocals', 'melody'];

  stems.forEach((stem) => {
    const marker = `<div class="loop-row" data-stem="${stem}">`;
    const start = html.indexOf(marker);
    if (start === -1) {
      throw new Error(`loop-row for ${stem} missing.`);
    }
    const end = html.indexOf('</div>', start);
    if (end === -1) {
      throw new Error(`loop-row for ${stem} missing closing tag.`);
    }
    const block = html.slice(start, end + 6);
    const count = countMatches(/data-loop="[0-3]"/g, block);
    if (count !== 4) {
      throw new Error(`loop-row for ${stem} should have 4 buttons, found ${count}.`);
    }
  });
});

check('Transport controls exist and are guarded by readiness state', () => {
  assertRegex(/document\.getElementById\('btnPlay'\)\.addEventListener\('click',\(\)=>\{[\s\S]*?if\(!state\.ready\)return;/m, 'Play button guard missing.');
  assertRegex(/document\.getElementById\('btnStop'\)\.addEventListener\('click',\(\)=>\{[\s\S]*?if\(!state\.ready\)return;/m, 'Stop button guard missing.');
  assertRegex(/document\.getElementById\('btnRestart'\)\.addEventListener\('click',\(\)=>\{[\s\S]*?if\(!state\.ready\)return;/m, 'Restart button guard missing.');
  assertRegex(/document\.getElementById\('timeline'\)\.addEventListener\('keydown',/m, 'Timeline keyboard controls missing.');
});

check('Sample tracks map to existing local files', () => {
  const matches = [...html.matchAll(/url:\'\.\/samples\/([^']+\.mp3)\'/g)];
  if (!matches.length) {
    throw new Error('No sample URLs found in SAMPLE_TRACKS.');
  }

  const expected = ['stem-sample-1.mp3', 'stem-sample-2.mp3', 'stem-sample-3.mp3'];
  const actual = new Set(matches.map((m) => m[1]));
  for (const name of expected) {
    if (!actual.has(name)) {
      throw new Error(`Expected sample file ${name} not found in SAMPLE_TRACKS.`);
    }
  }

  for (const fileName of expected) {
    const full = path.join(root, 'samples', fileName);
    const stat = fs.statSync(full);
    if (!stat.isFile() || stat.size <= 0) {
      throw new Error(`Sample file not usable: ${fileName}`);
    }
  }
});

check('Sample loading has failure guards', () => {
  assertRegex(/Track is not an audio file \(.*\)/m, 'Sample MIME validation missing.');
  assertRegex(/Sample file is empty\./m, 'Sample empty-file guard missing.');
  assertRegex(/new URL\(track\.url, location\.href\)/m, 'sample URL normalization missing.');
});

check('WAV export panel exists with stem and mix buttons', () => {
  const start = html.indexOf('id="export-panel"');
  if (start === -1) throw new Error('export-panel missing.');
  const stems = ['drums', 'bass', 'vocals', 'melody', 'mix'];
  for (const kind of stems) {
    if (!new RegExp(`data-export="${kind}"`).test(html)) {
      throw new Error(`export button for ${kind} missing.`);
    }
  }
});

check('WAV export helpers are defined and wired', () => {
  assertRegex(/function\s+audioBufferToWav\s*\(/m, 'audioBufferToWav encoder missing.');
  assertRegex(/function\s+renderMix\s*\(/m, 'renderMix offline mixer missing.');
  assertRegex(/async\s+function\s+exportStem\s*\(/m, 'exportStem handler missing.');
  assertRegex(/document\.querySelectorAll\('\.export-rows button'\)\.forEach/m, 'export buttons not wired.');
});

check('Keyboard shortcuts are bound', () => {
  assertRegex(/document\.addEventListener\('keydown',\s*e\s*=>/m, 'global keydown handler missing.');
  assertRegex(/document\.getElementById\('btnPlay'\)\.click\(\)/m, 'space-to-play shortcut missing.');
  assertRegex(/toggleSolo\(stem\)/m, 'number-key solo shortcut missing.');
});

check('Separator mode preference is persisted', () => {
  assertRegex(/MODE_STORAGE_KEY/m, 'mode storage key missing.');
  assertRegex(/localStorage\.setItem\(MODE_STORAGE_KEY/m, 'mode persistence write missing.');
  assertRegex(/localStorage\.getItem\(MODE_STORAGE_KEY\)/m, 'mode persistence read missing.');
});

check('Timeline loop region indicator exists', () => {
  assertRegex(/id="timelineLoop"/m, 'timeline loop band element missing.');
  assertRegex(/function\s+updateLoopBand\s*\(/m, 'updateLoopBand function missing.');
});

check('Inline app script has no syntax errors', () => {
  const scriptRe = new RegExp('<script>([\\s\\S]*?)<\\/script>');
  const m = html.match(scriptRe);
  if (!m) {
    throw new Error('Could not extract inline script block.');
  }
  try {
    new vm.Script(m[1]);
  } catch (err) {
    throw new Error(`Script parse failed: ${err.message}`);
  }
});

if (failures.length) {
  console.log('\nRegression check FAILED:');
  for (const fail of failures) {
    console.log(`- ${fail.label}: ${fail.error}`);
  }
  process.exitCode = 1;
} else {
  console.log('\nRegression check passed.');
}
