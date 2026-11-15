// 生成「打点表」：从三关叠轨音乐用到的每段 loop（wav）里找出每一下声音落在第几拍。
// 低 / 中 / 高三个频段分开找（大致对应底鼓 / 军鼓拍手 / 镲），另外有一个不分频段的 all。
// 输出到 stages/shared/beat_fx/hits/，路径照 assets/audio/ 下的路径，扩展名换成 .json。
// BeatFx 组件在游戏里读这些表，按音乐正在放的那段 loop 触发效果。
//
// 用法（在项目根目录）：node stages/shared/beat_fx/tools/make_hit_tables.mjs
// 换了音乐、加了新 loop 以后重跑一次。只读 wav，不改音乐文件。

import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const LEVEL_JSONS = ['levels/music/level_1_disco.json', 'levels/music/level_2_tv_wall.json', 'levels/music/level_3_spaceship.json'];
const OUT_DIR = 'stages/shared/beat_fx/hits';

const HOP = 256;          // 每帧 256 个采样（44.1kHz 下约 5.8 毫秒）
const WIN = 512;          // 算能量的窗口
const MIN_GAP_SEC = 0.07; // 同一频段两下之间至少隔这么久
const BANDS = {
  low: (x, sr) => lowpass(lowpass(x, 150, sr), 150, sr),
  mid: (x, sr) => sub(lowpass(x, 3000, sr), lowpass(x, 250, sr)),
  high: (x, sr) => sub(x, lowpass(x, 5000, sr)),
  all: (x) => x,
};

function readWav(file) {
  const b = fs.readFileSync(file);
  if (b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') throw new Error('不是 wav：' + file);
  let off = 12, fmt = null, data = null;
  while (off + 8 <= b.length) {
    const id = b.toString('ascii', off, off + 4), size = b.readUInt32LE(off + 4);
    if (id === 'fmt ') fmt = { channels: b.readUInt16LE(off + 10), rate: b.readUInt32LE(off + 12), bits: b.readUInt16LE(off + 22) };
    if (id === 'data') data = b.subarray(off + 8, off + 8 + size);
    off += 8 + size + (size % 2);
  }
  if (!fmt || !data || fmt.bits !== 16) throw new Error('只支持 16 位 PCM：' + file);
  const n = Math.floor(data.length / (2 * fmt.channels));
  const x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    let s = 0;
    for (let c = 0; c < fmt.channels; c++) s += data.readInt16LE((i * fmt.channels + c) * 2);
    x[i] = s / fmt.channels / 32768;
  }
  return { x, rate: fmt.rate };
}

function lowpass(x, fc, sr) {
  const a = Math.exp(-2 * Math.PI * fc / sr);
  const y = new Float32Array(x.length);
  let v = 0;
  for (let i = 0; i < x.length; i++) { v = (1 - a) * x[i] + a * v; y[i] = v; }
  return y;
}

function sub(a, b) {
  const y = new Float32Array(a.length);
  for (let i = 0; i < a.length; i++) y[i] = a[i] - b[i];
  return y;
}

// loop 是首尾相接的：前面补上结尾的一小段，第 0 拍那一下才找得到
function circular(x, pad) {
  const y = new Float32Array(x.length + pad);
  y.set(x.subarray(x.length - pad), 0);
  y.set(x, pad);
  return y;
}

// 在这一帧附近按 32 个采样一小格找起音：第一个超过这一带最大值 30% 的小格
function attackSample(signal, f) {
  const from = Math.max(0, (f - 2) * HOP), to = Math.min(signal.length - 32, f * HOP + WIN);
  const cells = [];
  for (let i = from; i < to; i += 32) {
    let s = 0;
    for (let k = 0; k < 32; k++) s += Math.abs(signal[i + k]);
    cells.push(s / 32);
  }
  const top = cells.reduce((m, v) => Math.max(m, v), 0);
  const quiet = cells.slice(0, 4).reduce((m, v) => Math.min(m, v), Infinity);
  for (let c = 0; c < cells.length; c++) if (cells[c] > quiet + (top - quiet) * 0.3) return from + c * 32;
  return f * HOP;
}

