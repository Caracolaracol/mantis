import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const assets = [
  ['../../docs/images/library.png', 'images/library.png'],
  ['../../docs/images/library-es.png', 'images/library-es.png'],
  ['../../Resources/Brand/mantis-head.svg', 'images/mantis.svg'],
];
await mkdir(new URL('public/images/', root), { recursive: true });
for (const [source, target] of assets) {
  await copyFile(new URL(source, import.meta.url), new URL(`public/${target}`, root));
}
const symbol = await readFile(new URL('../../Resources/Brand/mantis-head-symbol.svg', import.meta.url), 'utf8');
await writeFile(new URL('public/images/mantis-mark.svg', root), symbol.replace('stroke="#000"', 'stroke="#e8cfd4"').replace('fill="#000" d="M21', 'fill="#e8cfd4" d="M21'));
