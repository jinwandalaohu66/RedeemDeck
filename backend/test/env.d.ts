declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    MANAGEMENT_API_TOKEN: string;
    DESTINATION_ENCRYPTION_KEY: string;
    PUBLIC_BASE_URL: string;
  }
}
