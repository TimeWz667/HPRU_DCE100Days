// DOM-free helpers shared by the browser app (app.js) and the Node image compiler (build/compile.mjs)

export const ICON_BASE = 'https://raw.githubusercontent.com/TimeWz667/HPRU_DCE100Days/refs/heads/main/Icons/';

// id: output folder name; attrs: attribute definition file whose order sets the table row order
// hold: true => not compiled and not offered in the app for now
export const VERSIONS = [
  { id: 'CHD', label: 'CHD pilot', file: 'Survey_CHD_pilot.csv', attrs: 'attributes_chd.json' },
  { id: 'CHD_nocross', label: 'CHD pilot (no cross)', file: 'Survey_CHD_pilot.csv_nocross.csv', attrs: 'attributes_chd.json', hold: true },
  { id: 'OLD', label: 'OLD pilot', file: 'Survey_OLD_pilot.csv', attrs: 'attributes_old.json' },
  { id: 'OLD_nocross', label: 'OLD pilot (no cross)', file: 'Survey_OLD_pilot.csv_nocross.csv', attrs: 'attributes_old.json', hold: true },
];

export const ACTIVE_VERSIONS = VERSIONS.filter(v => !v.hold);

// icon: name used in Icons/Attr_<icon>_<code>.png
export const ATTRIBUTES = {
  PHSM: { title: 'Measures', icon: 'PHSM' },
  DURATION: { title: 'Duration', icon: 'Duration' },
  VACCINE: { title: 'Vaccine', icon: 'Vaccine' },
  INFECTION: { title: 'Infection', icon: 'Infection' },
  HOSP: { title: 'Hospital admissions', icon: 'Hosp' },
  DEATH: { title: 'Death', icon: 'Death' },
  FINANCES: { title: 'Finances', icon: 'Finances' },
  EDUCATION: { title: 'Education', icon: 'Education' },
};

export function parseCsv(text) {
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

// { block: [ {alt1: row, alt2: row}, ... ] } with sets ordered numerically; question n = index + 1
export function groupByBlock(rows) {
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

// Positional path of a compiled attribute image, relative to the Pages root
export function imagePath(id, block, n, alt, key) {
  return `${id}/b${block}/q${String(n).padStart(2, '0')}/a${alt}_${key}.png`;
}
