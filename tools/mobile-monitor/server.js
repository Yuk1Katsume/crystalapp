#!/usr/bin/env node
import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';
import WebSocket from 'ws';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PORTS = [9000, 9001, 9002, 9003];
const DISCOVERY_INTERVAL = 5000;
const POLL_INTERVAL = 2000;

// Application State
let cascades = new Map(); // Map<cascadeId, { id, cdp: { ws, call, contexts, rootContextId }, metadata, snapshot, snapshotHash, css }>
let wss = null;

// --- Helpers ---

function hashString(str) {
  let hash = 0;
  if (!str) return '0';
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return hash.toString(36);
}

function getJson(url) {
  return new Promise((resolve) => {
    const req = http.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch (e) { resolve([]); }
      });
    });
    req.on('error', () => resolve([]));
    req.setTimeout(2000, () => {
      req.destroy();
      resolve([]);
    });
  });
}

// --- CDP Logic ---

async function connectCDP(url) {
  const ws = new WebSocket(url);
  await new Promise((resolve, reject) => {
    ws.on('open', resolve);
    ws.on('error', reject);
  });

  let idCounter = 1;
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = idCounter++;
    const handler = (msg) => {
      try {
        const data = JSON.parse(msg);
        if (data.id === id) {
          ws.off('message', handler);
          if (data.error) reject(data.error);
          else resolve(data.result);
        }
      } catch (e) {}
    };
    ws.on('message', handler);
    ws.send(JSON.stringify({ id, method, params }));
  });

  const contexts = [];
  ws.on('message', (msg) => {
    try {
      const data = JSON.parse(msg);
      if (data.method === 'Runtime.executionContextCreated') {
        contexts.push(data.params.context);
      } else if (data.method === 'Runtime.executionContextDestroyed') {
        const idx = contexts.findIndex(c => c.id === data.params.executionContextId);
        if (idx !== -1) contexts.splice(idx, 1);
      }
    } catch (e) {}
  });

  await call("Runtime.enable");
  await new Promise(r => setTimeout(r, 600));

  return { ws, call, contexts, rootContextId: null };
}

async function evalInCDP(cdp, expression) {
  // 1. If rootContextId is set, try it first
  if (cdp.rootContextId) {
    try {
      const res = await cdp.call("Runtime.evaluate", { expression, returnByValue: true, contextId: cdp.rootContextId });
      if (res?.result?.value && !res.result.value.error) {
        return { value: res.result.value, contextId: cdp.rootContextId };
      }
    } catch (e) {
      cdp.rootContextId = null;
    }
  }

  // 2. Try default context (no contextId specified)
  try {
    const res = await cdp.call("Runtime.evaluate", { expression, returnByValue: true });
    if (res?.result?.value && !res.result.value.error) {
      return { value: res.result.value, contextId: null };
    }
  } catch (e) {}

  // 3. Try each known sub-context
  for (const ctx of cdp.contexts) {
    try {
      const res = await cdp.call("Runtime.evaluate", { expression, returnByValue: true, contextId: ctx.id });
      if (res?.result?.value && !res.result.value.error) {
        return { value: res.result.value, contextId: ctx.id };
      }
    } catch (e) {}
  }

  return null;
}

async function extractMetadata(cdp) {
  const SCRIPT = `(() => {
    const container = document.querySelector('#conversation') ||
                      document.querySelector('.antigravity-agent-side-panel') ||
                      document.querySelector('#antigravity\\\\.agentViewContainerId') ||
                      document.getElementById('cascade') ||
                      document.querySelector('.interactive-session') ||
                      document.querySelector('[id*="chat"]');
    if (!container) return { found: false };

    let chatTitle = null;
    const possibleTitleSelectors = ['h1', 'h2', 'header', '[class*="title"]', '.monaco-pane-view .title'];
    for (const sel of possibleTitleSelectors) {
      const el = document.querySelector(sel);
      if (el && el.textContent.length > 2 && el.textContent.length < 50) {
        chatTitle = el.textContent.trim();
        break;
      }
    }

    let cleanTitle = chatTitle || document.title.replace(' - Antigravity IDE', '').trim() || 'Antigravity Chat';

    return {
      found: true,
      chatTitle: cleanTitle,
      isActive: document.hasFocus()
    };
  })()`;

  const res = await evalInCDP(cdp, SCRIPT);
  if (res?.value?.found) {
    return { ...res.value, contextId: res.contextId };
  }
  return null;
}

