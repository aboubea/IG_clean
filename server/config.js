import path from 'node:path';
import fs from 'node:fs';

const dataDir = path.resolve(process.env.DATA_DIR || './data');
fs.mkdirSync(dataDir, { recursive: true });

export const config = {
  dataDir,
  dbPath: path.join(dataDir, 'ig.sqlite'),
  profileDir: path.join(dataDir, 'browser-profile'),
  port: Number(process.env.PORT || 3001),
  mock: process.env.IG_MOCK === '1',
  headless: process.env.HEADLESS === '1',
  // Ex. BROWSER_CHANNEL=chrome pour piloter le Chrome installé plutôt que le Chromium de Playwright.
  browserChannel: process.env.BROWSER_CHANNEL || undefined,
};

export const DEFAULT_SETTINGS = {
  snapshotHour: 10, // heure locale à partir de laquelle le scan quotidien se lance
  autoSnapshot: true,
  hourlyCap: 20,
  dailyCap: 100,
  delayMinSec: 40,
  delayMaxSec: 120,
};
