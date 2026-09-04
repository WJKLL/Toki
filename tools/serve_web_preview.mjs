// tools/serve_web_preview.mjs — 本地静态预览服务器（零依赖，仅 Node 标准库）
// 用途：把 build/web 产物以静态站点方式提供（对应 Web 预览），
//       支持 SPA 回退（未知路径 → index.html，配合 go_router 路径路由）。
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = normalize(join(fileURLToPath(new URL('.', import.meta.url)), '..', 'build', 'web'));
const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? '127.0.0.1';

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};

createServer(async (req, res) => {
  try {
    let pathname = decodeURIComponent(new URL(req.url, `http://${req.headers.host}`).pathname);
    if (pathname === '/') pathname = '/index.html';
    const filePath = normalize(join(root, pathname));
    // 防目录穿越
    if (!filePath.startsWith(root)) {
      res.writeHead(403).end('Forbidden');
      return;
    }
    let target = filePath;
    try {
      const s = await stat(filePath);
      if (s.isDirectory()) target = join(filePath, 'index.html');
    } catch { /* fallthrough to SPA fallback */ }
    try {
      const data = await readFile(target);
      const type = mime[extname(target).toLowerCase()] ?? 'application/octet-stream';
      res.writeHead(200, {
        'Content-Type': type,
        'Cache-Control': type.startsWith('text/html') ? 'no-cache' : 'public, max-age=3600',
      });
      res.end(data);
    } catch {
      // SPA 回退：路径路由（R-02 ~ R-09）刷新/直达一律回落到 index.html
      const data = await readFile(join(root, 'index.html'));
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' });
      res.end(data);
    }
  } catch (err) {
    res.writeHead(500).end(String(err));
  }
}).listen(port, host, () => {
  console.log(`[preview] 箱具工 Web 预览已就绪: http://${host}:${port}`);
  console.log(`[preview] 静态根目录: ${root}`);
});
