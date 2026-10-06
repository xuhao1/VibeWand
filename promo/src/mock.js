// Pieces the scenes share: text that lands on the narrator's words, the devices, and the pretend desktop
// (windows and apps drawn here are illustrations; VibeWand's own overlay is always the filmed one).
const Mock = (() => {
  const { el, tl, word, vo, clamp, lang, L } = Film;

  /// Lines of large text whose pieces arrive as the narrator says them.
  /// rows: [[piece, ...], ...]; a piece is "text", ["text", "spoken text to wait for", which occurrence] or ["text", seconds].
  const kinetic = (parent, lineId, rows, { cls = 'zh-l', x = 150, y = 300, out = null, lead = 0.1, align = 'left' } = {}) => {
    const box = el('div', 'abs ' + cls, parent);
    Object.assign(box.style, { left: x + 'px', top: y + 'px', textAlign: align, whiteSpace: 'nowrap' });
    if (align === 'center') Object.assign(box.style, { left: '0', right: '0' });
    let last = vo(lineId).at;
    for (const row of rows) {
      const line = el('div', '', box);
      for (const piece of row) {
        const bare = piece => piece.replace(/<[^>]+>/g, '');
        const [html, cue, nth = 0] = Array.isArray(piece) ? piece : [piece, lang === 'zh' ? bare(piece).replace(/[，。？！：、——…\s]/gu, '') : bare(piece)];
        const at = typeof cue === 'number' ? cue : word(lineId, cue, nth);
        last = Math.max(last, at);
        const span = el('span', 'word', line, html);
        tl.fromTo(span, { autoAlpha: 0, y: 46, filter: 'blur(14px)', scale: 0.94 },
          { autoAlpha: 1, y: 0, filter: 'blur(0px)', scale: 1, duration: 0.5, ease: 'back.out(1.5)' }, Math.max(0, at - lead));
      }
    }
    if (out !== null) tl.to(box, { autoAlpha: 0, y: -30, filter: 'blur(10px)', duration: 0.38, ease: 'power2.in' }, out);
    return box;
  };

  const art = { controller: [1086, 1448], gamepad: [1536, 1024], remote: [1024, 1536] };
  /// Where things are on each device's picture, as fractions of its width and height (radius as a fraction of the width).
  const spots = {
    controller: { dial: [0.5, 0.322, 0.135], voice: [0.5, 0.518, 0.078], ok: [0.5, 0.665, 0.078], escape: [0.5, 0.814, 0.078] },
    gamepad: { voice: [0.796, 0.274, 0.036], ok: [0.885, 0.372, 0.036], escape: [0.796, 0.471, 0.036], square: [0.731, 0.371, 0.036], touchpad: [0.5, 0.278, 0.11], mic: [0.5, 0.52, 0.03] },
    remote: { voice: [0.5, 0.176, 0.07], ok: [0.5, 0.332, 0.085], home: [0.5, 0.468, 0.06] },
  };
  /// A device picture `h` pixels tall, centred on (x, y), with a glow behind it and rings to light on its controls.
  const device = (parent, kind, { x, y, h, aura = 0.5 }) => {
    const w = h * art[kind][0] / art[kind][1];
    const root = el('div', 'device', parent);
    Object.assign(root.style, { left: x - w / 2 + 'px', top: y - h / 2 + 'px', width: w + 'px', height: h + 'px' });
    const halo = el('div', 'aura', root); halo.style.opacity = aura;
    const img = el('img', '', root); img.src = `../../assets/device/${kind}.png`;
    const ring = name => {
      const [px, py, pr] = spots[kind][name], r = pr * w;
      const node = el('div', 'ring', root);
      Object.assign(node.style, { left: px * w - r + 'px', top: py * h - r + 'px', width: 2 * r + 'px', height: 2 * r + 'px' });
      gsap.set(node, { autoAlpha: 0, scale: 0.8 });
      return node;
    };
    /// A ring that flares for a press held from `at` for `hold` seconds.
    const press = (name, at, hold = 0.25) => {
      const node = ring(name);
      Film.sfx('click', at, 0.8);
      tl.to(node, { autoAlpha: 1, scale: 1, duration: 0.12, ease: 'power2.out' }, at)
        .to(node, { autoAlpha: 0, scale: 1.25, duration: 0.3, ease: 'power2.in' }, at + hold);
      return node;
    };
    return { root, img, halo, w, h, ring, press, spots: spots[kind] };
  };

  const win = (parent, { x, y, w, h, title = '' }) => {
    const root = el('div', 'win', parent);
    Object.assign(root.style, { left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px' });
    el('div', 'bar', root, `<i></i><i></i><i></i><b>${title}</b>`);
    const body = el('div', 'body', root);
    return { root, body, titleEl: root.querySelector('.bar b') };
  };

  const reply = `
<div class="you">登录页偶尔报 401，帮我看看是哪里的问题</div>
<div class="ai">
<p>找到了。问题不在登录页本身，而在刷新令牌的时机：<b>两个请求同时发现令牌过期</b>，各自去刷新，后到的那个把先到的顶掉了。</p>
<h5>1. 复现</h5>
<p>把令牌有效期调到 5 秒，并发打开两个需要鉴权的页面，就能稳定看到 401。</p>
<pre><span class="c">// auth/session.ts（修改前）</span>
<span class="k">export async function</span> <span class="f">ensureFresh</span>(session) {
  <span class="k">if</span> (session.expiresAt &lt; Date.now()) {
    <span class="d">- session.token = await refresh(session.refreshToken)</span>
    <span class="a">+ session.token = await single(() =&gt; refresh(session.refreshToken))</span>
  }
  <span class="k">return</span> session.token
}</pre>
<h5>2. 修复</h5>
<p>用一个进行中的 Promise 把并发的刷新合并成一次：第一个请求去刷新，其余的等它的结果。</p>
<pre><span class="k">let</span> pending: Promise&lt;string&gt; | <span class="k">null</span> = <span class="k">null</span>
<span class="k">function</span> <span class="f">single</span>(run: () =&gt; Promise&lt;string&gt;) {
  pending ??= run().<span class="f">finally</span>(() =&gt; { pending = <span class="k">null</span> })
  <span class="k">return</span> pending
}</pre>
<h5>3. 验证</h5>
<p>我补了一个并发用例：20 个请求同时触发刷新，断言刷新接口只被调用一次。</p>
<pre><span class="a">✓</span> refresh is shared by concurrent requests <span class="c">(12 ms)</span>
<span class="a">✓</span> a failed refresh is retried by the next request <span class="c">(8 ms)</span>
<span class="a">✓</span> login page recovers after token expiry <span class="c">(31 ms)</span>

Tests  <span class="a">3 passed</span> · 0 failed</pre>
<h5>4. 还可以做的</h5>
<p>刷新失败时现在会直接跳回登录页。更稳妥的做法是先重试一次，再提示用户；需要的话我接着改。</p>
<pre><span class="c">// 重试一次，再放弃</span>
<span class="k">const</span> token = <span class="k">await</span> <span class="f">retry</span>(() =&gt; <span class="f">single</span>(refreshNow), { times: <span class="s">1</span> })</pre>
<p>要我把这个也一起提交吗？</p>
</div>`;

  const replyEn = `
<div class="you">The login page throws a 401 now and then. Can you find out why?</div>
<div class="ai">
<p>Found it. The login page itself is fine; the trouble is when the token gets refreshed: <b>two requests notice the expired token at the same moment</b>, each refreshes it, and the later one invalidates the earlier one.</p>
<h5>1. Reproduce</h5>
<p>Set the token lifetime to 5 seconds and open two authenticated pages at once. The 401 shows up every time.</p>
<pre><span class="c">// auth/session.ts (before)</span>
<span class="k">export async function</span> <span class="f">ensureFresh</span>(session) {
  <span class="k">if</span> (session.expiresAt &lt; Date.now()) {
    <span class="d">- session.token = await refresh(session.refreshToken)</span>
    <span class="a">+ session.token = await single(() =&gt; refresh(session.refreshToken))</span>
  }
  <span class="k">return</span> session.token
}</pre>
<h5>2. Fix</h5>
<p>Share one in-flight promise between concurrent refreshes: the first request refreshes, the others wait for its result.</p>
<pre><span class="k">let</span> pending: Promise&lt;string&gt; | <span class="k">null</span> = <span class="k">null</span>
<span class="k">function</span> <span class="f">single</span>(run: () =&gt; Promise&lt;string&gt;) {
  pending ??= run().<span class="f">finally</span>(() =&gt; { pending = <span class="k">null</span> })
  <span class="k">return</span> pending
}</pre>
<h5>3. Verify</h5>
<p>I added a concurrency test: 20 requests trigger a refresh together, and the refresh endpoint must be called once.</p>
<pre><span class="a">✓</span> refresh is shared by concurrent requests <span class="c">(12 ms)</span>
<span class="a">✓</span> a failed refresh is retried by the next request <span class="c">(8 ms)</span>
<span class="a">✓</span> login page recovers after token expiry <span class="c">(31 ms)</span>

Tests  <span class="a">3 passed</span> · 0 failed</pre>
<h5>4. What else could be done</h5>
<p>A failed refresh currently sends the user straight back to the login page. Retrying once before giving up would be kinder; say the word and I will add it.</p>
<pre><span class="c">// retry once, then give up</span>
<span class="k">const</span> token = <span class="k">await</span> <span class="f">retry</span>(() =&gt; <span class="f">single</span>(refreshNow), { times: <span class="s">1</span> })</pre>
<p>Shall I commit this as well?</p>
</div>`;

  /// The pretend AI coding app: chats on the left, a long reply to read, a composer at the bottom.
  const chat = (body, { chats = L(['修复登录页 401', '重构支付模块', 'VibeWand 交互设计', '整理实验记录'], ['Fix login page 401', 'Refactor payments', 'VibeWand interaction design', 'Tidy lab notes']), active = 0, model = 'Pro', effort = L('高', 'High') } = {}) => {
    const root = el('div', 'chat', body);
    const side = el('div', 'side', root, `<h6>${L('会话', 'CHATS')}</h6>`);
    const items = chats.map((name, i) => el('div', i === active ? 'on' : '', side, name));
    const main = el('div', 'main', root);
    const thread = el('div', 'thread', main, L(reply, replyEn));
    const composer = el('div', 'composer', main);
    const text = el('span', '', composer, `<span class="hint">${L('继续说点什么…', 'Say something…')}</span>`);
    const caret = el('span', 'caret', composer);
    const meta = el('div', 'meta', composer);
    const modelPill = el('span', 'pill', meta, L('模型 · ', 'Model · ') + model), effortPill = el('span', 'pill', meta, L('强度 · ', 'Effort · ') + effort);
    return { root, side, items, main, thread, composer, text, caret, modelPill, effortPill };
  };

  /// The filmed overlay, shown `w` pixels wide with its top-left corner at (x, y).
  const overlay = (parent, { x, y, w }) => {
    const root = el('div', 'overlay-take', parent);
    Object.assign(root.style, { left: x + 'px', top: y + 'px', width: w + 'px' });
    const img = el('img', '', root);
    return { root, img };
  };

  return { kinetic, device, win, chat, overlay, spots };
})();
