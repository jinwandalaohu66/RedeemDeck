import { decryptDestination, encryptDestination, randomSlug, sha256 } from "./crypto";
import { empty, error, gone, json, redirect } from "./http";
import type { Env, LinkRow } from "./types";
import { validateClientId, validateDestination, validateExpiration, validatePublicBaseURL } from "./validation";

const MAX_BODY_BYTES = 32 * 1024;
const SLUG_PATTERN = /^[A-Za-z0-9_-]{22}$/;

function managementPath(pathname: string): boolean {
  return pathname === "/v1/health" || pathname === "/v1/links" || pathname === "/v1/links/status";
}

async function tokensMatch(candidate: string, expected: string): Promise<boolean> {
  const [candidateHash, expectedHash] = await Promise.all([sha256(candidate), sha256(expected)]);
  let difference = 0;
  for (let index = 0; index < expectedHash.length; index += 1) {
    difference |= expectedHash.charCodeAt(index) ^ candidateHash.charCodeAt(index);
  }
  return difference === 0;
}

async function isAuthorized(request: Request, env: Env): Promise<boolean> {
  if (!env.MANAGEMENT_API_TOKEN || env.MANAGEMENT_API_TOKEN.length < 32) return false;
  const header = request.headers.get("Authorization") ?? "";
  if (!header.startsWith("Bearer ")) return false;
  return tokensMatch(header.slice(7), env.MANAGEMENT_API_TOKEN);
}

async function parseJSON(request: Request): Promise<unknown> {
  const contentType = request.headers.get("Content-Type")?.split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "application/json") throw new Error("Content-Type must be application/json");
  const declaredLength = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) throw new Error("Request body is too large");
  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_BODY_BYTES) throw new Error("Request body is too large");
  try {
    return JSON.parse(new TextDecoder().decode(body));
  } catch {
    throw new Error("Request body must contain valid JSON");
  }
}

function objectBody(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Request body must be an object");
  return value as Record<string, unknown>;
}

async function checkConfiguration(env: Env): Promise<void> {
  if (!env.MANAGEMENT_API_TOKEN || env.MANAGEMENT_API_TOKEN.length < 32) {
    throw new Error("MANAGEMENT_API_TOKEN must contain at least 32 characters");
  }
  validatePublicBaseURL(env.PUBLIC_BASE_URL);
  await encryptDestination("configuration-check", env.DESTINATION_ENCRYPTION_KEY);
  await env.DB.prepare("SELECT 1 AS ok").first();
}

