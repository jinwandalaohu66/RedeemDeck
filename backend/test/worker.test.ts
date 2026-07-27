import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it, vi } from "vitest";
import migration from "../migrations/0001_create_tracked_links.sql?raw";
import worker from "../src/index";
import type { Env, RateLimitBinding } from "../src/types";

const TOKEN = "synthetic-management-token-at-least-32-characters";
const CLIENT_ID = "019fb466-7cf0-7d4b-9521-755577d17001";
const DESTINATION = "https://apps.apple.com/redeem?ctx=offercodes&id=1234567890&code=SYNTHETIC-CODE";

function managementRequest(path: string, init: RequestInit = {}): Request {
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${TOKEN}`);
  return new Request(`https://worker.example.test${path}`, { ...init, headers });
}

function jsonRequest(path: string, body: unknown, headers: HeadersInit = {}): Request {
  return managementRequest(path, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

function testEnv(overrides: Partial<Env> = {}): Env {
  return {
    DB: env.DB,
    MANAGEMENT_API_TOKEN: TOKEN,
    DESTINATION_ENCRYPTION_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    PUBLIC_BASE_URL: "https://links.example.test",
    ...overrides,
  };
}

async function fetch(request: Request, overrides: Partial<Env> = {}): Promise<Response> {
  return worker.fetch(request, testEnv(overrides));
}

async function createLink(
  clientId = CLIENT_ID,
  destinationURL = DESTINATION,
  expiresAt?: string,
): Promise<{ response: Response; body: { id: string; shortURL: string; createdAt: string; expiresAt: string | null } }> {
  const response = await fetch(
    jsonRequest("/v1/links", { clientId, destinationURL, ...(expiresAt ? { expiresAt } : {}) }, { "Idempotency-Key": clientId }),
  );
  return { response, body: await response.json() };
}

beforeEach(async () => {
  await env.DB.exec("DROP TABLE IF EXISTS tracked_links;");
  await env.DB.exec(migration);
});

describe("management authentication and health", () => {
  it("requires bearer authentication on every management route", async () => {
    for (const [path, method] of [["/v1/health", "GET"], ["/v1/links", "POST"], ["/v1/links/status", "POST"]]) {
      const response = await fetch(new Request(`https://worker.example.test${path}`, { method }));
      expect(response.status).toBe(401);
      expect(response.headers.get("Cache-Control")).toBe("no-store");
    }
  });

  it("checks database, URL, token, and encryption configuration", async () => {
    expect((await fetch(managementRequest("/v1/health"))).status).toBe(200);
    expect((await fetch(managementRequest("/v1/health"), { DESTINATION_ENCRYPTION_KEY: "bad" })).status).toBe(503);
    expect((await fetch(managementRequest("/v1/health"), { PUBLIC_BASE_URL: "http://unsafe.test" })).status).toBe(503);
  });
});

describe("link registration", () => {
  it("registers an encrypted destination with a 128-bit opaque slug", async () => {
    const { response, body } = await createLink();
    expect(response.status).toBe(201);
    expect(body.shortURL).toMatch(/^https:\/\/links\.example\.test\/r\/[A-Za-z0-9_-]{22}$/);
    expect(body.expiresAt).toBeNull();

    const row = await env.DB.prepare(
      "SELECT destination_ciphertext, destination_iv, destination_hash, slug FROM tracked_links WHERE id = ?",
    ).bind(body.id).first<Record<string, string>>();
    expect(row).not.toBeNull();
    expect(JSON.stringify(row)).not.toContain(DESTINATION);
    expect(row!.slug).toHaveLength(22);
  });

  it("is idempotent and rejects a changed destination or expiration", async () => {
    const first = await createLink();
    const second = await createLink();
    expect(second.response.status).toBe(200);
    expect(second.body).toEqual(first.body);

    const changed = await createLink(CLIENT_ID, DESTINATION.replace("SYNTHETIC-CODE", "OTHER-CODE"));
    expect(changed.response.status).toBe(409);
  });

  it("retries a random slug collision", async () => {
    const first = await createLink();
    const firstSlug = new URL(first.body.shortURL).pathname.split("/").at(-1)!;
    const normalized = firstSlug.replaceAll("-", "+").replaceAll("_", "/");
    const binary = atob(normalized.padEnd(24, "="));
    const collisionBytes = Uint8Array.from(binary, character => character.charCodeAt(0));
    const original = crypto.getRandomValues.bind(crypto) as (array: Uint8Array<ArrayBuffer>) => Uint8Array<ArrayBuffer>;
    let collided = false;
    const implementation = ((array: Uint8Array<ArrayBuffer>): Uint8Array<ArrayBuffer> => {
      if (!collided && array.byteLength === 16) {
        collided = true;
        array.set(collisionBytes);
        return array;
      }
      return original(array);
    }) as typeof crypto.getRandomValues;
    const random = vi.spyOn(crypto, "getRandomValues").mockImplementation(implementation);
    try {
      const second = await createLink("019fb466-7cf0-7d4b-9521-755577d17002", DESTINATION.replace("CODE", "CODE-2"));
      expect(second.response.status).toBe(201);
      expect(second.body.shortURL).not.toBe(first.body.shortURL);
      expect(collided).toBe(true);
    } finally {
      random.mockRestore();
    }
  });

  it("requires a matching idempotency key", async () => {
    const response = await fetch(jsonRequest("/v1/links", { clientId: CLIENT_ID, destinationURL: DESTINATION }));
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: { code: "invalid_idempotency_key" } });
  });

  it.each([
    "http://apps.apple.com/redeem?id=1&code=X",
    "https://example.com/redeem?id=1&code=X",
    "https://apps.apple.com/other?id=1&code=X",
    "https://apps.apple.com/redeem?id=1",
    "https://apps.apple.com/redeem?id=text&code=X",
    "https://apps.apple.com/redeem?id=1&code=X#fragment",
    "https://apps.apple.com/redeem?id=1&code=X&redirect=https://example.test",
    "https://user:password@apps.apple.com/redeem?id=1&code=X",
  ])("rejects unsafe or malformed Apple destination %s", async destinationURL => {
    expect((await createLink(CLIENT_ID, destinationURL)).response.status).toBe(400);
  });

  it("rejects expired dates, oversized bodies, and unsupported JSON fields", async () => {
    const expired = await createLink(CLIENT_ID, DESTINATION, "2020-01-01T00:00:00.000Z");
    expect(expired.response.status).toBe(400);
    expect((await createLink(CLIENT_ID, DESTINATION, "January 1, 2099")).response.status).toBe(400);

    const oversized = await fetch(jsonRequest(
      "/v1/links",
      { clientId: CLIENT_ID, destinationURL: DESTINATION, padding: "x".repeat(33 * 1024) },
      { "Idempotency-Key": CLIENT_ID },
    ));
    expect(oversized.status).toBe(400);
  });

  it("applies the registration rate limiter", async () => {
    const limiter: RateLimitBinding = { limit: vi.fn(async () => ({ success: false })) };
    const response = await fetch(
      jsonRequest("/v1/links", { clientId: CLIENT_ID, destinationURL: DESTINATION }, { "Idempotency-Key": CLIENT_ID }),
      { REGISTRATION_RATE_LIMITER: limiter },
    );
    expect(response.status).toBe(429);
  });
});

