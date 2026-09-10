// Loads the exported browser build in a real Chromium and checks it runs.
//
//   node tests/playtest/browser_check.mjs
//
// This is a smoke check, not a performance gate. A headless CI browser has no
// GPU and falls back to software rendering, so its frame rate measures the
// emulator rather than anyone's machine. What it does prove is that the wasm
// loads, the game reaches the point of running, and nothing throws on the way.
//
// For a real frame rate, serve the build with tools/serve_web.sh, open it in
// your own browser and press F3.

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';
import { chromium } from 'playwright';

const ROOT = resolve(process.argv[2] ?? 'build/web');
const PORT = Number(process.env.PORT ?? 8060);
const SEED = 20260910;
const BOOT_TIMEOUT_MS = 180_000;

const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json',
};

const server = createServer(async (req, res) => {
  try {
    const path = join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    const body = await readFile(path);
    res.writeHead(200, { 'Content-Type': MIME[extname(path)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});
await new Promise((r) => server.listen(PORT, r));

const browser = await chromium.launch({
  args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });

const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));

let failed = 0;
const ok = (label, cond, detail = '') => {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${detail ? ` (${detail})` : ''}`);
  if (!cond) failed++;
};

console.log('Abyssbound browser check');
console.log('------------------------');

await page.goto(`http://localhost:${PORT}/index.html?start&seed=${SEED}`, { waitUntil: 'load' });

// The build is loaded with ?start, which skips the title screen. Getting a
// key press into a Godot canvas from an automated browser turned out to be
// its own problem, and the check should be testing the game rather than
// Playwright's focus handling.
const canvas = page.locator('canvas');
await canvas.waitFor({ state: 'visible', timeout: BOOT_TIMEOUT_MS });
await page.screenshot({ path: 'build/browser_title.png' });

let stats = null;
try {
  await page.waitForFunction(() => window.__abyss?.ready === true, null,
    { timeout: BOOT_TIMEOUT_MS, polling: 500 });
  stats = await page.evaluate(() => window.__abyss);
} catch {
  // reported below
}

ok('the browser build boots, starts, and enters the world', stats !== null,
  stats === null ? 'never reached the world' : '');

if (stats) {
  ok('it generated the world it was asked for', stats.seed === SEED, `seed ${stats.seed}`);
  ok('the player is somewhere sane', Array.isArray(stats.tile) && stats.tile[1] > 0,
    `tile ${stats.tile} in ${stats.biome}`);
  ok('chunks are streaming', stats.chunks > 0, `${stats.chunks} loaded`);

  // Let it run, then report. Informational: software rendering, no GPU.
  const samples = [];
  for (let i = 0; i < 12; i++) {
    await page.waitForTimeout(500);
    const s = await page.evaluate(() => window.__abyss);
    if (s?.fps) samples.push(s.fps);
  }
  samples.sort((a, b) => a - b);
  const median = samples[Math.floor(samples.length / 2)] ?? 0;
  const light = (await page.evaluate(() => window.__abyss))?.light_ms ?? 0;
  console.log(`\n  software-rendered fps (not a hardware figure): median ${median} over ${samples.length} samples`);
  console.log(`  light pass in the browser: ${light} ms`);
  ok('it keeps running rather than stalling', samples.length > 0 && median > 0);
}

ok('nothing threw in the console', errors.length === 0,
  errors.slice(0, 3).join(' | ') || 'clean');

await page.screenshot({ path: 'build/browser_check.png' });
console.log('\n  screenshots: build/browser_title.png, build/browser_check.png');

await browser.close();
server.close();
console.log('------------------------');
console.log(failed === 0 ? 'browser build is healthy' : `${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
