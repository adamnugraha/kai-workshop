// Renders the README figures from the HTML files in this folder to PNG files
// one folder up, at 1.5 times their CSS size so they stay sharp on GitHub.
//
//   npm install playwright && npx playwright install chromium
//   node docs/assets/src/render.js                 # every figure
//   node docs/assets/src/render.js hero.html       # one figure
//
// The figures use the Caladea, Carlito and DejaVu Sans Mono fonts
// (Ubuntu: sudo apt install fonts-crosextra-caladea fonts-crosextra-carlito fonts-dejavu-core).
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

(async () => {
  const dir = __dirname;
  const names = process.argv.slice(2).length
    ? process.argv.slice(2)
    : fs.readdirSync(dir).filter((f) => f.endsWith('.html'));
  const browser = await chromium.launch();
  for (const name of names) {
    const page = await browser.newPage({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 1.5 });
    await page.goto('file://' + path.join(dir, name));
    await page.evaluate(() => document.fonts.ready);
    await page.waitForLoadState('networkidle');
    const size = await page.evaluate(() => ({ w: document.body.offsetWidth, h: document.body.offsetHeight }));
    await page.setViewportSize({ width: size.w, height: size.h });
    const out = path.join(dir, '..', name.replace(/\.html$/, '.png'));
    await page.screenshot({ path: out });
    console.log(`${name} -> ${path.relative(process.cwd(), out)} (${size.w}x${size.h})`);
    await page.close();
  }
  await browser.close();
})();
