const SURVEY_DIR = '../Surveys/';
const ICON_BASE = 'https://raw.githubusercontent.com/TimeWz667/HPRU_DCE100Days/refs/heads/main/Icons/';

const DEF_DIR = '../def/';

// attrs: attribute definition file whose order sets the table row order
const VERSIONS = [
  { label: 'CHD pilot', file: 'Survey_CHD_pilot.csv', attrs: 'attributes_chd.json' },
  { label: 'CHD pilot (no cross)', file: 'Survey_CHD_pilot.csv_nocross.csv', attrs: 'attributes_chd.json' },
  { label: 'OLD pilot', file: 'Survey_OLD_pilot.csv', attrs: 'attributes_old.json' },
  { label: 'OLD pilot (no cross)', file: 'Survey_OLD_pilot.csv_nocross.csv', attrs: 'attributes_old.json' },
];

const ATTRIBUTES = {
  PHSM: { title: 'Measures', icon: 'PHSM' },
  DURATION: { title: 'Duration', icon: 'Duration' },
  VACCINE: { title: 'Vaccine', icon: 'Vaccine' },
  INFECTION: { title: 'Infection', icon: 'Infection' },
  HOSP: { title: 'Hospitalisation', icon: 'Hosp' },
  DEATH: { title: 'Death', icon: 'Death' },
  FINANCES: { title: 'Finances', icon: 'Finances' },
  EDUCATION: { title: 'Education', icon: 'Education' },
};

const CELL = 'border: 1px solid rgb(204, 204, 204); padding: 8px;';

const el = id => document.getElementById(id);
const state = { order: [], blocks: {}, block: null, copied: new Set() };

function parseCsv(text) {
  const rows = [];
  let row = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.some(v => v !== '')) rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const [header, ...body] = rows;
  return { header, rows: body.map(r => Object.fromEntries(header.map((h, i) => [h, (r[i] ?? '').trim()]))) };
}

const setNumber = s => parseInt(s.replace(/\D/g, ''), 10);

// { block: [ {alt1: row, alt2: row}, ... ] } with sets ordered numerically
function groupByBlock(rows) {
  const blocks = {};
  for (const r of rows) {
    const sets = (blocks[r.Block] ??= {});
    (sets[r.Set] ??= {})[r.Alt] = r;
  }
  return Object.fromEntries(Object.entries(blocks).map(([b, sets]) => [
    b,
    Object.keys(sets).sort((a, c) => setNumber(a) - setNumber(c)).map(s => sets[s]),
  ]));
}

function renderCell(key, row) {
  const code = row[`${key}_C`];
  const img = code === undefined || code === ''
    ? ''
    : `<img src="${ICON_BASE}Attr_${ATTRIBUTES[key].icon}_${code}.png" style="width: 35%;">\n\t\t\t\t`;
  return `\t\t\t\t<td style="${CELL}">
\t\t\t\t<div>${img}<div>${row[key]}</div>
\t\t\t\t</div>
\t\t\t\t</td>`;
}

function renderQuestion(n, set) {
  const rows = state.order.map(key => `\t\t\t<tr>
\t\t\t\t<td style="${CELL}">${ATTRIBUTES[key].title}</td>
${renderCell(key, set.alt1)}
${renderCell(key, set.alt2)}
\t\t\t</tr>`).join('\n');
  return `<div>
<h4>Question: ${n}</h4>

<table style="width: 100%; border-collapse: collapse; border: 1px solid rgb(204, 204, 204); font-family: Arial, sans-serif;">
\t<colgroup>
\t\t<col style="width: 20%;">
\t\t<col style="width: 40%;">
\t\t<col style="width: 40%;">
\t</colgroup>
\t<thead>
\t\t<tr style="background-color: rgb(242, 242, 242);">
\t\t\t<th style="${CELL} text-align: left;">Attribute</th>
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

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
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
      const html = renderQuestion(n, set);
      await copyText(html);
      el('preview').innerHTML = html;
      el('preview-title').textContent = `Preview: Block ${state.block}, Question ${n}`;
      state.copied.add(copiedKey(state.block, n));
      btn.classList.add('copied');
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
select.replaceChildren(...VERSIONS.map(v => new Option(v.label, v.file)));
select.onchange = () => loadVersion(select.value);
el('reset').onclick = () => { state.copied.clear(); renderQuestions(); };
loadVersion(select.value);
