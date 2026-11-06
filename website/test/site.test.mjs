import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const pages = ['index.html', 'documentation/index.html', 'license/index.html', 'es/index.html', 'documentacion/index.html', 'licencia/index.html'];

test('all pages have the right language, metadata, navigation and one main heading', async () => {
  for (const file of pages) {
    const html = await readFile(path.join(root, file), 'utf8');
    const language = ['es/index.html', 'documentacion/index.html', 'licencia/index.html'].includes(file) ? 'es' : 'en';
    assert.ok(html.includes(`<html lang="${language}"`));
    assert.match(html, /hreflang="en"/);
    assert.match(html, /hreflang="es"/);
    assert.match(html, /hreflang="x-default"/);
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
  assert.match(home, /releases\/download\/v0\.3\.0\/Mantis-0\.3\.0\.dmg/);
  assert.match(home, /not notarized/);
  for (const text of ['ScreenCapture', 'local.agus.MeetingRecorder', 'FileVault', 'Gatekeeper', 'SketchyBar']) assert.ok(docs.includes(text));
});

test('home defaults to English and updated copy is present in both languages', async () => {
  const english = await readFile(path.join(root, 'index.html'), 'utf8');
  const spanish = await readFile(path.join(root, 'es/index.html'), 'utf8');
  assert.match(english, /What you hear,/);
  assert.match(english, /Mantis records\./);
  assert.match(spanish, /Lo que escuchas,/);
  assert.match(spanish, /Mantis lo graba\./);
  for (const html of [english, spanish]) {
    assert.doesNotMatch(html, /UNA PEQUEÑA APP PARA ESCUCHAR MEJOR|Sin mandar tus grabaciones a una nube/);
    assert.doesNotMatch(html, /Illustrative screenshot with fictional recordings|Captura ilustrativa con grabaciones ficticias/);
    assert.match(html, /images\/mantis-mark\.svg/);
    assert.match(html, /class="language-switch"/);
  }
});

test('occasional attack and fading silhouette are decorative and can be disabled', async () => {
  const html = await readFile(path.join(root, 'index.html'), 'utf8');
  const css = await readFile(new URL('../src/styles/global.css', import.meta.url), 'utf8');
  assert.match(html, /class="mantis-attack" aria-hidden="true"/);
  assert.match(html, /class="attack-arm"/);
  assert.match(html, /class="attack-trace"/);
  assert.equal((html.match(/class="attack-arm"/g) || []).length, 2);
  assert.equal((html.match(/class="attack-trace"/g) || []).length, 2);
  assert.match(html, /attack-side-right/);
  assert.match(html, /attack-side-left/);
  assert.equal((html.match(/class="arm-spine"/g) || []).length, 56);
  for (const segment of ['coxa', 'femur', 'tibia']) assert.match(html, new RegExp(`arm-${segment}`));
  assert.match(css, /mantis-strike/);
  assert.match(css, /mantis-afterimage/);
  assert.match(css, /\.mantis-attack \{ display: none; \}/);
});

test('header and footer span viewport while content has a slightly wider cap', async () => {
  for (const file of pages) {
    const html = await readFile(path.join(root, file), 'utf8');
    assert.match(html, /<header class="site-header">/);
    assert.doesNotMatch(html, /<header class="site-header wrap"/);
    assert.match(html, /<footer class="site-footer">/);
    assert.doesNotMatch(html, /<footer class="site-footer wrap"/);
  }
  const css = await readFile(new URL('../src/styles/global.css', import.meta.url), 'utf8');
  assert.match(css, /\.site-header \{ width: 100%; padding-inline: clamp\(/);
  assert.match(css, /\.site-footer \{ width: 100%; padding-inline: clamp\(/);
  assert.match(css, /\.wrap \{ width: min\(1280px, calc\(100% - 96px\)\)/);
});

test('first strike starts after five seconds and opposite side follows 300ms later', async () => {
  const layout = await readFile(new URL('../src/layouts/SiteLayout.astro', import.meta.url), 'utf8');
  const css = await readFile(new URL('../src/styles/global.css', import.meta.url), 'utf8');
  assert.match(layout, /first \? 5000 : 26000 \+ Math\.random\(\) \* 26000/);
  assert.match(css, /\.attack-side-left \{ transform: scaleX\(-1\); --attack-delay: 300ms; \}/);
  assert.match(css, /mantis-strike 800ms .*var\(--attack-delay\) both/);
  assert.match(css, /mantis-afterimage 8s .*var\(--attack-delay\) both/);
});

test('arms and silhouettes have soft fills without outlines and an accelerated strike', async () => {
  const css = await readFile(new URL('../src/styles/global.css', import.meta.url), 'utf8');
  const html = await readFile(path.join(root, 'index.html'), 'utf8');
  assert.match(css, /\.attack-arm \{ filter: blur\(1\.5px\); \}/);
  assert.match(css, /\.attack-trace \{ fill: #07140e; filter: blur\(2\.5px\);/);
  assert.match(css, /\.attack-arm \*, \.attack-trace \* \{ stroke: none; \}/);
  assert.doesNotMatch(html, /class="arm-ridge"/);
  assert.match(css, /animation-timing-function: cubic-bezier\(\.55, 0, 1, \.6\)/);
  assert.match(css, /animation-timing-function: cubic-bezier\(\.3, 0, \.8, \.25\)/);
  const luminance = hex => {
    const rgb = hex.match(/\w\w/g).map(channel => {
      const value = parseInt(channel, 16) / 255;
      return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
    });
    return rgb[0] * .2126 + rgb[1] * .7152 + rgb[2] * .0722;
  };
  const background = luminance(css.match(/--forest: #([0-9a-f]{6})/)[1]);
  for (const part of ['body', 'tibia', 'spine', 'joint']) {
    assert.ok(luminance(css.match(new RegExp(`\\.arm-${part} \\{ fill: #([0-9a-f]{6})`))[1]) > background);
  }
  assert.ok(luminance(css.match(/\.attack-trace \{ fill: #([0-9a-f]{6})/)[1]) < background);
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
