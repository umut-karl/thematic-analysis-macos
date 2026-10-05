import { execFileSync, spawnSync } from 'node:child_process';
import { createReadStream, existsSync } from 'node:fs';
import { stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const production = process.env.NODE_ENV === 'production';
const port = Number(process.env.PORT || 4173);
const host = process.env.HOST || '127.0.0.1';
const maximumFileSize = 25 * 1024 * 1024;
const supportedExtensions = new Set(['mp3', 'mp4', 'mpeg', 'mpga', 'm4a', 'wav', 'webm', 'flac', 'ogg']);
const bundleID = 'app.thematicanalysis.macos';
const preferenceKey = 'openAIAPIKey';
const keychainService = 'com.umutkarlikli.ThematicAnalysis.openai';
const keychainAccount = 'OpenAIAPIKey';

let vite;
if (!production) {
  const { createServer: createViteServer } = await import('vite');
  vite = await createViteServer({ root, server: { middlewareMode: true }, appType: 'spa' });
}

function readAPIKey() {
  const environmentKey = String(process.env.OPENAI_API_KEY || '').trim();
  if (environmentKey) return { key: environmentKey, source: 'environment' };
  if (process.platform !== 'darwin') return { key: '', source: null };
  try {
    const key = execFileSync('/usr/bin/security', ['find-generic-password', '-s', keychainService, '-a', keychainAccount, '-w'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 2_000,
    }).trim();
    if (key) return { key, source: 'native-settings' };
  } catch { /* fall back to the legacy native preference */ }
  try {
    const key = execFileSync('/usr/bin/defaults', ['read', bundleID, preferenceKey], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 2_000,
    }).trim();
    return { key, source: key ? 'native-settings' : null };
  } catch {
    return { key: '', source: null };
  }
}

function json(response, status, value) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(JSON.stringify(value));
}

function applySecurityHeaders(response) {
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
}

async function readUpload(request) {
  const advertised = Number(request.headers['content-length'] || 0);
  if (advertised > maximumFileSize) throw Object.assign(new Error('Ses dosyası 25 MB sınırını aşıyor.'), { status: 413 });
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximumFileSize) throw Object.assign(new Error('Ses dosyası 25 MB sınırını aşıyor.'), { status: 413 });
    chunks.push(chunk);
  }
  if (!size) throw Object.assign(new Error('Ses dosyası boş.'), { status: 400 });
  return Buffer.concat(chunks);
}

async function readSmallBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16 * 1024) throw Object.assign(new Error('İstek gövdesi çok büyük.'), { status: 413 });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

async function saveAPIKey(request, response) {
  if (process.platform !== 'darwin') return json(response, 501, { error: 'Bu sistemde anahtarı sunucunun OPENAI_API_KEY ortam değişkeninde tanımlayın.' });
  try {
    const payload = JSON.parse(await readSmallBody(request));
    const key = typeof payload?.apiKey === 'string' ? payload.apiKey.trim() : '';
    if (key.length < 20 || /[\r\n]/.test(key)) throw Object.assign(new Error('Geçerli bir OpenAI API anahtarı girin.'), { status: 400 });
    const result = spawnSync('/usr/bin/security', ['add-generic-password', '-U', '-a', keychainAccount, '-s', keychainService, '-w'], {
      input: `${key}\n`, encoding: 'utf8', stdio: ['pipe', 'ignore', 'pipe'], timeout: 10_000,
    });
    if (result.status !== 0) throw new Error(result.stderr?.trim() || 'API anahtarı Keychain’e kaydedilemedi.');
    try { execFileSync('/usr/bin/defaults', ['delete', bundleID, preferenceKey], { stdio: 'ignore', timeout: 2_000 }); } catch { /* no legacy value */ }
    return json(response, 200, { configured: true, source: 'native-settings' });
  } catch (error) {
    return json(response, Number(error?.status) || 500, { error: error instanceof Error ? error.message : 'API anahtarı kaydedilemedi.' });
  }
}

function deleteAPIKey(response) {
  if (process.platform !== 'darwin') return json(response, 501, { error: 'Bu sistemde OPENAI_API_KEY ortam değişkenini sunucu ortamından kaldırın.' });
  try { execFileSync('/usr/bin/security', ['delete-generic-password', '-s', keychainService, '-a', keychainAccount], { stdio: 'ignore', timeout: 5_000 }); } catch { /* already absent */ }
  try { execFileSync('/usr/bin/defaults', ['delete', bundleID, preferenceKey], { stdio: 'ignore', timeout: 2_000 }); } catch { /* already absent */ }
  return json(response, 200, { configured: false, source: null });
}

