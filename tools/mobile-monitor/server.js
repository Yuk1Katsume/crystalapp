#!/usr/bin/env node
import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';
import WebSocket from 'ws';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import fs from 'fs';
import path from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Ensure temp_uploads directory exists
const TEMP_DIR = join(__dirname, 'temp_uploads');
if (!fs.existsSync(TEMP_DIR)) {
  fs.mkdirSync(TEMP_DIR, { recursive: true });
}

const PORTS = [9000, 9001, 9002, 9003];
const DISCOVERY_INTERVAL = 5000;
const POLL_INTERVAL = 1000;

// Application State
let cascades = new Map(); // Map<cascadeId, { id, cdp, metadata, snapshot, snapshotHash, css, actions, actionsHash }>
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
  await call("DOM.enable").catch(() => {});
  await new Promise(r => setTimeout(r, 600));

  return { ws, call, contexts, rootContextId: null };
}

async function evalInCDP(cdp, expression, returnByValue = true) {
  if (cdp.rootContextId) {
    try {
      const res = await cdp.call("Runtime.evaluate", { expression, returnByValue, contextId: cdp.rootContextId });
      if (res?.result && !res.result.value?.error) {
        return { value: res.result.value, result: res.result, contextId: cdp.rootContextId };
      }
    } catch (e) {
      cdp.rootContextId = null;
    }
  }

  try {
    const res = await cdp.call("Runtime.evaluate", { expression, returnByValue });
    if (res?.result && !res.result.value?.error) {
      return { value: res.result.value, result: res.result, contextId: null };
    }
  } catch (e) {}

  for (const ctx of cdp.contexts) {
    try {
      const res = await cdp.call("Runtime.evaluate", { expression, returnByValue, contextId: ctx.id });
      if (res?.result && !res.result.value?.error) {
        return { value: res.result.value, result: res.result, contextId: ctx.id };
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
                      document.querySelector('.interactive-session');
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
          css += rule.cssText + '\\n';
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
                   document.querySelector('.interactive-session');
    if (!target) return { error: 'chat container not found' };

    const clone = target.cloneNode(true);
    
    // Remove input box and overlays from snapshot
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

// Extract active review actions (Accept, Reject, Proceed, Review, changed files)
async function extractActions(cdp) {
  const SCRIPT = `(() => {
    const actions = [];
    const changedFiles = new Set();

    // 1. Scan for action buttons in conversation and side panel
    const allButtons = Array.from(document.querySelectorAll(
      '.antigravity-agent-side-panel button, #conversation button, .review-button, [aria-label*="Accept"], [aria-label*="Reject"], [aria-label*="Proceed"], [aria-label*="Review"], [aria-label*="Undo"]'
    ));

    for (const b of allButtons) {
      const txt = (b.textContent || '').trim();
      const aria = (b.getAttribute('aria-label') || '').trim();
      const lower = (txt + ' ' + aria).toLowerCase();

      if (lower.includes('accept') && !lower.includes('model')) {
        actions.push({ id: 'accept', label: txt || 'Accept', type: 'accept', aria });
      } else if (lower.includes('reject')) {
        actions.push({ id: 'reject', label: txt || 'Reject', type: 'reject', aria });
      } else if (lower.includes('proceed') || lower.includes('continue')) {
        actions.push({ id: 'proceed', label: txt || 'Proceed', type: 'proceed', aria });
      } else if (lower.includes('review') && !lower.includes('response')) {
        actions.push({ id: 'review', label: txt || 'Review Changes', type: 'review', aria });
      } else if (lower.includes('undo changes')) {
        actions.push({ id: 'undo', label: 'Undo Changes', type: 'undo', aria });
      } else if (lower.includes('load older messages')) {
        actions.push({ id: 'load_older', label: 'Load Older Messages', type: 'load_older', aria });
      }

      // Check if button text is a filename
      if (/^[\\w\\-\\.\\/\\\\]+\\.(dart|js|mjs|ts|tsx|jsx|html|css|json|yaml|yml|md|py|xml|gradle|lock)$/i.test(txt)) {
        changedFiles.add(txt);
      }
    }

    // 2. Scan for filename elements in code blocks or file links
    const fileElements = Array.from(document.querySelectorAll(
      '.antigravity-agent-side-panel a, .antigravity-agent-side-panel span, .antigravity-agent-side-panel code, .antigravity-agent-side-panel div'
    ));
    for (const el of fileElements) {
      const t = el.textContent?.trim() || '';
      if (/^[\\w\\-\\.\\/\\\\]+\\.(dart|js|mjs|ts|tsx|jsx|html|css|json|yaml|yml|md|py|xml|gradle|lock)$/i.test(t) && t.length < 60 && !t.includes('\\n')) {
        changedFiles.add(t);
      }
    }

    // Deduplicate actions by ID
    const uniqueActions = [];
    const seen = new Set();
    for (const a of actions) {
      if (!seen.has(a.id)) {
        seen.add(a.id);
        uniqueActions.push(a);
      }
    }

    return {
      actions: uniqueActions,
      changedFiles: Array.from(changedFiles).slice(0, 15)
    };
  })()`;

  const res = await evalInCDP(cdp, SCRIPT);
  return res?.value || { actions: [], changedFiles: [] };
}

// Click specific action in Antigravity IDE
async function clickActionInIDE(cdp, actionName) {
  const SCRIPT = `(() => {
    const act = "${actionName.toLowerCase()}";
    const allButtons = Array.from(document.querySelectorAll(
      '.antigravity-agent-side-panel button, #conversation button, .review-button, button[aria-label], [role="button"]'
    ));

    for (const b of allButtons) {
      const txt = (b.textContent || '').trim().toLowerCase();
      const aria = (b.getAttribute('aria-label') || '').trim().toLowerCase();
      const combined = txt + ' ' + aria;

      if (act === 'accept' && combined.includes('accept') && !combined.includes('model')) {
        b.click();
        return { ok: true, clicked: b.textContent || b.getAttribute('aria-label') };
      }
      if (act === 'reject' && combined.includes('reject')) {
        b.click();
        return { ok: true, clicked: b.textContent || b.getAttribute('aria-label') };
      }
      if ((act === 'proceed' || act === 'continue') && (combined.includes('proceed') || combined.includes('continue'))) {
        b.click();
        return { ok: true, clicked: b.textContent || b.getAttribute('aria-label') };
      }
      if (act === 'review' && combined.includes('review') && !combined.includes('response')) {
        b.click();
        return { ok: true, clicked: b.textContent || b.getAttribute('aria-label') };
      }
      if (act === 'undo' && combined.includes('undo changes')) {
        b.click();
        return { ok: true, clicked: b.textContent || b.getAttribute('aria-label') };
      }
      if (act === 'load_older' && combined.includes('load older messages')) {
        b.click();
        return { ok: true, clicked: b.textContent || b.getAttribute('aria-label') };
      }
      // Direct text match
      if (txt === act || aria === act) {
        b.click();
        return { ok: true, clicked: txt || aria };
      }
    }

    return { ok: false, reason: "Button not found for action: " + act };
  })()`;

  const res = await evalInCDP(cdp, SCRIPT);
  return res?.value || { ok: false, reason: "Evaluation failed" };
}

// Injects message with optional attached image
async function injectMessageWithImage(cdp, text, imageBase64, imageName) {
  try {
    // 1. Attach image if provided
    if (imageBase64) {
      let ext = 'png';
      if (imageBase64.startsWith('data:image/jpeg') || imageBase64.startsWith('data:image/jpg')) ext = 'jpg';
      else if (imageBase64.startsWith('data:image/gif')) ext = 'gif';
      else if (imageBase64.startsWith('data:image/webp')) ext = 'webp';

      const cleanBase64 = imageBase64.replace(/^data:image\/\w+;base64,/, '');
      const buffer = Buffer.from(cleanBase64, 'base64');
      const filename = `attach_${Date.now()}_${(imageName || 'image').replace(/[^a-zA-Z0-9_\.]/g, '')}.${ext}`;
      const tempFilePath = path.resolve(TEMP_DIR, filename);

      fs.writeFileSync(tempFilePath, buffer);

      // Find file input in Antigravity
      const fileNodeRes = await cdp.call("Runtime.evaluate", {
        expression: `document.querySelector('#antigravity\\\\.agentSidePanelInputBox input[type="file"]')`,
        returnByValue: false
      });

      if (fileNodeRes?.result?.objectId) {
        await cdp.call("DOM.setFileInputFiles", {
          files: [tempFilePath],
          objectId: fileNodeRes.result.objectId
        });
        await new Promise(r => setTimeout(r, 400));
      }

      // Schedule deletion of temporary file after a delay
      setTimeout(() => {
        try { fs.unlinkSync(tempFilePath); } catch (e) {}
      }, 5000);
    }

    // 2. Focus editor and select all text
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

    // 3. Insert text natively via CDP
    if (text) {
      try {
        await cdp.call("Input.insertText", { text });
      } catch (e) {
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
    }

    await new Promise(r => setTimeout(r, 100));

    // 4. Dispatch native Enter key event via CDP
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

    // 5. Also trigger synthetic submit / button click fallback
    const submitFallbackScript = `(() => {
      const box = document.querySelector('#antigravity\\\\.agentSidePanelInputBox');
      if (box) {
        const buttons = Array.from(box.querySelectorAll('button'));
        const sendBtn = buttons.find(b => {
          const aria = (b.getAttribute('aria-label') || '').toLowerCase();
          return (aria.includes('send') || aria.includes('enviar')) && !aria.includes('cancel');
        }) || box.querySelector('button.bg-primary');
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
        const initialActions = await extractActions(cdp);
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
          snapshotHash: initialSnap ? hashString(initialSnap.html) : null,
          actions: initialActions,
          actionsHash: hashString(JSON.stringify(initialActions))
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
      const acts = await extractActions(c.cdp);

      if (snap) {
        const hash = hashString(snap.html);
        if (hash !== c.snapshotHash) {
          c.snapshot = snap;
          c.snapshotHash = hash;
          broadcast({ type: 'snapshot_update', cascadeId: c.id });
        }
      }

      if (acts) {
        const aHash = hashString(JSON.stringify(acts));
        if (aHash !== c.actionsHash) {
          c.actions = acts;
          c.actionsHash = aHash;
          broadcast({ type: 'actions_update', cascadeId: c.id, actions: acts });
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

  // Increase payload limit to 50MB for image uploads
  app.use(express.json({ limit: '50mb' }));
  app.use(express.urlencoded({ extended: true, limit: '50mb' }));
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

  app.get('/actions/:id', async (req, res) => {
    const c = cascades.get(req.params.id);
    if (!c) return res.status(404).json({ error: 'Not found' });
    if (!c.actions) {
      c.actions = await extractActions(c.cdp);
    }
    res.json(c.actions || { actions: [], changedFiles: [] });
  });

  app.post('/click-action/:id', async (req, res) => {
    const c = cascades.get(req.params.id);
    if (!c) return res.status(404).json({ error: 'Chat not found' });

    const { action } = req.body;
    if (!action) return res.status(400).json({ error: 'Action is required' });

    console.log(`⚡ Clicking action [${action}] in [${c.metadata.chatTitle}]`);
    const result = await clickActionInIDE(c.cdp, action);
    
    // Trigger immediate action & snapshot update
    setTimeout(updateSnapshots, 300);
    res.json(result);
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

    const { message, imageBase64, imageName } = req.body;
    console.log(`📤 Sending message to [${c.metadata.chatTitle}] (image: ${!!imageBase64})`);

    const result = await injectMessageWithImage(c.cdp, message || '', imageBase64, imageName);
    if (result.ok) {
      setTimeout(updateSnapshots, 300);
      res.json({ success: true });
    } else {
      res.status(500).json(result);
    }
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