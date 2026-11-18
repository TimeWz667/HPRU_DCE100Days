// Publish the current main to the "release" branch (what respondents see via jsDelivr) and purge changed images.
// Usage: node build/release.mjs   (or: npm run release)
import { execFileSync } from 'node:child_process';

const REPO = 'TimeWz667/HPRU_DCE100Days';
const BRANCH = 'release';
const DIST = 'survey_formatter/dist';

const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim();
const fail = msg => { console.error(`Aborted: ${msg}`); process.exit(1); };

if (git('status', '--porcelain')) fail('working tree has uncommitted changes. Commit them first.');
git('fetch', 'origin');
const head = git('rev-parse', 'HEAD');
if (head !== git('rev-parse', 'origin/main')) fail('HEAD is not the same as origin/main. Push (or pull) main first.');

let previous = null;
try { previous = git('rev-parse', `origin/${BRANCH}`); } catch { /* first release */ }
if (previous === head) { console.log(`${BRANCH} is already at ${head.slice(0, 7)}. Nothing to publish.`); process.exit(0); }

// Fast-forward only: a diverged release branch makes git refuse instead of overwriting
try { git('push', 'origin', `HEAD:refs/heads/${BRANCH}`); } catch (err) { fail(`push to ${BRANCH} was refused: ${err.message}`); }
console.log(`${BRANCH}: ${previous ? previous.slice(0, 7) : '(new)'} -> ${head.slice(0, 7)}`);

if (!previous) process.exit(0);

// jsDelivr caches branch files, so purge the images that changed
const changed = git('diff', '--name-only', '--diff-filter=MD', previous, head, '--', DIST).split('\n').filter(Boolean);
console.log(`${changed.length} changed or deleted image file(s) to purge`);
let failed = 0;
for (const file of changed) {
  try {
    const res = await fetch(`https://purge.jsdelivr.net/gh/${REPO}@${BRANCH}/${file}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
  } catch (err) {
    failed++;
    console.error(`purge failed for ${file}: ${err.message}`);
  }
}
if (failed) console.error(`${failed} purge(s) failed. Rerun, or wait for the CDN cache to expire.`);
