const encoder = new TextEncoder();
const decoder = new TextDecoder();

function bytesToBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function base64ToBytes(value: string): Uint8Array<ArrayBuffer> {
  let binary: string;
  try {
    binary = atob(value);
  } catch {
    throw new Error("DESTINATION_ENCRYPTION_KEY must be valid base64");
  }
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

async function encryptionKey(base64Key: string): Promise<CryptoKey> {
  const raw = base64ToBytes(base64Key);
  if (raw.byteLength !== 32) {
    throw new Error("DESTINATION_ENCRYPTION_KEY must decode to exactly 32 bytes");
  }
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function sha256(value: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
  return bytesToBase64URL(digest);
}

export async function encryptDestination(
  destination: string,
  base64Key: string,
): Promise<{ ciphertext: string; iv: string }> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await encryptionKey(base64Key), encoder.encode(destination)),
  );
  return { ciphertext: bytesToBase64URL(ciphertext), iv: bytesToBase64URL(iv) };
}

function base64URLToBytes(value: string): Uint8Array<ArrayBuffer> {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return base64ToBytes(padded);
}

export async function decryptDestination(ciphertext: string, iv: string, base64Key: string): Promise<string> {
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64URLToBytes(iv) },
    await encryptionKey(base64Key),
    base64URLToBytes(ciphertext),
  );
  return decoder.decode(plaintext);
}

export function randomSlug(): string {
  return bytesToBase64URL(crypto.getRandomValues(new Uint8Array(16)));
}
