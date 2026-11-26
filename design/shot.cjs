const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1320, height: 900 }, deviceScaleFactor: 2 });
  await p.goto('file://' + __dirname + '/mockups.html');
  for (const [id, name] of [['A', 'proposition-A-pulse'], ['B', 'proposition-B-tri'], ['C', 'proposition-C-brief']])
    await p.locator('#' + id).screenshot({ path: `${name}.png` });
  await b.close();
})();
