// Close: the name, where to find it, who made it and with what help, and what is real in this film.
Film.scene('end', ({ root, start, end }) => {
  const { tl, el, vo, word, L } = Film, mood = Backdrop.mood;
  const e1 = vo('end1'), e2 = vo('end2');
  tl.to(mood, { glow: 1.0, hue: 262, lift: 0.2, grid: 0.6, duration: 1.2 }, start);

  const lockup = el('div', 'abs', root); lockup.style.cssText = 'inset:0';
  const icon = el('img', 'abs', lockup); icon.src = '../../assets/app-icon/AppIcon.png';
  icon.style.cssText = 'left:835px;top:70px;width:250px;height:250px;filter:drop-shadow(0 30px 80px rgba(120,90,255,.75))';
  const name = el('div', 'abs en-xl glow-text grad', lockup, 'VibeWand'); name.style.cssText = 'left:0;right:0;top:330px;text-align:center;font-size:170px';
  const zh = el('div', 'abs', lockup, L('如意魔棒', '')); zh.style.cssText = 'left:0;right:0;top:548px;text-align:center;font:700 50px/1 var(--zh);letter-spacing:.62em;text-indent:.62em;color:#cfc8ff';
  const line = el('div', 'abs en-m', lockup, 'One wand to command them all.'); line.style.cssText = 'left:0;right:0;top:640px;text-align:center;font-size:46px;color:#fff';
  Film.sfx('impact', start + 0.15, 1.1); Film.sfx('shimmer', start + 0.5, 0.8); Film.sfx('pop', word('end1', L('开发中', 'Still')) - 0.2, 0.7); Film.sfx('pop', word('end1', L('欢迎', 'Come')) - 0.2, 0.7);
  tl.fromTo(icon, { autoAlpha: 0, scale: 0.4, rotation: -40 }, { autoAlpha: 1, scale: 1, rotation: 0, duration: 0.9, ease: 'back.out(1.5)' }, start + 0.15)
    .fromTo(name, { autoAlpha: 0, y: 60, filter: 'blur(16px)' }, { autoAlpha: 1, y: 0, filter: 'blur(0px)', duration: 0.8 }, start + 0.4)
    .fromTo(zh, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.8 }, start + 0.9)
    .fromTo(line, { autoAlpha: 0, y: 20 }, { autoAlpha: 1, y: 0, duration: 0.7 }, start + 1.2);
  const chips = el('div', 'abs', lockup); chips.style.cssText = 'left:0;right:0;top:770px;display:flex;justify-content:center;gap:20px';
  const wip = el('span', 'chip hot', chips, L('🚧 开发中 · Work in progress', '🚧 Work in progress')), site = el('span', 'chip', chips, '<span class="mono">vibewand.xuhao1.me</span>');
  [wip, site].forEach(chip => chip.style.fontSize = '32px');
  tl.fromTo(wip, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.45, ease: 'back.out(2)' }, word('end1', L('开发中', 'Still')) - 0.2)
    .fromTo(site, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.45, ease: 'back.out(2)' }, word('end1', L('欢迎', 'Come')) - 0.2);

  // Credits: the lockup moves up and makes room.
  const credits = e1.at + e1.seconds + 0.5;
  Film.sfx('whoosh-soft', credits, 0.6); Film.sfx('whoosh-soft', e2.at - 0.4, 0.6);
  tl.to(lockup, { y: -64, scale: 0.82, transformOrigin: '50% 30%', duration: 0.9, ease: 'power3.inOut' }, credits);
  const card = el('div', 'abs', root); card.style.cssText = 'left:0;right:0;top:690px;text-align:center';
  const rows = [
    ['<span style="font:800 44px/1.3 var(--en)">by Dr. Xu</span><span style="margin:0 22px;color:#6f6b9e">·</span><span class="mono" style="font-size:32px;color:#cfc8ff">xuhao1.me</span><span style="margin:0 22px;color:#6f6b9e">·</span><span class="mono" style="font-size:32px;color:#cfc8ff">github.com/xuhao1</span>', 0],
    [L('<span style="font:700 31px/1.6 var(--zh);letter-spacing:.04em">本项目在 <b class="hl">Codex</b>、<b class="hl">Claude Code</b> 与 <b class="hl">DeepSeek Harness</b> 的协助下开发</span>',
      '<span style="font:600 30px/1.6 var(--en)">Developed with the help of <b class="hl">Codex</b>, <b class="hl">Claude Code</b> and <b class="hl">DeepSeek Harness</b></span>'), 0.5],
    [L('<span style="font:500 21px/1.7 var(--zh);letter-spacing:.05em;color:#8a86b8">悬浮窗画面为实机录制（演示模式）；应用窗口为界面示意；旁白与配乐由 AI 合成<br>VibeWand 是独立项目，与 Ulanzi、Sony、小米及片中提到的应用厂商无关联，产品名称与商标归各自所有者</span>',
      '<span style="font:600 19px/1.7 var(--en);color:#8a86b8">The overlay is filmed in the app (demo mode); the app windows are illustrations; narration and music are AI-made<br>VibeWand is an independent project, not affiliated with Ulanzi, Sony, Xiaomi or the makers of the apps shown; names and trademarks belong to their owners</span>'), 1.1],
  ];
  rows.forEach(([html, delay]) => { const row = el('div', '', card, html); row.style.marginBottom = '14px'; tl.fromTo(row, { autoAlpha: 0, y: 24 }, { autoAlpha: 1, y: 0, duration: 0.55 }, credits + 0.35 + delay); });

  // One more thing.
  const ps = el('div', 'abs', root); ps.style.cssText = 'inset:0;background:rgba(4,3,12,.94)';
  const box = el('div', 'abs', ps); box.style.cssText = 'left:0;right:0;top:360px;text-align:center';
  el('div', 'en-m', box, 'P.S.').style.cssText = 'color:#8b6cff;font-size:40px;letter-spacing:.2em;margin-bottom:26px';
  const said = el('div', 'zh-m', box); said.style.fontSize = '64px';
  L([['这支视频，', '这支'], ['也是我说了几句话，', '也是'], ['<br><span class="grad-hot">Claude Code</span> ', 'Claude'], ['做出来的。', '做出来']],
    [['This video? ', 'this'], ['I said a few sentences,', 'I said'], ['\n'], ['and <span class="grad-hot">Claude Code</span> ', 'and Claude'], ['made it.', 'made']]).forEach(([html, cue]) => {
    if (html === '\n') { el('br', '', said); return; }
    const span = el('span', 'word', said, html);
    tl.fromTo(span, { autoAlpha: 0, y: 30, filter: 'blur(10px)' }, { autoAlpha: 1, y: 0, filter: 'blur(0px)', duration: 0.45 }, word('end2', cue) - 0.08);
  });
  gsap.set(ps, { autoAlpha: 0 });
  tl.to(ps, { autoAlpha: 1, duration: 0.5 }, e2.at - 0.4);
});
