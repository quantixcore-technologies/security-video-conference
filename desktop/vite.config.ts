import { defineConfig } from "vite";

// Tauri kutadi: sobit port, clearScreen o'chirilgan
export default defineConfig({
  clearScreen: false,
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    target: "es2021",
    outDir: "dist",
  },
});
