export class IgError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
export const loggedOut = () =>
  new IgError('LOGGED_OUT', 'Session Instagram absente ou expirée : reconnecte-toi.');
export const rateLimited = (detail = '') =>
  new IgError('RATE_LIMITED', `Instagram a limité les actions du compte. ${detail}`.trim());
export const checkpoint = () =>
  new IgError('CHECKPOINT', 'Instagram demande une vérification de sécurité : ouvre Instagram et valide-la.');
