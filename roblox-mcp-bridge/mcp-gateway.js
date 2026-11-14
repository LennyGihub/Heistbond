// Single-process MCP gateway: ONE Studio MCP (mcp.bat) shared by every Claude session.
//
// Why: supergateway --stateful starts a new mcp.bat for every MCP session / reconnect. Each copy
// fights for Studio's single connection, so Studio keeps jumping between them and every other
// call fails with "No Roblox Studio instances are connected". This gateway starts mcp.bat once,
// keeps it alive (restarts it if it dies) and multiplexes all sessions onto it by remapping
// JSON-RPC ids. Streamable HTTP, JSON responses (no SSE), API key, 127.0.0.1 only.
//
// Env: PORT (8765), KEYFILE (bridge key file), HELPER (cmd that starts Studio's mcp.bat)
const http = require("http");
const fs = require("fs");
const crypto = require("crypto");
const { spawn } = require("child_process");

const PORT = Number(process.env.PORT || 8765);
const KEY = fs.readFileSync(process.env.KEYFILE, "utf8").trim();
const HELPER = process.env.HELPER;
const CALL_TIMEOUT_MS = 10 * 60 * 1000; // generate_mesh etc. can take minutes

let child = null;
let buf = "";
let nextId = 1;
const pending = new Map(); // internal id -> { resolve }
let initResult = null; // cached result of our own initialize
let ready = null; // promise resolved when the child is initialized

function log(...a) {
  console.log(new Date().toISOString().slice(11, 19), ...a);
}

function send(msg) {
  child.stdin.write(JSON.stringify(msg) + "\n");
}

function request(method, params) {
  const id = nextId++;
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      resolve({ jsonrpc: "2.0", id, error: { code: -32001, message: "Studio MCP timed out" } });
    }, CALL_TIMEOUT_MS);
    pending.set(id, { resolve: (m) => { clearTimeout(timer); resolve(m); } });
    send({ jsonrpc: "2.0", id, method, params });
  });
}

function onChildMessage(msg) {
  if (msg.id !== undefined && (msg.result !== undefined || msg.error !== undefined)) {
    const p = pending.get(msg.id);
    if (p) {
      pending.delete(msg.id);
      p.resolve(msg);
    }
  } else if (msg.method && msg.id !== undefined) {
    // server -> client request (e.g. ping): answer it ourselves
    send({ jsonrpc: "2.0", id: msg.id, result: {} });
  } // server notifications are dropped (no SSE stream to deliver them on)
}

function startChild() {
  log("starting Studio MCP:", HELPER);
  buf = "";
  child = process.platform === "win32"
    ? spawn("cmd.exe", ["/c", HELPER], { stdio: ["pipe", "pipe", "pipe"], windowsHide: true })
    : spawn("sh", [HELPER], { stdio: ["pipe", "pipe", "pipe"] });
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    buf += chunk;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      try {
        onChildMessage(JSON.parse(line));
      } catch {
        log("child (non-JSON):", line.slice(0, 200));
      }
    }
  });
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (d) => process.stderr.write("[studio-mcp] " + d));
  child.on("exit", (code) => {
    log("Studio MCP exited with code", code, "- restarting in 2 s");
    for (const [id, p] of pending) p.resolve({ jsonrpc: "2.0", id, error: { code: -32002, message: "Studio MCP restarted" } });
    pending.clear();
    initResult = null;
    setTimeout(boot, 2000);
  });
}

function boot() {
  startChild();
  ready = request("initialize", {
    protocolVersion: "2025-03-26",
    capabilities: {},
    clientInfo: { name: "roblox-mcp-bridge", version: "2.0" },
  }).then((r) => {
    if (r.error) throw new Error(r.error.message);
    initResult = r.result;
    send({ jsonrpc: "2.0", method: "notifications/initialized" });
    log("Studio MCP ready:", JSON.stringify(initResult.serverInfo || {}));
  });
  ready.catch((e) => log("initialize failed:", e.message));
}

function authorized(req) {
  const a = req.headers["authorization"] || "";
  const x = req.headers["x-api-key"] || "";
  const token = a.startsWith("Bearer ") ? a.slice(7) : a;
  const ok = (t) => t && t.length === KEY.length && crypto.timingSafeEqual(Buffer.from(t), Buffer.from(KEY));
  return ok(token.trim()) || ok(String(x).trim());
}

async function handle(msg) {
  if (msg.method === "initialize") {
    await ready;
    return { jsonrpc: "2.0", id: msg.id, result: initResult };
  }
  if (msg.id === undefined) {
    // client notification: "initialized" was already sent by us; forward anything else
    if (msg.method && msg.method !== "notifications/initialized") send(msg);
    return null;
  }
  if (!msg.method) return null; // a client response to a server request: nothing waits for it
  await ready;
  const r = await request(msg.method, msg.params);
  return { jsonrpc: "2.0", id: msg.id, ...(r.error ? { error: r.error } : { result: r.result }) };
}

http
  .createServer((req, res) => {
    if (!req.url.startsWith("/mcp")) {
      res.writeHead(404).end();
      return;
    }
    if (!authorized(req)) {
      res.writeHead(401).end("unauthorized");
      return;
    }
    if (req.method === "DELETE") {
      res.writeHead(200).end();
      return;
    }
    if (req.method !== "POST") {
      res.writeHead(405, { Allow: "POST, DELETE" }).end();
      return;
    }
    let body = "";
    req.setEncoding("utf8");
    req.on("data", (c) => (body += c));
    req.on("end", async () => {
      let parsed;
      try {
        parsed = JSON.parse(body);
      } catch {
        res.writeHead(400).end("bad json");
        return;
      }
      const batch = Array.isArray(parsed);
      const msgs = batch ? parsed : [parsed];
      const headers = { "Content-Type": "application/json" };
      if (msgs.some((m) => m.method === "initialize")) headers["Mcp-Session-Id"] = crypto.randomUUID();
      else if (req.headers["mcp-session-id"]) headers["Mcp-Session-Id"] = req.headers["mcp-session-id"];
      try {
        const out = (await Promise.all(msgs.map(handle))).filter(Boolean);
        if (out.length === 0) {
          res.writeHead(202, headers).end();
          return;
        }
        const tool = msgs.find((m) => m.method === "tools/call");
        if (tool) log("call", tool.params && tool.params.name);
        res.writeHead(200, headers).end(JSON.stringify(batch ? out : out[0]));
      } catch (e) {
        res.writeHead(500, headers).end(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32603, message: String(e.message || e) } }));
      }
    });
  })
  .listen(PORT, "127.0.0.1", () => log("MCP gateway on http://127.0.0.1:" + PORT + "/mcp (one shared Studio MCP)"));

boot();
