// Compile one flat PNG per choice attribute cell: icon on top, level label below.
// Usage: node build/compile.mjs [--design CHD] [--block 1] [--q 1]
import { existsSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { GlobalFonts, createCanvas, loadImage } from '@napi-rs/canvas';
import sharp from 'sharp';
import { ACTIVE_VERSIONS, ATTRIBUTES, groupByBlock, imagePath, parseCsv } from '../shared.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = path.join(ROOT, 'survey_formatter', 'dist');

// Look parameters (px)
const WIDTH = 480;
const PAD = 14;
const ICON_TO_LABEL = 0.9; // icon box width = this x the longest label width (all designs)
const ICON_HEIGHT_SCALE = 0.7;
const GAP = 10;
const FONT_SIZE = 36;
const LINE_HEIGHT = 44;
const LABEL_LINES = 2;
const PALETTE_COLOURS = 64;
// Attributes whose icons have blank margins that are cropped before scaling
const TRIM = new Set(['HOSP', 'EDUCATION']);

const FONT_CANDIDATES = [
  'C:/Windows/Fonts/arial.ttf',
  '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];
const fontPath = FONT_CANDIDATES.find(existsSync);
if (!fontPath) throw new Error(`No font found; tried ${FONT_CANDIDATES.join(', ')}`);
GlobalFonts.registerFromPath(fontPath, 'SurveyFont');

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => (
  a.startsWith('--') ? [...acc, [a.slice(2), all[i + 1]]] : acc
), []));

async function loadDesign(version) {
  const { rows } = parseCsv(await readFile(path.join(ROOT, 'Surveys', version.file), 'utf8'));
  const order = JSON.parse(await readFile(path.join(ROOT, 'def', version.attrs), 'utf8')).map(a => a.name_short);
  return { rows, order };
}

// Icon size is fixed from the longest label across every design, so icons stay the same size everywhere
async function longestLabelWidth() {
  const ctx = createCanvas(WIDTH, 100).getContext('2d');
  ctx.font = `${FONT_SIZE}px SurveyFont`;
  let longest = { width: 0, text: '' };
  for (const version of ACTIVE_VERSIONS) {
    const { rows, order } = await loadDesign(version);
    for (const row of rows) for (const key of order) {
      const width = ctx.measureText(row[key]).width;
      if (width > longest.width) longest = { width, text: row[key] };
    }
  }
  return longest;
}

const longest = await longestLabelWidth();
const ICON_BOX = Math.round(ICON_TO_LABEL * longest.width);
// Icon frame is 4:3 (width:height) with height = 70% of the square box; icons are fitted inside, blank on the sides
const ICON_H = Math.round(ICON_HEIGHT_SCALE * ICON_BOX);
const ICON_W = Math.round(ICON_H * 4 / 3);
const HEIGHT = PAD + ICON_H + GAP + LINE_HEIGHT * LABEL_LINES + PAD;

function wrap(ctx, text, maxWidth) {
  const lines = [];
  let line = '';
  for (const word of text.split(/\s+/)) {
    const next = line ? `${line} ${word}` : word;
    if (line && ctx.measureText(next).width > maxWidth) { lines.push(line); line = word; }
    else line = next;
  }
  return [...lines, line];
}

// Bounding box of the non-transparent pixels of an image
function contentBox(icon) {
  const canvas = createCanvas(icon.width, icon.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(icon, 0, 0);
  const { data } = ctx.getImageData(0, 0, icon.width, icon.height);
  let x0 = icon.width, y0 = icon.height, x1 = -1, y1 = -1;
  for (let y = 0; y < icon.height; y++) for (let x = 0; x < icon.width; x++) {
    if (data[(y * icon.width + x) * 4 + 3] > 10) {
      if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
    }
  }
  return x1 < 0 ? { x: 0, y: 0, w: icon.width, h: icon.height } : { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

async function drawCell(label, iconFile, trim) {
  const canvas = createCanvas(WIDTH, HEIGHT);
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);

  if (iconFile) {
    const icon = await loadImage(iconFile);
    const src = trim ? contentBox(icon) : { x: 0, y: 0, w: icon.width, h: icon.height };
    const scale = Math.min(ICON_W / src.w, ICON_H / src.h);
    const w = src.w * scale, h = src.h * scale;
    ctx.drawImage(icon, src.x, src.y, src.w, src.h, (WIDTH - w) / 2, PAD + (ICON_H - h) / 2, w, h);
  }

  let size = FONT_SIZE, lines;
  do {
    ctx.font = `${size}px SurveyFont`;
    lines = wrap(ctx, label, WIDTH - 2 * PAD);
    size -= 2;
  } while (lines.length > LABEL_LINES && size > 16);

  ctx.fillStyle = '#222';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  const top = PAD + ICON_H + GAP;
  const offset = (LINE_HEIGHT * LABEL_LINES - LINE_HEIGHT * lines.length) / 2;
  lines.forEach((l, i) => ctx.fillText(l, WIDTH / 2, top + offset + LINE_HEIGHT * (i + 0.5)));

  return sharp(canvas.toBuffer('image/png')).png({ palette: true, colours: PALETTE_COLOURS }).toBuffer();
}

const manifest = {};
let count = 0, bytes = 0;

for (const version of ACTIVE_VERSIONS) {
  if (args.design && args.design !== version.id) continue;
  const { rows, order } = await loadDesign(version);
  const blocks = groupByBlock(rows);

  for (const [block, sets] of Object.entries(blocks)) {
    if (args.block && args.block !== block) continue;
    for (const [i, set] of sets.entries()) {
      const n = i + 1;
      if (args.q && Number(args.q) !== n) continue;
      for (const alt of [1, 2]) {
        for (const key of order) {
          const row = set[`alt${alt}`];
          const code = row[`${key}_C`];
          const iconFile = code ? path.join(ROOT, 'Icons', `Attr_${ATTRIBUTES[key].icon}_${code}.png`) : null;
          if (iconFile && !existsSync(iconFile)) throw new Error(`Missing icon ${iconFile}`);
          const rel = imagePath(version.id, block, n, alt, key);
          const png = await drawCell(row[key], iconFile, TRIM.has(key));
          await mkdir(path.dirname(path.join(OUT, rel)), { recursive: true });
          await writeFile(path.join(OUT, rel), png);
          manifest[rel] = { label: row[key], set: row.Set, icon: iconFile && path.basename(iconFile) };
          count++; bytes += png.length;
        }
      }
    }
  }
}

await mkdir(OUT, { recursive: true });
await writeFile(path.join(OUT, 'manifest.json'), JSON.stringify(manifest, null, 1));
console.log(`icon frame ${ICON_W}x${ICON_H}px (4:3), from box ${ICON_BOX}px (0.9 x "${longest.text}" at ${Math.round(longest.width)}px)`);
console.log(`${count} images, ${(bytes / 1024).toFixed(0)} KB total, ${(bytes / Math.max(count, 1) / 1024).toFixed(1)} KB avg, ${WIDTH}x${HEIGHT}`);
