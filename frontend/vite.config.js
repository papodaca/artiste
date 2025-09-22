import { defineConfig } from "vite"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import tailwindcss from "@tailwindcss/vite"

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    tailwindcss(),
    svelte()
  ],
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:4567",
        changeOrigin: true,
        secure: false
      },
      "/photos": {
        target: "http://localhost:4567",
        changeOrigin: true,
        secure: false
      }
    }
  }
})
