import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // ponytail: one ~190 KB (gzip) app chunk (React, Radix, Framer Motion). Lazy-load the sheets if first load gets slow.
  build: { chunkSizeWarningLimit: 700 },
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
});
