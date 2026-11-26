const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1720, height: 1000 }, deviceScaleFactor: 2 });
  await p.goto('file://' + __dirname + '/multi.html');
  await p.locator('.board').screenshot({ path: 'multi-reseaux.png' });
  await b.close();
})();
