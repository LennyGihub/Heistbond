// Image relay for Roblox Studio's upload_image tool.
// Studio only uploads images from trusted URLs such as http://localhost/...,
// so this serves http://localhost:8770/<commit>/<path>.png by fetching
// https://raw.githubusercontent.com/LennyGihub/game-art/<commit>/<path>.png
// Only that one public repo, only .png/.jpg, only on 127.0.0.1.
const http = require("http");
const PORT = 8770;
const REPO = "https://raw.githubusercontent.com/LennyGihub/game-art/";
const SAFE = /^\/[0-9a-f]{7,40}\/[A-Za-z0-9_\-\/]+\.(png|jpg|jpeg)$/;

http.createServer(async (req, res) => {
  const path = (req.url || "").split("?")[0];
  if (req.method !== "GET" || !SAFE.test(path) || path.includes("..")) {
    res.writeHead(404); return res.end("not found");
  }
  try {
    const r = await fetch(REPO + path.slice(1));
    if (!r.ok) { res.writeHead(r.status); return res.end("upstream " + r.status); }
    const body = Buffer.from(await r.arrayBuffer());
    res.writeHead(200, { "Content-Type": path.endsWith(".png") ? "image/png" : "image/jpeg", "Content-Length": body.length });
    res.end(body);
    console.log("served", path, body.length, "bytes");
  } catch (e) {
    res.writeHead(502); res.end("relay error"); console.log("error", path, e.message);
  }
}).listen(PORT, "127.0.0.1", () => console.log("Image relay on http://localhost:" + PORT));