describe("redirect tracking", () => {
  it("counts GET requests atomically and reports aggregate status", async () => {
    const { body } = await createLink();
    const redirectPath = new URL(body.shortURL).pathname;
    const responses = await Promise.all(
      Array.from({ length: 12 }, () => fetch(new Request(`https://worker.example.test${redirectPath}`))),
    );
    expect(responses.every(response => response.status === 302)).toBe(true);
    expect(responses[0].headers.get("Location")).toBe(DESTINATION);
    expect(responses[0].headers.get("Referrer-Policy")).toBe("no-referrer");

    const status = await fetch(jsonRequest("/v1/links/status", { ids: [body.id] }));
    expect(status.status).toBe(200);
    const payload = await status.json() as { links: Array<Record<string, unknown>> };
    expect(payload.links).toHaveLength(1);
    expect(payload.links[0]).toMatchObject({ id: body.id, visitCount: 12 });
    expect(payload.links[0].firstSeenAt).toEqual(expect.any(String));
    expect(payload.links[0].lastSeenAt).toEqual(expect.any(String));
  });

  it("redirects HEAD without counting it", async () => {
    const { body } = await createLink();
    const response = await fetch(new Request(body.shortURL, { method: "HEAD" }));
    expect(response.status).toBe(302);
    const row = await env.DB.prepare("SELECT visit_count, first_seen_at FROM tracked_links WHERE id = ?")
      .bind(body.id).first<{ visit_count: number; first_seen_at: string | null }>();
    expect(row).toEqual({ visit_count: 0, first_seen_at: null });
  });

  it("returns 410 for expired links without recording an interaction", async () => {
    const { body } = await createLink(CLIENT_ID, DESTINATION, "2099-01-01T00:00:00.000Z");
    await env.DB.prepare("UPDATE tracked_links SET expires_at = ? WHERE id = ?")
      .bind("2020-01-01T00:00:00.000Z", body.id).run();
    const response = await fetch(new Request(body.shortURL));
    expect(response.status).toBe(410);
    expect(response.headers.get("Content-Security-Policy")).toContain("default-src 'none'");
    const row = await env.DB.prepare("SELECT visit_count FROM tracked_links WHERE id = ?")
      .bind(body.id).first<{ visit_count: number }>();
    expect(row!.visit_count).toBe(0);
  });

  it("does not record an interaction when the destination cannot be decrypted", async () => {
    const { body } = await createLink();
    await env.DB.prepare("UPDATE tracked_links SET destination_ciphertext = ? WHERE id = ?")
      .bind("corrupt", body.id).run();
    const response = await fetch(new Request(body.shortURL));
    expect(response.status).toBe(503);
    const row = await env.DB.prepare("SELECT visit_count FROM tracked_links WHERE id = ?")
      .bind(body.id).first<{ visit_count: number }>();
    expect(row!.visit_count).toBe(0);
  });

  it("applies redirect rate limits using only the opaque slug", async () => {
    const { body } = await createLink();
    const limit = vi.fn(async () => ({ success: false }));
    const response = await fetch(new Request(body.shortURL), { REDIRECT_RATE_LIMITER: { limit } });
    expect(response.status).toBe(429);
    expect(limit).toHaveBeenCalledWith({ key: new URL(body.shortURL).pathname.split("/").at(-1) });
  });
});

