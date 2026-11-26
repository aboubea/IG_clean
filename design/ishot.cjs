const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await b.newPage({ viewport:{width:460,height:800}, deviceScaleFactor:2 }); await p.goto('file://'+__dirname+'/influx.html'); await p.screenshot({path:'hot-influx.png'}); await b.close(); })();
