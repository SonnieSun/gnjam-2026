"""The ending song for the credits: Can-Can's famous tune (SONGS['can_can'] in compose_classics.py) at half
speed, as a slow cat lullaby. Played once under the credits crawl, not looped.

  bars 1-2    intro: a music box rolls up a G chord over a warm pad
  bars 3-10   the tune, first half: one cat sings it (whole meows, legato), the music box doubles it an
              octave up, pad + soft bass on 1 and 3
  bars 11-16  second half: + soft kick / brush and two cats on the off-beat chord notes
  bars 15-17  ritardando into the last note (the tempo halves over two bars), drums drop out
  last note   held: the lead cat's long MIAO, three cats singing the G chord, the music box rolls up,
              pad and bass ring out; a kitten 'mew' after it

Prints when the last note lands (seconds from the start of the file): the credits crawl stops there.

usage: python -I make_ending_song.py <loops dir> <out.wav>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_argv = sys.argv
loops, out_path = _argv[1], _argv[2]
sys.argv = [_argv[0], loops, '__no_song__']   # compose_classics renders the songs named here: none
import compose_classics as cc  # noqa: E402
sys.argv = _argv
from audio import (SR, adsr, bandpass, highpass, lowpass, mtof, nm, noise, osc_sine, osc_supersaw, pan,  # noqa: E402
                   place, reverb, softclip, t2n, write_wav)
from psola import sing_miao  # noqa: E402

STEP = cc.STEP
song = cc.slowed(cc.SONGS['can_can'], 2)        # 16 bars, one chord per bar
CHORDS = song['chords'][::2]                     # slowed() doubled each half-bar chord: one per bar
INTRO = 2                                        # bars before the tune
T0 = INTRO * 16                                  # step where the tune starts
TUNE_BARS = 16
LAST = T0 + 15 * 16                              # the last note (G4, tune bar 16)
RIT_FROM = T0 + 13 * 16                          # ritardando from tune bar 14 ...
RIT_TO = LAST                                    # ... to the last note
RIT_SPEED = 0.5                                  # tempo at the last note, of the starting tempo
FERMATA = 3.4                                    # seconds the last chord is held
TAIL = 4.0


# --- time: 16th steps -> seconds, slowing down over the ritardando -----------------------
def speed(step):
    if step <= RIT_FROM:
        return 1.0
    if step >= RIT_TO:
        return RIT_SPEED
    return 1.0 - (1.0 - RIT_SPEED) * (step - RIT_FROM) / (RIT_TO - RIT_FROM)


GRID = np.arange(LAST + 33)
_T = np.concatenate([[0.0], np.cumsum([STEP / speed(s + 0.5) for s in GRID[:-1]])])


def sec(step):
    return float(np.interp(step, GRID, _T))


def at(step):
    return t2n(sec(step))


LAND = sec(LAST)
TOTAL = LAND + FERMATA + TAIL


def blank():
    return np.zeros((t2n(TOTAL) + SR, 2))


# --- instruments ---------------------------------------------------------------------------
def music_box(midi, seconds=1.4):
    """A music-box tine: a sine with two short inharmonic partials, a quick decay."""
    n = t2n(seconds)
    t = np.arange(n) / SR
    f = mtof(midi)
    v = (osc_sine(f, n) + 0.3 * osc_sine(f * 3.0, n) * np.exp(-t / 0.10)
         + 0.15 * osc_sine(f * 5.4, n) * np.exp(-t / 0.04))
    return v * np.exp(-t / 0.55) * np.clip(t / 0.002, 0, 1) * 0.3


def pad(notes, seconds):
    n = t2n(seconds + 0.8)
    x = sum(osc_supersaw(mtof(m), n, voices=5, detune=0.12) for m in notes) / len(notes)
    return lowpass(x, 1300) * adsr(n, a=0.4, d=0.3, s=0.8, r=0.7, gate=seconds)[:, None]


def soft_bass(midi, seconds):
    n = t2n(seconds + 0.2)
    t = np.arange(n) / SR
    f = mtof(midi)
    v = osc_sine(f, n) + 0.25 * osc_sine(2 * f, n) * np.exp(-t / 0.15)
    return v * adsr(n, a=0.01, d=0.3, s=0.6, r=0.15, gate=seconds) * 0.7


def brush(seconds=0.12):
    n = t2n(seconds)
    t = np.arange(n) / SR
    return bandpass(noise(n)[:, None], 3000, 9000)[:, 0] * np.exp(-t / 0.035) * 0.5


layers = {}

# pad: the chord of each bar (intro: G), the last chord held
x = blank()
bars_chords = ['G'] * INTRO + CHORDS
for b, c in enumerate(bars_chords):
    s0, s1 = b * 16, (b + 1) * 16
    if s0 >= LAST:
        break
    notes, _ = cc.chord(c)
    place(x, pad(notes, sec(s1) - sec(s0)), at(s0), 1.0)
notes, root = cc.chord('G')
place(x, pad(notes + [notes[0] + 12], FERMATA), at(LAST), 1.1)
layers['pad'] = (reverb(highpass(x, 120), 2.2, 0.5, mix=0.3)[: len(x)], 0.050)

# bass: root on beat 1, fifth on beat 3 (from the tune on), the last root held
x = blank()
for b, c in enumerate(CHORDS):
    s0 = T0 + b * 16
    if s0 >= LAST:
        break
    _, r = cc.chord(c)
    for half, m in ((0, r + 12), (8, r + 19)):
        place(x, pan(soft_bass(m, sec(s0 + half + 8) - sec(s0 + half) - 0.05), 0.0), at(s0 + half))
place(x, pan(soft_bass(root + 12, FERMATA), 0.0), at(LAST))
layers['bass'] = (x, 0.12)

# music box: the intro roll, then the tune an octave up, then the last roll
x = blank()
for k, m in enumerate(['G4', 'B4', 'D5', 'G5', 'B5', 'D6', 'G6', 'D6', 'B5', 'G5', 'D5', 'B4', 'A4', 'C5', 'D5', 'F#5']):
    place(x, pan(music_box(nm(m)), 0.2 if k % 2 else -0.2), at(k * 2))
for s, p, ln in song['melody']:
    place(x, pan(music_box(nm(p) + 12), 0.15), at(T0 + s), 0.55)
for k, m in enumerate(['G4', 'B4', 'D5', 'G5', 'B5', 'D6', 'G6']):
    place(x, pan(music_box(nm(m), 2.2), -0.3 + k * 0.1), t2n(LAND + k * 0.09), 0.9)
layers['box'] = (reverb(highpass(x, 300), 1.8, 0.45, mix=0.28)[: len(x)], 0.055)

# the lead cat: whole meows, each ringing until the next note (the flow lead of compose_classics)
x = blank()
mel = cc.merge_repeats(song['melody'], 0)
ends = {max(i for i, (s, _, _) in enumerate(mel) if s // 16 == b) for b in (3, 7, 11)}
everyone = [(c.mean(axis=1) if c.ndim == 2 else c, cc.native(c)) for c in cc.LONG + cc.ACCENT + cc.SHORT]
high_cat = max(everyone, key=lambda c: c[1])
for i, (s, p, ln) in enumerate(mel):
    m = nm(p)
    a = T0 + s
    if a >= LAST:
        break
    nxt = T0 + mel[i + 1][0] if i + 1 < len(mel) else a + ln
    seconds = sec(a + ln) - sec(a)
    room = t2n(sec(nxt) - sec(a))
    if i + 1 < len(mel) and mel[i + 1][1] == p:
        room = max(t2n(0.06), room - t2n(cc.SAME_PITCH_GAP + cc.TAIL_FADE))
    if m >= cc.HIGH_FROM:
        k = cc.hit(high_cat[0], high_cat[1], m, max(seconds * 0.95, 0.09))
        place(x, pan(cc.tail_cut(cc.resonate(k, m, even=True), room), 0.0), at(a), 0.45)
    if i in ends and ln >= 4:
        place(x, pan(cc.tail_cut(cc.resonate(cc.shout(m, seconds), cc.lift(m), cc.FX), room), 0.0), at(a), 1.2)
        place(x, pan(cc.tail_cut(cc.resonate(cc.shout(m - 12, seconds, 'shout_lo'), cc.lift(m - 12), cc.FX), room), 0.0), at(a), 0.5)
    else:
        v = cc.miao(m, seconds, 'mix', flow=sec(nxt) - sec(a))
        place(x, pan(cc.tail_cut(cc.resonate(v, cc.lift(m), cc.FX), room), 0.0), at(a))
# the last note: one long MIAO on G, an octave-below cat under it
g = nm('G4')
place(x, pan(cc.resonate(cc.shout(g, FERMATA), cc.lift(g), cc.FX), 0.0), at(LAST), 1.25)
place(x, pan(cc.resonate(cc.shout(g + 12, FERMATA * 0.8, 'shout_hi'), cc.lift(g + 12), cc.FX), 0.0), at(LAST), 0.35)
layers['lead'] = (reverb(cc.punch(highpass(x, 120)), 1.6, 0.4, mix=0.16)[: len(x)], 0.135)

# second half: two cats on the off-beat chord notes (beats 2 and 4), quiet
x = blank()
for b in range(8, 14):
    notes, _ = cc.chord(CHORDS[b])
    for beat in (1, 3):
        for m, side in zip([m + 12 for m in notes[-2:]], (-0.4, 0.4)):
            v = sing_miao(cc.turn(cc.SHORT, 'stab', m), m, 0.14, keep=0.2)
            place(x, pan(v, side), at(T0 + b * 16 + beat * 4), 0.6)
layers['stabs'] = (reverb(highpass(x, 280), 1.0, 0.3, mix=0.12)[: len(x)], 0.035)

# the last chord: three cats sing G B D, spread
x = blank()
for m, side, delay in ((nm('G4'), -0.5, 0.0), (nm('B4'), 0.5, 0.06), (nm('D5'), 0.0, 0.12)):
    v = sing_miao(cc.turn(cc.LONG + cc.ACCENT, 'choir', m), m, FERMATA - delay, keep=0.4)
    place(x, pan(v, side), t2n(LAND + delay))
# and a kitten after it
mew = cc.miao(nm('D6'), 0.22)
place(x, pan(mew, 0.45), t2n(LAND + FERMATA + 0.35), 0.5)
layers['choir'] = (reverb(highpass(x, 150), 2.4, 0.5, mix=0.3)[: len(x)], 0.07)

# drums: soft kick on 1 and 3, a brush on 2 and 4, from the second half until the ritardando
x = blank()
kick = lowpass(cc.KICK, 1800)
for b in range(8, 13):
    for beat in range(4):
        a = at(T0 + b * 16 + beat * 4)
        if beat % 2 == 0:
            place(x, kick, a, 0.5)
        else:
            place(x, pan(brush(), 0.25), a, 0.6)
place(x, lowpass(cc.CRASH, 6000), at(LAST), 0.25)
layers['drums'] = (reverb(x, 1.2, 0.3, mix=0.1)[: len(x)], 0.06)

# mix: each layer to its level (RMS over the part where it plays), then a gentle clip and fade
mix = blank()
for name, (y, level) in layers.items():
    act = np.abs(y).mean(axis=1) > 1e-4
    r = float(np.sqrt(np.mean(y[act] ** 2))) if act.any() else 0.0
    mix += y * (level / (r + 1e-9))
    print(f'  {name:6s} rms {level:.3f}')
n = t2n(TOTAL)
mix = mix[:n]
f = t2n(1.5)
mix[-f:] *= np.linspace(1, 0, f)[:, None]
write_wav(out_path, softclip(mix * 1.1, 1.2), peak=0.89)
print(f'ENDING_SONG {out_path}')
print(f'  length {TOTAL:.2f} s, last note lands at {LAND:.2f} s, tune starts at {sec(T0):.2f} s')
