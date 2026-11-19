// List the Qualtrics questions whose pasted HTML is out of date.
// Only a change to a cell's alt text (or a cell added/removed) needs re-pasting; the image files themselves are served by URL.
//
// Usage (from survey_formatter/):
//   npm run changed                  compare the current manifest with the last pasted commit
//   npm run changed -- <commit>      compare with a given commit
//   npm run changed -- --mark        record the current HEAD as "last pasted" (after re-pasting)
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const MANIFEST = 'survey_formatter/dist/manifest.json';

// -> { repaste: Map<question, string[]>, imagesOnly: Set<question> }
export function compare(oldManifest, newManifest) {
  const repaste = new Map();
  const imagesOnly = new Set();
  const question = file => {
    const [design, block, q] = file.split('/');
    return `${design} block ${block.slice(1)} Q${Number(q.slice(1))}`;
  };
  // Manifests from before alt text was recorded only have the label, so compare labels unless both sides have alt text
  const field = (before, after) => (before.alt !== undefined && after.alt !== undefined ? 'alt' : 'label');
  const note = (file, msg) => {
    const q = question(file);
    if (!repaste.has(q)) repaste.set(q, []);
    repaste.get(q).push(`${path.basename(file, '.png')}: ${msg}`);
  };

  for (const file of new Set([...Object.keys(oldManifest), ...Object.keys(newManifest)])) {
    const before = oldManifest[file], after = newManifest[file];
    if (!before) note(file, 'new cell');
    else if (!after) note(file, 'removed');
    else if (before[field(before, after)] !== after[field(before, after)]) {
      const f = field(before, after);
      note(file, `"${before[f]}" -> "${after[f]}"`);
    }
    else if (before.icon !== after.icon) imagesOnly.add(question(file));
  }
  for (const q of repaste.keys()) imagesOnly.delete(q);
  return { repaste, imagesOnly };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const git = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  const root = git('rev-parse', '--show-toplevel');
  const markFile = path.join(root, 'survey_formatter', 'last_pasted.txt');
  const arg = process.argv[2];

  if (arg === '--mark') {
    writeFileSync(markFile, `${git('rev-parse', 'HEAD')}\n`);
    console.log(`Recorded ${git('rev-parse', '--short', 'HEAD')} as the last pasted commit. Commit survey_formatter/last_pasted.txt to share it.`);
    process.exit(0);
  }

  const base = arg ?? (existsSync(markFile) ? readFileSync(markFile, 'utf8').trim() : null);
  if (!base) {
    console.error('No commit to compare with. Pass one (npm run changed -- <commit>) or record it with: npm run changed -- --mark');
    process.exit(1);
  }

  let oldManifest;
  try { oldManifest = JSON.parse(git('show', `${base}:${MANIFEST}`)); }
  catch { console.error(`Could not read ${MANIFEST} at ${base}.`); process.exit(1); }
  const newManifest = JSON.parse(readFileSync(path.join(root, MANIFEST), 'utf8'));
  if (!Object.values(oldManifest).some(e => 'alt' in e)) console.log('Note: that commit predates recorded alt text, so labels were compared instead.\n');

  const { repaste, imagesOnly } = compare(oldManifest, newManifest);
  if (!repaste.size) console.log(`No question needs re-pasting since ${base.slice(0, 7)}.`);
  else {
    console.log(`Re-paste ${repaste.size} question(s) since ${base.slice(0, 7)}:\n`);
    for (const [q, notes] of repaste) console.log(`  ${q}\n${notes.map(n => `      ${n}`).join('\n')}`);
  }
  if (imagesOnly.size) console.log(`\n${imagesOnly.size} question(s) have updated images only; no re-paste needed (publish with npm run release).`);
  if (repaste.size) console.log('\nAfter re-pasting, run: npm run changed -- --mark');
}
