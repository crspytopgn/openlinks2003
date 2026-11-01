// Renders the brand images in renders.json with the pre-installed Chromium
// (Playwright): SVGs to PNG at any size, and the HTML templates (banners,
// screenshot cards, social card) to PNG, then WebP or JPEG by extension.
//
//   node tools/brand/render.js [part-of-an-output-name]
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const HERE = __dirname;
const OUT = path.resolve(HERE, '../../docs/brand');

(async () => {
	const jobs = JSON.parse(fs.readFileSync(path.join(HERE, 'renders.json'), 'utf8'));
	const only = process.argv[2];
	const browser = await chromium.launch();
	for (const j of jobs) {
		if (only && !j.out.includes(only)) continue;
		const scale = j.scale || 1;
		const ctx = await browser.newContext({ deviceScaleFactor: scale, viewport: { width: j.w, height: j.h } });
		const page = await ctx.newPage();
		const src = path.join(HERE, j.src);
		let url = 'file://' + src + (j.query ? '?' + j.query : '');
		if (src.endsWith('.svg')) {
			const tmp = path.join(os.tmpdir(), 'brand-wrap.html');
			fs.writeFileSync(tmp, `<html><body style="margin:0;background:transparent"><img src="file://${src}" style="width:${j.w}px;height:${j.h}px;display:block"></body></html>`);
			url = 'file://' + tmp;
		}
		await page.goto(url);
		await page.waitForLoadState('networkidle');
		await page.evaluate(() => document.fonts.ready);
		const out = path.join(OUT, j.out);
		fs.mkdirSync(path.dirname(out), { recursive: true });
		const png = out.replace(/\.(webp|jpg)$/, '.tmp.png');
		await page.screenshot({ path: out.endsWith('.png') ? out : png, omitBackground: true });
		if (!out.endsWith('.png')) {
			// Pillow does the WebP/JPEG encoding.
			execFileSync('python3', ['-I', path.join(HERE, 'encode.py'), png, out, String(j.quality || 88)]);
			fs.unlinkSync(png);
		}
		console.log('wrote', path.relative(process.cwd(), out), fs.statSync(out).size, 'bytes');
		await ctx.close();
	}
	await browser.close();
})();
