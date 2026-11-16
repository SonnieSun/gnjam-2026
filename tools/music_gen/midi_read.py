"""Reading a MIDI file as sheet music: notes with their channel and program, printed bar by bar, so a tune and
its chords can be written into compose_classics.py by hand. (The files in reference/ are untrusted downloads:
run with python -I.)

  python -I midi_read.py <file.mid>                                 the tracks / channels and what is in them
  python -I midi_read.py <file.mid> bars <first> <last> [options]   one line per bar: the top note on every step
      --beats N      beats (quarter notes) in a bar, default 4      --grid N   steps in a whole note, default 16
      --offset B     the first bar starts B beats into the file     --ch a,b   only these channels (0-15)
      --low M        ignore notes below MIDI note M                 --chords   also name the chord of each bar
"""
import struct
import sys

NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


def name(m):
    return '%s%d' % (NAMES[m % 12], m // 12 - 1)


def read(path):
    """-> (ticks per quarter, [(start tick, end tick, midi, channel, velocity)], {channel: program}, tempo, (num, den))."""
    b = open(path, 'rb').read()
    ntr, div = struct.unpack('>HH', b[10:14])
    p, notes, prog, tempo, sig = 14, [], {}, 120.0, (4, 4)
    for _ in range(ntr):
        ln = struct.unpack('>I', b[p + 4:p + 8])[0]
        d = b[p + 8:p + 8 + ln]
        p += 8 + ln
        i = tick = run = 0
        on = {}
        while i < len(d):
            v = 0
            while True:
                c = d[i]
                i += 1
                v = (v << 7) | (c & 0x7f)
                if c < 0x80:
                    break
            tick += v
            st = d[i]
            if st == 0xff:
                ty = d[i + 1]
                i += 2
                ln2 = 0
                while True:
                    c = d[i]
                    i += 1
                    ln2 = (ln2 << 7) | (c & 0x7f)
                    if c < 0x80:
                        break
                data = d[i:i + ln2]
                i += ln2
                if ty == 0x51 and tick == 0:
                    tempo = 60000000 / int.from_bytes(data, 'big')
                if ty == 0x58 and tick == 0:
                    sig = (data[0], 2 ** data[1])
                continue
            if st in (0xf0, 0xf7):
                i += 1
                ln2 = 0
                while True:
                    c = d[i]
                    i += 1
                    ln2 = (ln2 << 7) | (c & 0x7f)
                    if c < 0x80:
                        break
                i += ln2
                continue
            if st & 0x80:
                run = st
                i += 1
            hi, ch = run & 0xf0, run & 0x0f
            if hi in (0xc0, 0xd0):
                if hi == 0xc0:
                    prog[ch] = d[i]
                i += 1
                continue
            a, v2 = d[i], d[i + 1]
            i += 2
            if hi == 0x90 and v2 > 0:
                on[(ch, a)] = (tick, v2)
            elif hi == 0x80 or (hi == 0x90 and v2 == 0):
                if (ch, a) in on:
                    t0, vel = on.pop((ch, a))
                    notes.append((t0, tick, a, ch, vel))
    return div, sorted(notes), prog, tempo, sig


TRIADS = {'': (0, 4, 7), 'm': (0, 3, 7), '7': (0, 4, 7, 10), 'm7': (0, 3, 7, 10), 'dim': (0, 3, 6)}


def chord_of(notes, t0, t1):
    """The chord a stretch of notes spells: the triad / seventh whose tones cover the most sounding time."""
    w = [0.0] * 12
    low, low_w = None, {}
    for a, b, m, _, _ in notes:
        d = min(b, t1) - max(a, t0)
        if d > 0:
            w[m % 12] += d
            if m < 60:
                low_w[m % 12] = low_w.get(m % 12, 0.0) + d
    if sum(w) == 0:
        return '-'
    if low_w:
        low = max(low_w, key=low_w.get)
    best = None
    for root in range(12):
        for q, tones in TRIADS.items():
            score = sum(w[(root + t) % 12] for t in tones) - 0.6 * sum(w[k] for k in range(12) if (k - root) % 12 not in tones)
            score += 0.25 * sum(w) * (root == low) - 0.05 * sum(w) * (len(tones) > 3)
            if best is None or score > best[0]:
                best = (score, NAMES[root] + q)
    return best[1]


if __name__ == '__main__':
    div, notes, prog, tempo, sig = read(sys.argv[1])
    args = sys.argv[2:]
    opt = {'--beats': 4.0, '--grid': 16, '--offset': 0.0, '--ch': '', '--low': 0}
    for k in list(opt):
        if k in args:
            opt[k] = type(opt[k])(args[args.index(k) + 1])
    if not args or args[0] != 'bars':
        print('ticks per quarter %d, tempo %.0f, time %d/%d, %.0f beats' % (div, tempo, sig[0], sig[1], max(n[1] for n in notes) / div))
        for ch in sorted({n[3] for n in notes}):
            ns = [n for n in notes if n[3] == ch]
            print('  channel %2d  program %3s  %5d notes  %s..%s  mean length %.2f beats' % (
                ch, prog.get(ch, '-'), len(ns), name(min(n[2] for n in ns)), name(max(n[2] for n in ns)),
                sum(n[1] - n[0] for n in ns) / len(ns) / div))
        sys.exit()
    chans = {int(c) for c in opt['--ch'].split(',') if c != ''}
    use = [n for n in notes if (not chans or n[3] in chans) and n[2] >= opt['--low']]
    bar, step = div * opt['--beats'], div * 4.0 / opt['--grid']
    for k in range(int(args[1]) - 1, int(args[2])):
        t0 = opt['--offset'] * div + k * bar
        row = []
        for s in range(int(round(bar / step))):
            ts = t0 + s * step
            ns = [n for n in use if abs(n[0] - ts) < step / 3 and n[1] - n[0] > step / 4]
            row.append(name(max(x[2] for x in ns)) if ns else '.')
        tail = '   ' + chord_of([n for n in notes if n[3] != 9], t0, t0 + bar) if '--chords' in args else ''
        print('bar %3d: %s%s' % (k + 1, ' '.join('%-4s' % r for r in row), tail))
