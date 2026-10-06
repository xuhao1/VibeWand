// Cold open: a knob bought for a few hundred yuan whose own driver can only pretend to be three keys.
Film.scene('hook', ({ root, start, end }) => {
  const { tl, el, vo, word } = Film, mood = Backdrop.mood;
  tl.set(mood, { glow: 0, hue: 250, lift: 0, grid: 0 }, 0)
    .to(mood, { glow: 0.42, duration: 2.5 }, 0.8)
    .to(mood, { glow: 0.95, hue: 292, duration: 0.8 }, vo('hook2').at - 0.2)
    .to(mood, { glow: 0.3, hue: 238, duration: 1.0 }, vo('hook3').at - 0.4)
    .to(mood, { glow: 0.14, duration: 1.4 }, vo('hook5').at + 1.6);

  // The knob, drawn out of the dark by a passing light.
  const knob = Mock.device(root, 'controller', { x: 1400, y: 520, h: 860, aura: 0 });
  tl.fromTo(knob.root, { scale: 0.9, y: 30 }, { scale: 1, y: 0, duration: 3.2, ease: 'power2.out' }, 0.4)
    .fromTo(knob.img, { filter: 'brightness(0.02) drop-shadow(0 50px 70px rgba(0,0,0,.65))' }, { filter: 'brightness(1) drop-shadow(0 50px 70px rgba(0,0,0,.65))', duration: 1.9, ease: 'power2.inOut' }, 0.5)
    .to(knob.halo, { opacity: 0.45, duration: 2.2 }, 0.9)
    .to(knob.root, { scale: 1.05, duration: 14, ease: 'none' }, 3.6);
  const click = knob.ring('dial');
  Film.sfx('knob', 0.55, 1.2); Film.sfx('knob', 0.95, 0.5);
  tl.fromTo(click, { autoAlpha: 0.9, scale: 0.6 }, { autoAlpha: 0, scale: 1.7, duration: 0.9, ease: 'power2.out' }, 0.55);

  // 1 · bought it
  const h1 = vo('hook1'), h2 = vo('hook2'), h3 = vo('hook3'), h4 = vo('hook4'), h5 = vo('hook5');
  Mock.kinetic(root, 'hook1', [['我花了', '几百块，'], ['买了', '一个', '<span class="grad">旋钮</span>。']], { cls: 'zh-xl', x: 150, y: 330, out: h2.at - 0.35 });
  const receipt = el('div', 'abs', root, '<span class="chip" style="font-size:32px;padding:14px 26px">📦 已签收</span>');
  Object.assign(receipt.style, { left: '156px', top: '700px' });
  tl.fromTo(receipt, { autoAlpha: 0, x: -30 }, { autoAlpha: 1, x: 0, duration: 0.5 }, word('hook1', '旋钮') + 0.25).to(receipt, { autoAlpha: 0, duration: 0.3 }, h2.at - 0.35);

  // 2 · the promise on the box
  Mock.kinetic(root, 'hook2', [['听说，', '它是'], [['Vibe Coding ', 'Vibe'], '的', '<span class="grad-hot">神器</span>。']], { cls: 'zh-xl', x: 150, y: 330, out: h3.at - 0.4 });
  const promises = [['✨ Vibe Coding 神器', 940, 170, -7], ['解放双手', 1600, 290, 6], ['AI 编程必备', 960, 800, 5], ['效率起飞 🚀', 1570, 770, -5]];
  promises.forEach(([text, x, y, tilt], i) => {
    const chip = el('div', 'abs', root, `<span class="chip hot" style="font-size:34px;padding:16px 28px">${text}</span>`);
    Object.assign(chip.style, { left: x + 'px', top: y + 'px' });
    Film.sfx('sparkle', h2.at + 0.5 + i * 0.3, 0.7);
    tl.fromTo(chip, { autoAlpha: 0, scale: 0.3, rotation: tilt * 3 }, { autoAlpha: 1, scale: 1, rotation: tilt, duration: 0.55, ease: 'back.out(2.2)' }, h2.at + 0.5 + i * 0.3)
      .to(chip, { y: 260 + i * 30, rotation: tilt * 7, autoAlpha: 0, duration: 0.8, ease: 'power2.in' }, h3.at - 0.5 + i * 0.07);
  });

  // 3 · what its driver really does
  Mock.kinetic(root, 'hook3', [['结果', '它的', '驱动，'], [['只会', '只'], '一件事——']], { cls: 'zh-l', x: 150, y: 150, out: h4.at - 0.3 });
  const driver = Mock.win(root, { x: 150, y: 450, w: 780, h: 400, title: '设备驱动 · 按键映射' });
  driver.root.style.filter = 'saturate(.35)';
  const rows = [['旋钮 左转', '↑'], ['旋钮 右转', '↓'], ['按下旋钮', '⏎']];
  const keys = rows.map(([name, key], i) => {
    const row = el('div', 'abs', driver.body, `<span style="font:500 30px/1 var(--zh);color:#9c9ab8;letter-spacing:.06em">${name}</span><span style="color:#55536f;margin:0 26px;font-size:30px">→</span>`);
    Object.assign(row.style, { left: '54px', top: 46 + i * 104 + 'px', display: 'flex', alignItems: 'center' });
    const cap = el('span', 'key sm', row, key); cap.style.cssText += 'min-width:78px;height:70px;font-size:32px;border-radius:14px';
    tl.fromTo(row, { autoAlpha: 0, x: -24 }, { autoAlpha: 1, x: 0, duration: 0.4 }, word('hook3', '驱动') + 0.25 + i * 0.22);
    return cap;
  });
  Film.sfx('drop', h3.at - 0.4, 0.8); Film.sfx('pop', word('hook3', '驱动') - 0.1, 0.7);
  tl.fromTo(driver.root, { autoAlpha: 0, y: 60, scale: 0.96 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.6 }, word('hook3', '驱动') - 0.1);

  // 4 · three keys, that is all
  Mock.kinetic(root, 'hook4', [['假装', '自己是'], [['几个', '几个'], '<span class="hl">键盘按键</span>。']], { cls: 'zh-l', x: 150, y: 150, out: h5.at - 0.3 });
  tl.to(driver.root, { autoAlpha: 0.0, scale: 0.94, duration: 0.5 }, h4.at + 0.1);
  const big = ['↑', '↓', '⏎'].map((symbol, i) => {
    const cap = el('div', 'key abs', root, symbol);
    Object.assign(cap.style, { left: 190 + i * 190 + 'px', top: '560px' });
    Film.sfx('thud', h4.at + 0.35 + i * 0.28 + 0.45, 0.9);
    tl.fromTo(cap, { autoAlpha: 0, x: 1150 - i * 190, y: -40, scale: 0.2, rotation: 40 }, { autoAlpha: 1, x: 0, y: 0, scale: 1, rotation: 0, duration: 0.7, ease: 'back.out(1.4)' }, h4.at + 0.35 + i * 0.28);
    return cap;
  });
  const sigh = el('div', 'abs zh-s', root, '就这？');
  Object.assign(sigh.style, { left: '790px', top: '606px' });
  tl.fromTo(sigh, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.3 }, h4.at + h4.seconds + 0.15).to(sigh, { autoAlpha: 0, duration: 0.25 }, h5.at - 0.3);

  // 5 · then why not just use the keyboard
  Mock.kinetic(root, 'hook5', [['那我', '为什么，'], [['不直接', '直接'], '按键盘', '呢？']], { cls: 'zh-l', x: 150, y: 150, out: end - 1.9 });
  const board = el('div', 'abs', root);
  Object.assign(board.style, { left: '150px', top: '520px', width: '930px', padding: '22px', borderRadius: '26px', background: 'rgba(255,255,255,.04)', border: '1px solid rgba(255,255,255,.1)' });
  const layout = [14, 14, 13, 12];
  const lit = { '1-13': '⏎', '3-10': '↑', '3-11': '↓' };
  layout.forEach((count, r) => {
    const line = el('div', '', board); line.style.cssText = 'display:flex;gap:8px;margin-bottom:8px;justify-content:center';
    for (let c = 0; c < count; c++) {
      const key = el('div', '', line, lit[`${r}-${c}`] || '');
      key.style.cssText = `flex:${(c === count - 1 || c === 0) && r > 0 ? 1.7 : 1};height:54px;border-radius:10px;background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.08);display:flex;align-items:center;justify-content:center;font:700 24px/1 var(--en);color:#fff`;
      if (lit[`${r}-${c}`]) tl.to(key, { backgroundColor: 'rgba(98,230,255,.85)', boxShadow: '0 0 30px rgba(98,230,255,.9)', color: '#06202a', duration: 0.25 }, word('hook5', '按键盘') + 0.1 + c * 0.02);
    }
  });
  Film.sfx('whoosh', h5.at, 0.6); Film.sfx('clack', word('hook5', '按键盘') + 0.12, 0.9); Film.sfx('clack', word('hook5', '按键盘') + 0.3, 0.8); Film.sfx('womp', h5.at + 0.9, 0.8);
  tl.fromTo(board, { autoAlpha: 0, y: 140 }, { autoAlpha: 1, y: 0, duration: 0.7 }, h5.at + 0.1);
  big.forEach((cap, i) => tl.to(cap, { autoAlpha: 0, scale: 0.3, y: 60, duration: 0.4, ease: 'power2.in' }, h5.at + 0.1 + i * 0.05));
  // The knob has nothing to say for itself.
  tl.to(knob.img, { filter: 'brightness(0.42) drop-shadow(0 50px 70px rgba(0,0,0,.65))', duration: 1.2 }, h5.at + 0.6)
    .to(knob.root, { rotation: 7, y: 26, duration: 1.2, ease: 'power2.inOut' }, h5.at + 0.6)
    .to(knob.halo, { opacity: 0.08, duration: 1.2 }, h5.at + 0.6);
  // Everything else leaves; the knob is alone in the dark.
  tl.to(board, { autoAlpha: 0, y: 80, duration: 0.6, ease: 'power2.in' }, end - 1.9)
    .to(knob.root, { x: -440, rotation: 0, y: 0, scale: 1.12, duration: 1.7, ease: 'power3.inOut' }, end - 1.9);
});
