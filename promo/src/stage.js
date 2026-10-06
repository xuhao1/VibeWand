// The stage every scene is built on. Nothing here runs on a clock: the page shows whatever moment `film.seek(t)`
// names, so a frame can be rendered at any time, in any order, by any number of browsers at once.
const Film = (() => {
  const DATA = window.DATA;
  const tl = gsap.timeline({ paused: true, defaults: { ease: 'power3.out' } });
  const hooks = [];
  const cues = [];
  /// Something to be heard at a moment of the film; the mixer places the sound.
  const sfx = (name, at, gain = 1) => { cues.push({ name, at: Math.round(at * 1000) / 1000, gain }); };
  let pending = [];

  const el = (tag, cls, parent, html) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (html !== undefined) node.innerHTML = html;
    if (parent) parent.appendChild(node);
    return node;
  };
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, p) => a + (b - a) * p;
  const ease = { out: p => 1 - Math.pow(1 - p, 3), inOut: p => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2), back: p => 1 + 2.70158 * Math.pow(p - 1, 3) + 1.70158 * Math.pow(p - 1, 2) };
  /// 0 before `a`, 1 after `b`, eased in between.
  const span = (t, a, b, curve = ease.inOut) => curve(clamp((t - a) / (b - a)));
  /// A value read off a list of [time, value] points, straight lines between them.
  const along = (points, t) => {
    if (t <= points[0][0]) return points[0][1];
    for (let i = 1; i < points.length; i++) {
      if (t <= points[i][0]) { const [t0, v0] = points[i - 1], [t1, v1] = points[i]; return lerp(v0, v1, (t - t0) / (t1 - t0 || 1)); }
    }
    return points[points.length - 1][1];
  };
  /// The other way round: the time at which a rising list of [time, value] points reaches `value`.
  const reach = (points, value) => {
    for (let i = 1; i < points.length; i++) {
      const [t0, v0] = points[i - 1], [t1, v1] = points[i];
      if (value >= v0 && value <= v1 && v1 > v0) return lerp(t0, t1, (value - v0) / (v1 - v0));
    }
    return value < points[0][1] ? points[0][0] : points[points.length - 1][0];
  };
  /// The same sequence of numbers on every run.
  const random = seed => () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed); x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };

  const vo = id => DATA.vo[id];
  /// When the narrator reaches some text: the start of the spoken word in which its `nth` occurrence begins.
  const word = (id, text, nth = 0) => {
    const words = vo(id).words, joined = words.map(w => w[0]).join('');
    let from = -1;
    for (let i = 0; i <= nth; i++) from = joined.indexOf(text, from + 1);
    if (from < 0) { console.warn('no word', id, text); return vo(id).at; }
    let seen = 0;
    for (const w of words) { seen += w[0].length; if (from < seen) return w[1]; }
    return vo(id).at;
  };

  /// A layer shown for the scene's stretch of the timeline. `build` gets times relative to the film.
  const scene = (name, build) => {
    const [start, end] = DATA.scenes[name];
    const root = el('div', 'scene scene-' + name, document.getElementById('scenes'));
    gsap.set(root, { autoAlpha: 0 });
    tl.set(root, { autoAlpha: 1 }, start).set(root, { autoAlpha: 0 }, end);
    const api = { root, start, end, name, frame: fn => hooks.push(t => { if (t >= start - 0.001 && t < end) fn(t); }) };
    build(api);
    return api;
  };

  /// Shows frame `clipTime` of a filmed take in an <img>.
  const showTake = (img, take, clipTime) => {
    const info = DATA.takes[take];
    if (!info) return;
    const index = clamp(Math.round(clipTime * info.fps) + 1, 1, info.frames);
    if (img._index === index && img._take === take) return;
    img._index = index; img._take = take;
    img.src = `../../output/promo/seq/${take}/${String(index).padStart(5, '0')}.png`;
    pending.push(img.decode().catch(() => {}));
  };
  /// When something happened in a take, in the take's own seconds.
  const takeEvents = (take, match) => (DATA.takes[take]?.events || []).filter(match).map(e => e.t);

  // Subtitles follow the narration; a spoken command is shown by its scene instead.
  const captions = () => {
    const layer = document.getElementById('captions');
    for (const [id, line] of Object.entries(DATA.vo)) {
      if (line.role !== 'narrator') continue;
      const text = line.text.replace(/[。]$/u, '').replace(/——$/u, '');
      const row = el('div', 'caption', layer, `<span>${text}</span>`);
      gsap.set(row, { autoAlpha: 0, y: 8 });
      tl.to(row, { autoAlpha: 1, y: 0, duration: 0.18 }, line.at - 0.06)
        .to(row, { autoAlpha: 0, duration: 0.2, ease: 'power1.in' }, line.at + line.seconds + 0.12);
    }
  };

  const ready = () => {
    captions();
    Backdrop.build();
    const fade = document.getElementById('fade');
    gsap.set(fade, { autoAlpha: 1 });
    tl.to(fade, { autoAlpha: 0, duration: 0.9, ease: 'power1.out' }, 0.15)
      .to(fade, { autoAlpha: 1, duration: 1.4, ease: 'power1.in' }, DATA.duration - 1.5);
    tl.set({}, {}, DATA.duration);
    const grain = document.getElementById('grain');
    hooks.push(t => { const r = random(Math.round(t * DATA.fps) + 7); grain.style.backgroundPosition = `${Math.floor(r() * 256)}px ${Math.floor(r() * 256)}px`; });
    window.film = {
      duration: DATA.duration, fps: DATA.fps, cues,
      async seek(t) {
        tl.time(t, false);
        for (const hook of hooks) hook(t);
        const waiting = pending; pending = [];
        await Promise.all(waiting);
        await document.fonts.ready;
      },
    };
    document.fonts.ready.then(() => { window.filmReady = true; });
  };

  return { DATA, tl, el, sfx, clamp, lerp, ease, span, along, reach, random, vo, word, scene, showTake, takeEvents, ready, frame: fn => hooks.push(fn) };
})();

