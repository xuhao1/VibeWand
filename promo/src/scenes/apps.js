// Many tools, each with shortcuts of its own; one set of motions for all of them.
Film.scene('apps', ({ root, start, end, frame }) => {
  const { tl, el, vo, word, random, L } = Film, mood = Backdrop.mood;
  const a1 = vo('apps1'), a2 = vo('apps2'), a3 = vo('apps3'), a4 = vo('apps4');
  tl.to(mood, { glow: 0.5, hue: 222, duration: 0.8 }, start)
    .to(mood, { glow: 0.75, hue: 338, duration: 1.2 }, a2.at)
    .to(mood, { glow: 0.9, hue: 256, grid: 0.5, duration: 1.2 }, a3.at);

  const apps = [
    { name: 'Codex', hue: 212, cue: ['Codex', 0], at: [120, 250, -5] },
    { name: 'Claude', hue: 22, cue: ['Claude', 0], at: [660, 180, 4] },
    { name: 'DeepSeek Harness', hue: 232, cue: ['DeepSeek', 0], at: [1240, 250, -3] },
    { name: L('终端 · Claude Code', 'Terminal · Claude Code'), hue: 140, cue: L(['终端', 0], ['Claude', 1]), at: [330, 540, 6], mono: true },
    { name: L('浏览器', 'Browsers'), hue: 188, cue: [L('浏览器', 'Browsers'), 0], at: [900, 470, -6] },
    { name: L('微信', 'WeChat'), hue: 128, cue: [L('微信', 'WeChat'), 0], at: [1380, 590, 5] },
    { name: L('飞书', 'Feishu'), hue: 204, cue: [L('飞书', 'Feishu'), 0], at: [640, 690, -2] },
  ];
  const W = 500, H = 310;
  const wins = apps.map((app, i) => {
    const node = el('div', 'win', root);
    node.style.cssText = `left:${app.at[0]}px;top:${app.at[1]}px;width:${W}px;height:${H}px;border-color:hsla(${app.hue},80%,70%,.45);box-shadow:0 30px 70px rgba(0,0,0,.6),0 0 50px hsla(${app.hue},90%,60%,.16)`;
    el('div', 'bar', node, '<i></i><i></i><i></i>').style.height = '34px';
    const lines = el('div', 'abs', node);
    lines.style.cssText = `left:${app.mono ? 22 : 120}px;right:22px;top:50px;bottom:16px;opacity:.5;background:repeating-linear-gradient(180deg,hsla(${app.hue},70%,74%,.55) 0 8px,transparent 8px 26px);-webkit-mask-image:linear-gradient(90deg,#000 0 62%,transparent 62% 68%,#000 68% 86%,transparent 86%)`;
    if (!app.mono) { const side = el('div', 'abs', node); side.style.cssText = `left:0;top:34px;bottom:0;width:100px;background:hsla(${app.hue},40%,50%,.12);border-right:1px solid rgba(255,255,255,.06)`; }
    const label = el('div', 'abs', node, app.name);
    label.style.cssText = `left:0;right:0;top:128px;text-align:center;font:${app.mono ? '700 34px/1.2 var(--mono)' : '800 42px/1.2 var(--en)'};color:#fff;text-shadow:0 2px 30px #000,0 0 40px hsla(${app.hue},95%,60%,.9);letter-spacing:.01em`;
    Film.sfx('pop', word('apps1', ...app.cue) - 0.08, 0.9);
    tl.fromTo(node, { autoAlpha: 0, scale: 0.4, rotation: app.at[2] * 4, y: 120 }, { autoAlpha: 1, scale: 1, rotation: app.at[2], y: 0, duration: 0.55, ease: 'back.out(1.7)' }, word('apps1', ...app.cue) - 0.12);
    return { node, lines, app };
  });

  Mock.kinetic(root, 'apps1', L([['可是，', '工具', '<span class="hl">越来越多</span>。']], [[['But the tools ', 'But'], ['keep ', 'keep'], '<span class="hl">multiplying</span>.']]), { cls: 'zh-l', x: 110, y: 60, out: a2.at - 0.3 });
  Mock.kinetic(root, 'apps2', L([['每一个，', '都有', [' 自己的', '自己'], '<span class="grad-hot">一套快捷键</span>。']],
    [[['And every one ', 'And'], ['has its own ', 'has'], ['<span class="grad-hot">shortcuts</span>.', 'shortcuts']]]), { cls: 'zh-l', x: 110, y: 60, out: a3.at - 0.3 });

  // The shortcuts pile up.
  const r = random(21);
  const combos = ['⌘K', '⌘⇧P', '/resume', '/model', '⌃Tab', '⌘F', '⌘⇧K', '⌥⌘↑', '⌘L', 'Esc Esc', '⇧Tab', '⌘↵', '⌃`', '⌘1', '⌘⇧O', '⌥Space', '⌘J', '⌃R'];
  const chips = combos.map((combo, i) => {
    const chip = el('div', 'abs key sm', root, combo);
    const x = 140 + r() * 1560, y = 230 + r() * 640, tilt = (r() - 0.5) * 30;
    chip.style.cssText += `left:${x}px;top:${y}px;height:64px;min-width:64px;font-size:27px;padding:0 18px;border-color:rgba(255,160,220,.55)`;
    Film.sfx('clack', a2.at + 0.15 + i * 0.13, 0.55);
    tl.fromTo(chip, { autoAlpha: 0, scale: 0, rotation: tilt * 3 }, { autoAlpha: 1, scale: 1, rotation: tilt, duration: 0.4, ease: 'back.out(2.4)' }, a2.at + 0.15 + i * 0.13)
      .to(chip, { y: 520 + r() * 200, rotation: tilt * 5, autoAlpha: 0, duration: 0.75, ease: 'power2.in' }, a3.at - 0.25 + r() * 0.3);
    return chip;
  });
  wins.forEach(({ node, app }, i) => tl.to(node, { rotation: app.at[2] + (i % 2 ? 4 : -4), x: (i % 2 ? 14 : -14), duration: 0.12, repeat: 9, yoyo: true, ease: 'sine.inOut' }, a2.at + 1.2));

  // One wand: the windows fall into a fan around it.
  const knob = Mock.device(root, 'controller', { x: 960, y: 880, h: 600, aura: 0.9 });
  Film.sfx('drop', a3.at - 0.25, 0.7); Film.sfx('whoosh', a3.at + 0.15, 0.9); Film.sfx('impact-soft', a4.at - 0.1, 1);
  tl.fromTo(knob.root, { autoAlpha: 0, y: 260 }, { autoAlpha: 1, y: 0, duration: 0.9, ease: 'back.out(1.3)' }, a3.at + 0.1);
  const beams = el('canvas', 'abs', root); beams.width = 1920; beams.height = 1080;
  root.insertBefore(beams, wins[0].node);
  const fan = wins.map((w, i) => {
    const angle = (-66 + i * 22) * Math.PI / 180, cx = 960 + Math.sin(angle) * 840, cy = 1000 - Math.cos(angle) * 720;
    tl.to(w.node, { left: cx - W / 2, top: cy - H / 2, x: 0, y: 0, rotation: (-66 + i * 22) * 0.42, scale: 0.6, duration: 1.0, ease: 'power3.inOut' }, a3.at + 0.15 + i * 0.05);
    return [cx, cy];
  });
  // Each turn of the dial moves every app at once.
  const pulses = [a3.at + 1.7, a3.at + 2.6, a3.at + 3.5, a3.at + 4.4, a4.at + 0.5, a4.at + 1.5, a4.at + 2.5];
  pulses.forEach((at, k) => {
    knob.press('dial', at, 0.22); Film.sfx('spark', at + 0.05, 0.7);
    wins.forEach(w => tl.to(w.lines, { backgroundPositionY: -(k + 1) * 52, duration: 0.5, ease: 'power2.out' }, at + 0.05));
  });
  const g = beams.getContext('2d'), dial = [960, 880 - 300 + 0.322 * 600];
  frame(t => {
    g.clearRect(0, 0, 1920, 1080);
    const grown = Film.span(t, a3.at + 0.9, a3.at + 1.7);
    if (grown <= 0) return;
    fan.forEach(([cx, cy], i) => {
      const ex = dial[0] + (cx - dial[0]) * grown, ey = dial[1] + (cy + 60 - dial[1]) * grown;
      const line = g.createLinearGradient(dial[0], dial[1], ex, ey);
      line.addColorStop(0, 'rgba(98,230,255,.85)'); line.addColorStop(1, `hsla(${apps[i].hue},90%,70%,.15)`);
      g.strokeStyle = line; g.lineWidth = 2.5; g.beginPath(); g.moveTo(dial[0], dial[1]); g.lineTo(ex, ey); g.stroke();
      // A spark runs out along each line with every turn.
      for (const at of pulses) {
        const p = (t - at) / 0.55; if (p <= 0 || p >= 1) continue;
        const px = dial[0] + (cx - dial[0]) * p, py = dial[1] + (cy + 60 - dial[1]) * p;
        g.fillStyle = `rgba(190,245,255,${1 - p})`; g.beginPath(); g.arc(px, py, 7, 0, 6.28); g.fill();
      }
    });
  });
  Mock.kinetic(root, 'apps3', L([[['不替代', '不'], '它们。']], [[['Replaces', 'replaces']], [['none of them.', 'none']]]), { cls: 'zh-m', x: 150, y: L(760, 812), out: a4.at - 0.3 });
  Mock.kinetic(root, 'apps3', L([[['收进', '收进']], [['<span class="grad">同一套手势</span>。', '同']]], [[['The same', 'same']], [['<span class="grad">few motions</span>.', 'few']]]), { cls: 'zh-m', x: L(1290, 1380), y: L(730, 812), out: a4.at - 0.3 });

  // The line.
  const dimmed = [...wins.map(w => w.node), beams];
  tl.to(dimmed, { opacity: 0.2, filter: 'blur(5px)', duration: 0.6 }, a4.at - 0.25);
  Mock.kinetic(root, 'apps4', L([[['一根', '一'], '<span class="grad">魔棒</span>，'], ['号令', '<span class="grad-hot">所有</span>。']],
    [[['One ', 'One'], '<span class="grad">wand</span>,'], [['for ', 'for'], ['<span class="grad-hot">all of them</span>.', 'all']]]), { cls: 'zh-xl', x: 0, y: 190, align: 'center', out: end - 0.5 });
  const en = el('div', 'abs en-m', root, 'One wand to command them all.'); en.style.cssText += 'left:0;right:0;top:520px;text-align:center;color:#d9d4ff;letter-spacing:.02em';
  tl.fromTo(en, { autoAlpha: 0, y: 20 }, { autoAlpha: 1, y: 0, duration: 0.6 }, a4.at + 1.5).to(en, { autoAlpha: 0, duration: 0.4 }, end - 0.5);
  tl.to([knob.root, ...dimmed], { autoAlpha: 0, duration: 0.45, ease: 'power2.in' }, end - 0.5).to(mood, { grid: 0, duration: 0.5 }, end - 0.5);
});
