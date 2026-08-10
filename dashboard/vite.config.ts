import { defineConfig } from "vite";

// Das Dashboard ist eine einzelne Seite ohne Router – keine Rewrites nötig.
// `base: "./"` hält die Asset-Pfade relativ, damit der Build auch unter einem
// Unterpfad ausgeliefert werden kann (z. B. GitHub Pages).
export default defineConfig({
  base: "./",
  build: {
    outDir: "dist",
    sourcemap: true,
    target: "es2022",
  },
  server: {
    port: 5173,
  },
});