async function createLink(request: Request, env: Env): Promise<Response> {
  if (env.REGISTRATION_RATE_LIMITER && !(await env.REGISTRATION_RATE_LIMITER.limit({ key: "create-link" })).success) {
    return error(429, "rate_limited", "Too many link registration requests");
  }

  let body: Record<string, unknown>;
  let clientId: string;
  let destinationURL: string;
  let expiresAt: string | null;
  try {
    body = objectBody(await parseJSON(request));
    const unknownKeys = Object.keys(body).filter(key => !["clientId", "destinationURL", "expiresAt"].includes(key));
    if (unknownKeys.length > 0) throw new Error(`Unsupported field: ${unknownKeys[0]}`);
    clientId = validateClientId(body.clientId);
    destinationURL = validateDestination(body.destinationURL);
    expiresAt = validateExpiration(body.expiresAt, new Date());
  } catch (caught) {
    return error(400, "invalid_request", caught instanceof Error ? caught.message : "Invalid request");
  }

  if (request.headers.get("Idempotency-Key")?.toLowerCase() !== clientId) {
    return error(400, "invalid_idempotency_key", "Idempotency-Key must match clientId");
  }

  const destinationHash = await sha256(destinationURL);
  const existing = await env.DB.prepare("SELECT * FROM tracked_links WHERE client_id = ?")
    .bind(clientId)
    .first<LinkRow>();
  if (existing) {
    if (existing.destination_hash !== destinationHash || existing.expires_at !== expiresAt) {
      return error(409, "client_id_conflict", "clientId is already registered with different link data");
    }
    return createResponse(existing, env);
  }

  const encrypted = await encryptDestination(destinationURL, env.DESTINATION_ENCRYPTION_KEY);
  const createdAt = new Date().toISOString();
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const row: LinkRow = {
      id: crypto.randomUUID(),
      slug: randomSlug(),
      client_id: clientId,
      destination_ciphertext: encrypted.ciphertext,
      destination_iv: encrypted.iv,
      destination_hash: destinationHash,
      created_at: createdAt,
      expires_at: expiresAt,
      first_seen_at: null,
      last_seen_at: null,
      visit_count: 0,
    };
    try {
      await env.DB.prepare(
        `INSERT INTO tracked_links
          (id, slug, client_id, destination_ciphertext, destination_iv, destination_hash, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      )
        .bind(
          row.id,
          row.slug,
          row.client_id,
          row.destination_ciphertext,
          row.destination_iv,
          row.destination_hash,
          row.created_at,
          row.expires_at,
        )
        .run();
      return createResponse(row, env, 201);
    } catch {
      const raced = await env.DB.prepare("SELECT * FROM tracked_links WHERE client_id = ?")
        .bind(clientId)
        .first<LinkRow>();
      if (raced) {
        if (raced.destination_hash !== destinationHash || raced.expires_at !== expiresAt) {
          return error(409, "client_id_conflict", "clientId is already registered with different link data");
        }
        return createResponse(raced, env);
      }
    }
  }
  return error(503, "registration_unavailable", "Unable to allocate a link identifier");
}

function createResponse(row: LinkRow, env: Env, status = 200): Response {
  const baseURL = validatePublicBaseURL(env.PUBLIC_BASE_URL);
  return json(
    {
      id: row.id,
      shortURL: `${baseURL}/r/${row.slug}`,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
    },
    status,
  );
}

async function linkStatuses(request: Request, env: Env): Promise<Response> {
  let ids: string[];
  try {
    const body = objectBody(await parseJSON(request));
    if (Object.keys(body).some(key => key !== "ids")) throw new Error("Request body may contain only ids");
    if (!Array.isArray(body.ids) || body.ids.length < 1 || body.ids.length > 100) {
      throw new Error("ids must contain between 1 and 100 link IDs");
    }
    ids = body.ids.map(validateClientId);
    if (new Set(ids).size !== ids.length) throw new Error("ids must not contain duplicates");
  } catch (caught) {
    return error(400, "invalid_request", caught instanceof Error ? caught.message : "Invalid request");
  }

  const placeholders = ids.map(() => "?").join(", ");
  const result = await env.DB.prepare(
    `SELECT id, first_seen_at, last_seen_at, visit_count FROM tracked_links WHERE id IN (${placeholders})`,
  )
    .bind(...ids)
    .all<Pick<LinkRow, "id" | "first_seen_at" | "last_seen_at" | "visit_count">>();
  const rows = new Map(result.results.map(row => [row.id, row]));
  return json({
    links: ids.flatMap(id => {
      const row = rows.get(id);
      return row
        ? [{ id, firstSeenAt: row.first_seen_at, lastSeenAt: row.last_seen_at, visitCount: row.visit_count }]
        : [];
    }),
  });
}

async function followLink(request: Request, env: Env, slug: string): Promise<Response> {
  if (!SLUG_PATTERN.test(slug)) return error(404, "not_found", "Link not found");
  if (env.REDIRECT_RATE_LIMITER && !(await env.REDIRECT_RATE_LIMITER.limit({ key: slug })).success) {
    return error(429, "rate_limited", "Too many redirect requests");
  }

  const row = await env.DB.prepare("SELECT * FROM tracked_links WHERE slug = ?").bind(slug).first<LinkRow>();
  if (!row) return error(404, "not_found", "Link not found");
  const now = new Date();
  if (row.expires_at && Date.parse(row.expires_at) <= now.getTime()) return gone();

  let destination: string;
  try {
    destination = await decryptDestination(row.destination_ciphertext, row.destination_iv, env.DESTINATION_ENCRYPTION_KEY);
  } catch {
    return error(503, "link_unavailable", "Link is temporarily unavailable");
  }

  if (request.method === "GET") {
    const seenAt = now.toISOString();
    const update = await env.DB.prepare(
      `UPDATE tracked_links
       SET visit_count = visit_count + 1,
           first_seen_at = COALESCE(first_seen_at, ?),
           last_seen_at = ?
       WHERE id = ? AND (expires_at IS NULL OR expires_at > ?)`,
    )
      .bind(seenAt, seenAt, row.id, seenAt)
      .run();
    if ((update.meta.changes ?? 0) !== 1) return gone();
  }

  return redirect(destination);
}

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (managementPath(url.pathname)) {
    if (!(await isAuthorized(request, env))) return error(401, "unauthorized", "A valid bearer token is required");
    if (url.pathname === "/v1/health") {
      if (request.method !== "GET") return empty(405, { Allow: "GET" });
      try {
        await checkConfiguration(env);
        return json({ status: "ok" });
      } catch {
        return error(503, "service_misconfigured", "Service configuration is invalid");
      }
    }
    if (url.pathname === "/v1/links" && request.method === "POST") return createLink(request, env);
    if (url.pathname === "/v1/links/status" && request.method === "POST") return linkStatuses(request, env);
    return empty(405, { Allow: "POST" });
  }

  const match = url.pathname.match(/^\/r\/([^/]+)$/);
  if (match && (request.method === "GET" || request.method === "HEAD")) return followLink(request, env, match[1]);
  if (match) return empty(405, { Allow: "GET, HEAD" });
  return error(404, "not_found", "Route not found");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await handle(request, env);
    } catch {
      return error(500, "internal_error", "An unexpected error occurred");
    }
  },
} satisfies ExportedHandler<Env>;
