import { defineConfig } from 'vitest/config';

export default defineConfig({
  build: {
    // ExcelJS is intentionally isolated behind a dynamic import; it is fetched
    // only when XLSX import/export is used rather than on initial app load.
    chunkSizeWarningLimit: 1_000,
  },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
});
