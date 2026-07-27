const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ALLOWED_QUERY_NAMES = new Set(["ctx", "id", "code"]);

export function validateClientId(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) throw new Error("clientId must be a UUID");
  return value.toLowerCase();
}

export function validateDestination(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 4096) {
    throw new Error("destinationURL must be a non-empty URL no longer than 4096 characters");
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("destinationURL is malformed");
  }
  if (url.protocol !== "https:" || url.hostname !== "apps.apple.com" || url.port || url.username || url.password) {
    throw new Error("destinationURL must use https://apps.apple.com");
  }
  if (url.pathname !== "/redeem" || url.hash) throw new Error("destinationURL must use /redeem and have no fragment");

  const present = new Set<string>();
  for (const [name, value] of url.searchParams) {
    if (!ALLOWED_QUERY_NAMES.has(name)) throw new Error(`destinationURL contains unsupported parameter: ${name}`);
    if (present.has(name)) throw new Error(`destinationURL contains duplicate parameter: ${name}`);
    if (!value) throw new Error(`destinationURL parameter ${name} must not be empty`);
    present.add(name);
  }
  if (!present.has("id") || !present.has("code")) throw new Error("destinationURL must contain id and code parameters");
  if (!/^\d+$/.test(url.searchParams.get("id")!)) throw new Error("destinationURL id must be numeric");
  const context = url.searchParams.get("ctx");
  if (context !== null && context !== "offercodes") throw new Error("destinationURL ctx must be offercodes");
  return url.toString();
}

export function validateExpiration(value: unknown, now: Date): string | null {
  if (value === undefined || value === null) return null;
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)
  ) {
    throw new Error("expiresAt must be an ISO 8601 string");
  }
  const time = Date.parse(value);
  if (!Number.isFinite(time)) throw new Error("expiresAt must be a valid ISO 8601 date");
  if (time <= now.getTime()) throw new Error("expiresAt must be in the future");
  return new Date(time).toISOString();
}

export function validatePublicBaseURL(value: string): string {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("PUBLIC_BASE_URL is invalid");
  }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash || url.pathname !== "/") {
    throw new Error("PUBLIC_BASE_URL must be an HTTPS origin without path, credentials, query, or fragment");
  }
  return url.origin;
}
