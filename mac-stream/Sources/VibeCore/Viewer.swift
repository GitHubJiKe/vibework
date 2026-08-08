/// 内嵌在服务器里的远程控制页（iPhone Safari / 任意浏览器）。
/// __TOKEN_REQUIRED__ 是占位符，服务器会根据是否设置口令替换成 true/false。
public let viewerHTML = """
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="VibePilot">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<link rel="manifest" href="/manifest.json">
<link rel="apple-touch-icon" href="/icon-180.png">
<title>VibePilot · 远程控制</title>
<style>
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; font-family: -apple-system, "PingFang SC", sans-serif; touch-action: manipulation; }
  #stage { position: fixed; inset: 0 0 138px 0; display: flex; align-items: center; justify-content: center; background: #000; }
  #view { max-width: 100%; max-height: 100%; object-fit: contain; pointer-events: none; }
  #view { transition: transform .15s ease; }
  #touchpad { position: absolute; inset: 0; touch-action: none; }
  #status { position: fixed; left: 10px; top: 10px; padding: 5px 10px; border-radius: 6px; background: rgba(0,0,0,.6); color: #fff; font-size: 12px; pointer-events: none; z-index: 5; max-width: 75%; }
  #appbar { position: fixed; top: 8px; left: 50%; transform: translateX(-50%); z-index: 6; display: none; gap: 6px; max-width: 82%; overflow-x: auto; background: rgba(0,0,0,.6); border: 1px solid #333; border-radius: 10px; padding: 4px; scrollbar-width: none; }
  #appbar::-webkit-scrollbar { display: none; }
  #appbar button { height: 30px; border-radius: 7px; border: 1px solid #444; background: #222; color: #fff; font-size: 13px; padding: 0 10px; white-space: nowrap; flex: 0 0 auto; }
  #appbar button.active { background: #3a6ea5; border-color: #3a6ea5; }
  #controls { position: fixed; left: 0; right: 0; bottom: 0; height: 138px; background: #111; border-top: 1px solid #333; padding: 8px; z-index: 10; display: flex; flex-direction: column; gap: 8px; }
  .row { display: flex; gap: 6px; align-items: center; }
  #keys { overflow-x: auto; -webkit-overflow-scrolling: touch; scrollbar-width: none; }
  #keys::-webkit-scrollbar { display: none; }
  #keys button { flex: 0 0 auto; min-width: 46px; height: 40px; border-radius: 8px; border: 1px solid #444; background: #222; color: #fff; font-size: 15px; }
  #keys button:active { background: #3a6ea5; }
  #text { flex: 1; min-width: 0; height: 40px; border-radius: 8px; border: 1px solid #444; background: #1a1a1a; color: #fff; padding: 0 10px; font-size: 16px; }
  #typing button { flex: 0 0 auto; height: 40px; border-radius: 8px; border: 1px solid #444; background: #222; color: #fff; font-size: 16px; padding: 0 10px; }
  #typing button:active { background: #3a6ea5; }
  #typing button:disabled { opacity: .5; }
  #hint { color: #999; font-size: 11px; text-align: center; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  #controls, #controls button, #controls input { touch-action: manipulation; }
  #login { position: fixed; inset: 0; z-index: 100; background: rgba(0,0,0,.92); display: none; align-items: center; justify-content: center; }
  #login .box { width: 280px; padding: 24px; border-radius: 14px; background: #1a1a1a; border: 1px solid #333; }
  #login h2 { margin: 0 0 12px; color: #fff; font-size: 18px; text-align: center; }
  #login input { width: 100%; height: 42px; border-radius: 8px; border: 1px solid #444; background: #111; color: #fff; padding: 0 10px; font-size: 16px; margin-bottom: 10px; }
  #login button { width: 100%; height: 42px; border-radius: 8px; border: none; background: #3a6ea5; color: #fff; font-size: 16px; }
  #loginErr { color: #ff6b6b; font-size: 12px; margin-top: 8px; min-height: 16px; }
  #aiModal { position: fixed; inset: 0; z-index: 200; background: rgba(0,0,0,.94); display: none; flex-direction: column; padding: 14px; }
  #aiModal .box { display: flex; flex-direction: column; flex: 1; min-height: 0; background: #1a1a1a; border: 1px solid #333; border-radius: 12px; padding: 14px; }
  #aiModal h2 { margin: 0 0 10px; color: #fff; font-size: 16px; text-align: center; }
  #aiModal textarea { flex: 1; min-height: 0; width: 100%; resize: none; border-radius: 8px; border: 1px solid #444; background: #111; color: #fff; padding: 10px; font-size: 15px; line-height: 1.55; -webkit-appearance: none; }
  #aiModal .row { display: flex; gap: 8px; margin-top: 12px; }
  #aiModal .row button { flex: 1; height: 44px; border-radius: 8px; border: none; font-size: 16px; }
  #aiCancel { background: #333; color: #fff; }
  #aiSend { background: #3a6ea5; color: #fff; }
</style>
</head>
<body>
<div id="login">
  <div class="box">
    <h2>VibePilot</h2>
    <input id="token" type="password" placeholder="请输入访问口令" autocomplete="off">
    <button id="loginBtn">连接</button>
    <div id="loginErr"></div>
  </div>
</div>
<div id="aiModal">
  <div class="box">
    <h2>编辑内容 · 确认后发送</h2>
    <textarea id="aiText" spellcheck="false" autocomplete="off" autocapitalize="off" autocorrect="off"></textarea>
    <div class="row">
      <button id="aiCancel">取消</button>
      <button id="aiSend">确认并发送</button>
    </div>
  </div>
</div>
<div id="stage">
  <img id="view" alt="">
  <div id="touchpad"></div>
</div>
<div id="status">连接中…</div>
<div id="appbar"></div>
<div id="controls">
  <div id="keys" class="row">
    <button data-scroll="0,-1" title="向上滚动（双击=顶部）">▲</button>
    <button data-scroll="-1,0" title="向左滚动">◀</button>
    <button data-scroll="1,0" title="向右滚动">▶</button>
    <button data-scroll="0,1" title="向下滚动（双击=底部）">▼</button>
    <button data-key="tab" title="Tab：补全 / 缩进">⇥</button>
    <button data-key="esc" title="Esc：取消 / 退出">⎋</button>
    <button data-key="backspace" title="清空输入框">⌫</button>
    <button id="zoom" title="画面缩放（放大聚焦窗口中心）">🔍</button>
  </div>
  <div id="typing" class="row">
    <input id="text" placeholder="输入或说出内容" autocomplete="off" autocapitalize="off" autocorrect="off" enterkeyhint="send">
    <button id="edit" title="全屏编辑输入内容">📝</button>
    <button id="ai" title="AI 优化文本">✨</button>
    <button id="send">发送</button>
    <button id="gear" title="DeepSeek Key">⚙</button>
  </div>
  <div id="hint">拖动=移动光标 · 双指=滚动 · ▲▼◀▶=滚动（双击▲▼=滚到顶/底） · 📝=全屏编辑</div>
</div>
<script>
(() => {
  const view = document.getElementById('view');
  const touchpad = document.getElementById('touchpad');
  const status = document.getElementById('status');
  const textInput = document.getElementById('text');
  const sendBtn = document.getElementById('send');
  const editBtn = document.getElementById('edit');
  const aiBtn = document.getElementById('ai');
  const gearBtn = document.getElementById('gear');
  const login = document.getElementById('login');
  const aiModal = document.getElementById('aiModal');
  const aiText = document.getElementById('aiText');
  const aiCancelBtn = document.getElementById('aiCancel');
  const aiSendBtn = document.getElementById('aiSend');
  const zoomBtn = document.getElementById('zoom');
  const appbar = document.getElementById('appbar');
  const tokenInput = document.getElementById('token');
  const loginBtn = document.getElementById('loginBtn');
  const loginErr = document.getElementById('loginErr');

  // 服务端注入：是否需要访问口令
  const TOKEN_REQUIRED = __TOKEN_REQUIRED__;
  // 服务端注入：已加载的应用列表（多应用时显示切换栏）
  const APPS = __APPS__;
  let authToken = '';
  try { authToken = localStorage.getItem('vibepilot_token') || ''; } catch (e) {}

  let ws = null;
  let shownUrl = null;
  let frames = 0;
  let lastFrameAt = 0;
  let lastMoveSentAt = 0;
  let pendingMove = null;
  let lastTapAt = 0;
  let oneFinger = null;
  let twoFinger = null;
  let loginVisible = false;
  let aiLoading = false;
  let aiTimeout = null;
  let currentApp = 0;
  const ZOOM_STEPS = [1, 1.5, 2.5];
  let zoomStep = 0;

  // 多应用切换栏
  function renderAppBar() {
    if (!Array.isArray(APPS) || APPS.length < 2) return;
    appbar.style.display = 'flex';
    APPS.forEach((name, i) => {
      const b = document.createElement('button');
      b.textContent = name;
      if (i === currentApp) b.classList.add('active');
      b.addEventListener('click', () => {
        if (i === currentApp) return;
        send({ type: 'switch', index: i });
        status.textContent = '正在切换到 ' + name + '…';
      });
      appbar.appendChild(b);
    });
  }
  function highlightApp(index) {
    currentApp = index;
    [...appbar.children].forEach((b, i) => b.classList.toggle('active', i === index));
  }
  renderAppBar();

  // —— 连接与登录 ——
  function connect() {
    if (loginVisible) return;
    if (TOKEN_REQUIRED && !authToken) { showLogin(''); return; }
    const proto = location.protocol === 'https:' ? 'wss://' : 'ws://';
    let url = proto + location.host + '/stream';
    if (TOKEN_REQUIRED) url += '?token=' + encodeURIComponent(authToken);
    ws = new WebSocket(url);
    ws.binaryType = 'blob';
    ws.onopen = () => { status.textContent = '已连接'; send({ type: 'getkey' }); };
    ws.onclose = (e) => {
      status.textContent = '连接断开，1 秒后重连…';
      if (aiLoading) { clearTimeout(aiTimeout); setAiLoading(false); }
      if (TOKEN_REQUIRED && e.code === 1006) showLogin('口令无效或未输入，请重新输入');
      setTimeout(connect, 1000);
    };
    ws.onerror = () => { try { ws.close(); } catch (e) {} };
    ws.onmessage = (e) => {
      if (typeof e.data === 'string') { handleServerMessage(e.data); return; }
      lastFrameAt = Date.now();
      const url = URL.createObjectURL(e.data);
      const previous = shownUrl;
      shownUrl = url;
      view.onload = () => { if (previous) URL.revokeObjectURL(previous); frames += 1; };
      view.src = url;
    };
  }

  function showLogin(msg) {
    loginVisible = true;
    login.style.display = 'flex';
    if (msg) loginErr.textContent = msg;
    tokenInput.focus();
  }

  function doLogin() {
    const t = tokenInput.value.trim();
    if (!t) { loginErr.textContent = '请输入口令'; return; }
    authToken = t;
    try { localStorage.setItem('vibepilot_token', t); } catch (e) {}
    login.style.display = 'none';
    loginVisible = false;
    loginErr.textContent = '';
    connect();
  }

  loginBtn.addEventListener('click', doLogin);
  tokenInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') doLogin(); });
  if (TOKEN_REQUIRED && !authToken) showLogin('');

  function handleServerMessage(s) {
    let m; try { m = JSON.parse(s); } catch (e) { return; }
    if (m.type === 'ai_result') {
      clearTimeout(aiTimeout);
      setAiLoading(false);
      if (m.ok) openEditor(m.text);
      else status.textContent = 'AI 优化失败：' + (m.error || '未知错误');
    } else if (m.type === 'key_status') {
      status.textContent = m.hasKey ? 'DeepSeek Key 已配置' : '未配置 DeepSeek Key（点 ⚙ 设置）';
    } else if (m.type === 'switch_ok') {
      if (m.ok) {
        highlightApp(m.index);
        status.textContent = '已切换到 ' + (APPS[m.index] || ('应用 ' + m.index));
      } else {
        status.textContent = '切换失败：' + (m.error || '未知错误');
      }
    }
  }

  function send(obj) {
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
  }

  function contentRect() {
    const r = view.getBoundingClientRect();
    const iw = view.naturalWidth || 16;
    const ih = view.naturalHeight || 9;
    const s = Math.min(r.width / iw, r.height / ih);
    const w = iw * s, h = ih * s;
    return { left: r.left + (r.width - w) / 2, top: r.top + (r.height - h) / 2, width: w, height: h };
  }

  function norm(clientX, clientY) {
    const r = contentRect();
    return {
      x: Math.max(0, Math.min(1, (clientX - r.left) / r.width)),
      y: Math.max(0, Math.min(1, (clientY - r.top) / r.height))
    };
  }

  function sendMouse(action, p) {
    send({ type: 'mouse', action: action, x: p.x, y: p.y });
  }

  function sendMove(clientX, clientY) {
    pendingMove = norm(clientX, clientY);
    const now = Date.now();
    if (now - lastMoveSentAt >= 24) { sendMouse('move', pendingMove); lastMoveSentAt = now; }
  }

  // 单指快速甩动 = 滚动（带惯性）：像手机 App 那样刷内容。
  // 慢速拖动仍是移动光标；甩动方向与 iOS 原生一致（手指上滑=看下方内容）。
  let flingTimer = null;
  function flingScroll(vx, vy) {
    if (flingTimer) { clearInterval(flingTimer); flingTimer = null; }
    let sx = -vx, sy = -vy;
    flingTimer = setInterval(() => {
      const px = sx * 0.02, py = sy * 0.02; // 20ms 内的位移
      if (Math.abs(px) < 1.5 && Math.abs(py) < 1.5) {
        clearInterval(flingTimer); flingTimer = null;
        return;
      }
      send({ type: 'scroll', dx: px / 40, dy: py / 40 });
      sx *= 0.88; sy *= 0.88;
    }, 20);
  }

  // 桌面浏览器鼠标
  touchpad.addEventListener('mousemove', (e) => sendMove(e.clientX, e.clientY));
  touchpad.addEventListener('mousedown', (e) => { e.preventDefault(); sendMouse('down', norm(e.clientX, e.clientY)); });
  touchpad.addEventListener('mouseup', (e) => { e.preventDefault(); sendMouse('up', norm(e.clientX, e.clientY)); });
  touchpad.addEventListener('wheel', (e) => { e.preventDefault(); send({ type: 'scroll', dx: e.deltaX, dy: e.deltaY }); }, { passive: false });

  // 手机触控
  touchpad.addEventListener('touchstart', (e) => {
    e.preventDefault();
    if (e.touches.length === 1) {
      const t = e.touches[0];
      oneFinger = { x: t.clientX, y: t.clientY, t: Date.now(), moved: false, trail: [{ x: t.clientX, y: t.clientY, t: Date.now() }] };
      twoFinger = null;
    } else if (e.touches.length === 2) {
      oneFinger = null;
      twoFinger = { x: (e.touches[0].clientX + e.touches[1].clientX) / 2, y: (e.touches[0].clientY + e.touches[1].clientY) / 2, t: Date.now(), moved: false };
    }
  }, { passive: false });

  touchpad.addEventListener('touchmove', (e) => {
    e.preventDefault();
    if (e.touches.length === 1 && oneFinger) {
      const t = e.touches[0];
      const dx = t.clientX - oneFinger.x, dy = t.clientY - oneFinger.y;
      if (Math.abs(dx) + Math.abs(dy) > 8) oneFinger.moved = true;
      sendMove(t.clientX, t.clientY);
      oneFinger.trail.push({ x: t.clientX, y: t.clientY, t: Date.now() });
      if (oneFinger.trail.length > 6) oneFinger.trail.shift();
    } else if (e.touches.length === 2 && twoFinger) {
      const cx = (e.touches[0].clientX + e.touches[1].clientX) / 2;
      const cy = (e.touches[0].clientY + e.touches[1].clientY) / 2;
      const dx = cx - twoFinger.x, dy = cy - twoFinger.y;
      if (Math.abs(dx) + Math.abs(dy) > 3) {
        twoFinger.moved = true;
        // iOS 原生方向：手指上滑 = 看下方内容，位移方向与滚动方向相反
        send({ type: 'scroll', dx: -dx * 4, dy: -dy * 4 });
        twoFinger.x = cx; twoFinger.y = cy;
      }
    }
  }, { passive: false });

  touchpad.addEventListener('touchend', (e) => {
    e.preventDefault();
    const changed = Array.from(e.changedTouches);
    if (changed.length === 1 && oneFinger) {
      const t = changed[0];
      const now = Date.now();
      if (oneFinger.moved) {
        // 用最近 ~120ms 的速度窗口算甩动速度（避免最后一小段减速导致速度为 0）
        oneFinger.trail.push({ x: t.clientX, y: t.clientY, t: now });
        if (oneFinger.trail.length > 7) oneFinger.trail.shift();
        const trail = oneFinger.trail;
        const lastP = trail[trail.length - 1];
        const cutoff = lastP.t - 120;
        let start = trail[0];
        for (const p of trail) { if (p.t >= cutoff) { start = p; break; } }
        const dt = Math.max(8, lastP.t - start.t);
        const vx = ((lastP.x - start.x) / dt) * 1000;
        const vy = ((lastP.y - start.y) / dt) * 1000;
        const dist = Math.hypot(t.clientX - oneFinger.x, t.clientY - oneFinger.y);
        if (dist > 50 && Math.hypot(vx, vy) > 700) {
          flingScroll(vx, vy);
          status.textContent = '已滚动';
        }
      } else {
        const p = norm(t.clientX, t.clientY);
        if (now - oneFinger.t < 250) {
          if (now - lastTapAt < 350) sendMouse('doubleclick', p);
          else sendMouse('click', p);
          lastTapAt = now;
        }
      }
    }
    if (changed.length === 1 && twoFinger && !twoFinger.moved && Date.now() - twoFinger.t < 250) {
      const t = changed[0];
      const p = norm(t.clientX, t.clientY);
      send({ type: 'mouse', action: 'rightclick', x: p.x, y: p.y });
    }
    if (e.touches.length === 0) { oneFinger = null; twoFinger = null; }
  }, { passive: false });

  // 方向滚动键：点按滚一档，按住连续滚；▲▼ 双击 = 滚到顶部/底部
  const SCROLL_STEP = 2; // 一档 ≈ 80px
  const DOUBLE_TAP_MS = 350;
  function scrollDir(dx, dy) {
    send({ type: 'scroll', dx: dx * SCROLL_STEP, dy: dy * SCROLL_STEP });
  }
  document.querySelectorAll('[data-scroll]').forEach((b) => {
    let timer = null;
    let lastTapAt = 0;
    const parts = (b.dataset.scroll || '0,0').split(',').map(Number);
    const start = (e) => {
      e.preventDefault();
      const now = Date.now();
      const isVertical = parts[1] !== 0;
      const isDouble = isVertical && (now - lastTapAt) < DOUBLE_TAP_MS;
      lastTapAt = isDouble ? 0 : now;
      if (isDouble) {
        if (timer) clearInterval(timer);
        timer = null;
        const edge = parts[1] < 0 ? 'top' : 'bottom';
        send({ type: 'scroll', edge: edge });
        status.textContent = edge === 'top' ? '已滚到顶部' : '已滚到底部';
        return;
      }
      if (timer) clearInterval(timer);
      scrollDir(parts[0], parts[1]);
      timer = setInterval(() => scrollDir(parts[0], parts[1]), 120);
    };
    const stop = () => { if (timer) { clearInterval(timer); timer = null; } };
    b.addEventListener('touchstart', start, { passive: false });
    b.addEventListener('touchend', stop);
    b.addEventListener('touchcancel', stop);
    b.addEventListener('mousedown', start);
    b.addEventListener('mouseup', stop);
    b.addEventListener('mouseleave', stop);
    b.addEventListener('contextmenu', (e) => e.preventDefault());
  });

  // 快捷按键
  document.querySelectorAll('#keys button').forEach((b) => {
    b.addEventListener('click', () => {
      const key = b.dataset.key;
      if (!key) return;
      const flags = (b.dataset.flags || '').split(',').filter(Boolean);
      if (key === 'backspace') {
        // 一键清空：先全选再删除
        send({ type: 'key', key: 'a', flags: ['cmd'] });
        setTimeout(() => send({ type: 'key', key: 'backspace', flags: [] }), 200);
      } else {
        send({ type: 'key', key: key, flags: flags });
      }
    });
  });

  // 画面缩放：放大聚焦窗口中心（宽屏窗口在手机上完整显示时太小）
  function applyZoom() {
    const scale = ZOOM_STEPS[zoomStep];
    view.style.transform = scale === 1 ? '' : `scale(${scale})`;
    zoomBtn.textContent = scale === 1 ? '🔍' : `🔍 ${scale}x`;
  }
  zoomBtn.addEventListener('click', () => {
    zoomStep = (zoomStep + 1) % ZOOM_STEPS.length;
    applyZoom();
  });

  // 文字输入
  function sendInput() {
    const v = textInput.value.trim();
    if (!v) return;
    send({ type: 'text', text: v, enter: true });
    textInput.value = '';
    voiceBuffer = '';
    status.textContent = '已发送 ✓';
  }
  sendBtn.addEventListener('click', sendInput);
  textInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); sendInput(); } });

  // 全屏编辑器：查看/编辑完整内容，确认后发送并自动回车
  // 入口：📝 按钮（任意输入内容）、DeepSeek 优化结果
  function openEditor(text) {
    aiText.value = text;
    aiModal.style.display = 'flex';
    status.textContent = '全屏查看内容，可直接修改';
    setTimeout(() => aiText.focus(), 100);
  }
  function closeAiModal() {
    aiModal.style.display = 'none';
  }
  aiCancelBtn.addEventListener('click', () => {
    const kept = aiText.value.trim();
    closeAiModal();
    if (kept) { textInput.value = kept; voiceBuffer = kept; status.textContent = '已保留到输入框，可修改后发送'; }
    else status.textContent = '已取消';
  });
  aiSendBtn.addEventListener('click', () => {
    const v = aiText.value.trim();
    if (!v) { status.textContent = '内容为空，未发送'; return; }
    closeAiModal();
    textInput.value = '';
    voiceBuffer = '';
    send({ type: 'text', text: v, enter: true });
    status.textContent = '已发送 ✓';
  });

  // 📝 全屏编辑：把输入框当前内容弹到全屏查看/编辑
  editBtn.addEventListener('click', () => {
    const v = textInput.value.trim();
    if (!v) { status.textContent = '输入框还是空的，先输入或说出内容'; return; }
    openEditor(textInput.value);
  });

  // AI 文本优化（DeepSeek）
  function setAiLoading(on) {
    aiLoading = on;
    aiBtn.disabled = on;
    aiBtn.textContent = on ? '⏳' : '✨';
  }

  aiBtn.addEventListener('click', () => {
    if (aiLoading) return;
    const v = textInput.value.trim();
    if (!v) { status.textContent = '先输入或说出内容，再点 ✨ 优化'; return; }
    setAiLoading(true);
    status.textContent = '正在请 DeepSeek 优化…';
    send({ type: 'ai', action: 'optimize', text: v });
    aiTimeout = setTimeout(() => {
      setAiLoading(false);
      status.textContent = 'AI 优化超时，请重试';
    }, 35000);
  });

  // DeepSeek API Key 设置（保存到本机 ~/.vibework，重启不丢失）
  gearBtn.addEventListener('click', () => {
    const k = prompt('输入 DeepSeek API Key（保存到本机，重启不丢失）', '');
    if (k === null) return;
    send({ type: 'setkey', key: k.trim() });
  });

  // —— 语音：连续聆听模式（网页识别）—— 说“回车发送”自动发送并回车 ——
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  let voiceRec = null;
  let voiceListening = false;
  let voiceBuffer = '';
  let dictateMode = false;
  let dictateTimer = null;

  function startDictation() {
    dictateMode = true;
    status.textContent = '键盘听写：在键盘上点麦克风说话，停顿后自动发送';
    textInput.focus();
  }

  function resetVoiceUI() {
    dictateMode = false;
  }

  function handleFinalUtterance(raw) {
    const t = raw.replace(/[，。！？、,.!?;；:：]/g, '').trim();
    if (!t) return;
    if (/回车\\s*发送|发送|回车/.test(t)) {
      const content = voiceBuffer.trim();
      if (content) send({ type: 'text', text: content, enter: true });
      voiceBuffer = '';
      textInput.value = '';
      status.textContent = '已发送并回车 ✓（继续聆听，说“停止”结束）';
      return;
    }
    if (/停止|结束|关闭/.test(t)) { stopVoice(); return; }
    if (/全选/.test(t)) { send({ type: 'key', key: 'a', flags: ['cmd'] }); return; }
    if (/复制/.test(t)) { send({ type: 'key', key: 'c', flags: ['cmd'] }); return; }
    if (/粘贴/.test(t)) { send({ type: 'key', key: 'v', flags: ['cmd'] }); return; }
    if (/撤销/.test(t)) { send({ type: 'key', key: 'z', flags: ['cmd'] }); return; }
    if (/删除|退格/.test(t)) { send({ type: 'key', key: 'backspace', flags: [] }); return; }
    voiceBuffer = (voiceBuffer + ' ' + t).trim();
    textInput.value = voiceBuffer;
  }

  function startVoice() {
    if (!SR) { startDictation(); return; }
    try {
      voiceRec = new SR();
      voiceRec.lang = 'zh-CN';
      voiceRec.continuous = true;
      voiceRec.interimResults = true;
      voiceRec.maxAlternatives = 1;
      voiceRec.onresult = (e) => {
        let interim = '';
        for (let i = e.resultIndex; i < e.results.length; i++) {
          const r = e.results[i];
          const t = r[0].transcript.trim();
          if (r.isFinal) handleFinalUtterance(t);
          else interim = t;
        }
        if (interim) textInput.value = (voiceBuffer + ' ' + interim).trim();
      };
      voiceRec.onerror = (e) => {
        stopVoice();
        if (e.error === 'not-allowed' || e.error === 'service-not-allowed' || e.error === 'network') {
          startDictation();
        }
      };
      voiceRec.onend = () => {
        if (voiceListening) { try { voiceRec.start(); } catch (e) {} }
      };
      voiceRec.start();
      voiceListening = true;
      status.textContent = '🎙 聆听中…（说完后说“回车发送”；“停止”结束）';
    } catch (e) {
      startDictation();
    }
  }

  function stopVoice() {
    voiceListening = false;
    voiceBuffer = '';
    if (voiceRec) { try { voiceRec.stop(); } catch (e) {} voiceRec = null; }
    textInput.value = '';
    resetVoiceUI();
    status.textContent = '已停止聆听';
  }

  // 键盘听写兜底：输入框内容停顿 0.9 秒后自动发送
  textInput.addEventListener('input', () => {
    if (!dictateMode) return;
    clearTimeout(dictateTimer);
    dictateTimer = setTimeout(() => {
      const v = textInput.value.trim();
      if (v) send({ type: 'text', text: v });
      textInput.value = '';
      resetVoiceUI();
    }, 900);
  });

  connect();
  setInterval(() => {
    if (pendingMove && Date.now() - lastMoveSentAt >= 24) {
      sendMouse('move', pendingMove);
      lastMoveSentAt = Date.now();
      pendingMove = null;
    }
    if (ws && ws.readyState === WebSocket.OPEN && !loginVisible) {
      if (frames > 0) {
        status.textContent = '已连接 · ' + frames + ' fps';
        frames = 0;
      } else if (Date.now() - lastFrameAt > 2000) {
        status.textContent = '已连接 · 等待画面帧…';
      }
    }
  }, 1000);
})();
</script>
</body>
</html>
"""
