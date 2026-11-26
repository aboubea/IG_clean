import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { config } from "./config.js";

let key: Buffer | undefined;

function encryptionKey(): Buffer {
  if (key) return key;
  if (config.tokenEncryptionKey) {
    key = Buffer.from(config.tokenEncryptionKey, "base64");
    if (key.length !== 32) throw new Error("TOKEN_ENCRYPTION_KEY doit faire 32 octets encodés en base64.");
  } else if (config.production) {
    throw new Error("TOKEN_ENCRYPTION_KEY est obligatoire en production.");
  } else {
    // Développement : clé éphémère, les jetons chiffrés ne survivent pas au redémarrage.
    key = randomBytes(32);
  }
  return key;
}

/** Chiffre les jetons d'accès des réseaux (AES-256-GCM) avant de les stocker. */
export function seal(plaintext: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const body = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), body].map((part) => part.toString("base64url")).join(".");
}

export function open(sealed: string): string {
  const [iv, tag, body] = sealed.split(".").map((part) => Buffer.from(part, "base64url"));
  if (!iv || !tag || !body) throw new Error("Jeton chiffré illisible.");
  const decipher = createDecipheriv("aes-256-gcm", encryptionKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(body), decipher.final()]).toString("utf8");
}

export const randomToken = (bytes = 32) => randomBytes(bytes).toString("base64url");
export const sha256 = (value: string) => createHash("sha256").update(value).digest("hex");
