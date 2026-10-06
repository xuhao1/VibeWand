// Command mode: hold the key, say a sentence, and an agent finds the app and the controls for you.
// The overlay is VibeWand's own, filmed; the app windows are drawn to follow what it reports.
Film.scene('command', ({ root, start, end, frame }) => {
  const { tl, el, vo, word, along, reach, showTake, clamp, DATA, L } = Film, mood = Backdrop.mood;
  const c1 = vo('cmd1'), c2 = vo('cmd2'), c3 = vo('cmd3'), c4 = vo('cmd4');
  tl.to(mood, { glow: 0.35, hue: 205, duration: 1 }, start);

  // The thought.
  Mock.kinetic(root, 'cmd1', L([['后来', '我想：'], [['它都能听我', '它'], '<span class="hl">说话</span>了，'], ['为什么', [' 不干脆，', '不干脆']], [['听我', '听', 1], '<span class="grad-hot">号令</span>？']],
    [[['Then I thought:', 'Then']], [['it already ', 'it already'], ['<span class="hl">listens</span> ', 'listens'], ['to me talk.', 'to me']], [['Why not let it', 'Why']], [['<span class="grad-hot">take orders</span>?', 'take']]]), { cls: 'zh-l', x: 0, y: 190, align: 'center', out: c1.at + c1.seconds + 0.15 });

  // The name of the mode.
  const flashAt = c1.at + c1.seconds + 0.3, firstSay = vo('say_music').at;
  const card = el('div', 'abs', root); card.style.cssText = 'inset:0';
  el('div', 'abs zh-xl grad-hot', card, L('号令模式', 'Command mode')).style.cssText = L('left:0;right:0;top:300px;text-align:center;font-size:210px;letter-spacing:.06em', 'left:0;right:0;top:330px;text-align:center;font-size:190px');
  el('div', 'abs en-m', card, L('COMMAND MODE', 'SAY IT · IT’S DONE')).style.cssText = 'left:0;right:0;top:590px;text-align:center;letter-spacing:.5em;text-indent:.5em;color:#ffd9a0;font-size:40px';
  el('div', 'abs', card, `<span class="chip">${L('按住命令键 · 说一句话', 'Hold the command key · say a sentence')}</span>`).style.cssText = 'left:0;right:0;top:700px;text-align:center';
  Film.sfx('riser-short', flashAt - 1.2, 0.8); Film.sfx('impact', flashAt, 1.1);
  tl.fromTo(card, { autoAlpha: 0, scale: 1.5, filter: 'blur(20px)' }, { autoAlpha: 1, scale: 1, filter: 'blur(0px)', duration: 0.4, ease: 'expo.out' }, flashAt)
    .to(card, { autoAlpha: 0, scale: 0.9, filter: 'blur(12px)', duration: 0.3, ease: 'power2.in' }, firstSay - 0.55)
    .to(mood, { glow: 1.0, hue: 22, duration: 0.3 }, flashAt).to(mood, { glow: 0.6, hue: 250, duration: 0.8 }, firstSay - 0.5);

  /// One demonstration: a drawn app on the left, the filmed overlay on the right, the spoken words above it.
  const demo = ({ take, say, until, title, build }) => {
    const events = DATA.takes[take]?.events || [], line = vo(say);
    const began = events.find(e => e.event === 'command')?.t ?? 0, released = events.find(e => e.event === 'released')?.t ?? began + 2.4;
    const done = events.find(e => e.event === 'hud' && e.phase === 'done')?.t ?? released + 8;
    const releaseAt = line.at + line.seconds + 0.25, doneAt = until - 1.5;
    const map = [[line.at - 0.9, began - 0.9], [line.at, began], [releaseAt, released], [doneAt, done], [until, done + 1.4]];
    const filmAt = clip => reach(map, clip);
    /// When the overlay first reports a step, in film time.
    const step = (text, nth = 0) => { const found = events.filter(e => e.event === 'hud' && e.status.includes(text))[nth]; return found ? filmAt(found.t) : doneAt; };

    const stage = el('div', 'abs', root); stage.style.cssText = 'inset:0';
    const app = Mock.win(stage, { x: 70, y: 96, w: 1190, h: 800, title });
    const overlay = Mock.overlay(stage, { x: 1330 - 166 * 1.22, y: 268 - 30 * 1.22, w: 580 * 1.22 });
    frame(t => { if (t > line.at - 1 && t < until + 0.5) showTake(overlay.img, take, along(map, t)); });
    el('div', 'abs tag', stage, L('应用窗口 · 界面示意', 'APP WINDOW · ILLUSTRATION')).style.cssText += 'left:70px;top:912px';
    el('div', 'abs tag', stage, L('VibeWand 悬浮窗 · 实机录制（演示内核）', 'VIBEWAND OVERLAY · FILMED IN THE APP (STAND-IN KERNEL)')).style.cssText += 'left:1330px;top:1004px';
    // The sentence, as it is spoken.
    const bubble = el('div', 'abs', stage); bubble.style.cssText = 'left:1330px;top:84px;width:500px;min-height:150px;padding:22px 28px;border-radius:26px 26px 26px 6px;background:rgba(14,30,44,.92);border:1px solid rgba(98,230,255,.5);box-shadow:0 0 60px rgba(98,230,255,.2)';
    const wave = el('canvas', '', bubble); wave.width = 440; wave.height = 36; const wg = wave.getContext('2d');
    const quote = el('div', '', bubble); quote.style.cssText = L('font:700 30px/1.35 var(--zh);letter-spacing:.02em;color:#eafcff;margin-top:8px', 'font:600 29px/1.35 var(--en);color:#eafcff;margin-top:8px');
    line.words.forEach(w => { const span = el('span', 'word', quote, /^[A-Za-z]/.test(w[0]) ? w[0] + ' ' : w[0]); tl.fromTo(span, { autoAlpha: 0, y: 8 }, { autoAlpha: 1, y: 0, duration: 0.18 }, w[1]); });
    frame(t => {
      wg.clearRect(0, 0, 440, 36); wg.fillStyle = '#62e6ff';
      const loud = t > line.at && t < line.at + line.seconds ? 1 : 0.1;
      for (let k = 0; k < 37; k++) { const h = 4 + 30 * loud * Math.abs(Math.sin(t * 9 + k * 1.3) * Math.sin(t * 3.1 + k * 0.5)); wg.fillRect(k * 12, 18 - h / 2, 6, h); }
    });
    gsap.set(stage, { autoAlpha: 0 });
    Film.sfx('whoosh-soft', line.at - 0.5, 0.6); Film.sfx('rec-on', line.at - 0.05, 0.9); Film.sfx('rec-off', releaseAt, 0.9); Film.sfx('ding', doneAt + 0.05, 1);
    events.filter(e => e.event === 'hud' && e.phase === 'working' && !e.status.includes(L('理解', 'thinking'))).forEach(e => Film.sfx('blip', filmAt(e.t), 0.7));
    tl.fromTo(stage, { autoAlpha: 0, y: 40 }, { autoAlpha: 1, y: 0, duration: 0.45 }, line.at - 0.5)
      .to(stage, { autoAlpha: 0, y: -30, duration: 0.35, ease: 'power2.in' }, until - 0.1);
    // Until the agent brings it forward, the app is in the background.
    tl.set(app.root, { opacity: 0.4, scale: 0.975, filter: 'saturate(.5)' }, line.at - 0.5)
      .to(app.root, { opacity: 1, scale: 1, filter: 'saturate(1)', duration: 0.35, ease: 'back.out(2)' }, step(L('切换应用', 'switching apps')) + 0.1);
    /// Outlines over the controls the agent reads: structure, not pixels.
    const outline = (boxes, at) => boxes.forEach(([x, y, w, h, name], i) => {
      const box = el('div', 'abs', app.body); box.style.cssText = `left:${x}px;top:${y}px;width:${w}px;height:${h}px;border:2px solid #62e6ff;border-radius:8px;box-shadow:0 0 16px rgba(98,230,255,.6)`;
      el('span', 'mono', box, name).style.cssText = 'position:absolute;left:-2px;top:-24px;font-size:14px;color:#06202a;background:#62e6ff;padding:2px 7px;border-radius:5px;white-space:nowrap';
      tl.fromTo(box, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.1 }, at + 0.1 + i * 0.09).to(box, { autoAlpha: 0, duration: 0.3 }, at + 0.75 + i * 0.05);
    });
    const finished = text => {
      const badge = el('div', 'abs', app.body, `<span class="chip" style="background:rgba(95,240,176,.18);border-color:rgba(95,240,176,.7);font-size:30px;padding:16px 28px">✓ ${text}</span>`);
      badge.style.cssText = 'right:40px;top:30px';
      tl.fromTo(badge, { autoAlpha: 0, scale: 0.5 }, { autoAlpha: 1, scale: 1, duration: 0.4, ease: 'back.out(2.2)' }, doneAt + 0.05);
    };
    build({ app, step, outline, finished, doneAt, line });
  };

  // 1 · music
  const keynoteSay = vo('say_keynote').at;
  demo({ take: 'ov-cmd-music', say: 'say_music', until: keynoteSay - 0.75, title: L('音乐', 'Music'), build: ({ app, step, outline, finished, doneAt }) => {
    const body = app.body; body.style.background = '#14141d';
    const side = el('div', 'abs', body); side.style.cssText = 'left:0;top:0;bottom:92px;width:230px;background:#191923;padding:22px 16px;font:500 19px/1 var(--zh);color:#8f8dac';
    L(['发现音乐', '私人漫游', '最近播放', '我喜欢的音乐'], ['Discover', 'For you', 'Recently played', 'Liked songs']).forEach((name, i) => el('div', '', side, name).style.cssText = `padding:13px 12px;border-radius:9px;${i === 0 ? 'background:rgba(255,90,110,.2);color:#fff' : ''}`);
    el('div', '', side, L('歌单', 'PLAYLISTS')).style.cssText = 'margin:24px 12px 10px;font-size:14px;letter-spacing:.14em;color:#5f5d7c';
    L(['编程专注', '深夜写代码', 'Lo-Fi 自习室'], ['Coding Focus', 'Late-night coding', 'Lo-Fi study room']).forEach(name => el('div', '', side, name).style.cssText = 'padding:11px 12px');
    const search = el('div', 'abs', body); search.style.cssText = 'left:270px;top:26px;width:440px;height:52px;border-radius:26px;background:#22222f;border:2px solid transparent;padding:0 24px;display:flex;align-items:center;font:500 20px/1 var(--zh);color:#6a6888';
    const query = el('span', '', search, L('搜索音乐、歌单', 'Search songs and playlists'));
    const colors = [[258, L('编程专注', 'Coding Focus')], [200, 'Lo-Fi Beats'], [330, L('电子氛围', 'Electronic Ambient')], [160, L('白噪音', 'White Noise')], [28, L('爵士咖啡馆', 'Jazz Café')], [280, L('合成器浪潮', 'Synthwave')], [210, L('雨声 · 深度工作', 'Rain · Deep Work')], [0, L('后摇精选', 'Post-rock Picks')]];
    const grid = el('div', 'abs', body); grid.style.cssText = 'left:270px;top:110px;right:36px;display:grid;grid-template-columns:repeat(4,1fr);gap:22px';
    colors.forEach(([hue, name]) => el('div', '', grid, `<div style="aspect-ratio:1;border-radius:16px;background:linear-gradient(140deg,hsl(${hue},70%,52%),hsl(${hue + 50},70%,26%))"></div><div style="font:500 18px/1.5 var(--zh);color:#c9c7e2;margin-top:8px">${name}</div>`));
    const results = el('div', 'abs', body); results.style.cssText = 'left:270px;top:110px;right:36px;font:500 21px/1 var(--zh);color:#d6d4ea';
    const tracks = L([['编程专注 · Deep Focus', '歌单 · 86 首'], ['写代码时听的纯音乐', '歌单 · 120 首'], ['Focus Flow', '专辑'], ['专注力：编程与阅读', '歌单 · 54 首'], ['Coding Night', '单曲']],
      [['Coding Focus · Deep Focus', 'Playlist · 86 songs'], ['Instrumentals for writing code', 'Playlist · 120 songs'], ['Focus Flow', 'Album'], ['Concentration: coding and reading', 'Playlist · 54 songs'], ['Coding Night', 'Single']]);
    const rowsEl = tracks.map(([name, kind], i) => el('div', '', results, `<span style="display:inline-block;width:56px;height:56px;border-radius:10px;vertical-align:middle;margin-right:20px;background:linear-gradient(140deg,hsl(${250 + i * 34},70%,55%),hsl(${290 + i * 34},70%,28%))"></span>${name}<span style="float:right;color:#6e6c8e;font-size:17px;line-height:56px">${kind}</span>`));
    rowsEl.forEach(row => row.style.cssText = 'padding:12px 16px;border-radius:14px;margin-bottom:6px');
    gsap.set(results, { autoAlpha: 0 });
    const player = el('div', 'abs', body); player.style.cssText = 'left:0;right:0;bottom:0;height:92px;background:#1d1d29;border-top:1px solid rgba(255,255,255,.07);display:flex;align-items:center;padding:0 30px;gap:22px;font:500 20px/1.3 var(--zh);color:#8f8dac';
    const button = el('div', '', player, '▶'); button.style.cssText = 'width:56px;height:56px;border-radius:50%;background:#2c2c3c;color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px';
    const now = el('div', '', player, L('未在播放', 'Not playing')); now.style.cssText = 'width:300px';
    const bars = el('canvas', '', player); bars.width = 220; bars.height = 56; const bg = bars.getContext('2d');
    const track = el('div', '', player); track.style.cssText = 'flex:1;height:6px;border-radius:3px;background:#2c2c3c;overflow:hidden';
    const fill = el('div', '', track); fill.style.cssText = 'width:100%;height:100%;background:linear-gradient(90deg,#ff5a6e,#ff9a6e);transform-origin:0 50%';
    gsap.set(fill, { scaleX: 0 });

    const typing = step(L('输入文字', 'typing')), reading = step(L('读取界面', 'reading the window')), pressing = step(L('操作界面', 'operating the window'));
    tl.to(search, { borderColor: '#62e6ff', boxShadow: '0 0 0 5px rgba(98,230,255,.2)', duration: 0.2 }, step(L('打开搜索', 'opening search')) + 0.1);
    L('编程 专注', 'coding focus').split('').forEach((_, i, all) => tl.set(query, { innerHTML: `<span style="color:#fff">${all.slice(0, i + 1).join('')}</span>` }, typing + 0.1 + i * L(0.09, 0.045)));
    tl.to(grid, { autoAlpha: 0, duration: 0.2 }, typing + 0.65).to(results, { autoAlpha: 1, duration: 0.25 }, typing + 0.7);
    outline([[270, 110, 884, 80, L('AXRow · 编程专注', 'AXRow · Coding Focus')], [270, 198, 884, 80, 'AXRow'], [270, 286, 884, 80, 'AXRow'], [30, 726, 56, 56, L('AXButton · 播放', 'AXButton · Play')]], reading);
    tl.to(rowsEl[0], { backgroundColor: 'rgba(255,90,110,.24)', duration: 0.2 }, pressing + 0.15)
      .set(button, { innerHTML: '❚❚', backgroundColor: '#ff5a6e' }, pressing + 0.35)
      .set(now, { innerHTML: L('<span style="color:#fff">编程专注 · Deep Focus</span><br>正在播放', '<span style="color:#fff">Coding Focus · Deep Focus</span><br>Now playing') }, pressing + 0.35)
      .to(fill, { scaleX: 0.12, duration: keynoteSay - pressing, ease: 'none' }, pressing + 0.35);
    frame(t => {
      bg.clearRect(0, 0, 220, 56); const on = t > pressing + 0.35 ? 1 : 0.06;
      for (let k = 0; k < 22; k++) { const h = 4 + 50 * on * Math.abs(Math.sin(t * (5 + k % 5) + k * 0.9) * Math.sin(t * 2.3 + k)); bg.fillStyle = `hsl(${350 + k * 3},95%,66%)`; bg.fillRect(k * 10, 56 - h, 6, h); }
    });
    finished(L('已开始播放', 'Now playing'));
  } });

  // 2 · a new deck with a title
  const keynoteEnd = c2.at - 0.6;
  demo({ take: 'ov-cmd-keynote', say: 'say_keynote', until: keynoteEnd, title: L('演示文稿', 'Slides'), build: ({ app, step, outline, finished, doneAt }) => {
    const body = app.body; body.style.background = '#1b1b27';
    const tools = el('div', 'abs', body); tools.style.cssText = 'left:0;right:0;top:0;height:62px;background:#1c1c28;border-bottom:1px solid rgba(255,255,255,.07);display:flex;align-items:center;gap:30px;padding:0 28px;font:500 19px/1 var(--zh);color:#9c9ab8';
    L(['文件', '编辑', '插入', '格式', '排列', '播放'], ['File', 'Edit', 'Insert', 'Format', 'Arrange', 'Play']).forEach(name => el('span', '', tools, name));
    const strip = el('div', 'abs', body); strip.style.cssText = 'left:0;top:62px;bottom:0;width:210px;background:#191923;padding:20px 22px';
    const thumbs = [0, 1, 2].map(i => { const thumb = el('div', '', strip); thumb.style.cssText = `height:94px;border-radius:8px;margin-bottom:16px;background:linear-gradient(140deg,#2b2a44,#1a1930);border:2px solid ${i === 0 ? '#62e6ff' : 'transparent'}`; return thumb; });
    const slide = el('div', 'abs', body); slide.style.cssText = 'left:260px;top:120px;width:880px;height:495px;border-radius:10px;background:radial-gradient(120% 120% at 20% 10%,#6a58e8,#2a2270 55%,#17123f);box-shadow:0 30px 70px rgba(0,0,0,.6);overflow:hidden';
    const old = el('div', 'abs', slide, '<div style="font:800 54px/1.2 var(--en);color:#fff">Q3 Review</div><div style="font:500 24px/2 var(--zh);color:#a7a3d6">' + L('上一份文稿', 'The previous deck') + '</div>'); old.style.cssText = 'left:70px;top:160px';
    const fresh = el('div', 'abs', slide); fresh.style.cssText = 'left:0;right:0;top:150px;text-align:center';
    const heading = el('div', '', fresh, `<span style="color:#55527c">${L('点按以编辑标题', 'Tap to edit the title')}</span>`); heading.style.cssText = 'font:800 52px/1.25 var(--en);color:#fff;padding:0 60px;min-height:140px';
    el('div', '', fresh, L('副标题', 'Subtitle')).style.cssText = 'font:500 26px/2 var(--zh);color:#55527c';
    gsap.set(fresh, { autoAlpha: 0 });
    const menu = el('div', 'menu', body); menu.style.cssText += 'left:16px;top:58px;width:300px';
    L(['新建', '打开…', '最近使用', '存储…'], ['New', 'Open…', 'Open Recent', 'Save…']).forEach((name, i) => el('div', 'row' + (i === 0 ? ' on' : ''), menu, `<span>${name}</span>`));
    gsap.set(menu, { autoAlpha: 0 });

    const read1 = step(L('读取界面', 'reading the window'), 0), pick = step(L('操作界面', 'operating the window')), read2 = step(L('读取界面', 'reading the window'), 1), typing = step(L('输入文字', 'typing'));
    outline([[14, 8, 70, 46, L('AXMenuBarItem · 文件', 'AXMenuBarItem · File')], [260, 120, 880, 495, 'AXLayoutArea'], [16, 78, 180, 100, 'AXImage']], read1);
    tl.fromTo(menu, { autoAlpha: 0, y: -10 }, { autoAlpha: 1, y: 0, duration: 0.18 }, pick + 0.1)
      .to(menu, { autoAlpha: 0, duration: 0.15 }, pick + 0.7)
      .to(old, { autoAlpha: 0, duration: 0.2 }, pick + 0.7).to(fresh, { autoAlpha: 1, duration: 0.3 }, pick + 0.85)
      .to(thumbs.slice(1), { autoAlpha: 0, height: 0, marginBottom: 0, duration: 0.3 }, pick + 0.75);
    outline([[330, 262, 740, 150, L('AXTextArea · 标题', 'AXTextArea · Title')], [540, 420, 320, 60, L('AXTextArea · 副标题', 'AXTextArea · Subtitle')]], read2);
    const text = 'One wand to command them all';
    const span = Math.max(0.9, doneAt - typing - 0.35);
    text.split('').forEach((_, i) => tl.set(heading, { innerHTML: text.slice(0, i + 1) + '<span style="color:#62e6ff">▍</span>' }, typing + 0.15 + (i / text.length) * span));
    tl.set(heading, { innerHTML: 'One <span class="grad">wand</span> to <span class="grad">command</span> them all' }, doneAt);
    finished(L('标题已写好', 'Title written'));
  } });

  // Who is doing this.
  const how = el('div', 'abs', root); how.style.cssText = 'inset:0;transform:scale(1.06);transform-origin:50% 48%';
  gsap.set(how, { autoAlpha: 0 });
  Film.sfx('whoosh', c2.at - 0.4, 0.6); Film.sfx('whoosh-soft', c3.at - 0.3, 0.6); Film.sfx('pop', word('cmd3', L('要发送', 'before')) - 0.1, 0.8); Film.sfx('impact-soft', c4.at - 0.1, 0.9);
  tl.to(how, { autoAlpha: 1, duration: 0.4 }, c2.at - 0.3).to(mood, { glow: 0.8, hue: 226, duration: 1 }, c2.at - 0.3);
  const nodes = L([['🎙', '一句话', '按住命令键说'], ['✦', 'Agent', 'DeepSeek Harness 内核'], ['⚙', '一份工具清单', '找应用 · 读界面 · 按 · 输入'], ['▣', '你的应用', '一次一个，前台窗口']],
    [['🎙', 'A sentence', 'hold the command key'], ['✦', 'Agent', 'runs on DeepSeek Harness'], ['⚙', 'A list of tools', 'find · read · press · type'], ['▣', 'Your apps', 'one at a time, the front window']]);
  const cells = nodes.map(([icon, name, sub], i) => {
    const cell = el('div', 'abs', how); const main = i === 1;
    cell.style.cssText = `left:${150 + i * 420}px;top:250px;width:360px;height:290px;border-radius:32px;text-align:center;padding-top:42px;background:${main ? 'linear-gradient(160deg,rgba(91,84,240,.55),rgba(98,230,255,.16))' : 'rgba(255,255,255,.05)'};border:1px solid ${main ? 'rgba(160,150,255,.9)' : 'rgba(255,255,255,.14)'};box-shadow:${main ? '0 0 90px rgba(110,100,255,.55)' : '0 30px 70px rgba(0,0,0,.4)'}`;
    cell.innerHTML = `<div style="font-size:70px;line-height:1">${icon}</div><div style="font:800 ${main ? 58 : 42}px/1.3 var(--en);margin-top:${main ? 12 : 22}px">${name}</div><div style="font:500 24px/1.5 var(--zh);color:#bdb9e6;margin-top:10px;letter-spacing:.03em">${sub}</div>`;
    if (i < 3) { const arrow = el('div', 'abs', how, '→'); arrow.style.cssText = `left:${150 + i * 420 + 366}px;top:350px;width:48px;text-align:center;font:800 50px/1 var(--en);color:#62e6ff`; tl.fromTo(arrow, { autoAlpha: 0, x: -20 }, { autoAlpha: 1, x: 0, duration: 0.3 }, c2.at + 0.45 + i * 0.3); }
    Film.sfx('pop', i === 1 ? word('cmd2', 'DeepSeek') - 0.5 : c2.at + 0.2 + i * 0.3, 0.6);
    tl.fromTo(cell, { autoAlpha: 0, y: 60, scale: 0.9 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.5, ease: 'back.out(1.6)' }, i === 1 ? word('cmd2', 'DeepSeek') - 0.5 : c2.at + 0.2 + i * 0.3);
    return cell;
  });
  const models = el('div', 'abs', how); models.style.cssText = 'left:0;right:0;top:640px;display:flex;justify-content:center;gap:18px';
  ['DeepSeek', 'OpenAI', 'Anthropic', 'Gemini', L('本地模型', 'Local models'), L('任意兼容地址', 'Any compatible endpoint')].forEach((name, i) => { const chip = el('span', 'chip', models, name); chip.style.fontSize = '30px'; tl.fromTo(chip, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.35, ease: 'back.out(2)' }, word('cmd2', L('模型', 'model')) - 0.1 + i * 0.1); });
  const pick = el('div', 'abs zh-m', how, L('模型，<span class="grad">你来选</span>', 'The model is <span class="grad">yours to choose</span>')); pick.style.cssText += 'left:0;right:0;top:760px;text-align:center';
  tl.fromTo(pick, { autoAlpha: 0, y: 20 }, { autoAlpha: 1, y: 0, duration: 0.4 }, word('cmd2', L('你来选', 'yours')) - 0.1);
  tl.to(how, { autoAlpha: 0, y: -30, duration: 0.35, ease: 'power2.in' }, c3.at - 0.4);

  // How it looks, and when it stops to ask.
  const rules = el('div', 'abs', root); rules.style.cssText = 'inset:0';
  gsap.set(rules, { autoAlpha: 0 });
  tl.to(rules, { autoAlpha: 1, duration: 0.35 }, c3.at - 0.15);
  const left = el('div', 'abs', rules); left.style.cssText = 'left:140px;top:120px;width:800px;transform:scale(1.14);transform-origin:0 0';
  const no = el('div', 'zh-l', left, '<span style="position:relative;display:inline-block">📷<span style="position:absolute;left:-10%;top:46%;width:120%;height:10px;background:#ff5a6e;border-radius:5px;transform:rotate(-38deg);box-shadow:0 0 20px #ff5a6e"></span></span> ' + L('默认不截屏', 'No screenshots')); no.style.fontSize = L('84px', '76px');
  if (Film.lang === 'en') el('div', '', no, 'by default').style.cssText = 'font:600 32px/1.2 var(--en);letter-spacing:0;color:#a7a3d6;margin:2px 0 0 104px';
  tl.fromTo(no, { autoAlpha: 0, x: -40 }, { autoAlpha: 1, x: 0, duration: 0.45, ease: 'back.out(1.6)' }, word('cmd3', L('不截屏', 'screenshots')) - 0.1);
  const tree = el('pre', 'mono', left); tree.style.cssText = 'margin-top:36px;font-size:27px;line-height:1.75;color:#b8f3ff;background:rgba(10,24,36,.75);border:1px solid rgba(98,230,255,.4);border-radius:20px;padding:28px 34px';
  L(['AXWindow  "音乐"', '├─ AXTextField  "搜索"', '├─ AXList', '│   ├─ AXRow  "编程专注"', '│   └─ AXRow  …', '└─ AXButton  "播放"'],
    ['AXWindow  "Music"', '├─ AXTextField  "Search"', '├─ AXList', '│   ├─ AXRow  "Coding Focus"', '│   └─ AXRow  …', '└─ AXButton  "Play"']).forEach((row, i) => { const line = el('div', '', tree, row.replace(/"(.*?)"/g, '<span style="color:#ffd9a0">"$1"</span>')); tl.fromTo(line, { autoAlpha: 0, x: -16 }, { autoAlpha: 1, x: 0, duration: 0.25 }, word('cmd3', L('系统', 'reads')) - 0.2 + i * 0.16); });
  const note = el('div', 'zh-s', left, L('读的是结构：控件的种类、名字、状态', 'It reads structure: what a control is, its name, its state')); note.style.cssText = 'margin-top:22px;color:#a9d8e6';
  tl.fromTo(note, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.4 }, word('cmd3', L('界面结构', 'structure')) + 0.3);
  const ask = el('div', 'abs', rules); ask.style.cssText = 'left:1090px;top:200px;width:700px;border-radius:30px;background:rgba(22,20,30,.94);border:1px solid rgba(255,207,107,.7);box-shadow:0 0 90px rgba(255,180,90,.25),0 40px 90px rgba(0,0,0,.6);padding:34px 40px';
  ask.innerHTML = `<div style="font:700 24px/1 var(--zh);color:#ffcf6b;letter-spacing:.08em">${L('命令 · 等你确认', 'Command · waiting for you')}</div><div style="font:700 44px/1.35 var(--zh);margin:22px 0 28px">${L('把这条消息<span class="grad-hot">发出去</span>吗？', '<span class="grad-hot">Send</span> this message?')}</div><div style="display:flex;gap:16px"><span class="chip hot" style="font-size:30px;padding:16px 34px">${L('确认', 'Confirm')}</span><span class="chip" style="font-size:30px;padding:16px 34px">${L('停止', 'Stop')}</span></div>`;
  tl.fromTo(ask, { autoAlpha: 0, y: 50, scale: 0.92 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.5, ease: 'back.out(1.6)' }, word('cmd3', L('要发送', 'before')) - 0.15);
  const risky = el('div', 'abs', rules); risky.style.cssText = 'left:1090px;top:600px;width:720px;display:flex;gap:14px;flex-wrap:wrap';
  L(['发送', '删除', '提交', '付款'], ['Send', 'Delete', 'Submit', 'Pay']).forEach((name, i) => { const chip = el('span', 'chip', risky, name + L(' · 先问你', ' · asks first')); chip.style.fontSize = '27px'; tl.fromTo(chip, { autoAlpha: 0, scale: 0.6 }, { autoAlpha: 1, scale: 1, duration: 0.3, ease: 'back.out(2)' }, word('cmd3', L('先问你', 'asks')) - 0.5 + i * 0.14); });
  tl.to(rules, { autoAlpha: 0, scale: 0.96, duration: 0.35, ease: 'power2.in' }, c4.at - 0.4);

  // The Chinese name, earned.
  tl.to(mood, { glow: 1.0, hue: 268, duration: 0.8 }, c4.at - 0.3);
  Mock.kinetic(root, 'cmd4', L([[['<span class="grad">如意魔棒</span>', '如意']]], [[['<span class="grad">VibeWand</span>', 'VibeWand']]]), { cls: 'zh-xl', x: 0, y: 250, align: 'center', out: end - 0.45 }).style.fontSize = '190px';
  Mock.kinetic(root, 'cmd4', L([['一句话，', ['<span class="grad-hot">如你所意</span>。', '如你']]], [[['Your word ', 'Your'], ['is its ', 'is'], ['<span class="grad-hot">command</span>.', 'command']]]), { cls: 'zh-l', x: 0, y: 540, align: 'center', out: end - 0.45 });
});
