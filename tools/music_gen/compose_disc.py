"""Scene 1 DISC, version 4: one scene, two style variations that can be swapped live.

Version 4: variation A is now eurobeat (the y2k para para sound) instead of chiptune, and the
shared bass is a proper eurobeat saw bass with a real filter sweep.

Both variations share tempo (160 BPM), key centre (G minor / Bb major), chord table and loop
length, so the game can switch a whole set at a bar line, or swap a single layer.

  Chords (one a bar): Ebmaj7 | F7 | Dm7 | Gm7   (IV - V - iii - vi in Bb: the J-pop "royal road")

  Shared skeleton (same file in both variations):
    L1 groove   the "ci": off-beat open hat, tambourine 16ths
    L2 bass     octave saw bass, low on the beat, high on the off-beat
  Variation A "eurobeat" (y2k para para):
    L0 keys     synth brass stabs (filter snapping shut) over a quiet "aah" choir
    L3 hook     supersaw lead riff, busy syncopated 16ths, portamento and vibrato
    L4 peak     16th supersaw arpeggio, orchestra hits, a snare roll into the next round
  Variation B "disco" (rough, jazzy):
    L0 keys     sampled piano stabs, saturated, record crackle
    L3 hook     the honky brass riff
    L4 peak     funk guitar chops, laser zaps, stutter

Writes to <out>/s1_disc/ the loops (s1_disc_<L1|L2>_..., s1_disc_A_..., s1_disc_B_...), the
player kit, the transition, and three 30-second previews:
  s1_disc_preview_A_20b.wav       variation A, layers stacking as in the design doc
  s1_disc_preview_B_20b.wav       variation B, same plan
  s1_disc_preview_switch_20b.wav  starts A, swaps only the hook to B in bars 9-12, goes all
                                  B in bars 13-16, back to all A for the crash stage

usage: python -I compose_disc.py <samples dir> <out dir>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from slicer import slices  # noqa: E402
from psola import sing  # noqa: E402


def stereo(v):
    """mono -> (n, 2)"""
    return np.stack([v, v], axis=1)
from audio import (BAR, SR, adsr, bandpass, bitcrush, delay, highpass, lowpass, mtof,  # noqa: E402
                   nm, noise, osc_fm, osc_pulse, osc_saw, osc_sine, osc_supersaw, pan, perc, place, read_wav,
                   resample, reverb, softclip, svf_lowpass, t2n, wrap, write_wav)

samples_dir, out_root = sys.argv[1], sys.argv[2]
OUT = os.path.join(out_root, 's1_disc')
os.makedirs(OUT, exist_ok=True)
PACK = os.path.join(samples_dir, '99sounds_music_loops', '99Sounds x Monosounds - Music Loops')
KIT = os.path.join(PACK, 'Drum Oneshots', 'Twilight - Dance Drum Kit')
INST = os.path.join(PACK, 'Instrument Oneshots', 'Instruments')

BARS = 4
HOOK_A_PEAK = 0.25   # RMS-matched to hook B
KEYS_A_PEAK = 0.73
PEAK_A_PEAK = 0.41
LEAD_ROOT = nm('F4')  # the pack's lead one-shots are recorded on F4
LEAD_PICK = '07'      # which 'Lead - NN' one-shot plays hook A
LEAD_CANDIDATES = ['05', '07', '10', '12', '15', '28']   # the fast-attack ones, for the audition
LOOP = t2n(BARS * BAR)          # 264600 samples
TAIL = t2n(2.0)
STEP = BAR / 16                 # a 16th note, seconds
BEAT = BAR / 4
C4 = nm('C4')                   # the instrument one-shots are all recorded on C4


def blank():
    return np.zeros((LOOP + TAIL, 2))


def finish_loop(x, peak=0.5):
    y = wrap(x, LOOP)
    return y * (peak / max(np.max(np.abs(y)), 1e-9))


def load(path, seconds=None, fade=0.01):
    x = read_wav(path)
    lead = np.argmax(np.max(np.abs(x), axis=1) > 0.01 * np.max(np.abs(x)))   # start on the hit
    x = x[lead:]
    if seconds:
        x = x[: t2n(seconds)].copy()
        f = t2n(fade)
        x[-f:] *= np.linspace(1, 0, f)[:, None]
    return x


def gated(x, seconds, fade=0.015):
    y = x[: t2n(seconds)].copy()
    f = min(t2n(fade), len(y))
    y[-f:] *= np.linspace(1, 0, f)[:, None]
    return y


def pitched(x, midi):
    return resample(x, 2 ** (-(midi - C4) / 12.0))


def dirt(x, drive=1.8):
    return softclip(bandpass(x, 70, 11000), drive)


def attack(n, ms=1.5):
    return np.clip(np.arange(n) / (ms / 1000 * SR), 0, 1)


def stutter(x, bars=(1, 3), bits=5):
    """The last half-beat of the given bars repeats in 1/32 grains, then gets bit-crushed."""
    edge = t2n(0.002)
    g = t2n(STEP / 2)
    ramp = np.ones(g)
    ramp[:edge] = np.linspace(0, 1, edge)
    ramp[-edge:] = np.linspace(1, 0, edge)
    for bar in bars:
        a = t2n(bar * BAR + 14 * STEP)
        grain = x[a: a + g].copy()
        for k in range(4):
            x[a + k * g: a + (k + 1) * g] = grain * ramp[:, None] * (1 - 0.12 * k)
        x[a: a + 4 * g] = bitcrush(x[a: a + 4 * g], bits=bits, hold=5) * np.tile(ramp, 4)[:, None]
    return x


# --- harmony: Ebmaj7 | F7 | Dm7 | Gm7 ------------------------------------------------
CHORDS = [
    (['G3', 'Bb3', 'D4', 'Eb4'], 'Eb1'),
    (['A3', 'C4', 'Eb4', 'F4'], 'F1'),
    (['A3', 'C4', 'D4', 'F4'], 'D1'),
    (['Bb3', 'D4', 'F4', 'G4'], 'G1'),
]
STABS = [0, 6, 12]              # x.....x.....x...  3+3+2: one clear syncopation for the keys


# ===== shared skeleton =====================================================================

def tambourine(n, accent):
    t = np.arange(n) / SR
    second = 0.5 * np.exp(-np.maximum(t - 0.012, 0) / 0.03) * (t > 0.012)
    return bandpass(noise(n), 5500, 12000) * (np.exp(-t / 0.035) + second) * accent


def layer_groove(open_hat):
    x = blank()
    for bar in range(BARS):
        for s in range(16):
            at = t2n(bar * BAR + s * STEP)
            if s % 4 == 2:
                place(x, open_hat, at, 0.9)
                n = t2n(0.14)
                place(x, pan(highpass(noise(n), 7000) * perc(n, 0.045) * 0.16, 0.1), at)
            if s % 4 == 2:          # the tambourine doubles the off-beat, nothing in between: a clean "ci"
                place(x, pan(tambourine(t2n(0.07), 0.5) * 0.5, -0.25), at)
            elif s % 4 == 0:        # a soft tick on the beat, under the player's kick
                place(x, pan(tambourine(t2n(0.05), 0.18) * 0.5, -0.25), at)
    return finish_loop(dirt(x, 1.3), peak=0.6)


def bass_note(freq, n):
    """Eurobeat bass: a bright, rubbery saw whose filter snaps open and shuts on every note."""
    t = np.arange(n) / SR
    tone = osc_supersaw(freq, n, voices=3, detune=0.08).mean(axis=1) * 0.7 + osc_pulse(freq, n, 0.5) * 0.3
    cutoff = 450 + 3200 * np.exp(-t / 0.045)
    tone = svf_lowpass(tone, cutoff, q=1.3)
    # a sub under every note: the fundamental on the low notes, an octave down on the high ones,
    # so the low end never drops out on the off-beats
    sub = osc_sine(freq, n) * 0.8 if freq < 120 else osc_sine(freq / 2, n) * 0.45
    env = adsr(n, a=0.002, d=0.08, s=0.55, r=0.02, gate=n / SR - 0.02)
    return (tone + sub) * env


def layer_bass():
    x = blank()
    for bar, (_, root) in enumerate(CHORDS):
        f = mtof(nm(root) + 12)
        for e in range(8):                                  # 8ths: low, high, low, high...
            high = e % 2 == 1
            n = t2n(STEP * 1.6)
            place(x, pan(bass_note(f * (2 if high else 1), n) * (0.85 if high else 1.0), 0.0), t2n(bar * BAR + e * 2 * STEP))
    return finish_loop(softclip(x * 1.8, 2.2), peak=0.6)   # more drive: harmonics that small speakers can play


# ===== variation A: eurobeat (y2k para para) =================================================

def saw_stack(freq, n, voices=7, detune=0.35):
    """A JP-8000-ish supersaw, wide and bright, with the mud under the note taken out."""
    x = osc_supersaw(freq, n, voices=voices, detune=detune)
    return highpass(x, max(60.0, float(np.min(freq)) * 0.7))


def filtered(x, start, end, tau, q=1.0):
    """Low-pass whose cutoff falls from `start` to `end` Hz with time constant `tau`: the
    snappy filter envelope that makes a synth brass or a lead speak."""
    t = np.arange(len(x)) / SR
    return svf_lowpass(x, end + (start - end) * np.exp(-t / tau), q=q)


def synth_brass(midis, n, gate):
    chord = sum(saw_stack(mtof(m), n, voices=5, detune=0.28) for m in midis) / len(midis)
    chord = filtered(chord, 7000, 1300, 0.07, q=1.1)
    return chord * adsr(n, 0.003, 0.14, 0.6, 0.05, gate=gate)[:, None]


def choir(midis, n):
    """An 'aah' pad: saws through the formants of the vowel a (800 / 1150 / 2900 Hz)."""
    raw = sum(saw_stack(mtof(m), n, voices=5, detune=0.2) for m in midis) / len(midis)
    voice = bandpass(raw, 680, 920) + bandpass(raw, 1000, 1300) * 0.5 + bandpass(raw, 2600, 3200) * 0.22
    return voice * adsr(n, 0.12, 0.5, 0.85, 0.3, gate=n / SR - 0.3)[:, None]


def upbeat_stab(midis, n):
    """The eurobeat 'upbeat': a short, bright chord blip on every off-beat. Three saws, detuned only
    a little (the Japanese how-tos warn that wide detune sounds loose), filter snapping shut."""
    t = np.arange(n) / SR
    chord = sum(saw_stack(mtof(m) * (1 + 0.004 * np.exp(-t / 0.02)), n, voices=3, detune=0.1) for m in midis) / len(midis)
    chord = filtered(chord, 9000, 1800, 0.035, q=1.0)
    return chord * (adsr(n, 0.001, 0.05, 0.4, 0.02, gate=n / SR - 0.02) * attack(n, 1))[:, None]


def layer_keys_a():
    """Bed of variation A: the upbeat stabs on every 'and' (the eurobeat off-beat) over a soft
    'aah' choir. With the off-beat hats and the octave bass this is the para-para pulse."""
    x = blank()
    for bar, (notes, _) in enumerate(CHORDS):
        midis = [nm(p) + 12 for p in notes]
        for s in (2, 6, 10, 14):
            n = t2n(0.11)
            place(x, upbeat_stab(midis, n) * (0.5 if s != 14 else 0.6), t2n(bar * BAR + s * STEP))
        place(x, choir([nm(p) for p in notes], t2n(BAR + 0.4)) * 0.28, t2n(bar * BAR))
    x = highpass(x, 180, order=3)
    return finish_loop(reverb(x, 0.8, 0.25, mix=0.1), peak=KEYS_A_PEAK)


# The riff, rewritten after transcribing a kawaii lead: sparse 8ths, every note short and cut
# off, rests between, one anchor note (Bb5, the fifth of the Eb chord) the phrase keeps coming
# back to, short climbs up the scale, a held note to end each bar.   (step, note, length in 16ths)
RIFF_A = [
    [(0, 'Bb5', 1), (2, 'Bb5', 1), (6, 'G5', 1), (8, 'Bb5', 1), (10, 'C6', 1), (12, 'D6', 3)],   # Ebmaj7
    [(0, 'C6', 3), (4, 'A5', 1), (6, 'F5', 1), (8, 'A5', 1), (10, 'Bb5', 1), (12, 'C6', 3)],     # F7
    [(0, 'A5', 1), (2, 'A5', 1), (6, 'F5', 1), (8, 'D5', 1), (10, 'F5', 1), (12, 'A5', 3)],      # Dm7
    [(0, 'Bb5', 1), (2, 'A5', 1), (4, 'G5', 3), (8, 'D5', 1), (10, 'G5', 1), (12, 'A5', 1), (14, 'Bb5', 1)],  # Gm7
]


def square_lead(midi, gate):
    """The lead as measured on the reference: one plain square wave, mono, no detune, no chorus,
    no delay; a little darker than a perfect square (odd harmonics falling a bit faster); an organ
    envelope that jumps to full, settles to 3/4 in 15 ms, holds, and stops within 20 ms."""
    n = t2n(gate + 0.03)
    v = osc_pulse(mtof(midi), n, 0.5)
    v = lowpass(v[:, None], 6000, order=1)[:, 0]
    v = v * adsr(n, 0.001, 0.015, 0.77, 0.02, gate=gate)
    return pan(v, 0.0)


def layer_hook_a(lead=None):
    """Hook A: the riff on the square lead. lead: optional one-shot sample to use instead."""
    x = blank()
    for bar in range(BARS):
        for s, p, length in RIFF_A[bar]:
            gate = length * STEP * (0.8 if length == 1 else 0.92)
            v = sampled_note(lead, nm(p), gate) if lead is not None else square_lead(nm(p), gate)
            place(x, v * 0.45, t2n(bar * BAR + s * STEP))
    x = highpass(x, 200)
    return finish_loop(reverb(x, 0.5, 0.15, mix=0.04), peak=HOOK_A_PEAK)


def sampled_note(lead, midi, gate):
    """A ready-made lead one-shot (recorded on F4), pitched to `midi` and cut to `gate` seconds."""
    v = resample(lead, 2 ** (-(midi - LEAD_ROOT) / 12.0))
    v = gated(v, gate + 0.03, fade=0.03)
    v[: t2n(0.001)] *= np.linspace(0, 1, t2n(0.001))[:, None]
    return v


def euro_brass(midis, n, gate):
    """Eurobeat synth brass: saws only slightly detuned, the detune and pitch starting wide and
    pulling in fast (the 'blat' at the front of every note), filter opening then settling."""
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for m in midis:
        f = mtof(m) * (1 + 0.012 * np.exp(-t / 0.025))
        out += saw_stack(f, n, voices=3, detune=0.12) + saw_stack(f * 1.003, n, voices=2, detune=0.3) * 0.5 * np.exp(-t / 0.05)[:, None]
    out = filtered(out / len(midis), 7500, 2200, 0.08, q=1.2)
    return out * adsr(n, 0.004, 0.12, 0.7, 0.04, gate=gate)[:, None]


def fm_bell(midi, n):
    t = np.arange(n) / SR
    return osc_fm(mtof(midi), n, ratio=3.5, index=3.0, index_decay=9.0) * np.exp(-t / 0.35) * attack(n, 1)


def orch_hit(midis, n):
    """The Y2K orchestra hit: a bright chord stack, a noise blast and a low thump, all at once."""
    t = np.arange(n) / SR
    chord = sum(saw_stack(mtof(m), n, voices=5, detune=0.3) for m in midis) / len(midis)
    chord = filtered(chord, 9000, 1800, 0.06, q=0.9) * np.exp(-t / 0.22)[:, None]
    blast = pan(bandpass(noise(n), 300, 4000) * np.exp(-t / 0.035), 0.0) * 0.6
    thump = pan(osc_sine(70 * (1 + np.exp(-t / 0.02)), n) * np.exp(-t / 0.08), 0.0) * 0.5
    return (chord + blast + thump) * attack(n, 1)[:, None]


# The brass answers the lead in its gaps: a 3-3-2 figure on chord tones, low enough not to fight it.
BRASS = [(0, 2), (3, 2), (6, 2), (10, 1), (11, 1), (14, 2)]


def layer_peak_a(snare):
    """Peak of variation A, the full para-para: eurobeat brass riff, a glockenspiel-like FM bell
    doubling the chord in two octaves on 8ths, orchestra hits at the top of each phrase, and a
    denpa glitch (stutter + bitcrush) at the end of bars 2 and 4."""
    x = blank()
    for bar, (notes, root) in enumerate(CHORDS):
        tones = sorted(nm(q) + 12 for q in notes)
        dyad = [tones[1], tones[3], tones[1] + 12]                 # third-ish, top, third up an octave
        for s, ln in BRASS:
            gate = ln * STEP * 0.85
            place(x, euro_brass(dyad, t2n(gate + 0.06), gate) * 0.42, t2n(bar * BAR + s * STEP))
        bell = [tones[0] + 24, tones[2] + 24, tones[0] + 36, tones[2] + 24]
        for e in range(8):
            n = t2n(0.5)
            place(x, pan(fm_bell(bell[e % 4], n) * 0.16, 0.35 if e % 2 else -0.35), t2n(bar * BAR + e * 2 * STEP))
        if bar in (0, 2):
            place(x, orch_hit([nm(q) for q in notes] + [nm(notes[0]) + 12], t2n(0.6)) * 0.5, t2n(bar * BAR))
    x = highpass(x, 140)
    x = stutter(x, bars=(1, 3), bits=6)
    return finish_loop(reverb(x, 0.9, 0.3, mix=0.1), peak=PEAK_A_PEAK)


# ===== variation B: rough disco ================================================================

def layer_keys_b(piano):
    x = blank()
    for bar, (notes, _) in enumerate(CHORDS):
        for s in STABS:
            length = 0.22 if s in (6, 12) else 0.14
            for p in notes:
                place(x, gated(pitched(piano, nm(p)), length) * 0.28, t2n(bar * BAR + s * STEP))
    crackle = np.zeros(len(x))
    r = np.random.default_rng(3)
    hits = r.integers(0, len(x), int(len(x) / SR * 14))
    crackle[hits] = r.standard_normal(len(hits)) ** 3
    x += pan(bandpass(crackle, 700, 6000) + bandpass(noise(len(x)), 1500, 5000) * 0.006, 0.0) * 0.35
    x = highpass(dirt(x * 1.2, 1.6), 150, order=3)
    return finish_loop(reverb(x, 0.5, 0.12, mix=0.08), peak=0.5)


RIFF_B = [
    [(0, 'G4', 1), (2, 'G4', 1), (3, 'Bb4', 1), (5, 'G4', 1), (6, 'F4', 1), (8, 'G4', 2), (11, 'D4', 1), (12, 'F4', 2), (14, 'G4', 1)],
    [(0, 'Bb4', 1), (2, 'Bb4', 1), (3, 'C5', 1), (5, 'Bb4', 1), (6, 'G4', 1), (8, 'F4', 2), (10, 'D4', 1), (12, 'F4', 1), (13, 'G4', 3)],
]


def layer_hook_b(brass):
    x = blank()
    for bar in range(BARS):
        for s, p, length in RIFF_B[bar % 2]:
            v = gated(pitched(brass, nm(p)), length * STEP * (0.95 if length > 2 else 0.85))
            if bar == 3 and s == 13:                                 # the last note falls off
                idx = np.cumsum(2 ** (np.linspace(0, -3, len(v)) / 12))
                v = v[idx[idx < len(v) - 1].astype(int)]
            place(x, v * 0.6, t2n(bar * BAR + s * STEP))
    x = dirt(highpass(x, 220) * 1.4, 2.2)
    x = delay(x, 0.75 * BEAT, feedback=0.18, mix=0.12)
    return finish_loop(reverb(x, 0.6, 0.15, mix=0.08), peak=0.37)   # as loud (RMS) as hook A


def layer_peak_b(guitar):
    x = blank()
    for bar, (notes, _) in enumerate(CHORDS):
        tones = [nm(p) + 12 for p in notes]
        for s in range(16):
            if s % 4 == 0:
                continue
            v = gated(pitched(guitar, tones[(s * 3) % len(tones)]), 0.055, fade=0.01)
            v = bandpass(v, 600, 2200 if s % 4 == 2 else 1200)
            place(x, v * (0.7 if s % 2 else 0.45), t2n(bar * BAR + s * STEP))
        n = t2n(0.18)
        t = np.arange(n) / SR
        zap = osc_pulse(1800 * np.exp(-t / 0.05) + 200, n, 0.3) * perc(n, 0.07) * attack(n) * 0.25
        place(x, pan(zap, 0.4 if bar % 2 else -0.4), t2n(bar * BAR + 14 * STEP))
    x = stutter(x)
    return finish_loop(dirt(x, 1.6), peak=0.3)



# ===== extra variation track: vocal chops (event-triggered, any variation) ======================

def retune(sl, target):
    """Pitch a slice so its detected note lands on `target` (unknown pitch: treat it as C4)."""
    src = sl['midi'] if sl['midi'] is not None else C4
    return resample(sl['audio'], 2 ** (-(target - src) / 12.0))


def layer_vox(soul, grains):
    """'ah' chops answering the riff where it rests, and a stuttered 'a-a-a-a' at the end of bar 4.
    Everything is tuned to the chord and pitched up an octave: a little chipmunk, very y2k."""
    x = blank()
    for bar, (notes, _) in enumerate(CHORDS):
        top = nm(notes[-1]) + 12
        answer = [(12, top, soul[bar % len(soul)]), (14, top + (2 if bar % 2 == 0 else -2), soul[(bar + 1) % len(soul)])]
        if bar % 2 == 1:                          # bars 2 and 4: the riff runs to step 15, so answer earlier
            answer = [(14, top, soul[bar % len(soul)])]
        for step, target, sl in answer:
            v = gated(retune(sl, target), 0.16, fade=0.03)
            place(x, v * 0.7, t2n(bar * BAR + step * STEP))
    # the stutter: eight 32nd-note grains of one syllable, climbing the chord
    g_notes = [nm(p) + 12 for p in CHORDS[3][0]] * 2
    for k in range(8):
        v = gated(retune(grains[k % len(grains)], g_notes[k]), STEP / 2 * 0.9, fade=0.005)
        place(x, v * (0.5 + 0.05 * k), t2n(3 * BAR + 12 * STEP + k * STEP / 2))
    x = highpass(x, 250)
    x = delay(x, 0.75 * BEAT, feedback=0.2, mix=0.15)
    return finish_loop(reverb(x, 0.8, 0.2, mix=0.1), peak=0.5)


# ===== extra variation tracks: cats and a seal (event-triggered) =================================

def load_kit(folder):
    """The meow kit written by meow_kit.py: [{audio, midi, src}], lowest note first."""
    out = []
    for line in open(os.path.join(folder, 'kit.txt'), encoding='utf-8'):
        if not line.startswith('meow_'):
            continue
        name, midi, src = line.rstrip('\n').split('\t')
        out.append(dict(audio=read_wav(os.path.join(folder, name)), midi=float(midi.split()[1]), src=src))
    return out


def layer_meow(kit):
    """The cats take the clap's place: one whole meow on beats 2 and 4 of every bar, sung on that
    riff note an octave down by one adult cat (the four meows of BigSoundBank 0903, taking turns so
    it never sounds copy-pasted), with a second cat (0098) a chord tone below. Bar 4 ends with a
    3-week-old kitten going "mew-mew" up at the riff's own pitch."""
    x = blank()
    adult = [k for k in kit if 'ID 0903' in k['src']]
    harm = [k for k in kit if 'ID 0098' in k['src']]
    kitten = [k for k in kit if 'ID 0390' in k['src']]
    n = 0
    for bar in range(BARS):
        riff = {st: p for st, p, _ in RIFF_A[bar]}
        chord = [nm(p) % 12 for p in CHORDS[bar][0]]
        for st in (4, 12) if bar < 3 else (4,):
            top = nm(riff[max(k for k in riff if k <= st)]) - 12
            under = max(m for m in range(top - 9, top - 2) if m % 12 in chord)
            at = t2n(bar * BAR + st * STEP)
            gate = 4 * STEP * 0.98
            place(x, stereo(sing(adult[n % len(adult)], top, gate)), at, 1.0)
            h = stereo(sing(harm[n % len(harm)], under, gate))
            place(x, pan(h.mean(axis=1), 0.35), at, 0.5)
            n += 1
        if bar == 3:
            for st, k in ((12, 0), (14, 1)):
                v = stereo(sing(kitten[k % len(kitten)], nm(riff[12]), 2 * STEP * 0.98))
                place(x, pan(v.mean(axis=1), -0.2 if k else 0.2), t2n(bar * BAR + st * STEP), 0.9)
    x = highpass(x, 120)
    x = softclip(x / np.max(np.abs(x)) * 1.3, 1.2)
    return finish_loop(reverb(x, 0.6, 0.18, mix=0.08), peak=0.8)


