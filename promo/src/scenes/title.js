// The turn: the knob is given a new soul, and the name arrives.
Film.scene('title', ({ root, start, end, frame }) => {
  const { tl, el, vo, word, clamp, random, L } = Film, mood = Backdrop.mood;
  const impact = vo('turn1').at + vo('turn1').seconds + 0.25;

  Film.sfx('riser', start + 0.1, 1); Film.sfx('impact', impact, 1.2); Film.sfx('shimmer', impact + 0.3, 0.8); Film.sfx('whoosh', end - 0.6, 0.6);
  tl.to(mood, { glow: 0.55, hue: 262, duration: 2.4, ease: 'power2.in' }, start)
    .to(mood, { glow: 1.25, lift: 1, duration: 0.12, ease: 'none' }, impact)
    .to(mood, { glow: 0.9, lift: 0.25, grid: 0.7, duration: 1.6 }, impact + 0.12);

  // The knob where the last scene left it.
  const knob = Mock.device(root, 'controller', { x: 960, y: 520, h: 963, aura: 0.08 });
  gsap.set(knob.img, { filter: 'brightness(0.42) drop-shadow(0 50px 70px rgba(0,0,0,.65))' });
  tl.to(knob.img, { filter: 'brightness(1.5) drop-shadow(0 0 60px rgba(139,108,255,.9))', duration: impact - start - 0.2, ease: 'power2.in' }, start + 0.2)
    .to(knob.halo, { opacity: 1, duration: impact - start - 0.2, ease: 'power2.in' }, start + 0.2)
    .to(knob.root, { scale: 0.86, duration: impact - start, ease: 'power2.in' }, start)
    .to(knob.root, { scale: 2.6, autoAlpha: 0, filter: 'blur(30px)', duration: 0.5, ease: 'power2.out' }, impact);

  Mock.kinetic(root, 'turn1', L([['所以，', '我给它'], ['换了个', '<span class="grad">灵魂</span>。']],
    [[['So I gave it', 'So']], [['a new ', 'a new'], '<span class="grad">soul</span>.']]), { cls: 'zh-l', x: 150, y: 400, out: impact - 0.12 });

  // Code pours into the dial.
  const canvas = el('canvas', 'abs', root); canvas.width = 1920; canvas.height = 1080;
  const g = canvas.getContext('2d'), r = random(9);
  const glyphs = ['{', '}', '<', '>', '/>', '=>', 'fn', 'let', '()', '[]', 'if', '&&', '::', 'await', '0x', '++', 'AX', 'HID', '?.', '#'];
  const motes = Array.from({ length: 150 }, () => ({ a: r() * 6.28, d: 620 + r() * 620, at: r(), text: glyphs[Math.floor(r() * glyphs.length)], turn: 1.2 + r() * 1.6, hue: 220 + r() * 90, size: 18 + r() * 20 }));
  const cx = 960, cy = 349;
  frame(t => {
    g.clearRect(0, 0, 1920, 1080);
    const window = impact - start - 0.5;
    for (const m of motes) {
      const p = clamp((t - start - 0.3 - m.at * (window - 1.1)) / 1.1);
      if (p <= 0 || p >= 1) continue;
      const e = p * p, d = m.d * (1 - e), a = m.a + m.turn * e;
      g.font = `700 ${m.size * (1 - e * 0.6)}px "JetBrains Mono"`;
      g.fillStyle = `hsla(${m.hue}, 95%, 76%, ${Math.sin(p * Math.PI) * 0.95})`;
      g.fillText(m.text, cx + Math.cos(a) * d, cy + Math.sin(a) * d * 0.72);
    }
    // Rings thrown out by the impact.
    const q = t - impact;
    if (q > 0 && q < 1.6) {
      for (let i = 0; i < 3; i++) {
        const p = clamp((q - i * 0.16) / 1.2); if (p <= 0) continue;
        g.strokeStyle = `hsla(${255 + i * 25}, 95%, 78%, ${(1 - p) * 0.8})`; g.lineWidth = 5 * (1 - p) + 1;
        g.beginPath(); g.ellipse(960, 470, 1250 * Film.ease.out(p), 1250 * Film.ease.out(p) * 0.62, 0, 0, 6.28); g.stroke();
      }
    }
  });
  const flash = el('div', 'abs', root); flash.style.cssText = 'inset:0;background:radial-gradient(circle at 50% 40%, #fff, #cfc4ff 40%, rgba(120,90,255,.0) 75%)';
  tl.fromTo(flash, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.09, ease: 'none' }, impact - 0.03).to(flash, { autoAlpha: 0, duration: 0.9, ease: 'power2.out' }, impact + 0.09);

  // The name.
  const lockup = el('div', 'abs', root); lockup.style.cssText = 'left:0;right:0;top:0;bottom:0';
  const icon = el('img', 'abs', lockup); icon.src = '../../assets/app-icon/AppIcon.png';
  icon.style.cssText = 'left:810px;top:96px;width:300px;height:300px;filter:drop-shadow(0 30px 80px rgba(120,90,255,.75))';
  tl.fromTo(icon, { autoAlpha: 0, scale: 2.4, rotation: -30, filter: 'blur(24px) drop-shadow(0 30px 80px rgba(120,90,255,.75))' },
    { autoAlpha: 1, scale: 1, rotation: 0, filter: 'blur(0px) drop-shadow(0 30px 80px rgba(120,90,255,.75))', duration: 0.9, ease: 'expo.out' }, impact + 0.05);
  const name = el('div', 'abs en-xl glow-text', lockup); name.style.cssText = 'left:0;right:0;top:420px;text-align:center;font-size:190px';
  'VibeWand'.split('').forEach((letter, i) => {
    const span = el('span', 'word', name, letter);
    span.style.cssText = `background:linear-gradient(180deg,#fff 30%,${i < 4 ? '#d9d0ff' : '#9d8bff'} 100%);-webkit-background-clip:text;background-clip:text;color:transparent`;
    tl.fromTo(span, { autoAlpha: 0, y: 120, rotationX: -80, scale: 0.7 }, { autoAlpha: 1, y: 0, rotationX: 0, scale: 1, duration: 0.8, ease: 'back.out(1.7)' }, impact + 0.28 + i * 0.055);
  });
  const zh = el('div', 'abs zh-m', lockup, L('如意魔棒', '')); zh.style.cssText = 'left:0;right:0;top:668px;text-align:center;letter-spacing:.62em;text-indent:.62em;color:#cfc8ff;font-weight:700;font-size:54px';
  tl.fromTo(zh, { autoAlpha: 0, letterSpacing: '1.6em', textIndent: '1.6em' }, { autoAlpha: 1, letterSpacing: '.62em', textIndent: '.62em', duration: 1.3, ease: 'power3.out' }, impact + 0.95);
  // The line, spoken.
  const line = el('div', 'abs en-m', lockup); line.style.cssText = 'left:0;right:0;top:800px;text-align:center;font-size:54px;font-weight:600;color:#fff';
  [['One ', 'One'], ['wand ', 'wand'], ['to ', 'to'], ['command ', 'command'], ['them ', 'them'], ['all.', 'all']].forEach(([text, cue]) => {
    const span = el('span', 'word', line, text);
    if (cue === 'wand' || cue === 'command') span.classList.add('grad');
    tl.fromTo(span, { autoAlpha: 0, y: 26, filter: 'blur(8px)' }, { autoAlpha: 1, y: 0, filter: 'blur(0px)', duration: 0.42 }, word('title', cue) - 0.08);
  });
  const rule = el('div', 'abs', lockup); rule.style.cssText = 'left:50%;top:768px;width:560px;height:2px;margin-left:-280px;background:linear-gradient(90deg,transparent,#8b6cff,#62e6ff,transparent)';
  tl.fromTo(rule, { scaleX: 0, autoAlpha: 0 }, { scaleX: 1, autoAlpha: 1, duration: 0.9 }, vo('title').at - 0.5);
  // A slow push while it holds, then out.
  tl.fromTo(lockup, { scale: 1 }, { scale: 1.045, duration: end - impact, ease: 'none' }, impact)
    .to(lockup, { autoAlpha: 0, scale: 1.25, filter: 'blur(18px)', duration: 0.55, ease: 'power2.in' }, end - 0.55)
    .to(mood, { grid: 0, glow: 0.5, duration: 0.6 }, end - 0.6);
});