async function captureCSS(cdp) {
  const SCRIPT = `(() => {
    let css = '';
    for (const sheet of document.styleSheets) {
      try {
        for (const rule of sheet.cssRules) {
          let text = rule.cssText;
          css += text + '\\n';
        }
      } catch (e) {}
    }
    return { css };
  })()`;

  const res = await evalInCDP(cdp, SCRIPT);
  return res?.value?.css || '';
}

async function captureHTML(cdp) {
  const SCRIPT = `(() => {
    const target = document.querySelector('#conversation') ||
                   document.querySelector('.antigravity-agent-side-panel') ||
                   document.querySelector('#antigravity\\\\.agentViewContainerId') ||
                   document.getElementById('cascade') ||
                   document.querySelector('.interactive-session') ||
                   document.querySelector('[id*="chat"]');
    if (!target) return { error: 'chat container not found' };

    const clone = target.cloneNode(true);
    
    // Remove input box and helper overlays from snapshot
    const inputParts = clone.querySelectorAll(
      '#antigravity\\\\.agentSidePanelInputBox, [aria-label="Message input"], div[id^="cascade"] > div:last-child, .interactive-input-part, .inline-chat-overflow'
    );
    inputParts.forEach(el => {
      const box = el.closest('#antigravity\\\\.agentSidePanelInputBox') || el.closest('div[class*="rounded-2xl"]') || el;
      if (box && box !== clone) box.remove();
    });

    const bodyStyles = window.getComputedStyle(document.body);
    const containerStyles = window.getComputedStyle(target);

    return {
      html: clone.outerHTML,
      bodyBg: containerStyles.backgroundColor !== 'rgba(0, 0, 0, 0)' ? containerStyles.backgroundColor : (bodyStyles.backgroundColor || '#121212'),
      bodyColor: containerStyles.color || bodyStyles.color || '#f5f5f7'
    };
  })()`;

  const res = await evalInCDP(cdp, SCRIPT);
  return res?.value && !res.value.error ? res.value : null;
}