def layer_seal(seal):
    """The seal answers: barks where the riff rests, tuned to the chord (root, then the fifth)."""
    x = blank()
    bark = seal['audio'][: t2n(0.22)].copy()          # the first, sharpest part of the call
    f = t2n(0.03)
    bark[-f:] *= np.linspace(1, 0, f)[:, None]
    sl = dict(seal, audio=bark)
    for bar, (notes, root) in enumerate(CHORDS):
        r = nm(root) + 36                              # around the middle of the keyboard
        hits = [(12, r), (14, r + 7)] if bar % 2 == 0 else [(14, r + 7), (15, r + 12)]
        for step, target in hits:
            place(x, retune(sl, target) * 0.8, t2n(bar * BAR + step * STEP))
    x = highpass(x, 150)
    return finish_loop(reverb(x, 0.6, 0.15, mix=0.08), peak=0.5)

# ===== transition =====================================================================

def riser(snare):
    n = t2n(BAR)
    k = np.arange(n) / n
    x = bitcrush(pan(svf_lowpass(noise(n), 300 + 7000 * k ** 2, q=1.6) * k ** 1.5, 0.0), bits=8, hold=2)
    x = x * (0.5 / np.max(np.abs(x)))
    # the eurobeat snare roll that used to sit in L4: 8ths, then 16ths, getting louder
    hits = [s * STEP for s in range(0, 8, 2)] + [s * STEP for s in range(8, 16)]
    for i, h in enumerate(hits):
        place(x, snare * (0.2 + 0.5 * i / len(hits)), t2n(h))
    return x * (0.6 / np.max(np.abs(x)))


