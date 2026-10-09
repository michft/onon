import { defineConfig } from "vite";
import { resolve } from "node:path";

export default defineConfig({
  publicDir: false,
  build: {
    outDir: resolve(process.env.ONON_DATA_ROOT ?? "../../.local/onon", "protomaps-trial/site"),
    emptyOutDir: true,
    rollupOptions: { input: resolve("protomaps.html") }
  }
});
