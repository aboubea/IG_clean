const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 900, height: 760 }, deviceScaleFactor: 2 });
  await p.goto('file://' + __dirname + '/card.html');
  await p.screenshot({ path: 'carte-bilan.png' });
  await b.close();
})();