def crash():
    n = t2n(1.6)
    c = highpass(noise(n), 3500) * perc(n, 0.45) + bandpass(noise(n), 500, 3000) * perc(n, 0.06) * 0.6
    x = pan(c, 0.0)
    return x * (0.6 / np.max(np.abs(x)))


# ===== render ===========================================================================

kick = load(os.path.join(KIT, 'Kicks', '99Sounds x Monosounds - Kick - 014.wav'), 0.34)
clap = load(os.path.join(KIT, 'Claps', '99Sounds x Monosounds - Claps - 02.wav'), 0.3)
open_hat = load(os.path.join(KIT, 'Hats', '99Sounds x Monosounds - Hats - 017.wav'))
snare = load(os.path.join(KIT, 'Snares', '99Sounds x Monosounds - Snare - 003.wav'), 0.2)
LEADS = os.path.join(PACK, 'Instrument Oneshots', 'Leads')
lead_shot = lambda k: load(os.path.join(LEADS, f'99Sounds x Monosounds - Lead - {k} - F.wav'))
piano = load(os.path.join(INST, '99Sounds x Monosounds - Piano 3 - C.wav'))
brass = load(os.path.join(INST, '99Sounds x Monosounds - Brass 5 - C.wav'))
guitar = load(os.path.join(INST, '99Sounds x Monosounds - Guitar 2 - C.wav'))
VOX = os.path.join(PACK, 'Vocals')
soul = slices(read_wav(os.path.join(VOX, 'Melodies', '99Sounds x Monosounds - Soul Vocals 08 Gm 140 BPM.wav')))
ANIMALS = os.path.join(samples_dir, 'commons_animals')
_cat = slices(read_wav(os.path.join(ANIMALS, 'Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav')))
meows = [m for m in _cat if m['midi'] and 55 < m['midi'] < 70 and m['end'] - m['start'] > t2n(0.4)]
meows += [m for m in slices(read_wav(os.path.join(ANIMALS, 'Meow of a Siamese cat - freemaster2.wav'))) if m['end'] - m['start'] > t2n(0.4)]
seal = slices(read_wav(os.path.join(ANIMALS, 'Arctocephalusgazellavocal.wav')))[0]
grains = [g for g in slices(read_wav(os.path.join(VOX, 'Stuttered', '99Sounds x Monosounds - Stuttered Vox - 120 BPM - 007 - G min.wav'))) if g['midi'] and g['midi'] > 55][:8]

print('rendering layers...')
L = {
    'L1_groove': layer_groove(open_hat),
    'L2_bass': layer_bass(),
    'A_L0_keys': layer_keys_a(),
    'A_L3_hook': layer_hook_a(),
    'A_L4_peak': layer_peak_a(snare),
    'B_L0_keys': layer_keys_b(piano),
    'B_L3_hook': layer_hook_b(brass),
    'B_L4_peak': layer_peak_b(guitar),
    'X_vox': layer_vox(soul, grains),
    'X_meow': layer_meow(load_kit(os.path.join(out_root, 'meow_kit'))),
    'X_seal': layer_seal(seal),
}
for name, x in L.items():
    write_wav(os.path.join(OUT, f's1_disc_{name}_4b.wav'), x)
    print(f'  {name}: {len(x)} samples')
write_wav(os.path.join(OUT, 's1_disc_kick.wav'), kick * (0.9 / np.max(np.abs(kick))))
write_wav(os.path.join(OUT, 's1_disc_clap.wav'), clap * (0.7 / np.max(np.abs(clap))))
rise, crs = riser(snare), crash()
write_wav(os.path.join(OUT, 's1_disc_riser_1b.wav'), rise)
write_wav(os.path.join(OUT, 's1_disc_crash.wav'), crs)

# ===== previews ===========================================================================
PLAN = {'L0': (1, 20), 'L1': (1, 19), 'L2': (5, 19), 'L3': (9, 20), 'L4': (13, 19), 'X': (13, 19)}   # X: the vocal-chop event track, here as if triggered in the stage-4 and crash bars
MIX = {'L0': 0.6, 'L1': 0.85, 'L2': 0.72, 'L3': 0.78, 'L4': 0.62, 'X': 0.7}
TOTAL_BARS = 20
bar_n = t2n(BAR)


def loop_for(layer, variation):
    if layer == 'L1':
        return L['L1_groove']
    if layer == 'L2':
        return L['L2_bass']
    if layer == 'X':
        return L['X_vox']
    name = {'L0': 'L0_keys', 'L3': 'L3_hook', 'L4': 'L4_peak'}[layer]
    return L[f'{variation}_{name}']


