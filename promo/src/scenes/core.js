// The core loop: turn to read, hold to speak, press to switch. The overlay on the right is VibeWand's own,
// filmed while the scripted device pressed these very controls; the app window on the left is drawn to follow it.
Film.scene('core', ({ root, start, end, frame }) => {
  const { tl, el, vo, word, along, reach, showTake, clamp } = Film, mood = Backdrop.mood;
  const take = 'ov-core', events = Film.DATA.takes[take]?.events || [];
  tl.to(mood, { glow: 0.62, hue: 248, duration: 1 }, start);

  // Film time → the take's own time. Holds and jumps are where the edit lingers or skips.
  const c2a = vo('core2a').at, said = vo('say_dictate'), c3 = vo('core3').at;
  const voiceDown = events.find(e => e.event === 'down' && e.control === 'voice')?.t ?? 5.16;
  const voiceUp = events.find(e => e.event === 'up' && e.control === 'voice')?.t ?? 8.36;
  const dialDowns = events.filter(e => e.event === 'down' && e.control === 'dial').map(e => e.t);
  const sessionsAt = dialDowns[0] ?? 9.71, modelsAt = dialDowns[1] ?? 14.37;
  const release = said.at + said.seconds + 0.3;
  const map = [[start, voiceDown - 4.3], [start + 0.4, 1.2], [start + 4.1, voiceDown - 0.2], [c2a - 0.02, voiceDown - 0.16], [c2a + 0.12, voiceDown],
    [release, voiceUp], [release + 1.4, voiceUp + 1.0], [c3 - 0.1, sessionsAt - 0.2], [c3 + 0.1, sessionsAt], [word('core3', '长按') - 0.05, sessionsAt + 3.9],
    [word('core3', '长按') + 0.1, modelsAt], [vo('core4').at - 0.1, modelsAt + 6.0], [end, modelsAt + 6.6]];
  const filmAt = clip => reach(map, clip);

  const stage = el('div', 'abs', root); stage.style.cssText = 'inset:0;transform-origin:50% 46%';
  const app = Mock.win(stage, { x: 70, y: 96, w: 1190, h: 800, title: 'AI 编程助手' });
  const chat = Mock.chat(app.body);
  const tag = el('div', 'abs tag', stage, '应用窗口 · 界面示意'); tag.style.cssText += 'left:70px;top:912px';
  const overlay = Mock.overlay(stage, { x: 1310 - 166 * 1.38, y: 332 - 30 * 1.38, w: 580 * 1.38 });
  const tag2 = el('div', 'abs tag', stage, 'VibeWand 悬浮窗 · 实机录制（演示模式）'); tag2.style.cssText += 'left:1310px;top:1000px';
  frame(t => showTake(overlay.img, take, along(map, t)));
  tl.fromTo(app.root, { autoAlpha: 0, x: -80, scale: 0.96 }, { autoAlpha: 1, x: 0, scale: 1, duration: 0.7 }, start + 0.05)
    .fromTo(overlay.root, { autoAlpha: 0, x: 80 }, { autoAlpha: 1, x: 0, duration: 0.7 }, start + 0.2)
    .fromTo([tag, tag2], { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.5 }, start + 0.9);

  // The verb of the moment, large, above the overlay.
  const verb = (glyph, sub, from, to, cls = 'grad') => {
    const box = el('div', 'abs', stage); box.style.cssText = 'left:1310px;top:88px;width:540px;display:flex;align-items:flex-end;gap:26px';
    el('div', cls, box, glyph).style.cssText = 'font:900 180px/1 var(--zh)';
    el('div', '', box, sub).style.cssText = 'font:700 38px/1.3 var(--zh);letter-spacing:.05em;color:#d9d4ff;padding-bottom:22px';
    tl.fromTo(box, { autoAlpha: 0, y: 40, filter: 'blur(12px)' }, { autoAlpha: 1, y: 0, filter: 'blur(0px)', duration: 0.45, ease: 'back.out(1.6)' }, from)
      .to(box, { autoAlpha: 0, y: -30, duration: 0.3, ease: 'power2.in' }, to);
  };
  verb('转', '读回复', vo('core1').at - 0.15, c2a - 0.35);
  verb('说', '松手，字就在<br>输入框里', c2a - 0.05, c3 - 0.4);
  verb('按', '换对话<br>长按，换模型', c3 - 0.1, vo('core4').at - 0.35);
  verb('靠', '活儿照样在干', vo('core4').at - 0.05, end - 0.4, 'grad-hot');

  // Reading: every detent of the dial moves the conversation.
  let scroll = 0;
  for (const e of events.filter(e => e.event === 'turn' && e.t > 1 && e.t < voiceDown)) {
    for (let i = 0; i < e.count; i++) {
      scroll = clamp(scroll + (e.direction === 'right' ? 76 : -76), 0, 620);
      tl.to(chat.thread, { y: -scroll, duration: 0.24, ease: 'power2.out' }, filmAt(e.t + i * e.every));
      Film.sfx('tick', filmAt(e.t + i * e.every), 0.75);
    }
  }

  // Speaking: the sentence arrives in the composer word by word while the key is held.
  const sentence = said.words.map(w => w[0]);
  const marks = { 3: '，', [sentence.length - 1]: '。' };
  let typed = '';
  tl.set(chat.text, { innerHTML: '' }, c2a + 0.1);
  said.words.forEach((w, i) => {
    typed += w[0] + (marks[i] || '');
    const snapshot = typed;
    tl.set(chat.text, { innerHTML: `<span style="color:#b8f3ff">${snapshot}</span>` }, w[1] + 0.18);
  });
  tl.set(chat.text, { innerHTML: typed }, release)
    .fromTo(chat.composer, { boxShadow: '0 -30px 40px #12121c, 0 0 0 0 rgba(98,230,255,0)' }, { boxShadow: '0 -30px 40px #12121c, 0 0 0 3px rgba(98,230,255,.85)', duration: 0.25 }, c2a + 0.1)
    .to(chat.composer, { boxShadow: '0 -30px 40px #12121c, 0 0 0 0 rgba(98,230,255,0)', duration: 0.5 }, release + 0.2)
    .to(chat.thread, { y: 0, duration: 0.01 }, c3 - 0.3);
  // What was said, as a voice.
  const bubble = el('div', 'abs', stage); bubble.style.cssText = 'left:160px;top:560px;width:1010px;padding:26px 34px;border-radius:26px;background:rgba(14,30,44,.92);border:1px solid rgba(98,230,255,.5);box-shadow:0 30px 80px rgba(0,0,0,.6),0 0 60px rgba(98,230,255,.2);display:flex;align-items:center;gap:26px';
  const wave = el('canvas', '', bubble); wave.width = 150; wave.height = 70;
  const quote = el('div', '', bubble); quote.style.cssText = 'font:700 36px/1.3 var(--zh);letter-spacing:.03em;color:#eafcff';
  const spans = said.words.map((w, i) => { const span = el('span', 'word', quote, w[0] + (marks[i] || '')); tl.fromTo(span, { autoAlpha: 0.0, y: 10 }, { autoAlpha: 1, y: 0, duration: 0.2 }, w[1]); return span; });
  Film.sfx('whoosh', start, 0.6); Film.sfx('rec-on', c2a + 0.12, 0.9); Film.sfx('rec-off', release, 0.9); Film.sfx('pop', release + 0.05, 0.6);
  tl.fromTo(bubble, { autoAlpha: 0, y: 30, scale: 0.96 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.35 }, said.at - 0.25)
    .to(bubble, { autoAlpha: 0, y: 40, scale: 0.92, duration: 0.35, ease: 'power2.in' }, release + 0.05);
  const wg = wave.getContext('2d');
  frame(t => {
    wg.clearRect(0, 0, 150, 70); wg.fillStyle = '#62e6ff';
    const loud = t > said.at && t < said.at + said.seconds ? 1 : 0.12;
    for (let k = 0; k < 13; k++) { const h = 8 + 56 * loud * Math.abs(Math.sin(t * 9 + k * 1.3) * Math.sin(t * 3.1 + k * 0.5)); wg.fillRect(6 + k * 11, 35 - h / 2, 6, h); }
  });

  // Switching chats: the app's own list, chosen with the dial.
  const other = el('div', 'thread', chat.main, `<div class="you">悬浮窗的旋钮提示，换成“读 / 说 / 切”三个字会不会更清楚？</div><div class="ai"><p>会。现在的提示按功能列了五行，第一次看要读完才知道该按哪个。</p><h5>建议</h5><p>把最常用的三件事放到最上面，用动词开头：<b>转 · 读回复</b>、<b>按住 · 说话</b>、<b>按一下 · 换对话</b>。其余的收进展开面板。</p><pre><span class="c">// OverlayGuidance.swift</span>\n<span class="k">let</span> primary: [Hint] = [.read, .speak, .switchChat]\n<span class="k">let</span> secondary = Hint.allCases.<span class="f">filter</span> { !primary.<span class="f">contains</span>($0) }</pre><p>我先改提示的顺序，再出一版截图给你看。</p></div>`);
  chat.main.insertBefore(other, chat.composer);
  const palette = el('div', 'palette', chat.main);
  el('div', 'q', palette, '切换会话…');
  const names = ['修复登录页 401', '重构支付模块', 'VibeWand 交互设计'];
  const rows = names.map((name, i) => el('div', 'row' + (i === 0 ? ' on' : ''), palette, `<span>${name}</span><small>${['刚刚', '2 小时前', '昨天'][i]}</small>`));
  const turns = events.filter(e => e.event === 'turn' && e.t > sessionsAt && e.t < modelsAt).map(e => e.t);
  const mturns = events.filter(e => e.event === 'turn' && e.t > modelsAt).map(e => e.t);
  const oks = events.filter(e => e.event === 'down' && e.control === 'ok').map(e => e.t);
  gsap.set(palette, { autoAlpha: 0 });
  Film.sfx('click', filmAt(sessionsAt), 0.9); Film.sfx('pop', filmAt(sessionsAt) + 0.12, 0.7);
  turns.slice(0, 2).forEach(at => Film.sfx('tick', filmAt(at), 0.9)); mturns.forEach(at => Film.sfx('tick', filmAt(at), 0.9));
  oks.slice(0, 3).forEach(at => Film.sfx('click', filmAt(at), 0.9));
  Film.sfx('click', filmAt(modelsAt), 0.9); Film.sfx('pop', filmAt(modelsAt + 0.75), 0.7);
  tl.fromTo(palette, { autoAlpha: 0, y: -24, scale: 0.97 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.25 }, filmAt(sessionsAt) + 0.12);
  turns.slice(0, 2).forEach((at, i) => tl.set(rows[i], { className: 'row' }, filmAt(at) + 0.05).set(rows[i + 1], { className: 'row on' }, filmAt(at) + 0.05));
  const picked = filmAt(oks[0] ?? sessionsAt + 3);
  tl.to(palette, { autoAlpha: 0, scale: 0.97, duration: 0.2 }, picked + 0.05)
    .set(chat.items[0], { className: '' }, picked + 0.1).set(chat.items[2], { className: 'on' }, picked + 0.1)
    .to(chat.thread, { autoAlpha: 0, duration: 0.15 }, picked + 0.05)
    .set(chat.text, { innerHTML: '<span class="hint">继续说点什么…</span>' }, picked + 0.2)
    .fromTo(other, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.3 }, picked + 0.22);

  // Long press: the model, then how hard it thinks.
  const menu = el('div', 'menu', chat.main); menu.style.cssText += 'left:46px;bottom:128px';
  const head = el('h6', '', menu, '模型');
  const options = ['Flash', 'Pro', 'Max'].map((name, i) => el('div', 'row' + (i === 1 ? ' on' : ''), menu, `<span>${name}</span>`));
  gsap.set(menu, { autoAlpha: 0 });
  tl.fromTo(menu, { autoAlpha: 0, y: 16 }, { autoAlpha: 1, y: 0, duration: 0.22 }, filmAt(modelsAt + 0.75));
  if (mturns[0]) tl.set(options[1], { className: 'row' }, filmAt(mturns[0]) + 0.05).set(options[2], { className: 'row on' }, filmAt(mturns[0]) + 0.05);
  if (oks[1]) {
    const at = filmAt(oks[1]) + 0.06;
    tl.set(chat.modelPill, { innerHTML: '模型 · Max' }, at).set(head, { innerHTML: '思考强度' }, at);
    ['低', '中', '高'].forEach((name, i) => tl.set(options[i], { innerHTML: `<span>${name}</span>`, className: 'row' + (i === 1 ? ' on' : '') }, at));
  }
  if (mturns[1]) tl.set(options[1], { className: 'row' }, filmAt(mturns[1]) + 0.05).set(options[2], { className: 'row on' }, filmAt(mturns[1]) + 0.05);
  if (oks[2]) tl.set(chat.effortPill, { innerHTML: '强度 · 高' }, filmAt(oks[2]) + 0.06).to(menu, { autoAlpha: 0, y: 12, duration: 0.2 }, filmAt(oks[2]) + 0.08);
  [chat.modelPill, chat.effortPill].forEach((pill, i) => { const at = filmAt(oks[1 + i] ?? 0) + 0.06; tl.fromTo(pill, { backgroundColor: '#62e6ff', color: '#06202a' }, { backgroundColor: '#2a2940', color: '#b9b6dc', duration: 0.9 }, at); });

  // Lean back: the work goes on by itself.
  const back = vo('core4').at;
  const lines = ['<span class="a">✓</span> 调整提示顺序', '<span class="a">✓</span> 更新 OverlayGuidanceTests', '<span class="a">✓</span> swift test · 214 个用例通过', '<span class="c">正在生成新截图…</span>'];
  Film.sfx('whoosh-soft', back - 0.2, 0.7); lines.forEach((_, i) => Film.sfx('blip', back + 0.3 + i * 0.75, 0.5));
  tl.to(stage, { scale: 0.9, y: 14, duration: 1.6, ease: 'power2.inOut' }, back - 0.2)
    .to(mood, { glow: 0.85, hue: 268, duration: 1.6 }, back - 0.2);
  const log = el('pre', '', other); log.style.cssText += 'margin-top:8px;min-height:150px';
  lines.forEach((line, i) => { const row = el('div', '', log, line); tl.fromTo(row, { autoAlpha: 0, x: -12 }, { autoAlpha: 1, x: 0, duration: 0.3 }, back + 0.3 + i * 0.75); });
  tl.fromTo(log, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.2 }, back + 0.2);
  tl.to(stage, { autoAlpha: 0, scale: 0.8, filter: 'blur(14px)', duration: 0.5, ease: 'power2.in' }, end - 0.5);
});
