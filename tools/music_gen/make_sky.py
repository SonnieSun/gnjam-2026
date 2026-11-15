"""The sky level (the cat is pulled up through the clouds, a storm with doom horns, then it suddenly
turns bright and holy and the Ode to Joy starts) and the bridge between two levels.

Loops, 8 bars, in C (C minor for the storm, C major for the light: the Ode to Joy stems are in C major, so
the storm resolving into them is the "it suddenly turns bright" moment):
  <loops>/sky/sky_drone_8b.wav        a low C and a dark C minor pad: the bass of the ascent
  <loops>/sky/sky_wind_8b.wav         flying through the clouds: wind, and clouds rushing past from side to side
  <loops>/sky/sky_doom_horns_8b.wav   doom horns: a long low brass blast every two bars (C, C, Ab, G), with thunder
  <loops>/sky/sky_metal_riff_8b.wav   the storm's riff: distorted, palm-muted power chords in a gallop (C, C, Ab, G)
  <loops>/sky/sky_blast_drums_8b.wav  the storm's drums: double kick on every 16th, snare on 2 and 4, and a kitten
                                      'mi' on the off-beats so it stays cute
  <loops>/sky/sky_holy_pad_8b.wav     a bright C major pad with a cat choir "aah" and high bells
  <loops>/sky/bridge_wait_4b.wav      4 bars to wait on between two levels: wind, a slow heartbeat, a low C
One-shots:
  <sfx>/sky_whoosh_up.wav    the cat flies off the top of the screen: a rising sweep and a meow sliding up
  <sfx>/sky_holy_hit.wav     the moment the light comes on: a big C major chord with bells
  <sfx>/count_in.wav         one bar, four rising kitten 'mi': the count-in when the player starts a level

usage: python -I make_sky.py <loops dir> <deliver sfx dir>
"""
import contextlib
import io
import os
import sys

import numpy as np

LOOPS, SFX = sys.argv[1], sys.argv[2]
sys.argv = [sys.argv[0], LOOPS, '__none__']          # compose_classics: load the cats, render no song
sys.path.insert(0, os.path.dirname(__file__))
with contextlib.redirect_stdout(io.StringIO()):
    import compose_classics as cc
from audio import (BAR, SR, bandpass, highpass, lowpass, mtof, noise, osc_saw, osc_sine, osc_supersaw, pan,  # noqa: E402
                   place, read_wav, reverb, softclip, t2n, wrap, write_wav)

OUT = os.path.join(LOOPS, 'sky')
os.makedirs(OUT, exist_ok=True)
DISC = os.path.join(LOOPS, 's1_disc')
rng = np.random.default_rng(42)
BARS = 8
N = t2n(BARS * BAR)
BAR_N = t2n(BAR)


def st_noise(n):
    return np.stack([noise(n), noise(n)], 1)


def level(x, target):
    return x * target / (np.sqrt(np.mean(x ** 2)) + 1e-9)


def save_loop(name, x, target, bars=BARS):
    x = level(wrap(x, t2n(bars * BAR)), target)
    x *= 1.0 / max(1.0, np.max(np.abs(x)) / 0.98)
    write_wav(os.path.join(OUT, f'{name}_{bars}b.wav'), x, peak=None)
    print(f'  {name}_{bars}b: rms {np.sqrt(np.mean(x ** 2)):.3f} peak {np.max(np.abs(x)):.2f}')


def save_sfx(name, x, peak=0.9):
    f = t2n(0.03)
    x[-f:] *= np.linspace(1, 0, f)[:, None]
    write_wav(os.path.join(SFX, name + '.wav'), x, peak=peak)
    print(f'  {name}: {len(x) / SR:.2f} s')