// What lies behind everything: a dark field with slow light and a few stars, brighter when a scene asks.
const Backdrop = (() => {
  /// Scenes turn these on the timeline: how much light there is, its colour, and how far the stars drift.
  const mood = { glow: 0.0, hue: 258, warp: 0, grid: 0, lift: 0 };
  const build = () => {
    const canvas = document.getElementById('backdrop'), g = canvas.getContext('2d');
    const r = Film.random(42);
    const stars = Array.from({ length: 170 }, () => ({ x: r(), y: r(), z: 0.2 + r() * 0.8, p: r() * 6.28 }));
    Film.frame(t => {
      g.globalCompositeOperation = 'source-over';
      const base = g.createLinearGradient(0, 0, 0, 1080);
      base.addColorStop(0, `hsl(${mood.hue - 14}, 46%, ${2.2 + mood.lift * 4}%)`);
      base.addColorStop(1, `hsl(${mood.hue + 6}, 52%, ${4 + mood.lift * 7}%)`);
      g.fillStyle = base; g.fillRect(0, 0, 1920, 1080);
      g.globalCompositeOperation = 'lighter';
      const blobs = [[0.22, 0.30, 760, mood.hue, 0.050, 0.07], [0.78, 0.64, 860, mood.hue + 36, 0.041, 0.09], [0.52, 0.92, 700, mood.hue - 42, 0.033, 0.05]];
      blobs.forEach(([x, y, size, hue, speed, drift], i) => {
        const cx = (x + Math.sin(t * speed * 6.28 + i * 2.1) * drift) * 1920, cy = (y + Math.cos(t * speed * 5.1 + i) * drift) * 1080;
        const glow = g.createRadialGradient(cx, cy, 0, cx, cy, size);
        glow.addColorStop(0, `hsla(${hue}, 88%, 58%, ${0.30 * mood.glow})`);
        glow.addColorStop(0.5, `hsla(${hue + 10}, 80%, 42%, ${0.10 * mood.glow})`);
        glow.addColorStop(1, 'hsla(0,0%,0%,0)');
        g.fillStyle = glow; g.fillRect(0, 0, 1920, 1080);
      });
      if (mood.grid > 0.001) {
        // A floor of lines running to the horizon.
        g.strokeStyle = `hsla(${mood.hue + 10}, 90%, 70%, ${0.14 * mood.grid})`; g.lineWidth = 1;
        const horizon = 640, shift = (t * 0.22) % 1;
        g.beginPath();
        for (let i = 0; i < 16; i++) { const p = Math.pow((i + shift) / 16, 2.2); const y = horizon + p * (1080 - horizon); g.moveTo(0, y); g.lineTo(1920, y); }
        for (let i = -14; i <= 14; i++) { g.moveTo(960 + i * 46, horizon); g.lineTo(960 + i * 330, 1080); }
        g.stroke();
      }
      for (const s of stars) {
        const x = ((s.x + t * 0.0016 * s.z + mood.warp * s.z * 0.12) % 1) * 1920, y = s.y * 1080;
        const a = (0.25 + 0.75 * (0.5 + 0.5 * Math.sin(t * 1.3 * s.z + s.p))) * s.z * (0.25 + 0.75 * mood.glow);
        g.fillStyle = `hsla(${mood.hue + 20}, 80%, 86%, ${a * 0.8})`;
        g.beginPath(); g.arc(x, y, 0.6 + s.z * 1.3, 0, 6.28); g.fill();
      }
      g.globalCompositeOperation = 'source-over';
      const shade = g.createRadialGradient(960, 520, 420, 960, 540, 1250);
      shade.addColorStop(0, 'rgba(0,0,0,0)'); shade.addColorStop(1, 'rgba(0,0,0,0.62)');
      g.fillStyle = shade; g.fillRect(0, 0, 1920, 1080);
    });
  };
  return { mood, build };
})();