def render_preview(path, variation_at):
    """variation_at(bar, layer) -> 'A' or 'B'."""
    music = np.zeros((t2n(TOTAL_BARS * BAR + 1.5), 2))
    for layer, (a, b) in PLAN.items():
        prev = None
        for bar in range(a, TOTAL_BARS + 1):
            thin = bar == 20 and layer in ('L1', 'L2')
            if bar > b and not thin:
                continue
            var = variation_at(bar, layer)
            off = ((bar - 1) % BARS) * bar_n
            seg = loop_for(layer, var)[off: off + bar_n].copy()
            if thin:
                seg = lowpass(seg, 600) * np.linspace(1, 0.3, len(seg))[:, None]
            if bar == a or var != prev:          # entry or a swap: 10 ms guard against clicks
                f = t2n(0.01)
                seg[:f] *= np.linspace(0, 1, f)[:, None]
            music[(bar - 1) * bar_n: bar * bar_n] += seg * MIX[layer]
            prev = var
    place(music, rise, (TOTAL_BARS - 1) * bar_n, 0.8)
    drums = np.zeros_like(music)
    kicks = [b * t2n(BEAT) for b in range(TOTAL_BARS * 4)] + [TOTAL_BARS * bar_n]
    for k in kicks:
        place(drums, kick, k, 0.95)
    place(drums, crs, TOTAL_BARS * bar_n, 0.7)
    gain = np.ones(len(music))
    t_rel = np.arange(t2n(0.3)) / SR
    dip = 1 - 0.5 * np.exp(-t_rel / 0.09) * np.clip(t_rel / 0.003, 0, 1)
    for k in kicks:
        j = min(len(gain), k + len(dip))
        gain[k:j] = np.minimum(gain[k:j], dip[: j - k])
    mix = softclip((music * gain[:, None] + drums) * 0.9, 1.4)
    write_wav(path, mix, peak=0.89)


def switching(bar, layer):
    if bar <= 8:
        return 'A'
    if bar <= 12:
        return 'B' if layer == 'L3' else 'A'     # only the hook changes style
    if bar <= 16:
        return 'B'                               # the whole set goes disco
    return 'A'                                   # back to y2k for the crash stage


render_preview(os.path.join(OUT, 's1_disc_preview_A_20b.wav'), lambda bar, layer: 'A')
render_preview(os.path.join(OUT, 's1_disc_preview_B_20b.wav'), lambda bar, layer: 'B')
render_preview(os.path.join(OUT, 's1_disc_preview_switch_20b.wav'), switching)
print('previews done ->', OUT)


def fun_preview(path):
    plan = {'L0': (1, 20), 'L1': (1, 19), 'L2': (5, 19), 'L4': (13, 19), 'M': (13, 19), 'S': (17, 19)}
    mix = dict(MIX, M=1.1, S=0.7)
    src = {'M': L['X_meow'], 'S': L['X_seal']}
    music = np.zeros((t2n(TOTAL_BARS * BAR + 1.5), 2))
    for layer, (a, b) in list(plan.items()) + [('L3', (9, 12)), ('L3', (17, 20))]:
        for bar in range(a, b + 1):
            loop = src[layer] if layer in src else loop_for(layer, 'A')
            off = ((bar - 1) % BARS) * bar_n
            seg = loop[off: off + bar_n].copy()
            if bar == a:
                f = t2n(0.01)
                seg[:f] *= np.linspace(0, 1, f)[:, None]
            music[(bar - 1) * bar_n: bar * bar_n] += seg * mix[layer]
    for layer in ('L1', 'L2'):                         # bar 20: low-passed, as in the design
        off = 3 * bar_n
        seg = lowpass(loop_for(layer, 'A')[off: off + bar_n], 600) * np.linspace(1, 0.3, bar_n)[:, None]
        music[19 * bar_n: 20 * bar_n] += seg * MIX[layer]
    place(music, rise, (TOTAL_BARS - 1) * bar_n, 0.8)
    drums = np.zeros_like(music)
    kicks = [b * t2n(BEAT) for b in range(TOTAL_BARS * 4)] + [TOTAL_BARS * bar_n]
    for k in kicks:
        place(drums, kick, k, 0.95)
    place(drums, crs, TOTAL_BARS * bar_n, 0.7)
    gain = np.ones(len(music))
    t_rel = np.arange(t2n(0.3)) / SR
    dip = 1 - 0.5 * np.exp(-t_rel / 0.09) * np.clip(t_rel / 0.003, 0, 1)
    for k in kicks:
        j = min(len(gain), k + len(dip))
        gain[k:j] = np.minimum(gain[k:j], dip[: j - k])
    write_wav(path, softclip((music * gain[:, None] + drums) * 0.9, 1.4), peak=0.89)


fun_preview(os.path.join(OUT, 's1_disc_preview_animals_20b.wav'))
print('animal preview done')



# ===== the cat band: every part can be swapped for a cat version ("more and more cat") =========
# Same chords, riff and loop length as everything else, so the game can swap one layer at a time:
#   C_drums  meow drums: "meow - meow - meow - meow" on the four beats, a short cat "mi" on the
#            off-beats like a hi-hat, a "meow-meow-meow-meow" roll at the end of bar 4. Added on top.
#   C_stabs  replaces L0: the upbeat chords sung by three cats in short "ba"-like chops.
#   C_bass   replaces L2: the octave bass as low meows (a Siamese) with a sine sub under it.
#   C_lead   replaces L3: the riff sung by cats, short meows on short notes, long ones held.
KIT = load_kit(os.path.join(out_root, 'meow_kit'))


def cats(tag):
    return [k for k in KIT if tag in k['src']]


def chop(meow, target, seconds, fade=0.008):
    """The front of a meow (the 'mya'), tuned to `target` and cut to `seconds`."""
    return stereo(sing(meow, target, seconds, fade_out=max(fade, 0.015)))      # the whole m-i-a-o, fitted in


def match_rms(x, target):
    return x * (target / (np.sqrt(np.mean(x ** 2)) + 1e-9))


