// Publish main's compiled images to the "release" branch (what respondents see via jsDelivr) and purge changed images.
// Usage: node build/release.mjs   (or: npm run release)
import { execFileSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const REPO = 'TimeWz667/HPRU_DCE100Days';
const BRANCH = 'release';
const DIST = 'survey_formatter/dist';

const git = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const fail = msg => { console.error(`Aborted: ${msg}`); process.exit(1); };

if (git('status', '--porcelain')) fail('working tree has uncommitted changes. Commit them first.');
git('fetch', 'origin');
const head = git('rev-parse', 'HEAD');
if (head !== git('rev-parse', 'origin/main')) fail('HEAD is not the same as origin/main. Push (or pull) main first.');

let previous = null;
try { previous = git('rev-parse', `origin/${BRANCH}`); } catch { /* first release */ }

// The branch holds only survey_formatter/dist (jsDelivr refuses repos over 50 MB, and main carries large model files).
// Its tree is main's dist folder at the same path, so image URLs match the paths in the manifest.
const distTree = git('rev-parse', `${head}:${DIST}`);
const index = path.join(os.tmpdir(), `release-index-${process.pid}`);
const env = { ...process.env, GIT_INDEX_FILE: index };
const gitIdx = (...args) => execFileSync('git', args, { encoding: 'utf8', env, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
gitIdx('read-tree', `--prefix=${DIST}/`, distTree);
const tree = gitIdx('write-tree');
rmSync(index, { force: true });

// A previous release that still mirrors the whole repo is replaced (force) instead of extended
const topLevel = previous ? git('ls-tree', '--name-only', previous).split(/\r?\n/) : [];
const legacy = previous !== null && topLevel.some(n => n !== 'survey_formatter');
const parent = previous && !legacy ? previous : null;
if (parent && git('rev-parse', `${parent}^{tree}`) === tree) { console.log(`${BRANCH} already has these images. Nothing to publish.`); process.exit(0); }

const commit = git('commit-tree', tree, ...(parent ? ['-p', parent] : []), '-m', `Images from ${head.slice(0, 7)}`);
// Fast-forward only, except the one-off replacement of a legacy full-repo branch
const pushArgs = legacy ? ['push', `--force-with-lease=refs/heads/${BRANCH}:${previous}`] : ['push'];
try { git(...pushArgs, 'origin', `${commit}:refs/heads/${BRANCH}`); } catch (err) { fail(`push to ${BRANCH} was refused: ${err.message}`); }
console.log(`${BRANCH}: ${previous ? previous.slice(0, 7) : '(new)'} -> ${commit.slice(0, 7)}${legacy ? ' (replaced full-repo branch with dist only)' : ''}`);

if (!previous) process.exit(0);

// jsDelivr caches branch files, so purge the images that changed
// A replaced branch may have cached 403 errors, so purge everything then
const changed = legacy
  ? git('ls-tree', '-r', '--name-only', commit).split(/\r?\n/).filter(Boolean)
  : git('diff', '--name-only', '--diff-filter=MD', previous, commit).split(/\r?\n/).filter(Boolean);
console.log(`${changed.length} image file(s) to purge`);
let failed = 0;
for (let i = 0; i < changed.length; i += 20) {
  await Promise.all(changed.slice(i, i + 20).map(async file => {
    try {
      const res = await fetch(`https://purge.jsdelivr.net/gh/${REPO}@${BRANCH}/${file}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
    } catch (err) {
      failed++;
      console.error(`purge failed for ${file}: ${err.message}`);
    }
  }));
}
if (failed) console.error(`${failed} purge(s) failed. Rerun, or wait for the CDN cache to expire.`);
