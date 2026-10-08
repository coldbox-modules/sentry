import { rmSync } from "node:fs";
rmSync("dist", { recursive: true, force: true });
import { build } from 'esbuild';
await build({ entryPoints: ['src/index.ts'], bundle: true, format: 'esm', splitting: true, outdir: 'dist/esm', target: 'es2022', minify: true });
await build({ entryPoints: ['src/script.ts'], bundle: true, format: 'iife', outfile: 'dist/sentry-box.js', target: 'es2022', minify: true });
