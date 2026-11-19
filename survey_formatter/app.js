import { ACTIVE_VERSIONS, ATTRIBUTES, ICON_BASE, VERSIONS, altText, groupByBlock, imagePath, parseCsv } from './shared.js';

const SURVEY_DIR = '../Surveys/';
const DEF_DIR = '../def/';

// Where compiled images are served; override locally with ?base=/survey_formatter/dist/
const IMAGE_BASE = new URLSearchParams(location.search).get('base')
  ?? 'https://cdn.jsdelivr.net/gh/TimeWz667/HPRU_DCE100Days@release/survey_formatter/dist/';
// Optional: Qualtrics pipes the respondent's block from embedded data "block" into the image URL
const BLOCK_PIPE = '${e://Field/block}';

// iframe version: q.html must be served from GitHub Pages (jsDelivr does not serve HTML pages). Override locally with ?pages=/
const PAGES_BASE = new URLSearchParams(location.search).get('pages') ?? 'https://timewz667.github.io/HPRU_DCE100Days/';
// Height measured from q.html at 320-700 px wide: 150% of the width fits phones, capped for desktop
const IFRAME_STYLE = 'width: 100%; height: min(150vw, 880px); border: 0;';

const CELL = 'border: 1px solid rgb(204, 204, 204); padding: 8px;';
// First column: font scales with the viewport (inline styles cannot use media queries) and long words wrap
const CELL_FIRST = 'border: 1px solid rgb(204, 204, 204); padding: 8px 4px; font-size: clamp(11px, 3.4vw, 16px); overflow-wrap: break-word; hyphens: auto;';

const el = id => document.getElementById(id);
const state = { order: [], blocks: {}, block: null, copied: new Set() };
const escapeAttr = s => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const currentVersion = () => VERSIONS.find(v => v.file === el('version').value);

function renderLegacyCell(key, row) {
  const code = row[`${key}_C`];
  const img = code === undefined || code === ''
    ? ''
    : `<img src="${ICON_BASE}Attr_${ATTRIBUTES[key].icon}_${code}.png" style="width: 35%;">\n\t\t\t\t`;
  return `\t\t\t\t<td style="${CELL}">
\t\t\t\t<div>${img}<div>${row[key]}</div>
\t\t\t\t</div>
\t\t\t\t</td>`;
}

// alt text carries the same label that is drawn into the image
function renderImageCell(key, n, altNo, block, row) {
  const src = IMAGE_BASE + imagePath(currentVersion().id, block, n, altNo, key);
  const alt = escapeAttr(altText(key, row[key]));
  return `				<td style="${CELL}">
				<img src="${src}" alt="${alt}" style="width: 95%; display: block; margin: 0 auto;">
				</td>`;
}

// block: the value written into the image URL (BLOCK_PIPE for Qualtrics, a number for previews)
function renderQuestion(n, set, { block, legacy = false }) {
  const rows = state.order.map(key => `\t\t\t<tr>
\t\t\t\t<td style="${CELL_FIRST}">${ATTRIBUTES[key].title}</td>
${legacy ? renderLegacyCell(key, set.alt1) : renderImageCell(key, n, 1, block, set.alt1)}
${legacy ? renderLegacyCell(key, set.alt2) : renderImageCell(key, n, 2, block, set.alt2)}
\t\t\t</tr>`).join('\n');
  return `<div>
<h4>Question: ${n}</h4>

<table style="width: 100%; border-collapse: collapse; border: 1px solid rgb(204, 204, 204); font-family: Arial, sans-serif;">
\t<colgroup>
\t\t<col style="width: 26%;">
\t\t<col style="width: 37%;">
\t\t<col style="width: 37%;">
\t</colgroup>
\t<thead>
\t\t<tr style="background-color: rgb(242, 242, 242);">
\t\t\t<th style="${CELL_FIRST} text-align: left;">Attribute</th>
\t\t\t<th style="${CELL} text-align: left;">Version 1</th>
\t\t\t<th style="${CELL} text-align: left;">Version 2</th>
\t\t</tr>
\t</thead>
\t<tbody>
${rows}
\t</tbody>
</table>
Which version would you choose?
</div>`;
}

