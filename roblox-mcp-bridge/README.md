# Roblox Studio MCP bridge (PC → cloud Claude)

Studio's MCP server is a local program (`%LOCALAPPDATA%\Roblox\mcp.bat`), so only a
Claude session running **on the PC** can start it. This bridge lets a **cloud** session
(the `Heistbond Game` environment) use the same tools, to compare it with a local session.

```
Roblox Studio ⇄ mcp.bat (stdio, ONE copy) ⇄ mcp-gateway.js :8765 (127.0.0.1, API key) ⇄ ngrok https ⇄ cloud Claude
```

## One-time setup on the PC

1. Install Node.js (for `npx`) if `npx -v` fails in a terminal.
2. Install ngrok: `winget install ngrok.ngrok`, create a free account at ngrok.com, then
   `ngrok config add-authtoken <your token>` (the token from the ngrok dashboard).
3. In the ngrok dashboard → **Domains**, claim your free static domain
   (looks like `something-something.ngrok-free.app`).
4. Open `start-bridge.bat` and set `NGROK_DOMAIN` to that domain.
5. Tell Claude the domain (not the key). Claude then adds it to the cloud environment and
   asks for the bridge key through a secure form: paste the content of
   `%USERPROFILE%\roblox-mcp-bridge-key.txt` there, never in the chat.

## Each time you want to test

1. Open Roblox Studio on your place, check **MCP Ready** (bottom-right).
2. Double-click `start-bridge.bat` (two windows open: gateway + ngrok).
3. Start a **new** cloud session on the `Heistbond Game` environment.
4. When done, close both windows: the bridge is off and nothing can reach Studio.

## Safety

- Anyone with the URL **and** the key can run Luau in your open Studio. The key stays in
  the file on your PC and in the environment's secret store; Claude never sees it.
- The gateway only listens on 127.0.0.1; the only way in is the ngrok address + key.
- Leave the bridge off when you are not testing. To change the key, delete the key file,
  start the bridge again (a new one is made) and update the secret in the environment.

## Why mcp-gateway.js (not supergateway)

`supergateway --stateful` started a new `mcp.bat` for every Claude session and every reconnect.
The copies fought over Studio's single connection, so Studio jumped between them and most calls
failed with "No Roblox Studio instances are connected" (log: `No studio available for proxy ...`,
`WebSocket error ... 10054`). `mcp-gateway.js` (plain Node, no packages) starts `mcp.bat` once,
restarts it if it dies, and shares it between all sessions. Its window logs each tool call.
