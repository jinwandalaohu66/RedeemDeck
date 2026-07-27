export interface RateLimitBinding {
  limit(input: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  DB: D1Database;
  MANAGEMENT_API_TOKEN: string;
  DESTINATION_ENCRYPTION_KEY: string;
  PUBLIC_BASE_URL: string;
  REGISTRATION_RATE_LIMITER?: RateLimitBinding;
  REDIRECT_RATE_LIMITER?: RateLimitBinding;
}

export interface LinkRow {
  id: string;
  slug: string;
  client_id: string;
  destination_ciphertext: string;
  destination_iv: string;
  destination_hash: string;
  created_at: string;
  expires_at: string | null;
  first_seen_at: string | null;
  last_seen_at: string | null;
  visit_count: number;
}
