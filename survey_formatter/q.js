// Renders one choice question from the URL: q.html?design=CHD&block=3&q=7
// Data comes from the same site (../Surveys, ../def, ../Icons), so editing those files on GitHub changes the question.
import { ATTRIBUTES, VERSIONS, groupByBlock, parseCsv } from './shared.js';

const root = document.getElementById('question');

function h(tag, props = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
}

async function fetchOk(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status} ${res.statusText}`);
  return res;
}

// Lets a parent page that listens for it resize the iframe; ignored otherwise
function reportHeight() {
  parent.postMessage({ type: 'dce-height', height: document.body.offsetHeight }, '*');
}

function cell(key, row) {
  const code = row[`${key}_C`];
  return h('td', {},
    code ? h('img', { src: `../Icons/Attr_${ATTRIBUTES[key].icon}_${code}.png`, alt: '' }) : '',
    h('div', {}, row[key]));
}

async function render() {
  const params = new URLSearchParams(location.search);
  const version = VERSIONS.find(v => v.id === params.get('design'));
  const block = params.get('block');
  const n = Number(params.get('q'));
  if (!version) throw new Error(`Unknown design "${params.get('design')}"`);

  const [csv, def] = await Promise.all([fetchOk(`../Surveys/${version.file}`), fetchOk(`../def/${version.attrs}`)]);
  const order = (await def.json()).map(a => a.name_short);
  const set = groupByBlock(parseCsv(await csv.text()).rows)[block]?.[n - 1];
  if (!set) throw new Error(`No question ${n} in block ${block} of ${version.id}`);

  root.replaceChildren(
    h('h4', {}, `Question: ${n}`),
    h('table', {},
      h('thead', {}, h('tr', {}, h('th', {}, 'Attribute'), h('th', {}, 'Version 1'), h('th', {}, 'Version 2'))),
      h('tbody', {}, ...order.map(key => h('tr', {},
        h('td', {}, ATTRIBUTES[key].title),
        cell(key, set.alt1),
        cell(key, set.alt2))))),
    h('p', {}, 'Which version would you choose?'));
}

render()
  .catch(err => root.replaceChildren(h('p', { className: 'error', role: 'alert' }, `Could not load question: ${err.message}`)))
  .finally(() => {
    reportHeight();
    addEventListener('resize', reportHeight);
    addEventListener('load', reportHeight);
  });