function findHits(signal, sr, pad, beatsTotal, duration, fullMax) {
  const frames = Math.floor((signal.length - WIN) / HOP);
  const rms = new Float32Array(frames), loge = new Float32Array(frames);
  for (let f = 0; f < frames; f++) {
    let s = 0;
    for (let i = 0; i < WIN; i++) { const v = signal[f * HOP + i]; s += v * v; }
    rms[f] = Math.sqrt(s / WIN);
    loge[f] = Math.log(rms[f] + 1e-6);
  }
  const maxRms = rms.reduce((m, v) => Math.max(m, v), 0);
  // 这个频段整体比全频段小很多（比如只有镲的 loop 的低频段）：当作这个频段没有声音
  if (maxRms < 1e-4 || maxRms < 0.12 * fullMax) return [];
  const rise = new Float32Array(frames);
  for (let f = 2; f < frames; f++) rise[f] = Math.max(0, loge[f] - Math.min(loge[f - 1], loge[f - 2]));
  const maxRise = rise.reduce((m, v) => Math.max(m, v), 0);
  const minGap = Math.round(MIN_GAP_SEC * sr / HOP);
  const peaks = [];
  for (let f = 3; f < frames - 3; f++) {
    if (rise[f] < 0.25 * maxRise || rise[f] < 0.35) continue;
    let local = true;
    for (let k = -3; k <= 3; k++) if (k !== 0 && rise[f + k] > rise[f]) { local = false; break; }
    if (!local) continue;
    // 这一下有多响：起音之后 30 毫秒内的最大能量
    let level = 0;
    for (let k = 0; k < Math.round(0.03 * sr / HOP) && f + k < frames; k++) level = Math.max(level, rms[f + k]);
    if (level < 0.06 * maxRms) continue; // 太小声的（混响尾巴、底噪）不要
    if (peaks.length && f - peaks[peaks.length - 1].f < minGap) {
      if (level > peaks[peaks.length - 1].level) peaks[peaks.length - 1] = { f, level };
      continue;
    }
    peaks.push({ f, level });
  }
  const out = [];
  for (const p of peaks) {
    const t = (attackSample(signal, p.f) - pad) / sr;
    if (t < -0.02 || t >= duration - 0.005) continue;
    let beat = ((t % duration) + duration) % duration / duration * beatsTotal;
    const grid = Math.round(beat * 48) / 48; // 生成的音乐基本卡在格子上：离 16 分 / 三连音格子很近就对齐
    if (Math.abs(grid - beat) < 0.025) beat = grid;
    if (beat >= beatsTotal - 1e-6) beat = 0;
    out.push([Math.round(beat * 1000) / 1000, Math.round(Math.min(1, p.level / maxRms) * 100) / 100]);
  }
  out.sort((a, b) => a[0] - b[0]);
  return out;
}

function peakRms(x) {
  let top = 0;
  for (let f = 0; f + WIN <= x.length; f += HOP) {
    let s = 0;
    for (let i = 0; i < WIN; i++) s += x[f + i] * x[f + i];
    top = Math.max(top, Math.sqrt(s / WIN));
  }
  return top;
}

const clips = new Map();
for (const j of LEVEL_JSONS) {
  const d = JSON.parse(fs.readFileSync(path.join(ROOT, j), 'utf8'));
  for (const lane of d.lanes || []) for (const c of lane.clips || []) {
    if (typeof c.file === 'string' && c.file.endsWith('.wav')) clips.set(c.file, true);
  }
}

let written = 0;
for (const res of [...clips.keys()].sort()) {
  const file = path.join(ROOT, res.replace('res://', ''));
  const m = path.basename(file).match(/_(\d+)b\.wav$/);
  if (!m) { console.warn('文件名里没有小节数，跳过：' + res); continue; }
  const beatsTotal = Number(m[1]) * 4;
  const { x, rate } = readWav(file);
  const duration = x.length / rate;
  const pad = Math.round(0.1 * rate);
  const table = { source: res, beats: beatsTotal, bands: {} };
  const fullMax = peakRms(x);
  for (const [name, filter] of Object.entries(BANDS)) {
    table.bands[name] = findHits(circular(filter(x, rate), pad), rate, pad, beatsTotal, duration, fullMax);
  }
  const rel = res.replace('res://assets/audio/', '').replace(/\.wav$/, '.json');
  const outFile = path.join(ROOT, OUT_DIR, rel);
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, JSON.stringify(table));
  written++;
  console.log(rel.padEnd(52), Object.entries(table.bands).map(([k, v]) => k + ' ' + v.length).join('  '));
}
console.log('写了 ' + written + ' 张打点表 → ' + OUT_DIR);
