// More than one wand: a dial, a game controller, a remote, or the keyboard already on the desk.
// The overlay on the right is filmed as the layout changes with the device.
Film.scene('devices', ({ root, start, end, frame }) => {
  const { tl, el, vo, word, along, showTake, DATA, L } = Film, mood = Backdrop.mood;
  const d1 = vo('dev1'), d2 = vo('dev2'), d3 = vo('dev3');
  tl.to(mood, { glow: 0.7, hue: 244, grid: 0.35, duration: 1 }, start);

  Mock.kinetic(root, 'dev1', L([['魔棒，', '也', '<span class="grad">不止一根</span>。']], [[['And there is ', 'And'], ['more than ', 'more'], ['<span class="grad">one wand</span>.', 'one']]]), { cls: 'zh-l', x: 110, y: 64, out: d3.at - 0.35 });

  const take = 'ov-templates', events = DATA.takes[take]?.events || [];
  const switched = id => events.find(e => e.event === 'template' && e.id === id)?.t ?? 0;
  const cues = { vibeKey: word('dev2', 'VibeKey'), dualSense: word('dev2', 'PS'), xiaomiRemote: word('dev2', L('小米', 'Xiaomi')), keyboard: word('dev2', L('或者', 'Or')) };
  const map = [[start, 0], [cues.vibeKey, 0.4], [cues.dualSense - 0.15, switched('dualSense') - 0.15], [cues.dualSense, switched('dualSense')],
    [cues.xiaomiRemote - 0.1, switched('xiaomiRemote') - 0.3], [cues.xiaomiRemote, switched('xiaomiRemote')],
    [cues.keyboard - 0.1, switched('keyboard') - 0.3], [cues.keyboard, switched('keyboard')], [end, switched('keyboard') + 3.6]];
  const overlay = Mock.overlay(root, { x: 1150, y: 170, w: 580 * 1.28 });
  frame(t => showTake(overlay.img, take, along(map, t)));
  tl.fromTo(overlay.root, { autoAlpha: 0, x: 80 }, { autoAlpha: 1, x: 0, duration: 0.6 }, cues.vibeKey - 0.3);
  el('div', 'abs tag', root, L('VibeWand 悬浮窗 · 实机录制（演示模式）', 'VIBEWAND OVERLAY · FILMED IN THE APP (DEMO MODE)')).style.cssText += 'left:1262px;top:1000px';

  // The four, in a row; the one being named is lit.
  const row = [
    { id: 'vibeKey', kind: 'controller', name: L('VibeKey 旋钮', 'VibeKey dial'), h: 470, x: 180 },
    { id: 'dualSense', kind: 'gamepad', name: L('PS5 手柄', 'PS5 controller'), h: 270, x: 470 },
    { id: 'xiaomiRemote', kind: 'remote', name: L('小米遥控器', 'Xiaomi remote'), h: 450, x: 770 },
    { id: 'keyboard', kind: null, name: L('手边的键盘', 'Your keyboard'), h: 0, x: 1010 },
  ];
  const order = ['vibeKey', 'dualSense', 'xiaomiRemote', 'keyboard'];
  const items = row.map(item => {
    const group = el('div', 'abs', root); group.style.cssText = 'inset:0';
    let body;
    if (item.kind) { body = Mock.device(group, item.kind, { x: item.x, y: 520, h: item.h, aura: 0.55 }).root; }
    else {
      body = el('div', 'abs', group); body.style.cssText = `left:${item.x - 90}px;top:430px;width:180px`;
      [['⌃', '⌥', '⌘'], ['Space']].forEach(keys => { const line = el('div', '', body); line.style.cssText = 'display:flex;gap:8px;margin-bottom:8px;justify-content:center'; keys.forEach(key => { const cap = el('span', 'key sm', line, key); if (key === 'Space') cap.style.minWidth = '170px'; }); });
    }
    const label = el('div', 'abs', group, item.name); label.style.cssText = `left:${item.x - 150}px;width:300px;top:800px;text-align:center;font:${L('700 30px/1 var(--zh);letter-spacing:.04em', '600 25px/1 var(--en)')};color:#fff`;
    Film.sfx('pop', cues[item.id] - 0.15, 0.9); Film.sfx('whoosh-soft', cues[item.id], 0.5);
    tl.fromTo(group, { autoAlpha: 0, y: 90, scale: 0.8 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.6, ease: 'back.out(1.6)' }, cues[item.id] - 0.2);
    const next = order[order.indexOf(item.id) + 1];
    if (next) tl.to(group, { opacity: 0.38, scale: 0.94, duration: 0.4 }, cues[next] - 0.15);
    tl.to(group, { opacity: 1, scale: 1, duration: 0.5 }, d3.at - 0.2);
    return group;
  });
  // The controller's own microphone can dictate.
  const mic = el('div', 'abs', root, `<span class="chip hot">${L('🎙 手柄自带的麦克风，也能听写', '🎙 Its own microphone takes dictation')}</span>`); mic.style.cssText = 'left:250px;top:250px';
  mic.firstChild.style.fontSize = '30px';
  tl.fromTo(mic, { autoAlpha: 0, y: 30, scale: 0.7 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.45, ease: 'back.out(2)' }, word('dev2', L('麦克风', 'microphone')) - 0.25)
    .to(mic, { autoAlpha: 0, duration: 0.3 }, cues.xiaomiRemote - 0.2);

  Mock.kinetic(root, 'dev3', L([['手上', '有什么，', ['就用', '就'], ['<span class="grad-hot">什么</span>。', '什么', 1]]], [[['Use ', 'Use'], ['whatever ', 'whatever'], ['<span class="grad-hot">you have</span>.', 'you']]]), { cls: 'zh-l', x: 110, y: 64, out: end - 0.45 });
  const free = el('div', 'abs', root, `<span class="chip">${L('不买新设备，也能开玩', 'No new hardware needed')}</span>`); free.style.cssText = 'left:116px;top:210px'; free.firstChild.style.fontSize = '30px';
  tl.fromTo(free, { autoAlpha: 0, x: -30 }, { autoAlpha: 1, x: 0, duration: 0.4 }, d3.at + 1.0);
  tl.to([overlay.root, ...items, free], { autoAlpha: 0, duration: 0.4, ease: 'power2.in' }, end - 0.45).to(mood, { grid: 0, duration: 0.5 }, end - 0.5);
});