function uploadMetadata(request) {
  let filename = 'audio.webm';
  try {
    const encoded = String(request.headers['x-file-name-base64'] || '');
    if (encoded) filename = Buffer.from(encoded, 'base64').toString('utf8');
  } catch { /* use fallback */ }
  filename = filename.replace(/[\r\n/\\"]/g, '-').slice(0, 240);
  const extension = extname(filename).slice(1).toLowerCase();
  if (!supportedExtensions.has(extension)) {
    throw Object.assign(new Error(`${extension.toUpperCase() || 'DOSYA'} biçimi desteklenmiyor.`), { status: 415 });
  }
  return { filename, extension, type: String(request.headers['content-type'] || 'application/octet-stream').split(';')[0] };
}

async function transcribe(request, response) {
  const { key } = readAPIKey();
  if (!key) return json(response, 401, { error: 'OpenAI API anahtarı bulunamadı. Native uygulamadaki Ayarlar bölümünden kaydedin veya sunucuda OPENAI_API_KEY tanımlayın.' });
  try {
    const metadata = uploadMetadata(request);
    const audio = await readUpload(request);
    const form = new FormData();
    form.append('model', 'gpt-4o-transcribe-diarize');
    form.append('response_format', 'diarized_json');
    form.append('chunking_strategy', 'auto');
    form.append('language', 'tr');
    form.append('file', new Blob([audio], { type: metadata.type }), metadata.filename);
    const upstream = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST', headers: { Authorization: `Bearer ${key}` }, body: form,
      signal: AbortSignal.timeout(15 * 60 * 1_000),
    });
    const payload = await upstream.json().catch(() => null);
    if (!upstream.ok) {
      const upstreamMessage = payload?.error?.message || `OpenAI isteği başarısız (HTTP ${upstream.status}).`;
      return json(response, upstream.status, { error: upstreamMessage });
    }
    const segments = Array.isArray(payload?.segments) ? payload.segments.filter((item) =>
      item && typeof item.speaker === 'string' && Number.isFinite(item.start) && Number.isFinite(item.end) && typeof item.text === 'string' && item.text.trim(),
    ).map((item) => ({ speaker: item.speaker, start: item.start, end: item.end, text: item.text.trim() })) : [];
    if (!segments.length) return json(response, 502, { error: 'OpenAI geçerli, konuşmacılı bir transkript döndürmedi.' });
    return json(response, 200, { model: 'gpt-4o-transcribe-diarize', segments });
  } catch (error) {
    return json(response, Number(error?.status) || 500, { error: error instanceof Error ? error.message : 'Ses transkripsiyonu tamamlanamadı.' });
  }
}

const mimeTypes = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

async function serveProduction(request, response) {
  const url = new URL(request.url || '/', 'http://local');
  const requested = url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname.slice(1));
  const safePath = normalize(requested).replace(/^(\.\.(\/|\\|$))+/, '');
  let filePath = join(root, 'dist', safePath);
  if (!existsSync(filePath) || !(await stat(filePath)).isFile()) filePath = join(root, 'dist', 'index.html');
  response.writeHead(200, { 'Content-Type': mimeTypes[extname(filePath)] || 'application/octet-stream' });
  createReadStream(filePath).pipe(response);
}

const server = createServer(async (request, response) => {
  applySecurityHeaders(response);
  const url = new URL(request.url || '/', 'http://local');
  if (request.method === 'GET' && url.pathname === '/api/openai/status') {
    const status = readAPIKey();
    return json(response, 200, { configured: Boolean(status.key), source: status.source });
  }
  if (request.method === 'PUT' && url.pathname === '/api/openai/key' && request.headers['x-tematik-analiz'] === 'local') return saveAPIKey(request, response);
  if (request.method === 'DELETE' && url.pathname === '/api/openai/key' && request.headers['x-tematik-analiz'] === 'local') return deleteAPIKey(response);
  if (request.method === 'POST' && url.pathname === '/api/openai/transcriptions') return transcribe(request, response);
  if (url.pathname.startsWith('/api/')) return json(response, 404, { error: 'API yolu bulunamadı.' });
  if (production) return serveProduction(request, response);
  return vite.middlewares(request, response, (error) => {
    if (error) vite.ssrFixStacktrace(error);
    json(response, 500, { error: error?.message || 'Web sunucusu hatası.' });
  });
});

server.listen(port, host, () => {
  process.stdout.write(`Tematik Analiz web: http://${host}:${port}/\n`);
});
