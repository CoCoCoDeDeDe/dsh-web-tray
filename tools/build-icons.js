#!/usr/bin/env node
// Build multi-size DSH whale icons from the dsh favicon SVG.
//
// Usage:
//   node tools/build-icons.js
//
// Environment:
//   DSH_PKG          path to the @deepseek-ai/dsh package (auto-detected from `dsh`)
//   DSH_WIN_APPDIR   Windows app dir in WSL form
//                    (default: /mnt/c/Users/13282/AppData/Local/DSH)
//   DSH_ICON_PREVIEW_DIR  where preview PNGs are written (default: $TMPDIR/dsh-icon-previews)
//
// Small sizes use 32-bit BMP ICO entries (best .NET/NotifyIcon compatibility);
// 256 uses a PNG entry (Explorer/shortcut icons).

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

function findDsh() {
  const attempts = [
    () => execFileSync('which', ['dsh']).toString().trim(),
    () => execFileSync('/bin/bash', ['-lc', 'command -v dsh']).toString().trim()
  ];
  for (const attempt of attempts) {
    try {
      const value = attempt();
      if (value) return value;
    } catch (_) { }
  }
  return null;
}

function detectPkg() {
  if (process.env.DSH_PKG) return process.env.DSH_PKG;
  const dshBin = findDsh();
  if (!dshBin) return null;
  try {
    const resolved = execFileSync('readlink', ['-f', dshBin]).toString().trim();
    const root = path.resolve(path.dirname(resolved), '..');
    if (fs.existsSync(path.join(root, 'package.json'))) return root;
  } catch (_) { }
  return null;
}

const PKG = detectPkg();
if (!PKG) {
  console.error('Could not locate the dsh package.');
  console.error('Set DSH_PKG to the package directory, e.g. ~/.nvm/versions/node/v24.18.0/lib/node_modules/@deepseek-ai/dsh');
  process.exit(1);
}

let sharp;
try {
  sharp = require(path.join(PKG, 'node_modules/sharp'));
} catch (err) {
  console.error('sharp was not found inside the dsh package.');
  console.error('Run this script with the same Node.js version that runs dsh (nvm use).');
  console.error(err.message);
  process.exit(1);
}

const SRC = path.join(PKG, 'node_modules/@deepseek-ai/dsh-web-frontend/dist/favicon.svg');
if (!fs.existsSync(SRC)) {
  console.error('favicon.svg not found: ' + SRC);
  process.exit(1);
}

const OUT = process.env.DSH_WIN_APPDIR || '/mnt/c/Users/13282/AppData/Local/DSH';
const previewDir = process.env.DSH_ICON_PREVIEW_DIR || path.join(os.tmpdir(), 'dsh-icon-previews');
const sizes = [16, 20, 24, 28, 32, 40, 48, 64, 128, 256];

const src = fs.readFileSync(SRC, 'utf8');
const inner = src
  .replace(/^[\s\S]*?<svg[^>]*>/, '')
  .replace(/<\/svg>[\s\S]*$/, '')
  .replace(/fill="#000"/g, 'fill="#fff"');
if (!inner.includes('fill="#fff"')) throw new Error('could not recolor whale path');

function iconSvg(size, bg) {
  const ratio = 0.78;
  const inset = (size * (1 - ratio)) / 2;
  const scale = (size * ratio) / 50;
  const rx = Math.round(size * 0.22 * 100) / 100;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">`
    + `<rect width="${size}" height="${size}" rx="${rx}" fill="${bg}"/>`
    + `<g transform="translate(${inset} ${inset}) scale(${scale})">${inner}</g>`
    + `</svg>`;
}

async function bmpEntry(png, size) {
  const { data } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const rowSize = size * 4;
  const xor = Buffer.alloc(rowSize * size);
  for (let y = 0; y < size; y++) {
    const srcRow = (size - 1 - y) * rowSize;
    for (let x = 0; x < size; x++) {
      const si = srcRow + x * 4;
      const di = y * rowSize + x * 4;
      xor[di] = data[si + 2];
      xor[di + 1] = data[si + 1];
      xor[di + 2] = data[si];
      xor[di + 3] = data[si + 3];
    }
  }
  const maskRowSize = Math.ceil(size / 32) * 4;
  const mask = Buffer.alloc(maskRowSize * size, 0);
  const header = Buffer.alloc(40);
  header.writeUInt32LE(40, 0);
  header.writeInt32LE(size, 4);
  header.writeInt32LE(size * 2, 8);
  header.writeUInt16LE(1, 12);
  header.writeUInt16LE(32, 14);
  header.writeUInt32LE(0, 16);
  header.writeUInt32LE(xor.length + mask.length, 20);
  header.writeInt32LE(0, 24);
  header.writeInt32LE(0, 28);
  header.writeUInt32LE(0, 32);
  header.writeUInt32LE(0, 36);
  return Buffer.concat([header, xor, mask]);
}

async function build(name, bg) {
  const entries = [];
  for (const size of sizes) {
    const png = await sharp(Buffer.from(iconSvg(size, bg))).png().toBuffer();
    fs.writeFileSync(path.join(previewDir, `${name}-${size}.png`), png);
    const data = size >= 256 ? png : await bmpEntry(png, size);
    entries.push({ size, data });
  }
  const n = entries.length;
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(n, 4);
  let offset = 6 + n * 16;
  const dir = [];
  for (const { size, data } of entries) {
    const e = Buffer.alloc(16);
    e.writeUInt8(size >= 256 ? 0 : size, 0);
    e.writeUInt8(size >= 256 ? 0 : size, 1);
    e.writeUInt8(0, 2);
    e.writeUInt8(0, 3);
    e.writeUInt16LE(1, 4);
    e.writeUInt16LE(32, 6);
    e.writeUInt32LE(data.length, 8);
    e.writeUInt32LE(offset, 12);
    offset += data.length;
    dir.push(e);
  }
  const ico = Buffer.concat([header, ...dir, ...entries.map(e => e.data)]);
  const dest = path.join(OUT, `${name}.ico`);
  fs.writeFileSync(dest, ico);
  console.log(`${dest}  ${ico.length} bytes  (BMP 16-128, PNG 256)`);
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  fs.mkdirSync(previewDir, { recursive: true });
  console.log('dsh package: ' + PKG);
  console.log('output dir:  ' + OUT);
  await build('dsh-web-running', '#4D6BFE');
  await build('dsh-web-stopped', '#64748B');
})();
