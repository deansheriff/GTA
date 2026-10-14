import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
import { VitePWA } from 'vite-plugin-pwa';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  // Relative base so the build works from any static host or sub-path.
  base: './',
  resolve: {
    alias: {
      // Use shared sources directly in dev and build; no separate build step needed.
      '@nsl/shared': fileURLToPath(new URL('../../packages/shared/src/index.ts', import.meta.url)),
    },
  },
  plugins: [
    preact(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      includeAssets: ['icon.svg'],
      manifest: {
        name: 'Naija Street Life',
        short_name: 'Naija Street',
        description: 'Naija Street Life: a Nigerian life-sim and comedy-crime game. Story mode: Up NEPA!',
        lang: 'en-NG',
        start_url: './',
        scope: './',
        display: 'standalone',
        orientation: 'any',
        background_color: '#1b1430',
        theme_color: '#f2b705',
        icons: [{ src: 'icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' }],
      },
      workbox: {
        // Cache the app shell and art forever (versioned by hash); never cache API calls.
        globPatterns: ['**/*.{js,css,html,svg,webp,png,json,woff2}'],
        maximumFileSizeToCacheInBytes: 3 * 1024 * 1024,
        navigateFallbackDenylist: [/^\/api\//],
      },
    }),
  ],
  build: {
    target: 'es2022',
    sourcemap: true,
    chunkSizeWarningLimit: 1600,
    rollupOptions: {
      output: {
        // Keep Phaser in its own long-lived cached chunk.
        manualChunks: (id) => (id.includes('node_modules/phaser') ? 'phaser' : undefined),
      },
    },
  },
  server: { port: 5173, host: true },
});