async function injectMessage(cdp, text) {
  try {
    // 1. Focus editor and select all text using DOM
    const focusScript = `(() => {
      const editor = document.querySelector('#antigravity\\\\.agentSidePanelInputBox [contenteditable="true"]') ||
                     document.querySelector('[aria-label="Message input"]') ||
                     document.querySelector('.antigravity-agent-side-panel [contenteditable="true"]') ||
                     document.querySelector('[contenteditable="true"]') ||
                     document.querySelector('textarea') ||
                     document.querySelector('.monaco-editor textarea');
      if (!editor) return { ok: false, reason: "No editor found" };

      editor.focus();

      if (editor.isContentEditable || editor.getAttribute('contenteditable') === 'true') {
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(editor);
        selection.removeAllRanges();
        selection.addRange(range);
      } else if (editor.select) {
        editor.select();
      }

      return { ok: true, isContentEditable: editor.isContentEditable };
    })()`;

    const focusRes = await evalInCDP(cdp, focusScript);
    if (!focusRes?.value?.ok) {
      return focusRes?.value || { ok: false, reason: 'Failed to focus editor' };
    }

    // 2. Insert text natively via CDP
    try {
      await cdp.call("Input.insertText", { text });
    } catch (e) {
      // Fallback to DOM insertText
      const fallbackScript = `(() => {
        const editor = document.querySelector('#antigravity\\\\.agentSidePanelInputBox [contenteditable="true"]') ||
                       document.querySelector('[aria-label="Message input"]');
        if (editor) {
          document.execCommand("selectAll", false, null);
          document.execCommand("insertText", false, ${JSON.stringify(text)});
          editor.dispatchEvent(new Event('input', { bubbles: true }));
        }
      })()`;
      await evalInCDP(cdp, fallbackScript);
    }

    await new Promise(r => setTimeout(r, 100));

    // 3. Dispatch native Enter key event via CDP
    await cdp.call("Input.dispatchKeyEvent", {
      type: "rawKeyDown",
      windowsVirtualKeyCode: 13,
      unmodifiedText: "\r",
      text: "\r",
      key: "Enter",
      code: "Enter"
    });
    await cdp.call("Input.dispatchKeyEvent", {
      type: "char",
      unmodifiedText: "\r",
      text: "\r",
      key: "Enter",
      code: "Enter"
    });
    await cdp.call("Input.dispatchKeyEvent", {
      type: "keyUp",
      windowsVirtualKeyCode: 13,
      key: "Enter",
      code: "Enter"
    });

    // 4. Also trigger synthetic submit / button click fallback
    const submitFallbackScript = `(() => {
      const box = document.querySelector('#antigravity\\\\.agentSidePanelInputBox');
      if (box) {
        const buttons = Array.from(box.querySelectorAll('button'));
        const sendBtn = buttons.find(b => {
          const aria = (b.getAttribute('aria-label') || '').toLowerCase();
          return (aria.includes('send') || aria.includes('enviar')) && !aria.includes('cancel');
        });
        if (sendBtn) sendBtn.click();
      }

      const editor = document.querySelector('#antigravity\\\\.agentSidePanelInputBox [contenteditable="true"]') ||
                     document.querySelector('[aria-label="Message input"]');
      if (editor) {
        editor.dispatchEvent(new KeyboardEvent('keydown', {
          key: 'Enter',
          code: 'Enter',
          keyCode: 13,
          which: 13,
          bubbles: true,
          cancelable: true
        }));
      }
      return { ok: true };
    })()`;

    await evalInCDP(cdp, submitFallbackScript);

    return { ok: true };
  } catch (err) {
    return { ok: false, reason: err.message };
  }
}

// --- Main App Logic ---

async function discover() {
  const allTargets = [];
  await Promise.all(PORTS.map(async (port) => {
    const list = await getJson(`http://127.0.0.1:${port}/json/list`);
    const valid = list.filter(t => t.type === 'page' || t.url?.includes('workbench') || t.title?.toLowerCase().includes('antigravity'));
    valid.forEach(t => allTargets.push({ ...t, port }));
  }));

  const newCascades = new Map();

  for (const target of allTargets) {
    const id = hashString(target.webSocketDebuggerUrl);

    if (cascades.has(id)) {
      const existing = cascades.get(id);
      if (existing.cdp.ws.readyState === WebSocket.OPEN) {
        const meta = await extractMetadata(existing.cdp);
        if (meta) {
          existing.metadata = { ...existing.metadata, ...meta };
          if (meta.contextId !== undefined) existing.cdp.rootContextId = meta.contextId;
          newCascades.set(id, existing);
          continue;
        }
      }
    }

    try {
      console.log(`🔌 Connecting to ${target.title || target.url}`);
      const cdp = await connectCDP(target.webSocketDebuggerUrl);
      const meta = await extractMetadata(cdp);

      if (meta) {
        if (meta.contextId !== undefined) cdp.rootContextId = meta.contextId;
        const initialSnap = await captureHTML(cdp);
        const cascade = {
          id,
          cdp,
          metadata: {
            windowTitle: target.title,
            chatTitle: meta.chatTitle || 'Antigravity Chat',
            isActive: meta.isActive
          },
          snapshot: initialSnap,
          css: await captureCSS(cdp),
          snapshotHash: initialSnap ? hashString(initialSnap.html) : null
        };
        newCascades.set(id, cascade);
        console.log(`✨ Added active chat: ${cascade.metadata.chatTitle}`);
      } else {
        cdp.ws.close();
      }
    } catch (e) {}
  }

  // Cleanup old
  for (const [id, c] of cascades.entries()) {
    if (!newCascades.has(id)) {
      console.log(`👋 Disconnected: ${c.metadata.chatTitle}`);
      try { c.cdp.ws.close(); } catch (e) {}
    }
  }

  const changed = cascades.size !== newCascades.size;
  cascades = newCascades;

  if (changed) broadcastCascadeList();
}

