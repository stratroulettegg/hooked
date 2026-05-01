// @ts-check
import { defineConfig } from 'astro/config';
import tailwind from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://hooked-fangtagebuch.app',
  trailingSlash: 'never',
  build: {
    assets: '_assets',
    inlineStylesheets: 'auto',
  },
  vite: {
    plugins: [tailwind()],
  },
  integrations: [
    sitemap({
      filter: (page) => !page.includes('/404'),
    }),
  ],
});