describe("batch status and privacy", () => {
  it("returns known IDs in requested order and omits unknown IDs", async () => {
    const first = await createLink();
    const second = await createLink("019fb466-7cf0-7d4b-9521-755577d17002", DESTINATION.replace("CODE", "CODE-2"));
    const unknown = "019fb466-7cf0-7d4b-9521-755577d17999";
    const response = await fetch(jsonRequest("/v1/links/status", { ids: [second.body.id, unknown, first.body.id] }));
    const payload = await response.json() as { links: Array<{ id: string }> };
    expect(payload.links.map(link => link.id)).toEqual([second.body.id, first.body.id]);
  });

  it("rejects empty, duplicate, malformed, or over-limit status batches", async () => {
    expect((await fetch(jsonRequest("/v1/links/status", { ids: [] }))).status).toBe(400);
    expect((await fetch(jsonRequest("/v1/links/status", { ids: [CLIENT_ID, CLIENT_ID] }))).status).toBe(400);
    expect((await fetch(jsonRequest("/v1/links/status", { ids: ["not-a-uuid"] }))).status).toBe(400);
    expect((await fetch(jsonRequest("/v1/links/status", { ids: Array.from({ length: 101 }, (_, index) =>
      `019fb466-7cf0-7d4b-9521-${String(index).padStart(12, "0")}`,
    ) }))).status).toBe(400);
  });

  it("does not log destinations, tokens, request metadata, or codes", async () => {
    const spies = [vi.spyOn(console, "log"), vi.spyOn(console, "info"), vi.spyOn(console, "warn"), vi.spyOn(console, "error")];
    try {
      await createLink();
      expect(spies.every(spy => spy.mock.calls.length === 0)).toBe(true);
    } finally {
      for (const spy of spies) spy.mockRestore();
    }
  });
});
