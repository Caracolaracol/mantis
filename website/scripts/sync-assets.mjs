import { copyFile, mkdir } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const assets = [
  ['../../docs/images/library.png', 'images/library.png'],
  ['../../Resources/Brand/mantis-head.svg', 'images/mantis.svg'],
];
await mkdir(new URL('public/images/', root), { recursive: true });
for (const [source, target] of assets) {
  await copyFile(new URL(source, import.meta.url), new URL(`public/${target}`, root));
}
