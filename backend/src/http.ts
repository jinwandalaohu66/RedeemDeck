const BASE_HEADERS: HeadersInit = {
  "Cache-Control": "no-store",
  "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
};

export function json(value: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...BASE_HEADERS, "Content-Type": "application/json; charset=utf-8", ...headers },
  });
}

export function empty(status: number, headers: HeadersInit = {}): Response {
  return new Response(null, { status, headers: { ...BASE_HEADERS, ...headers } });
}

export function error(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

export function redirect(location: string): Response {
  return empty(302, { Location: location });
}

export function gone(): Response {
  return new Response("<!doctype html><title>Link expired</title><p>This link has expired.</p>", {
    status: 410,
    headers: { ...BASE_HEADERS, "Content-Type": "text/html; charset=utf-8" },
  });
}
