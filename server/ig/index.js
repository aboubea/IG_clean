import { config } from '../config.js';

const impl = config.mock ? await import('./mock.js') : await import('./browser.js');
export const login = impl.login;
export const openSession = impl.openSession;
