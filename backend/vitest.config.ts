import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      main: "./src/index.ts",
      miniflare: {
        d1Databases: ["DB"],
        bindings: {
          MANAGEMENT_API_TOKEN: "synthetic-management-token-at-least-32-characters",
          DESTINATION_ENCRYPTION_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
          PUBLIC_BASE_URL: "https://links.example.test",
        },
      },
    }),
  ],
});
