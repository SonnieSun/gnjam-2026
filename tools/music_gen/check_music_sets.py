"""Prints every stage of every level's music (levels/music/*.json) and flags the two things a stage change
inside a scene must not do: start a tune without its melody, or take the melody away once it is playing.
(The rules are written out in make_music_sets.py above TUNES.) In fever the kiai lane counts as melody too.

usage: python check_music_sets.py <game project dir>
"""
import glob
import json
import os
import sys

MELODY = ('lead', 'kiai', 'hit')
bad = 0
for path in sorted(glob.glob(os.path.join(sys.argv[1], 'levels', 'music', '*.json'))):
    d = json.load(open(path, encoding='utf-8'))
    if not d.get('use_in_game'):
        continue
    print('==', os.path.basename(path))
    for s in d['sections']:
        cues = s.get('cues', {})
        points = sorted({0.0} | {float(p) for c in cues.values() for p, _ in c})
        fever = s.get('fever') or []
        fever = [fever] if fever and not isinstance(fever[0], list) else fever

        def at(lane, p):
            cur = ''
            for q, c in cues.get(lane, []):
                if q <= p + 1e-9:
                    cur = c
            return cur

        print('  %s   fill bars: tiers %s, before fever %s, on entering %s%s' % (
            s['title'], s.get('transition_tiers') or 'none', 'yes' if s.get('fever_fill', True) and fever else 'no',
            'no' if not s.get('enter_fill', True) else 'yes', ', written transition ' + s['enter'] if s.get('enter') else ''))
        before = None
        for p in points:
            mel = [at(lane, p) for lane in MELODY if at(lane, p)]
            if not mel and any(a <= p + 1e-9 < b or (b >= 0.999 and p >= a) for a, b in fever):
                mel = ['(fever: the kiai lane)']
            rest = [at(lane['id'], p) for lane in d['lanes'] if lane['id'] not in MELODY and at(lane['id'], p)]
            flag = ''
            if before and not mel:
                flag = '   <-- THE TUNE STOPS'
            elif p == 0.0 and not mel:
                flag = '   <-- no tune at the start'
            bad += bool(flag)
            print('     %5.1f%%  tune: %-30s | %s%s' % (p * 100, ' + '.join(mel) or '-', ' '.join(rest), flag))
            before = mel
print('%d flagged' % bad)
