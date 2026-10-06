// Renders the cover picture in Chinese and English, in both shapes: 16:9 (1920 x 1080) and 4:3 (1600 x 1200),
// into output/promo/cover/. The 16:9 ones are also the title picture of the READMEs and the site.
//   node promo/tools/cover.mjs
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const { chromium } = createRequire(path.join(root, 'output/promo-tools/'))('playwright-core');
const out = path.join(root, 'output/promo/cover');
mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--allow-file-access-from-files', '--force-color-profile=srgb', '--hide-scrollbars'] });
for (const lang of ['zh', 'en']) {
  for (const [shape, width, height] of [['16x9', 1920, 1080], ['4x3', 1600, 1200]]) {
    const page = await (await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 })).newPage();
    page.on('pageerror', error => console.log('[page error]', error.message));
    await page.goto(pathToFileURL(path.join(root, 'promo/src/cover.html')).href + `?shape=${shape}&lang=${lang}`);
    await page.waitForFunction(() => window.coverReady === true);
    await page.screenshot({ path: path.join(out, `VibeWand-cover-${shape}-${lang}.png`), type: 'png' });
    console.log(`VibeWand-cover-${shape}-${lang}.png ${width}x${height}`);
  }
}
await browser.close();
