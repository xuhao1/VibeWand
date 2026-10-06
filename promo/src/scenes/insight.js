// The observation the product rests on: most of vibe coding is not typing.
Film.scene('insight', ({ root, start, end, frame }) => {
  const { tl, el, vo, word, L } = Film, mood = Backdrop.mood;
  const i1 = vo('insight1'), i2 = vo('insight2'), i3 = vo('insight3');
  tl.to(mood, { glow: 0.5, hue: 232, grid: 0, lift: 0, duration: 1 }, start);

  Mock.kinetic(root, 'insight1', L([[['Vibe Coding ', 'Vibe'], '的时候，'], ['你其实', '<span class="hl">很少打字</span>。']],
    [[['When you ', 'When'], ['vibe code,', 'vibe']], [['you ', 'you', 1], ['<span class="hl">barely type</span>.', 'barely']]]), { cls: 'zh-xl', x: 0, y: 340, align: 'center', out: i2.at - 0.4 });

  // Four things you do instead, each on its word.
  const verbs = [
    { glyph: L('读', 'Read'), label: L('读回复', 'the reply'), cue: L('在读', 'read'), hue: 262 },
    { glyph: L('等', 'Wait'), label: L('等它干活', 'while it works'), cue: L('等', 'wait'), hue: 200 },
    { glyph: L('切', 'Switch'), label: L('切对话 · 切模型', 'chats and models'), cue: L('切换', 'switch'), hue: 318 },
    { glyph: L('说', 'Say'), label: L('说一句话', 'a sentence'), cue: L('说', 'say'), hue: 168 },
  ];
  const cards = verbs.map((verb, i) => {
    const card = el('div', 'abs', root);
    card.style.cssText = `left:${150 + i * 415}px;top:250px;width:375px;height:470px;border-radius:36px;background:linear-gradient(160deg,hsla(${verb.hue},80%,62%,.24),hsla(${verb.hue},70%,30%,.08));border:1px solid hsla(${verb.hue},90%,76%,.42);box-shadow:0 40px 90px rgba(0,0,0,.45),inset 0 1px 0 rgba(255,255,255,.16)`;
    const glyph = el('div', 'abs', card, verb.glyph);
    glyph.style.cssText = `left:0;right:0;top:36px;text-align:center;font:${L('900 190px/1.1 var(--zh)', '800 92px/2.27 var(--en)')};color:#fff;text-shadow:0 0 50px hsla(${verb.hue},95%,70%,.9)`;
    const art = el('canvas', 'abs', card); art.width = 300; art.height = 90; art.style.cssText = 'left:37px;top:268px';
    const label = el('div', 'abs', card, verb.label); label.style.cssText = 'left:0;right:0;bottom:38px;text-align:center;font:700 30px/1 var(--zh);letter-spacing:.08em;color:rgba(255,255,255,.86)';
    Film.sfx('pop', word('insight2', verb.cue) - 0.05, 0.9);
    tl.fromTo(card, { autoAlpha: 0, y: 150, scale: 0.7, rotation: (i - 1.5) * 5 }, { autoAlpha: 1, y: 0, scale: 1, rotation: 0, duration: 0.6, ease: 'back.out(1.8)' }, word('insight2', verb.cue) - 0.1);
    return { card, art: art.getContext('2d'), hue: verb.hue };
  });
  // A small moving picture under each word.
  frame(t => {
    cards.forEach(({ art: g, hue }, i) => {
      g.clearRect(0, 0, 300, 90); g.fillStyle = g.strokeStyle = `hsla(${hue}, 95%, 82%, .9)`; g.lineWidth = 6; g.lineCap = 'round';
      if (i === 0) { for (let k = 0; k < 5; k++) { const y = ((k * 22 - t * 26) % 110 + 110) % 110 - 10; g.globalAlpha = Math.sin(Math.PI * Film.clamp(y / 90)); g.fillRect(40, y, [220, 170, 200, 120, 190][k], 7); } g.globalAlpha = 1; }
      if (i === 1) { for (let k = 0; k < 3; k++) { g.globalAlpha = 0.3 + 0.7 * Math.max(0, Math.sin(t * 4 - k * 0.9)); g.beginPath(); g.arc(105 + k * 45, 45, 13, 0, 6.28); g.fill(); } g.globalAlpha = 1; }
      if (i === 2) { const p = 0.5 + 0.5 * Math.sin(t * 2.4); g.strokeRect(70 + p * 60, 14, 100, 62); g.globalAlpha = 0.45; g.strokeRect(130 - p * 60, 14, 100, 62); g.globalAlpha = 1; }
      if (i === 3) { for (let k = 0; k < 15; k++) { const h = 10 + 62 * Math.abs(Math.sin(t * 5.2 + k * 0.8) * Math.sin(t * 1.7 + k * 0.33)); g.fillRect(40 + k * 15.5, 45 - h / 2, 7, h); } }
    });
  });

  // They gather on the one device that does them all.
  const knob = Mock.device(root, 'controller', { x: 1420, y: 500, h: 800, aura: 0.6 });
  Film.sfx('whoosh', i3.at - 0.45, 0.7);
  tl.fromTo(knob.root, { autoAlpha: 0, scale: 0.7, y: 80 }, { autoAlpha: 1, scale: 1, y: 0, duration: 0.8, ease: 'back.out(1.4)' }, i3.at - 0.35);
  const homes = [[1120, 205, 'dial'], [1120, 300, 'dial'], [1120, 395, 'dial'], [1120, 490, 'voice']];
  cards.forEach(({ card }, i) => {
    tl.to(card, { left: 1040, top: 150 + i * 150, scale: 0.25, transformOrigin: '0 0', duration: 0.75, ease: 'power3.inOut' }, i3.at - 0.45 + i * 0.06);
  });
  Mock.kinetic(root, 'insight3', L([['这些事，'], [['<span class="grad">一只手</span>', '一只手'], '就够了。']],
    [[['All of that', 'All']], [['takes ', 'takes'], ['<span class="grad">one hand</span>.', 'one']]]), { cls: 'zh-xl', x: 150, y: 360, out: end - 0.5 });
  ['dial', 'voice', 'ok'].forEach((name, i) => knob.press(name, i3.at + 1.3 + i * 0.35, 0.3));
  tl.to([knob.root, ...cards.map(c => c.card)], { autoAlpha: 0, duration: 0.45, ease: 'power2.in' }, end - 0.5);
});
