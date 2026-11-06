import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const pages = ['index.html', 'documentacion/index.html', 'licencia/index.html'];

test('all pages have Spanish language, metadata, navigation and one main heading', async () => {
  for (const file of pages) {
    const html = await readFile(path.join(root, file), 'utf8');
    assert.match(html, /<html lang="es"/);
    assert.match(html, /name="description"/);
    assert.match(html, /rel="canonical"/);
    assert.match(html, /id="contenido"/);
    assert.equal((html.match(/<h1(?:\s|>)/g) || []).length, 1);
    assert.match(html, /https:\/\/agustinrojasm\.vercel\.app/);
    assert.match(html, /\/mantis\/images\/caracol\.png/);
    assert.match(html, /id="grain-toggle"/);
  }
});

test('local links, fragment targets and assets resolve under GitHub Pages base', async () => {
  for (const file of pages) {
    const html = await readFile(path.join(root, file), 'utf8');
    const current = new URL(file.replace('index.html', ''), 'https://caracolaracol.github.io/mantis/');
    for (const match of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
      const url = new URL(match[1], current);
      if (url.origin !== current.origin) continue;
      assert.ok(url.pathname.startsWith('/mantis/'), `${file}: missing base in ${url.pathname}`);
      const relative = decodeURIComponent(url.pathname.slice('/mantis/'.length));
      const destination = path.join(root, relative.endsWith('/') || !relative ? `${relative}index.html` : relative);
      await access(destination);
      if (url.hash && destination.endsWith('.html')) {
        const target = await readFile(destination, 'utf8');
        assert.ok(target.includes(`id="${decodeURIComponent(url.hash.slice(1))}"`), `Missing target ${url.href}`);
      }
    }
  }
});

test('MIT license page contains complete repository license and upstream credit', async () => {
  const license = await readFile(new URL('../../LICENSE', import.meta.url), 'utf8');
  const html = await readFile(path.join(root, 'licencia/index.html'), 'utf8');
  assert.match(license, /MIT License/);
  for (const phrase of ['Copyright (c) 2026 Agustin Rojas', 'Permission is hereby granted', 'THE SOFTWARE IS PROVIDED']) assert.ok(html.includes(phrase));
  assert.match(html, /https:\/\/github\.com\/handy-computer\/transcribe\.cpp/);
});

test('download links and privacy/signing limitations are explicit', async () => {
  const home = await readFile(path.join(root, 'index.html'), 'utf8');
  const docs = await readFile(path.join(root, 'documentacion/index.html'), 'utf8');
  assert.match(home, /releases\/download\/v0\.2\.2\/Mantis-0\.2\.2\.dmg/);
  assert.match(home, /sin notarización/);
  for (const text of ['ScreenCapture', 'local.agus.MeetingRecorder', 'FileVault', 'Gatekeeper', 'SketchyBar']) assert.ok(docs.includes(text));
});

test('grain is decorative, CSS animated, and respects reduced motion', async () => {
  const css = await readFile(new URL('../src/styles/global.css', import.meta.url), 'utf8');
  const html = await readFile(path.join(root, 'index.html'), 'utf8');
  assert.match(html, /class="grain" aria-hidden="true"/);
  assert.match(css, /steps\(1, end\)/);
  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(css, /animation: none/);
  assert.match(css, /pointer-events: none/);
  assert.match(css, /#12231d/);
  assert.match(css, /#e8cfd4/);
});