# --- the drone: a low C and a C minor pad, breathing slowly --------------------------------------
t = np.arange(N) / SR
sub = pan(osc_sine(mtof(36), N) * 0.9 + lowpass(np.stack([osc_saw(mtof(48), N)] * 2, 1), 260)[:, 0] * 0.35, 0.0)
pad = sum(osc_supersaw(mtof(m), N, voices=5, detune=0.3) for m in (48, 51, 55)) / 3
pad = lowpass(pad, 850) * (0.6 + 0.4 * np.sin(2 * np.pi * t / (2 * BAR)))[:, None]
save_loop('sky_drone', sub + pad * 0.7, 0.10)

# --- flying through the clouds: wind, and clouds rushing past from one side to the other -------------
tail = t2n(3.0)
x = np.zeros((N + tail, 2))
wind = bandpass(st_noise(N), 250, 1600) * (0.45 + 0.4 * np.sin(2 * np.pi * t / (4 * BAR) + 1.0) + 0.15 * np.sin(2 * np.pi * t / 0.9))[:, None]
x[:N] += wind * 0.6
for i, at in enumerate((0.4, 1.7, 2.9, 4.2, 5.4, 6.8)):  # a cloud every bar or so, alternating sides
    n = t2n(1.1)
    k = np.arange(n) / n
    body = bandpass(noise(n)[:, None] * np.ones((1, 2)), 350, 2600)[:, 0] * np.sin(np.pi * k) ** 2
    side = (k if i % 2 == 0 else 1 - k) * 0.9 + 0.05      # 0 = left, 1 = right: it crosses the screen
    cloud = np.stack([body * np.cos(side * np.pi / 2), body * np.sin(side * np.pi / 2)], 1)
    place(x, cloud, t2n(at * BAR), 1.6)
save_loop('sky_wind', x, 0.06)

# --- doom horns: a long low brass blast every two bars -----------------------------------------------
x = np.zeros((N + t2n(2.5), 2))
for i, root in enumerate((36, 36, 32, 31)):             # C, C, Ab, G
    n = t2n(1.7 * BAR)
    k = np.arange(n) / SR
    swell = np.clip(k / 0.35, 0, 1) ** 1.5 * np.clip((n / SR - k) / 0.45, 0, 1)
    bright = np.clip(k / 0.9, 0, 1) * np.clip((n / SR - k) / 0.6, 0, 1)        # the brass opens up as it grows
    voice = sum(osc_supersaw(mtof(m), n, voices=5, detune=0.22, stereo=0.5) * g for m, g in ((root, 1.0), (root + 12, 0.8), (root + 19, 0.5)))
    blast = (lowpass(voice, 420) + lowpass(voice, 1500) * bright[:, None] * 0.8) * swell[:, None]
    place(x, softclip(blast * 1.6, 1.5), t2n(i * 2 * BAR))
x = reverb(x, 2.2, 0.5, mix=0.28)
x = np.concatenate([x, np.zeros((t2n(2.0), 2))])
for bar in (1.5, 5.5):                                   # thunder between the blasts
    n = t2n(3.5)
    k = np.arange(n) / SR
    rumble = lowpass(st_noise(n), 110) * (np.exp(-k / 1.1) * (1 + 0.6 * np.sin(2 * np.pi * 7 * k) * np.exp(-k / 0.6)))[:, None]
    crack = bandpass(st_noise(n), 600, 3000) * (np.exp(-k / 0.08))[:, None] * 0.25
    place(x, rumble * 9 + crack, t2n(bar * BAR), 0.012)
save_loop('sky_doom_horns', x, 0.13)

