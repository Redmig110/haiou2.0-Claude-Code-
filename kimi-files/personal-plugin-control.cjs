const fs = require('fs');
const crypto = require('crypto');

const [action, statePath, wsModulePath, pluginId = 'seagull-2'] = process.argv.slice(2);
if (!action || !statePath || !wsModulePath) {
  console.error('usage: node personal-plugin-control.cjs <install|remove|status> <runner.state.json> <ws-module-path> [plugin-id]');
  process.exit(2);
}
if (!['install', 'remove', 'status', 'set-override', 'restore-override'].includes(action)) {
  throw new Error('Unsupported action: ' + action);
}
if (['install', 'remove', 'status'].includes(action) && !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(pluginId)) {
  throw new Error('Invalid plugin id: ' + pluginId);
}
if (['set-override', 'restore-override'].includes(action) && !fs.existsSync(pluginId)) {
  throw new Error('System prompt file not found: ' + pluginId);
}

const WebSocket = require(wsModulePath);
const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
const endpoint = state.control && state.control.endpoint;
if (!endpoint || !endpoint.url || !endpoint.auth || !endpoint.auth.token) {
  throw new Error('Daimon control endpoint is unavailable. Start Kimi Work first.');
}

const controlUrl = new URL(endpoint.url);
const loopbackHosts = new Set(['127.0.0.1', 'localhost', '::1', '[::1]']);
if (controlUrl.protocol !== 'ws:' || !loopbackHosts.has(controlUrl.hostname) || controlUrl.pathname !== '/control') {
  throw new Error('Refusing non-loopback Daimon endpoint: ' + controlUrl.origin + controlUrl.pathname);
}

const ws = new WebSocket(controlUrl, {
  headers: { Authorization: 'Bearer ' + endpoint.auth.token },
  handshakeTimeout: 5000,
  maxPayload: 1024 * 1024,
});
const pending = new Map();
let sequence = 1;

function rejectAll(error) {
  for (const [id, entry] of pending) {
    clearTimeout(entry.timer);
    pending.delete(id);
    entry.reject(error);
  }
}

function request(method, params = {}) {
  return new Promise((resolve, reject) => {
    if (ws.readyState !== WebSocket.OPEN) {
      reject(new Error('Daimon control socket is not open'));
      return;
    }
    const id = sequence++;
    const timer = setTimeout(() => {
      pending.delete(String(id));
      reject(new Error(method + ' timed out'));
    }, 15000);
    pending.set(String(id), { resolve, reject, timer });
    const payload = JSON.stringify({ jsonrpc: '2.0', id, method, params });
    try {
      ws.send(payload, (error) => {
        if (!error) return;
        const entry = pending.get(String(id));
        if (!entry) return;
        pending.delete(String(id));
        clearTimeout(entry.timer);
        entry.reject(error);
      });
    } catch (error) {
      pending.delete(String(id));
      clearTimeout(timer);
      reject(error);
    }
  });
}

ws.on('message', (raw) => {
  let message;
  try {
    message = JSON.parse(raw.toString());
  } catch (error) {
    rejectAll(new Error('Malformed Daimon control frame: ' + error.message));
    ws.terminate();
    return;
  }
  if (!message || message.jsonrpc !== '2.0' || message.id === undefined) return;
  const entry = pending.get(String(message.id));
  if (entry) {
    pending.delete(String(message.id));
    clearTimeout(entry.timer);
    if (message.error) entry.reject(new Error(message.error.message || JSON.stringify(message.error)));
    else entry.resolve(message.result);
  }
});

ws.on('open', async () => {
  try {
    let result;
    if (action === 'install') {
      result = await request('kimiPlugin.personal.installPlugin', { id: pluginId });
      let reload;
      let reloadError;
      try { reload = await request('kimiPlugin.reloadActiveSessions', {}); }
      catch (error) { reloadError = error.message; }
      const ok = reloadError === undefined;
      console.log(JSON.stringify({ ok, partialSuccess: !ok, action, plugin: result, reload, reloadError }, null, 2));
      if (!ok) process.exitCode = 3;
    } else if (action === 'remove') {
      result = await request('kimiPlugin.personal.removePlugin', { id: pluginId });
      let reload;
      let reloadError;
      try { reload = await request('kimiPlugin.reloadActiveSessions', {}); }
      catch (error) { reloadError = error.message; }
      const ok = reloadError === undefined;
      console.log(JSON.stringify({ ok, partialSuccess: !ok, action, plugin: result, reload, reloadError }, null, 2));
      if (!ok) process.exitCode = 3;
    } else if (action === 'status') {
      const list = await request('kimiPlugin.personal.listPlugins', {});
      if (!Array.isArray(list)) throw new Error('Invalid personal plugin list response');
      result = list.find((item) => item.id === pluginId) || null;
      console.log(JSON.stringify({ ok: true, action, plugin: result }, null, 2));
    } else if (action === 'set-override') {
      const content = fs.readFileSync(pluginId, 'utf8');
      result = await request('prompts.systemPromptOverride.set', { content });
      console.log(JSON.stringify({ ok: true, action, bytes: Buffer.byteLength(content), state: { mode: result.mode, enabled: result.enabled, sha256: result.sha256, utf8Bytes: result.utf8Bytes, effect: result.effect } }, null, 2));
    } else if (action === 'restore-override') {
      const content = fs.readFileSync(pluginId, 'utf8');
      const expectedSha = crypto.createHash('sha256').update(content).digest('hex');
      const current = await request('prompts.systemPromptOverride.get', {});
      if (!current.enabled) {
        console.log(JSON.stringify({ ok: true, action, restored: false, reason: 'override-not-enabled' }, null, 2));
      } else if (current.sha256 !== expectedSha) {
        console.log(JSON.stringify({ ok: true, action, restored: false, reason: 'override-owned-by-user', currentSha256: current.sha256 }, null, 2));
      } else {
        result = await request('prompts.systemPromptOverride.restoreDefault', {});
        console.log(JSON.stringify({ ok: true, action, restored: true, state: result }, null, 2));
      }
    }
    ws.close();
    const closeTimer = setTimeout(() => ws.terminate(), 1000);
    closeTimer.unref();
  } catch (error) {
    console.error(error.stack || String(error));
    ws.close();
    process.exitCode = 1;
  }
});

ws.on('error', (error) => {
  rejectAll(error);
  console.error(error.stack || String(error));
  process.exitCode = 1;
});

ws.on('close', () => {
  if (pending.size > 0) rejectAll(new Error('Daimon control socket closed before the response arrived'));
});