def layer_cat_drums():
    x = blank()
    short = cats('ID 1899') + cats('ID 1901')
    low_cats = cats('ID 0903')                                        # an adult cat already around F4
    # the off-beat "mi" was a 3-week kitten pushed up to F6: too shrill. Now a grown cat already
    # around D5-F5 (ID 1898), at F5, a little softer and with the top rolled off
    tick = cats('ID 1898')
    for bar in range(BARS):
        for beat in range(4):
            # "boom" low on 1 and 3, "tak" high on 2 and 4, each from a meow already near that pitch,
            # so it hardly gets shifted at all
            if beat % 2 == 0:
                v = chop(low_cats[(bar * 2 + beat // 2) % len(low_cats)], nm('F4'), 0.24, fade=0.04)
            else:
                v = chop(short[beat % len(short)], nm('Bb4'), 0.24, fade=0.04)
            place(x, pan(v.mean(axis=1), 0.0), t2n(bar * BAR + beat * BEAT), 1.0)
            if not (bar == 3 and beat == 3):
                v = lowpass(chop(tick[(bar + beat) % len(tick)], nm('F5'), 0.07, fade=0.02), 5000)
                place(x, pan(v.mean(axis=1), 0.3 if beat % 2 else -0.3), t2n(bar * BAR + beat * BEAT + 2 * STEP), 0.3)
        if bar == 3:                                                  # the roll into the next round
            for i, st in enumerate((12, 13, 14, 15)):
                v = chop(short[i % len(short)], nm('Bb4') + [0, 2, 5, 7][i], 0.085)
                place(x, pan(v.mean(axis=1), 0.0), t2n(bar * BAR + st * STEP), 0.9)
    x = highpass(x, 200)
    return match_rms(finish_loop(softclip(x * 1.5, 1.3), peak=0.8), 0.10)


def layer_cat_stabs():
    # thinned so it sits under a cat lead (two cats, shorter, low-mids cut): see scene1_cat_backing.py
    from scene1_cat_backing import cat_stabs
    return cat_stabs(cats('ID 0903'), CHORDS, RMS_REF['A_L0_keys'])


def layer_cat_bass():
    """The octave bass with a cat in it: the low notes on the beat stay a real bass (a meow pushed
    down that far turns into a growl), and the high notes on the off-beat are sung by an adult cat
    that is already near that pitch, with a sine under it so the low end never drops out."""
    # shorter notes and less low-mid than it had (see scene1_cat_backing.py)
    from scene1_cat_backing import cat_bass
    return cat_bass(cats('ID 0903'), CHORDS, bass_note, RMS_REF['L2_bass'])


def layer_cat_lead():
    x = blank()
    short = cats('ID 1899') + cats('ID 1901') + cats('ID 1898')
    long_ = cats('ID 0903')
    kitten = cats('ID 0390')
    k = 0
    for bar in range(BARS):
        for s, p, length in RIFF_A[bar]:
            target = nm(p) - 12
            at = t2n(bar * BAR + s * STEP)
            if length == 1:
                v = chop(short[k % len(short)], target, 0.13, fade=0.03)
            else:
                v = stereo(sing(long_[k % len(long_)], target, length * STEP * 0.95))
                kv = stereo(sing(kitten[k % len(kitten)], target + 12, length * STEP * 0.9))
                place(x, pan(kv.mean(axis=1), 0.25), at, 0.3)
            place(x, pan(v.mean(axis=1), 0.0), at, 1.0)
            k += 1
    x = highpass(x, 120)
    return match_rms(finish_loop(reverb(softclip(x * 1.15, 1.1), 0.6, 0.18, mix=0.07), peak=0.8), RMS_REF['A_L3_hook'])


RMS_REF = {n: float(np.sqrt(np.mean(L[n] ** 2))) for n in ('A_L0_keys', 'A_L3_hook', 'L2_bass')}
C = {'C_drums': layer_cat_drums(), 'C_stabs': layer_cat_stabs(), 'C_bass': layer_cat_bass(), 'C_lead': layer_cat_lead()}
for _name, _x in C.items():
    write_wav(os.path.join(OUT, f's1_disc_{_name}_4b.wav'), _x * (1.0 / max(1.0, np.max(np.abs(_x)) / 0.98)), peak=None)
    print(f'  {_name}: rms {np.sqrt(np.mean(_x ** 2)):.3f}  peak {np.max(np.abs(_x)):.2f}')


def catness_preview(path):
    """'More and more cat': every phase swaps one more part for its cat version.
       bars 1-4   keys + groove                         (catness 0)
       bars 5-8   + bass, + meow drums                  (1)
       bars 9-12  keys -> cat stabs, + lead (square)    (2)
       bars 13-16 lead -> cat lead, + peak              (3)
       bars 17-19 bass -> cat bass: the full cat band   (4)
       bar 20     transition"""
    music = np.zeros((t2n(TOTAL_BARS * BAR + 1.5), 2))
    plan = [
        (L['A_L0_keys'], 1, 8, MIX['L0']), (C['C_stabs'], 9, 20, MIX['L0']),
        (L['L1_groove'], 1, 19, MIX['L1']),
        (L['L2_bass'], 5, 16, MIX['L2']), (C['C_bass'], 17, 19, MIX['L2']),
        (C['C_drums'], 5, 19, 0.9),
        (L['A_L3_hook'], 9, 12, MIX['L3']), (C['C_lead'], 13, 20, MIX['L3']),
        (L['A_L4_peak'], 13, 19, MIX['L4']),
    ]
    for loop, a, b, g in plan:
        for bar in range(a, b + 1):
            off = ((bar - 1) % BARS) * bar_n
            seg = loop[off: off + bar_n].copy()
            if bar == a:
                f = t2n(0.01)
                seg[:f] *= np.linspace(0, 1, f)[:, None]
            music[(bar - 1) * bar_n: bar * bar_n] += seg * g
    for loop in (L['L1_groove'], C['C_bass']):
        seg = lowpass(loop[3 * bar_n: 4 * bar_n], 600) * np.linspace(1, 0.3, bar_n)[:, None]
        music[19 * bar_n: 20 * bar_n] += seg * 0.8
    place(music, rise, (TOTAL_BARS - 1) * bar_n, 0.8)
    drums = np.zeros_like(music)
    kicks = [b * t2n(BEAT) for b in range(TOTAL_BARS * 4)] + [TOTAL_BARS * bar_n]
    for k in kicks:
        place(drums, kick, k, 0.95)
    place(drums, crs, TOTAL_BARS * bar_n, 0.7)
    gain = np.ones(len(music))
    t_rel = np.arange(t2n(0.3)) / SR
    dip = 1 - 0.5 * np.exp(-t_rel / 0.09) * np.clip(t_rel / 0.003, 0, 1)
    for k in kicks:
        j = min(len(gain), k + len(dip))
        gain[k:j] = np.minimum(gain[k:j], dip[: j - k])
    write_wav(path, softclip((music * gain[:, None] + drums) * 0.9, 1.4), peak=0.89)


catness_preview(os.path.join(OUT, 's1_disc_preview_catness_20b.wav'))
print('catness preview done')


# ===== more styles on the same skeleton (same chords, riff, groove and bass) ====================
# Each style only brings its own L0 / L3 / L4, so the game can cross over at a bar line:
#   chip  8-bit denpa: pulse-wave arpeggios, a 25% pulse lead with a game-console echo,
#         square harmony and bit-crushed glitches.
#   fb    kawaii future bass: wide supersaw chords pumping on every beat, a bright pluck lead with
#         a bell on top, gated chord chops and white-noise sweeps.

def pulse_note(midi, n, width, decay=None, vib=0.0):
    t = np.arange(n) / SR
    f = mtof(midi) * (1 + vib * np.sin(2 * np.pi * 6.0 * t) * np.clip((t - 0.12) / 0.1, 0, 1))
    v = osc_pulse(f, n, width)
    env = np.exp(-t / decay) if decay else np.ones(n)
    return v * env * attack(n, 1)


def layer_chip_keys():
    """16th arpeggio up and down the chord on a thin 12.5% pulse, like an old console."""
    x = blank()
    for bar, (notes, _) in enumerate(CHORDS):
        tones = [nm(q) + 12 for q in notes]
        order = [0, 1, 2, 3, 2, 1] * 3
        for s in range(16):
            n = t2n(STEP * 0.9)
            v = pulse_note(tones[order[s]], n, 0.125, decay=0.08)
            place(x, pan(v * 0.5, -0.2), t2n(bar * BAR + s * STEP))
    x = highpass(x, 200)
    return match_rms(finish_loop(x, peak=0.8), RMS_REF['A_L0_keys'])


def layer_chip_hook():
    """The riff on a 25% pulse with a little vibrato on held notes and the console 'echo': the same
    note again a dotted 8th later, quieter, on the other side."""
    x = blank()
    for bar in range(BARS):
        for s, p, length in RIFF_A[bar]:
            gate = length * STEP * (0.8 if length == 1 else 0.92)
            n = t2n(gate + 0.01)
            v = pulse_note(nm(p), n, 0.25, vib=0.008 if length > 1 else 0.0) * adsr(n, 0.001, 0.02, 0.85, 0.01, gate=gate)
            at = t2n(bar * BAR + s * STEP)
            place(x, pan(v * 0.5, 0.0), at)
            place(x, pan(v * 0.18, 0.5), at + t2n(3 * STEP))
    x = highpass(x, 200)
    return match_rms(finish_loop(x, peak=0.8), RMS_REF['A_L3_hook'])


def layer_chip_peak():
    """Square harmony a chord tone under the riff, a noise-channel 'snare' on 2 and 4, a 32nd
    sparkle arpeggio at the top of every bar and bit-crushed glitches."""
    x = blank()
    for bar, (notes, _) in enumerate(CHORDS):
        chord = [nm(q) % 12 for q in notes]
        for s, p, length in RIFF_A[bar]:
            top = nm(p)
            under = max(m for m in range(top - 9, top - 2) if m % 12 in chord)
            gate = length * STEP * 0.8
            n = t2n(gate + 0.01)
            place(x, pan(pulse_note(under, n, 0.5) * adsr(n, 0.001, 0.02, 0.8, 0.01, gate=gate) * 0.32, -0.3), t2n(bar * BAR + s * STEP))
        for beat in (1, 3):
            n = t2n(0.12)
            sn = bitcrush(pan(noise(n) * perc(n, 0.04) * 0.5, 0.2), bits=4, hold=6)
            place(x, sn, t2n(bar * BAR + beat * BEAT))
        tones = [nm(q) + 24 for q in notes]
        for i in range(8):
            n = t2n(STEP / 2 * 0.9)
            place(x, pan(pulse_note(tones[i % 4], n, 0.125) * 0.22, 0.4), t2n(bar * BAR + i * STEP / 2))
    x = stutter(highpass(x, 150), bars=(1, 3), bits=4)
    return match_rms(finish_loop(x, peak=0.8), RMS_REF['A_L4_peak'])


def pump(n, at_beats=True):
    """Future-bass sidechain shape: silent on each beat, swelling back up over ~150 ms."""
    g = np.ones(n)
    t = np.arange(t2n(BEAT)) / SR
    shape = 1 - np.exp(-t / 0.06)
    for b in range(0, n, t2n(BEAT)):
        j = min(n, b + len(shape))
        g[b:j] = shape[: j - b]
    # duck over 4 ms instead of jumping to silence on the beat (a jump is a click)
    k = t2n(0.004)
    return np.convolve(np.concatenate([np.zeros(k), g]), np.ones(k) / k, mode="valid")[:n]


def layer_fb_keys():
    """Wide, detuned supersaw chords held for the whole bar, pumping on every beat."""
    x = blank()
    for bar, (notes, _) in enumerate(CHORDS):
        n = t2n(BAR)
        chord = sum(saw_stack(mtof(nm(q) + 12), n, voices=7, detune=0.4) for q in notes) / len(notes)
        chord = lowpass(chord, 5000)
        chord[-t2n(0.01):] *= np.linspace(1, 0, t2n(0.01))[:, None]
        place(x, chord * 0.6, t2n(bar * BAR))
    x = x * pump(len(x))[:, None]
    x = highpass(x, 180)
    return match_rms(finish_loop(reverb(x, 1.0, 0.3, mix=0.12), peak=0.8), RMS_REF['A_L0_keys'])


def kawaii_pluck(midi, n):
    t = np.arange(n) / SR
    v = saw_stack(mtof(midi), n, voices=3, detune=0.15)
    v = filtered(v, 9000, 900, 0.06, q=1.1)
    bell = pan(osc_fm(mtof(midi + 12), n, ratio=2.0, index=1.5, index_decay=10) * np.exp(-t / 0.2) * 0.25, 0.0)
    return (v + bell) * np.exp(-t / 0.18)[:, None] * attack(n, 1)[:, None]


def layer_fb_hook():
    x = blank()
    for bar in range(BARS):
        for s, p, length in RIFF_A[bar]:
            n = t2n(length * STEP + 0.15)
            place(x, kawaii_pluck(nm(p), n) * 0.5, t2n(bar * BAR + s * STEP))
    x = highpass(x, 200)
    x = delay(x, 0.75 * BEAT, feedback=0.3, mix=0.18)
    return match_rms(finish_loop(reverb(x, 1.2, 0.35, mix=0.15), peak=0.8), RMS_REF['A_L3_hook'])


def layer_fb_peak():
    """Gated chord chops on a 3-3-2 with a pitch dip on the last one, and a white-noise sweep up
    across every second bar."""
    x = blank()
    for bar, (notes, _) in enumerate(CHORDS):
        for s, ln in ((0, 2), (3, 2), (6, 2), (8, 1), (10, 2), (12, 1), (14, 2)):
            n = t2n(ln * STEP * 0.85 + 0.02)
            t = np.arange(n) / SR
            bend = 1 - (0.06 * np.clip(t / (ln * STEP), 0, 1) if s == 14 else 0)
            chord = sum(saw_stack(mtof(nm(q) + 24) * bend, n, voices=5, detune=0.3) for q in notes[1:]) / 3
            chord = filtered(chord, 8000, 3000, 0.05)
            place(x, chord * adsr(n, 0.002, 0.04, 0.7, 0.015, gate=n / SR - 0.015)[:, None] * 0.4, t2n(bar * BAR + s * STEP))
        if bar % 2 == 1:
            n = t2n(BAR)
            k = np.arange(n) / n
            sw = pan(svf_lowpass(noise(n), 500 + 9000 * k ** 2, q=1.2) * k * 0.25, 0.0)
            sw[-t2n(0.008):] *= np.linspace(1, 0, t2n(0.008))[:, None]
            place(x, sw, t2n(bar * BAR))
    x = highpass(x, 150)
    return match_rms(finish_loop(reverb(x, 0.9, 0.3, mix=0.1), peak=0.8), RMS_REF['A_L4_peak'])


RMS_REF['A_L4_peak'] = float(np.sqrt(np.mean(L['A_L4_peak'] ** 2)))
STYLES = {
    'chip_L0_keys': layer_chip_keys(), 'chip_L3_hook': layer_chip_hook(), 'chip_L4_peak': layer_chip_peak(),
    'fb_L0_keys': layer_fb_keys(), 'fb_L3_hook': layer_fb_hook(), 'fb_L4_peak': layer_fb_peak(),
}
L.update(STYLES)
for _name, _x in STYLES.items():
    write_wav(os.path.join(OUT, f's1_disc_{_name}_4b.wav'), _x * (1.0 / max(1.0, np.max(np.abs(_x)) / 0.98)), peak=None)
    print(f'  {_name}: rms {np.sqrt(np.mean(_x ** 2)):.3f}  peak {np.max(np.abs(_x)):.2f}')
render_preview(os.path.join(OUT, 's1_disc_preview_chip_20b.wav'), lambda bar, layer: 'chip')
render_preview(os.path.join(OUT, 's1_disc_preview_fb_20b.wav'), lambda bar, layer: 'fb')
# one scene, the style moving every 4 bars: eurobeat -> chip -> future bass -> disco -> eurobeat
_tour = {1: 'A', 5: 'A', 9: 'chip', 13: 'fb', 17: 'B'}
render_preview(os.path.join(OUT, 's1_disc_preview_styletour_20b.wav'),
               lambda bar, layer: _tour[max(k for k in _tour if k <= bar)] if bar < 20 else 'A')
print('style previews done')


# ===== shared helpers for the sections below ==================================================

def render_custom(path, layers, kick_steps, kick_gain=0.95, bars=TOTAL_BARS, swing=False, end_riser=True):
    """layers: (loop, first bar, last bar, gain), loops of any whole number of bars; kick_steps:
    16th steps in a bar where the player's kick lands (it ducks the music like the design says)."""
    music = np.zeros((t2n(bars * BAR + 1.5), 2))
    for loop, a, b, g in layers:
        nb = len(loop) // bar_n
        for bar in range(a, b + 1):
            off = ((bar - a) % nb) * bar_n          # a loop starts at its own bar 1 when it enters
            seg = loop[off: off + bar_n].copy()
            if bar == a:
                f = t2n(0.01)
                seg[:f] *= np.linspace(0, 1, f)[:, None]
            music[(bar - 1) * bar_n: bar * bar_n] += seg * g
    if end_riser:
        place(music, rise, (bars - 1) * bar_n, 0.7)
    drums = np.zeros_like(music)
    kicks = [b * bar_n + t2n(swing_t(s) if swing else s * STEP) for b in range(bars) for s in kick_steps] + [bars * bar_n]
    for k in kicks:
        place(drums, kick, k, kick_gain)
    place(drums, crs, bars * bar_n, 0.7)
    gain = np.ones(len(music))
    t_rel = np.arange(t2n(0.3)) / SR
    dip = 1 - 0.45 * np.exp(-t_rel / 0.09) * np.clip(t_rel / 0.003, 0, 1)
    for k in kicks:
        j = min(len(gain), k + len(dip))
        gain[k:j] = np.minimum(gain[k:j], dip[: j - k])
    write_wav(path, softclip((music * gain[:, None] + drums) * 0.9, 1.4), peak=0.89)


def swing_t(step, amount=2 / 3):
    """Seconds into the bar of a 16th step with swung 8ths: the off-beat 8th sits at 2/3 of the beat."""
    beat, r = divmod(step, 4)
    if r == 2:
        r = 4 * amount
    elif r == 1:
        r = 2 * amount
    elif r == 3:
        r = 4 * amount + (4 - 4 * amount) / 2
    return beat * BEAT + r * STEP


def closed_hat(n, accent=1.0):
    t = np.arange(n) / SR
    return pan(highpass(noise(n), 7500) * np.exp(-t / 0.018) * accent * 0.5, 0.15)


# ===== rhythm variants: the skeleton with other grooves ==========================================
# 'four' is the existing groove (four-on-the-floor kick from the player, off-beat hats, octave
# bass). Each new one is a groove loop + a bass loop + the steps the player's kick falls on.
#   half   half-time: kick on 1 and the "and" of 3, clap on 3, long bass notes. Future-bass friendly.
#   break  2-step: kick on 1, the "a" of 2 and the "and" of 3, clap on 2 and 4, syncopated bass.
#   club   jersey-club bounce: kick x..x..x...x.x.x., clap on 2 and 4. Best with the cats.
RHYTHMS = {
    'half': dict(kick=[0, 10], clap=[8], hats=[0, 2, 4, 6, 8, 10, 12, 14], open_=[14],
                 bass=[(0, 6, 0), (10, 6, 0)]),
    'break': dict(kick=[0, 7, 10], clap=[4, 12], hats=list(range(16)), open_=[6, 14],
                  bass=[(0, 3, 0), (3, 1, 1), (7, 2, 0), (10, 3, 0), (14, 2, 1)]),
    'club': dict(kick=[0, 3, 6, 10, 12, 14], clap=[4, 12], hats=[2, 6, 10, 14], open_=[],
                 bass=[(0, 2, 0), (3, 2, 0), (6, 2, 1), (10, 2, 0), (12, 1, 0), (14, 2, 1)]),
}


def layer_rhythm_groove(r):
    x = blank()
    for bar in range(BARS):
        for s in r['hats']:
            acc = 1.0 if s % 4 == 2 else (0.6 if s % 2 == 0 else 0.35)
            place(x, closed_hat(t2n(0.06), acc), t2n(bar * BAR + s * STEP))
        for s in r['open_']:
            place(x, open_hat, t2n(bar * BAR + s * STEP), 0.6)
        for s in r['clap']:
            place(x, clap, t2n(bar * BAR + s * STEP), 0.8)
    return finish_loop(dirt(x, 1.2), peak=0.6)


def layer_rhythm_bass(r):
    x = blank()
    for bar, (_, root) in enumerate(CHORDS):
        f = mtof(nm(root) + 12)
        for s, ln, octv in r['bass']:
            n = t2n(ln * STEP * 0.95)
            place(x, pan(bass_note(f * (2 if octv else 1), n), 0.0), t2n(bar * BAR + s * STEP))
    return match_rms(finish_loop(softclip(x * 1.8, 2.2), peak=0.6), RMS_REF['L2_bass'])


RG = {}
for _k, _r in RHYTHMS.items():
    RG[_k] = (layer_rhythm_groove(_r), layer_rhythm_bass(_r))
    write_wav(os.path.join(OUT, f's1_disc_R{_k}_L1_groove_4b.wav'), RG[_k][0])
    write_wav(os.path.join(OUT, f's1_disc_R{_k}_L2_bass_4b.wav'), RG[_k][1], peak=None)


def rhythm_preview(name, colour):
    g, b = RG[name]
    k0, k3, k4 = colour
    render_custom(os.path.join(OUT, f's1_disc_preview_rhythm_{name}_20b.wav'),
                  [(k0, 1, 20, MIX['L0']), (g, 1, 19, MIX['L1']), (b, 5, 19, MIX['L2']),
                   (k3, 9, 20, MIX['L3']), (k4, 13, 19, MIX['L4'])], RHYTHMS[name]['kick'])


rhythm_preview('half', (L['fb_L0_keys'], L['fb_L3_hook'], L['fb_L4_peak']))
rhythm_preview('break', (L['fb_L0_keys'], L['fb_L3_hook'], L['A_L4_peak']))
rhythm_preview('club', (C['C_stabs'], C['C_lead'], C['C_drums']))
print('rhythm previews done')


# ===== jazz: swing groove, walking bass, piano, sax ==============================================
# Its own skeleton (swing can't share a straight groove), same chords, with jazz voicings.
JAZZ_VOICE = [['G3', 'Bb3', 'D4', 'F4'],      # Ebmaj9 (rootless: 3 5 7 9)
              ['A3', 'Eb4', 'G4', 'D5'],      # F13   (3 7 9 13)
              ['F3', 'A3', 'C4', 'E4'],       # Dm9
              ['Bb3', 'D4', 'F4', 'A4']]      # Gm9


def ride(n, accent=1.0):
    t = np.arange(n) / SR
    metal = sum(np.sin(2 * np.pi * f * t + 3 * np.sin(2 * np.pi * f * 1.41 * t)) for f in (3150, 4370, 5210)) / 3
    v = (highpass(noise(n), 6000) * 0.6 + metal * 0.4) * np.exp(-t / 0.35) * (1 + 1.5 * np.exp(-t / 0.01))
    return pan(v * 0.25 * accent, 0.3)


def layer_jazz_groove():
    """Ride 'ding, ding-da ding, ding-da' with swung 8ths, hi-hat foot on 2 and 4, brush ghosts."""
    x = blank()
    rng = np.random.default_rng(3)
    for bar in range(BARS):
        for s, acc in ((0, 0.8), (4, 1.0), (6, 0.6), (8, 0.8), (12, 1.0), (14, 0.6)):
            place(x, ride(t2n(0.5), acc), t2n(bar * BAR + swing_t(s)))
        for s in (4, 12):
            n = t2n(0.05)
            place(x, pan(bandpass(noise(n), 3000, 9000) * np.exp(-np.arange(n) / SR / 0.012) * 0.4, -0.2), t2n(bar * BAR + s * STEP))
        for s in range(0, 16, 2):
            if rng.random() < 0.5:
                n = t2n(0.09)
                place(x, pan(bandpass(noise(n), 1500, 6000) * np.exp(-np.arange(n) / SR / 0.04) * 0.08, -0.4), t2n(bar * BAR + swing_t(s)))
    return finish_loop(x, peak=0.6)


def upright(midi, n):
    t = np.arange(n) / SR
    f = mtof(midi)
    v = svf_lowpass(osc_saw(f, n), 300 + 1500 * np.exp(-t / 0.05), q=0.9) * 0.6 + osc_sine(f, n) * 0.8
    return pan(v * np.exp(-t / 0.35) * attack(n, 3), 0.0)


def layer_jazz_bass():
    """Walking quarters: root, two chord tones, then a half-step into the next root."""
    x = blank()
    roots = [nm(r) + 12 for _, r in CHORDS]
    for bar, (notes, _) in enumerate(CHORDS):
        r = roots[bar]
        nxt = roots[(bar + 1) % BARS]
        tones = sorted({(nm(q) - r) % 12 for q in notes})
        walk = [r, r + (7 if 7 in tones else tones[1]), r + 12 if bar % 2 else r + (tones[1] if tones[1] > 2 else 4), nxt + (1 if nxt <= r else -1)]
        for i, m in enumerate(walk):
            place(x, upright(m, t2n(BEAT * 1.1)), t2n(bar * BAR + i * BEAT))
    return match_rms(finish_loop(x, peak=0.6), RMS_REF['L2_bass'] * 0.8)


def layer_jazz_piano(piano_s):
    """Rootless voicings on the Charleston (beat 1, and the swung 'and' of 2), pushed into the
    next chord on the 'and' of 4 every second bar."""
    x = blank()
    for bar in range(BARS):
        v = [nm(q) for q in JAZZ_VOICE[bar]]
        hits = [(0, v, 0.5), (6, v, 0.4)]
        if bar % 2 == 1:
            hits.append((14, [nm(q) for q in JAZZ_VOICE[(bar + 1) % BARS]], 0.45))
        for s, vo, g in hits:
            for m in vo:
                place(x, gated(pitched(piano_s, m), 0.35, fade=0.08) * g, t2n(bar * BAR + swing_t(s)))
    x = highpass(x, 120)
    return match_rms(finish_loop(reverb(x, 1.0, 0.3, mix=0.12), peak=0.6), RMS_REF['A_L0_keys'])


def sax(midi, n, gate):
    """A cheesy synth tenor: saw through the formants of a sax, breath noise, a scoop up into each
    note and a lazy vibrato on long ones."""
    t = np.arange(n) / SR
    scoop = 2 ** (-1.2 * np.exp(-t / 0.04) / 12)
    vib = 1 + 0.009 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.15) / 0.15, 0, 1)
    f = mtof(midi) * scoop * vib
    raw = osc_saw(f, n)[:, None]
    body = bandpass(raw, 350, 900) + bandpass(raw, 1300, 1900) * 0.6 + bandpass(raw, 2400, 3200) * 0.25
    breath = bandpass(noise(n)[:, None], 1500, 5000) * 0.05
    v = (body + breath)[:, 0] * adsr(n, 0.02, 0.1, 0.8, 0.06, gate=gate)
    return pan(softclip(v * 2.0, 1.5), 0.05)


def layer_jazz_sax():
    x = blank()
    for bar in range(BARS):
        for s, p, length in RIFF_A[bar]:
            gate = length * STEP * (0.75 if length == 1 else 0.95) + 0.03
            place(x, sax(nm(p) - 12, t2n(gate + 0.08), gate) * 0.5, t2n(bar * BAR + swing_t(s)))
    x = highpass(x, 150)
    return match_rms(finish_loop(reverb(x, 1.2, 0.35, mix=0.14), peak=0.6), RMS_REF['A_L3_hook'])


def layer_jazz_shout(brass_s):
    """Big-band shout: brass chords on the off-beat pushes, a vibraphone answering on top."""
    x = blank()
    for bar in range(BARS):
        v = [nm(q) + 12 for q in JAZZ_VOICE[bar]]
        for s in ((6, 14) if bar % 2 else (14,)):
            for m in v:
                place(x, gated(pitched(brass_s, m), 0.22, fade=0.05) * 0.3, t2n(bar * BAR + swing_t(s)))
        for i, m in enumerate(v):
            n = t2n(0.8)
            vib = osc_fm(mtof(m + 12), n, ratio=4.0, index=1.2, index_decay=4) * np.exp(-np.arange(n) / SR / 0.5) * (1 + 0.3 * np.sin(2 * np.pi * 5 * np.arange(n) / SR))
            place(x, pan(vib * 0.12, 0.4), t2n(bar * BAR + swing_t(8 + i * 2)))
    x = highpass(x, 150)
    return match_rms(finish_loop(reverb(x, 1.2, 0.35, mix=0.14), peak=0.6), RMS_REF['A_L4_peak'])


piano2 = load(os.path.join(INST, '99Sounds x Monosounds - Piano 2 - C.wav'))
JZ = {'J_L1_groove': layer_jazz_groove(), 'J_L2_bass': layer_jazz_bass(), 'J_L0_piano': layer_jazz_piano(piano2),
      'J_L3_sax': layer_jazz_sax(), 'J_L4_shout': layer_jazz_shout(brass)}
for _n, _x in JZ.items():
    write_wav(os.path.join(OUT, f's1_disc_{_n}_4b.wav'), _x * (1.0 / max(1.0, np.max(np.abs(_x)) / 0.98)), peak=None)
render_custom(os.path.join(OUT, 's1_disc_preview_jazz_20b.wav'),
              [(JZ['J_L0_piano'], 1, 20, 0.7), (JZ['J_L1_groove'], 1, 19, 0.85), (JZ['J_L2_bass'], 5, 19, 0.8),
               (JZ['J_L3_sax'], 9, 20, 0.8), (JZ['J_L4_shout'], 13, 19, 0.65), (L['X_seal'], 17, 19, 0.7)],
              [0, 4, 8, 12], kick_gain=0.55)
print('jazz preview done')


# ===== The Entertainer (Scott Joplin, 1902, public domain), cat remix ===========================
# Notes from the Mutopia Project edition (public domain). One 2/4 measure = one of our bars, a
# ragtime 16th = our 8th, so it runs at "not fast" (quarter = 80) inside our 160 BPM grid. The intro
# (4 measures) plus the A strain (16) is exactly a 20-bar scene. (slot = Joplin 16th, 0-7)
ENT = [
    [(0, 'D6', 1), (1, 'E6', 1), (2, 'C6', 1), (3, 'A5', 2), (5, 'B5', 1), (6, 'G5', 2)],
    [(0, 'D5', 1), (1, 'E5', 1), (2, 'C5', 1), (3, 'A4', 2), (5, 'B4', 1), (6, 'G4', 2)],
    [(0, 'D4', 1), (1, 'E4', 1), (2, 'C4', 1), (3, 'A3', 2), (5, 'B3', 1), (6, 'A3', 1), (7, 'Ab3', 1)],
    [(0, 'G3', 2), (6, 'D5', 1), (7, 'D#5', 1)],
]
_m5 = [(0, 'E5', 1), (1, 'C6', 2), (3, 'E5', 1), (4, 'C6', 2), (6, 'E5', 1), (7, 'C6', 6)]
_m6 = [(5, 'C6', 1), (6, 'D6', 1), (7, 'D#6', 1)]
_m7 = [(0, 'E6', 1), (1, 'C6', 1), (2, 'D6', 1), (3, 'E6', 2), (5, 'B5', 1), (6, 'D6', 2)]
_m17 = [(0, 'E6', 1), (1, 'C6', 1), (2, 'D6', 1), (3, 'E6', 2), (5, 'C6', 1), (6, 'D6', 1), (7, 'C6', 1)]
ENT += [_m5, _m6, _m7, [(0, 'C6', 6), (6, 'D5', 1), (7, 'D#5', 1)],
        _m5[:-1] + [(7, 'C6', 7)], [(6, 'A5', 1), (7, 'G5', 1)],
        [(0, 'F#5', 1), (1, 'A5', 1), (2, 'C6', 1), (3, 'E6', 2), (5, 'D6', 1), (6, 'C6', 1), (7, 'A5', 1)],
        [(0, 'D6', 6), (6, 'D5', 1), (7, 'D#5', 1)],
        _m5, _m6, _m7, [(0, 'C6', 6), (6, 'C6', 1), (7, 'D6', 1)],
        _m17, _m17, _m7, [(0, 'C6', 8)]]
# left hand, per half measure: (bass note, chord) - None = the unison intro
_C, _C7, _F, _G7 = ['E4', 'G4', 'C5'], ['E4', 'G4', 'Bb4'], ['F4', 'A4', 'C5'], ['F4', 'G4', 'B4']
ENT_LH = [None, None, None, [('G2', _G7), ('G2', _G7)],
          [('C3', _C), ('G2', _C7)], [('F2', _F), ('E2', _C)], [('G2', _C), ('G2', _G7)], [('C3', _C), ('C3', _C)],
          [('C3', _C), ('G2', _C7)], [('F2', _F), ('E2', None)], [('D3', ['F#4', 'A4', 'C5']), ('D3', ['F#4', 'A4', 'C5'])], [('G2', _G7), ('A2', None)],
          [('C3', _C), ('G2', _C7)], [('F2', _F), ('E2', _C)], [('G2', _C), ('G2', _G7)], [('C3', _C), ('C3', _C)],
          [('C3', _C), ('Bb2', _C7)], [('A2', _F), ('Ab2', ['F4', 'Ab4', 'C5'])], [('G2', _C), ('G2', _G7)], [('C3', _C), ('C3', _C)]]
EB = len(ENT)                                     # 20 bars
ENT_LOOP = t2n(EB * BAR)


def ent_blank():
    return np.zeros((ENT_LOOP + TAIL, 2))


def ent_melody(voice, octave=0):
    """voice(midi, seconds) -> stereo; every note of the tune, at Joplin-16th = our-8th."""
    x = ent_blank()
    for bar, notes in enumerate(ENT):
        for slot, p, ln in notes:
            place(x, voice(nm(p) + octave, ln * 2 * STEP), t2n(bar * BAR + slot * 2 * STEP))
    return x


def ent_oompah(bass_voice, chord_voice, bars):
    """Ragtime left hand: bass on 1 and 3, the chord on 2 and 4 (our beats)."""
    x = ent_blank()
    for bar in bars:
        lh = ENT_LH[bar]
        if lh is None:
            continue
        for half, (b, ch) in enumerate(lh):
            at = bar * BAR + half * 2 * BEAT
            place(x, bass_voice(nm(b), BEAT * 0.9), t2n(at))
            if ch:
                place(x, chord_voice([nm(q) for q in ch], BEAT * 0.5), t2n(at + BEAT))
    return x


adult_cats, short_cats, kitten_cats, siamese = cats('ID 0903'), cats('ID 1899') + cats('ID 1901') + cats('ID 1898'), cats('ID 0390'), cats('Siamese')[0]
_k = [0]


def cat_voice(midi, seconds):
    _k[0] += 1
    src = short_cats[_k[0] % len(short_cats)] if seconds < 0.3 else adult_cats[_k[0] % len(adult_cats)]
    target = midi - 12 if midi > 76 else midi
    return pan(sing(src, target, max(seconds * 0.95, 0.12)), 0.0)


def pluck_voice(midi, seconds):
    return kawaii_pluck(midi, t2n(seconds + 0.15)) * 0.5


def cat_bass_voice(midi, seconds):
    """Entertainer oom-pah bass: a real bass note with a cat two octaves up, near its own pitch."""
    n = t2n(seconds)
    out = np.zeros((n, 2))
    out += pan(bass_note(mtof(midi), n), 0.0)
    v = stereo(sing(adult_cats[midi % len(adult_cats)], midi + 24, min(seconds, 0.2)))
    out[: min(n, len(v))] += v[: min(n, len(v))] * 0.7
    return out


def cat_chord_voice(midis, seconds):
    out = None
    for i, (m, side) in enumerate(zip(midis, (-0.5, 0.0, 0.5))):
        v = pan(chop(adult_cats[i % len(adult_cats)], m, seconds).mean(axis=1), side) * 0.6
        out = v if out is None else out[: min(len(out), len(v))] + v[: min(len(out), len(v))]
    return out


def fb_chord_bed():
    """Future-bass supersaw chords, pumping on every beat, following the left hand's harmony."""
    x = ent_blank()
    for bar in range(EB):
        lh = ENT_LH[bar]
        if lh is None:
            continue
        for half, (b, ch) in enumerate(lh):
            ch = ch or lh[0][1] or _C
            n = t2n(2 * BEAT)
            c = sum(saw_stack(mtof(nm(q)), n, voices=7, detune=0.4) for q in ch) / len(ch)
            c = lowpass(c, 5000)
            c[-t2n(0.01):] *= np.linspace(1, 0, t2n(0.01))[:, None]
            place(x, c * 0.5, t2n(bar * BAR + half * 2 * BEAT))
    return x * pump(len(x))[:, None]


def cat_drum_track(low, high, bars):
    x = ent_blank()
    for bar in bars:
        for beat in range(4):
            src = adult_cats[(bar + beat) % len(adult_cats)] if beat % 2 == 0 else short_cats[beat % len(short_cats)]
            v = chop(src, low if beat % 2 == 0 else high, 0.24, fade=0.04)
            place(x, pan(v.mean(axis=1), 0.0), t2n(bar * BAR + beat * BEAT))
            v = chop(kitten_cats[(bar + beat) % len(kitten_cats)], high + 24, 0.07, fade=0.02)
            place(x, pan(v.mean(axis=1), 0.3 if beat % 2 else -0.3), t2n(bar * BAR + beat * BEAT + 2 * STEP), 0.35)
    return x


def entertainer(path):
    """bars 1-4   the intro cascade on the kawaii pluck, cats saying 'meow' on the downbeats
       bars 5-12  A strain: pluck tune over future-bass chords + cat oom-pah, meow drums
       bars 13-20 the tune again, sung by the cats; pluck an octave up, quieter"""
    lead_pluck = ent_melody(pluck_voice)
    lead_cat = ent_melody(cat_voice, octave=-12)
    oom = ent_oompah(cat_bass_voice, cat_chord_voice, range(3, EB))
    bed = fb_chord_bed()
    drums = cat_drum_track(nm('G4'), nm('C5'), range(4, EB))
    for x in (lead_pluck, lead_cat, oom, bed, drums):
        x[ENT_LOOP:] = 0
    mix = np.zeros((ENT_LOOP + t2n(1.5), 2))
    pl = np.ones(len(mix))
    pl[12 * bar_n:] = 0.35
    ct = np.zeros(len(mix))
    ct[12 * bar_n:] = 1.0
    n = min(len(mix), len(lead_pluck))
    mix[:n] += lead_pluck[:n] * pl[:n, None] * 0.55
    mix[:n] += highpass(lead_cat, 120)[:n] * ct[:n, None] * 1.1
    mix[:n] += oom[:n] * 0.6 + bed[:n] * 0.32 + highpass(drums, 200)[:n] * 0.7
    for b in range(3):                                   # the cats on the intro downbeats
        place(mix, pan(chop(adult_cats[b], nm('G4') - 5 * b, 0.35).mean(axis=1), 0.0), b * bar_n, 0.8)
    kicks = [b * bar_n + s * t2n(BEAT) for b in range(4, EB) for s in range(4)] + [EB * bar_n]
    kd = np.zeros_like(mix)
    for k in kicks:
        place(kd, kick, k, 0.9)
    place(kd, crs, EB * bar_n, 0.6)
    gain = np.ones(len(mix))
    t_rel = np.arange(t2n(0.3)) / SR
    dip = 1 - 0.4 * np.exp(-t_rel / 0.09) * np.clip(t_rel / 0.003, 0, 1)
    for k in kicks:
        j = min(len(gain), k + len(dip))
        gain[k:j] = np.minimum(gain[k:j], dip[: j - k])
    write_wav(path, softclip(reverb(mix, 0.8, 0.25, mix=0.06)[: len(mix)] * gain[:, None] + kd, 1.4), peak=0.89)


entertainer(os.path.join(OUT, 's1_disc_preview_entertainer_cat_20b.wav'))
print('entertainer done')


# ===== classic tunes as a lead layer over our own style ========================================
# Only the tune is borrowed: it becomes a 16-bar L3 loop in our key over our chords, groove, bass
# and colour layers, so it drops into any scene like any other hook. The Entertainer's A strain,
# moved down a tone to Bb, sits on Ebmaj7-F7-Dm7-Gm7 almost note for note: bar 1 of each line
# arpeggiates Bb over Ebmaj7, the run in bar 3 lands on D-A-C of Dm7, the held Bb lands on Gm7.
# Its ragtime syncopation stays (Joplin 16th = our 8th).
ENT_A = ENT[4:19] + [[(0, 'C6', 6), (6, 'D5', 1), (7, 'D#5', 1)]]   # m5-m19 + m20 with the pickup back in
ENT_SHIFT = -2                                                     # C major -> Bb major


def classic_lead(tune, voice, shift, octave=0):
    bars = len(tune)
    n = t2n(bars * BAR)
    x = np.zeros((n + TAIL, 2))
    for bar, notes in enumerate(tune):
        for slot, p, ln in notes:
            place(x, voice(nm(p) + shift + octave, ln * 2 * STEP), t2n(bar * BAR + slot * 2 * STEP))
    y = x[:n].copy()
    y[:TAIL] += x[n:n + TAIL]                                     # tails wrap round: a seamless loop
    return y


def square_voice(midi, seconds):
    return square_lead(midi, seconds * (0.8 if seconds < 0.2 else 0.92)) * 0.45


ENT_LEADS = {
    'ent_fb_L3_lead': highpass(classic_lead(ENT_A, pluck_voice, ENT_SHIFT), 200),
    'ent_cat_L3_lead': highpass(classic_lead(ENT_A, cat_voice, ENT_SHIFT, octave=-12), 120),
    'ent_A_L3_lead': highpass(classic_lead(ENT_A, square_voice, ENT_SHIFT), 200),
}
for _n in ENT_LEADS:
    ENT_LEADS[_n] = match_rms(ENT_LEADS[_n], RMS_REF['A_L3_hook'])
    write_wav(os.path.join(OUT, f's1_disc_{_n}_16b.wav'), ENT_LEADS[_n] * (1.0 / max(1.0, np.max(np.abs(ENT_LEADS[_n])) / 0.98)), peak=None)

# bars 1-4 bed + groove + bass, the tune from bar 5 for 16 bars, the peak layer from bar 13
render_custom(os.path.join(OUT, 's1_disc_preview_ent_fb_20b.wav'),
              [(L['fb_L0_keys'], 1, 20, MIX['L0']), (L['L1_groove'], 1, 19, MIX['L1']), (L['L2_bass'], 1, 19, MIX['L2']),
               (ENT_LEADS['ent_fb_L3_lead'], 5, 20, MIX['L3']), (L['fb_L4_peak'], 13, 19, MIX['L4'])], [0, 4, 8, 12])
render_custom(os.path.join(OUT, 's1_disc_preview_ent_cat_20b.wav'),
              [(C['C_stabs'], 1, 20, MIX['L0']), (L['L1_groove'], 1, 19, MIX['L1']), (C['C_bass'], 1, 19, MIX['L2']),
               (C['C_drums'], 1, 19, 0.8), (ENT_LEADS['ent_cat_L3_lead'], 5, 20, MIX['L3'] * 1.1),
               (L['fb_L4_peak'], 13, 19, MIX['L4'] * 0.8)], [0, 4, 8, 12])
render_custom(os.path.join(OUT, 's1_disc_preview_ent_euro_20b.wav'),
              [(L['A_L0_keys'], 1, 20, MIX['L0']), (L['L1_groove'], 1, 19, MIX['L1']), (L['L2_bass'], 1, 19, MIX['L2']),
               (ENT_LEADS['ent_A_L3_lead'], 5, 20, MIX['L3']), (L['A_L4_peak'], 13, 19, MIX['L4'])], [0, 4, 8, 12])
print('classic lead previews done')

def audition(path):
    """Each candidate lead plays the riff for 4 bars over keys, groove, bass and kick, in the
    order of LEAD_CANDIDATES, with a one-beat gap between them."""
    gap = t2n(BEAT)
    parts = []
    bed = L['A_L0_keys'] * 0.6 + L['L1_groove'] * 0.85 + L['L2_bass'] * 0.72
    for k in LEAD_CANDIDATES:
        hook = layer_hook_a(lead_shot(k))
        hook *= 0.125 / np.sqrt(np.mean(hook ** 2))      # all candidates equally loud
        seg = bed + hook * 0.78
        for b in range(BARS * 4):
            place(seg, kick, b * t2n(BEAT), 0.95)
        parts += [seg[:LOOP], np.zeros((gap, 2))]
    write_wav(path, softclip(np.concatenate(parts) * 0.8, 1.3), peak=0.89)

for _n in ('L0_keys', 'L3_hook', 'L4_peak'):
    print(_n, 'rms A %.4f  B %.4f' % tuple(float(np.sqrt(np.mean(L[f'{v}_{_n}'] ** 2))) for v in 'AB'))
