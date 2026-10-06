// Renders the page frame by frame in headless Chrome.
//
//   node render.mjs --stills 1.5,3,7.2 [--out dir] [--scale 0.5]      a few moments, as JPEGs, for looking at
//   node render.mjs --cues <file.json>                                the sounds the scenes ask for, and when
//   node render.mjs --frames [--from 0] [--to 186] [--fps 60] [--workers 6] [--out dir] [--png]   every frame (JPEG unless --png)
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const { chromium } = createRequire(path.join(root, 'output/promo-tools/'))('playwright-core');
const args = process.argv.slice(2);
const option = (name, fallback) => { const i = args.indexOf('--' + name); return i < 0 ? fallback : args[i + 1]; };
const out = path.resolve(option('out', path.join(root, 'output/promo/stills')));
mkdirSync(out, { recursive: true });
const scale = Number(option('scale', 1));
const page_url = pathToFileURL(path.join(root, 'promo/src/index.html')).href;

const browser = await chromium.launch({ channel: 'chrome', headless: true,
  args: ['--allow-file-access-from-files', '--force-color-profile=srgb', '--font-render-hinting=none', '--hide-scrollbars', '--disable-lcd-text'] });
const open = async () => {
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: scale });
  const page = await context.newPage();
  page.on('console', message => { if (message.type() === 'error' || message.type() === 'warning') console.log('[page]', message.text()); });
  page.on('pageerror', error => console.log('[page error]', error.message));
  await page.goto(page_url);
  await page.waitForFunction(() => window.filmReady === true, null, { timeout: 60000 });
  return page;
};

if (args.includes('--cues')) {
  const page = await open();
  const cues = await page.evaluate(() => window.film.cues);
  writeFileSync(path.resolve(option('cues')), JSON.stringify(cues, null, 1));
  console.log(`${cues.length} cues`);
} else if (args.includes('--stills')) {
  const page = await open();
  for (const moment of option('stills').split(',').map(Number)) {
    await page.evaluate(t => window.film.seek(t), moment);
    await page.screenshot({ path: path.join(out, `still-${moment.toFixed(2).padStart(6, '0')}.jpg`), type: 'jpeg', quality: 88 });
  }
} else {
  const fps = Number(option('fps', 60));
  const duration = await (await open()).evaluate(() => window.film.duration);
  const first = Math.round(Number(option('from', 0)) * fps), last = Math.round(Number(option('to', duration)) * fps);
  let next = first, done = 0;
  const began = Date.now();
  const work = async () => {
    const page = await open();
    while (next < last) {
      const frame = next++;
      await page.evaluate(t => window.film.seek(t), frame / fps);
      await page.screenshot(args.includes('--png') ? { path: path.join(out, String(frame).padStart(6, '0') + '.png'), type: 'png' }
        : { path: path.join(out, String(frame).padStart(6, '0') + '.jpg'), type: 'jpeg', quality: 96 });
      if (++done % 300 === 0) console.log(`${done}/${last - first} frames, ${((Date.now() - began) / 1000).toFixed(0)}s`);
    }
  };
  await Promise.all(Array.from({ length: Number(option('workers', 6)) }, work));
  console.log(`rendered ${done} frames in ${((Date.now() - began) / 1000).toFixed(0)}s`);
}
await browser.close();