# --- the storm as cute death metal: a galloping chug riff, double-kick drums with a kitten on the off-beats
STEP_N = BAR_N / 16.0
x = np.zeros((N + t2n(1.0), 2))
GALLOP = 'x.xxx.xxx.xxx.xx'                               # the metal gallop (and the eurobeat one)
for bar in range(BARS):
    root = (36, 36, 32, 31)[bar // 2]
    last = bar % 2 == 1
    for i, ch in enumerate(GALLOP):
        if ch != 'x' or (last and i >= 8):
            continue
        n = int(STEP_N * 0.85)
        k = np.arange(n) / SR
        for side, cents in ((-0.8, -6), (0.8, 7)):        # two takes, left and right
            f = 2 ** (cents / 1200)
            v = sum(osc_saw(mtof(m) * f, n) * g for m, g in ((root, 1.0), (root + 7, 0.8), (root + 12, 0.6)))
            v = np.tanh(v * 6.0) * np.exp(-k / 0.055) * np.clip(k / 0.002, 0, 1)      # distorted and palm-muted
            place(x, pan(v, side), int(bar * BAR_N + i * STEP_N), 1.0 if i % 4 == 0 else 0.75)
    if last:                                              # every second bar ends on a chord left to ring
        n = int(STEP_N * 7.5)
        k = np.arange(n) / SR
        for side, cents in ((-0.8, -6), (0.8, 7)):
            f = 2 ** (cents / 1200)
            v = sum(osc_saw(mtof(m) * f, n) * g for m, g in ((root, 1.0), (root + 7, 0.9), (root + 12, 0.7), (root + 19, 0.4)))
            v = np.tanh(v * 5.0) * np.exp(-k / 0.5) * np.clip(k / 0.003, 0, 1)
            place(x, pan(v, side), int(bar * BAR_N + 8 * STEP_N), 0.9)
x = lowpass(highpass(x, 85), 4200) + bandpass(x, 900, 2400) * 0.5         # a guitar cabinet, roughly
save_loop('sky_metal_riff', x, 0.11)

x = np.zeros((N + t2n(1.5), 2))
kick = read_wav(os.path.join(DISC, 's1_disc_kick.wav'))
clap = read_wav(os.path.join(DISC, 's1_disc_clap.wav'))
crash = read_wav(os.path.join(DISC, 's1_disc_crash.wav'))
mi_tick = read_wav(os.path.join(SFX, 'kitten_mi.wav'))[: t2n(0.07)]
for bar in range(BARS):
    for i in range(16):
        place(x, kick[: int(STEP_N * 1.6)], int(bar * BAR_N + i * STEP_N), 0.85 if i % 4 == 0 else 0.5)
    for i in (4, 12):
        place(x, clap, int(bar * BAR_N + i * STEP_N), 0.8)
    for i in (2, 6, 10, 14):                              # the kitten is the hi-hat
        place(x, mi_tick, int(bar * BAR_N + i * STEP_N), 0.45, semitones=5.0)
    if bar % 4 == 0:
        place(x, crash, bar * BAR_N, 0.5)
save_loop('sky_blast_drums', x, 0.075)

# --- the holy pad: C major, a cat choir, high bells --------------------------------------------------
x = np.zeros((N + t2n(3.0), 2))
pad = sum(osc_supersaw(mtof(m), N, voices=7, detune=0.35) for m in (60, 64, 67, 72, 79)) / 5
pad = lowpass(highpass(pad, 180), 6500) * (0.75 + 0.25 * np.sin(2 * np.pi * t / (2 * BAR)))[:, None]
x[:N] += pad * 0.8
long_cats = cc.LONG
for i in range(4):                                       # the choir: three cats hold a C major chord for two bars
    for j, m in enumerate((72, 76, 79)):
        v = cc.sing_miao(long_cats[(i + j) % len(long_cats)], m, 1.8 * BAR, keep=0.08)
        place(x, pan(v, (j - 1) * 0.5), t2n(i * 2 * BAR), 0.5)
for i in range(BARS * 4):                                # bells: a random chord tone on most beats
    if rng.random() < 0.7:
        m = rng.choice([84, 88, 91, 96])
        n = t2n(1.2)
        k = np.arange(n) / SR
        place(x, pan(osc_sine(mtof(m), n) * np.exp(-k / 0.35), rng.uniform(-0.7, 0.7)), t2n(i * BAR / 4), 0.22)
x = reverb(x, 2.8, 0.55, mix=0.35)
save_loop('sky_holy_pad', x, 0.085)

# --- the waiting loop between two levels: wind, a slow heartbeat, a low C ------------------------------
n4 = t2n(4 * BAR)
t4 = np.arange(n4) / SR
x = np.zeros((n4 + t2n(1.5), 2))
x[:n4] += bandpass(st_noise(n4), 300, 1400) * (0.5 + 0.35 * np.sin(2 * np.pi * t4 / (2 * BAR)))[:, None] * 0.5
x[:n4] += pan(osc_sine(mtof(36), n4), 0.0) * 0.8
kick = read_wav(os.path.join(DISC, 's1_disc_kick.wav'))
kick = lowpass(kick, 180)
for bar in range(4):                                     # lub-dub on the first beat of every bar
    place(x, kick, t2n(bar * BAR), 1.0)
    place(x, kick, t2n(bar * BAR + BAR / 8), 0.55)
save_loop('bridge_wait', x, 0.07, bars=4)

# --- one-shots ---------------------------------------------------------------------------------------
# the cat flies off the top: a sweep going up and a meow sliding up with it
n = t2n(2.0)
k = np.arange(n) / SR
x = np.zeros((n + t2n(1.0), 2))
sweep_f = 200 * (3200 / 200) ** (k / 2.0)
sweep = np.sin(2 * np.pi * np.cumsum(sweep_f) / SR) * (k / 2.0) ** 1.5 * 0.35
x[:n] += pan(sweep, 0.0) + highpass(st_noise(n), 3000) * ((k / 2.0) ** 3)[:, None] * 0.3
cat = cc.LONG[0]
cat = cat.mean(axis=1) if cat.ndim == 2 else cat
rate = 0.8 * (3.0 / 0.8) ** (k / 2.0)                    # the meow starts a little low and slides up two octaves
pos = np.cumsum(rate)
pos = pos[pos < len(cat) - 1] if pos[-1] >= len(cat) - 1 else pos
# loop the middle of the meow if it runs out before the slide ends
src = np.interp(np.mod(np.cumsum(rate), len(cat) * 0.8) + len(cat) * 0.1, np.arange(len(cat)), cat)
x[:n] += pan(src * np.clip(k / 0.05, 0, 1) * np.clip((2.0 - k) / 0.25, 0, 1), 0.0) * 0.8
save_sfx('sky_whoosh_up', reverb(x, 1.2, 0.4, mix=0.2))

# the light comes on: a big C major chord, a crash, bells
n = t2n(3.6)
k = np.arange(n) / SR
chord = sum(osc_supersaw(mtof(m), n, voices=7, detune=0.3) * g for m, g in ((36, 0.9), (48, 0.8), (55, 0.7), (60, 0.8), (64, 0.7), (67, 0.7), (72, 0.6), (84, 0.3)))
chord = lowpass(chord, 7000) * (np.clip(k / 0.01, 0, 1) * np.exp(-k / 1.4))[:, None]
x = np.zeros((n + t2n(2.0), 2))
x[:n] += chord * 0.5
place(x, read_wav(os.path.join(DISC, 's1_disc_crash.wav')), 0, 0.6)
for i, m in enumerate((84, 88, 91, 96, 100)):
    nb = t2n(1.6)
    kb = np.arange(nb) / SR
    place(x, pan(osc_sine(mtof(m), nb) * np.exp(-kb / 0.5), (i - 2) * 0.35), t2n(0.06 * i), 0.3)
save_sfx('sky_holy_hit', reverb(x, 2.6, 0.55, mix=0.3))

# the count-in: four kitten 'mi' on the four beats of one bar, climbing
mi = read_wav(os.path.join(SFX, 'kitten_mi.wav'))
x = np.zeros((BAR_N + t2n(0.3), 2))
for i, semis in enumerate((0, 2, 4, 7)):
    place(x, mi[: t2n(0.12)], t2n(i * BAR / 4), 0.8 + 0.07 * i, semitones=semis)
save_sfx('count_in', x, peak=0.8)
print('sky done ->', OUT)