async function updateSnapshots() {
  await Promise.all(Array.from(cascades.values()).map(async (c) => {
    try {
      const snap = await captureHTML(c.cdp);
      if (snap) {
        const hash = hashString(snap.html);
        if (hash !== c.snapshotHash) {
          c.snapshot = snap;
          c.snapshotHash = hash;
          broadcast({ type: 'snapshot_update', cascadeId: c.id });
        }
      }
    } catch (e) {}
  }));
}

function broadcast(msg) {
  if (!wss) return;
  wss.clients.forEach(c => {
    if (c.readyState === WebSocket.OPEN) c.send(JSON.stringify(msg));
  });
}

function broadcastCascadeList() {
  const list = Array.from(cascades.values()).map(c => ({
    id: c.id,
    title: c.metadata.chatTitle || 'Antigravity Chat',
    window: c.metadata.windowTitle,
    active: c.metadata.isActive
  }));
  broadcast({ type: 'cascade_list', cascades: list });
}

// --- Server Setup ---

async function main() {
  const app = express();
  const server = http.createServer(app);
  wss = new WebSocketServer({ server });

  app.use(express.json());
  app.use(express.static(join(__dirname, 'public')));

  app.get('/cascades', (req, res) => {
    res.json(Array.from(cascades.values()).map(c => ({
      id: c.id,
      title: c.metadata.chatTitle || 'Antigravity Chat',
      active: c.metadata.isActive
    })));
  });

  app.get('/snapshot/:id', async (req, res) => {
    const c = cascades.get(req.params.id);
    if (!c) return res.status(404).json({ error: 'Not found' });
    if (!c.snapshot) {
      c.snapshot = await captureHTML(c.cdp);
    }
    if (!c.snapshot) return res.status(503).json({ error: 'No snapshot available' });
    res.json(c.snapshot);
  });

  app.get('/styles/:id', (req, res) => {
    const c = cascades.get(req.params.id);
    if (!c) return res.status(404).json({ error: 'Not found' });
    res.json({ css: c.css || '' });
  });

  app.get('/snapshot', async (req, res) => {
    const active = Array.from(cascades.values()).find(c => c.metadata.isActive) || cascades.values().next().value;
    if (!active) return res.status(503).json({ error: 'No active chat' });
    if (!active.snapshot) {
      active.snapshot = await captureHTML(active.cdp);
    }
    if (!active.snapshot) return res.status(503).json({ error: 'No snapshot' });
    res.json(active.snapshot);
  });

  app.post('/send/:id', async (req, res) => {
    const c = cascades.get(req.params.id);
    if (!c) return res.status(404).json({ error: 'Chat not found' });

    console.log(`📤 Sending message to [${c.metadata.chatTitle}]: ${req.body.message}`);
    const result = await injectMessage(c.cdp, req.body.message);
    if (result.ok) res.json({ success: true });
    else res.status(500).json(result);
  });

  wss.on('connection', () => {
    broadcastCascadeList();
  });

  const PORT = process.env.PORT || 3000;
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on http://localhost:${PORT}`);
  });

  // Start Loops
  discover();
  setInterval(discover, DISCOVERY_INTERVAL);
  setInterval(updateSnapshots, POLL_INTERVAL);
}

main();