// Render outlined SVGs to transparent PNGs with Chromium.
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const [root, ...widths] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch();
  const page = await b.newPage();
  const files = [];
  const walk = d => fs.readdirSync(d).forEach(n => { const p = path.join(d, n); fs.statSync(p).isDirectory() ? walk(p) : (p.includes('/distribution/') && p.endsWith('.svg') && files.push(p)); });
  walk(root);
  for (const f of files) {
    const svg = fs.readFileSync(f, 'utf8');
    const m = svg.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/); const vw = +m[1], vh = +m[2];
    for (const w of widths.map(Number)) {
      const h = Math.ceil(w * vh / vw);
      await page.setViewportSize({ width: w, height: h });
      const sized = svg.replace(/width="[\d.]+" height="[\d.]+"/, `width="${w}" height="${h}"`);
      await page.setContent(`<html><body style="margin:0;background:transparent">${sized.replace(/<\?xml[^>]*>/, '')}</body></html>`);
      const out = f.replace('/distribution/', '/png/').replace(/\.svg$/, `-${w}w.png`);
      fs.mkdirSync(path.dirname(out), { recursive: true });
      await page.screenshot({ path: out, omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } });
    }
  }
  await b.close(); console.log('rendered', files.length, 'svgs');
})();