// base: everything before q.html in the URL
function iframeSnippet(n, block, base) {
  const src = `${base}q.html?design=${currentVersion().id}&amp;block=${block}&amp;q=${n}`;
  return `<iframe src="${src}" title="Choice question ${n}" style="${IFRAME_STYLE}"></iframe>`;
}

// Returns true if the text reached the clipboard
async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    return ok;
  }
}

const copiedKey = (block, n) => `${el('version').value}|${block}|${n}`;

function showMessage(text) {
  el('message').textContent = text;
  el('message').hidden = !text;
}

function renderTabs() {
  el('tabs').replaceChildren(...Object.keys(state.blocks).map(b => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.setAttribute('role', 'tab');
    btn.setAttribute('aria-selected', String(b === state.block));
    btn.textContent = `Block ${b}`;
    btn.onclick = () => { state.block = b; renderTabs(); renderQuestions(); };
    return btn;
  }));
}

function renderQuestions() {
  const sets = state.blocks[state.block] ?? [];
  el('questions').replaceChildren(...sets.map((set, i) => {
    const n = i + 1;
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = `Q${n}`;
    btn.classList.toggle('copied', state.copied.has(copiedKey(state.block, n)));
    btn.onclick = async () => {
      try {
        const legacy = el('legacy')?.checked ?? false;
        // Copied HTML carries the selected block's number; the pipe is only for surveys with embedded data "block"
        const copyBlock = el('pipe')?.checked ? BLOCK_PIPE : state.block;
        const useIframe = el('iframe')?.checked ?? false;
        const html = useIframe
          ? iframeSnippet(n, copyBlock, `${PAGES_BASE}survey_formatter/`)
          : renderQuestion(n, set, { block: copyBlock, legacy });
        const ok = await copyText(html);
        // The iframe preview loads the local q.html so it shows the current files, not what is on GitHub Pages
        el('preview').innerHTML = useIframe
          ? iframeSnippet(n, state.block, '')
          : renderQuestion(n, set, { block: state.block, legacy });
        el('preview-title').textContent = `Preview: Block ${state.block}, Question ${n}`;
        el('raw').value = html;
        el('raw').hidden = ok;
        showMessage(ok ? '' : 'The browser blocked copying. Copy the HTML from the box below instead.');
        if (ok) {
          state.copied.add(copiedKey(state.block, n));
          btn.classList.add('copied');
        }
      } catch (err) {
        console.error(err);
        showMessage(`Could not build question ${n}: ${err.message}`);
      }
    };
    return btn;
  }));
}

async function fetchOk(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status} ${res.statusText}`);
  return res;
}

async function loadVersion(file) {
  showMessage('');
  try {
    const { attrs } = VERSIONS.find(v => v.file === file);
    const [csv, def] = await Promise.all([fetchOk(SURVEY_DIR + file), fetchOk(DEF_DIR + attrs)]);
    const { rows } = parseCsv(await csv.text());
    state.order = (await def.json()).map(a => a.name_short);
    state.blocks = groupByBlock(rows);
    state.block = Object.keys(state.blocks)[0];
  } catch (err) {
    state.blocks = {};
    showMessage(`Could not load survey (${err.message}). Serve the repo root, e.g. "python -m http.server 8000", and open /survey_formatter/.`);
  }
  el('preview').replaceChildren();
  el('preview-title').textContent = 'Preview';
  renderTabs();
  renderQuestions();
}

const select = el('version');
select.replaceChildren(...ACTIVE_VERSIONS.map(v => new Option(v.label, v.file)));
select.onchange = () => loadVersion(select.value);
el('reset').onclick = () => { state.copied.clear(); renderQuestions(); };
loadVersion(select.value);
