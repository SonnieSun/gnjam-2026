"""Writes the starting music set of every level to levels/music/level_<n>.json (the file the Music
autoload plays and the Music Director panel edits). Run once; after that edit in the panel.

A set is: the tracks (each a looping WAV, all started together) and, per section of the level, which
tracks sound at which gauge progress (0 = section just started, 1 = gauge full):

  {"title", "bpm", "use_in_game", "quantize_beats",
   "tracks":   [{"id", "file", "group", "gain_db"}],
   "sections": [{"title", "rules": {track id: [[from, to], ...]}}]}

usage: python -I make_music_sets.py <godot project dir> [--force]
"""
import json
import os
import sys

G = sys.argv[1]
FORCE = '--force' in sys.argv
OUT = os.path.join(G, 'levels', 'music')
os.makedirs(OUT, exist_ok=True)
M = 'res://assets/audio/music/'
S1 = M + 'scene1/'


def t(id_, path, group, gain=0.0):
    return {'id': id_, 'file': path, 'group': group, 'gain_db': gain}


SKELETON = [t('groove', S1 + 'skeleton/s1_L1_groove_4b.wav', 'groove'),
            t('bass', S1 + 'skeleton/s1_L2_bass_4b.wav', 'bass')]


def style(key, folder, prefix):
    return [t(f'{key}_keys', f'{S1}{folder}/s1_{prefix}_L0_keys_4b.wav', 'bed'),
            t(f'{key}_hook', f'{S1}{folder}/s1_{prefix}_L3_hook_4b.wav', 'hook'),
            t(f'{key}_peak', f'{S1}{folder}/s1_{prefix}_L4_peak_4b.wav', 'peak')]


CATS = [t('cat_drums', S1 + 'cat_band/s1_C_drums_4b.wav', 'cat'),
        t('cat_stabs', S1 + 'cat_band/s1_C_stabs_4b.wav', 'bed'),
        t('cat_lead', S1 + 'cat_band/s1_C_lead_4b.wav', 'hook'),
        t('cat_bass', S1 + 'cat_band/s1_C_bass_4b.wav', 'bass')]
EVENTS = [t('ev_meow', S1 + 'events/s1_X_meow_4b.wav', 'event'),
          t('ev_seal', S1 + 'events/s1_X_seal_4b.wav', 'event')]
JAZZ = [t('jazz_piano', S1 + 'style_jazz/s1_J_L0_piano_4b.wav', 'bed'),
        t('jazz_groove', S1 + 'style_jazz/s1_J_L1_groove_4b.wav', 'groove'),
        t('jazz_bass', S1 + 'style_jazz/s1_J_L2_bass_4b.wav', 'bass'),
        t('jazz_sax', S1 + 'style_jazz/s1_J_L3_sax_4b.wav', 'hook'),
        t('jazz_shout', S1 + 'style_jazz/s1_J_L4_shout_4b.wav', 'peak')]


def stack(key, extra=None):
    """The usual build-up of one style over a section: bed and groove from the start, bass at a
    quarter, the hook at half, the peak at three quarters."""
    r = {'groove': [[0, 1]], f'{key}_keys': [[0, 1]], 'bass': [[0.25, 1]],
         f'{key}_hook': [[0.5, 1]], f'{key}_peak': [[0.75, 1]]}
    r.update(extra or {})
    return r


def more_cat(key, n):
    """Section n (0-5) of a six-section level, one more cat layer each section: the swaps happen
    halfway through, so each section starts where the last one ended."""
    r = stack(key)
    if n >= 1:
        r['cat_drums'] = [[0.5 if n == 1 else 0, 1]]
    if n >= 2:
        r[f'{key}_keys'] = [[0, 0.5]] if n == 2 else []
        r['cat_stabs'] = [[0.5 if n == 2 else 0, 1]]
    if n >= 3:
        r[f'{key}_hook'] = [[0.5, 1]] if n == 2 else ([] if n > 3 else [])
        r['cat_lead'] = [[0.5 if n == 3 else 0, 1]]
        if n == 3:
            r[f'{key}_hook'] = []
    if n >= 4:
        r['bass'] = [[0.25, 0.5]] if n == 4 else []
        r['cat_bass'] = [[0.5 if n == 4 else 0.25, 1]]
    if n >= 5:
        r['ev_meow'] = [[0.75, 1]]
    return {k: v for k, v in r.items() if v}


SETS = {
    1: {'title': 'LEVEL 1', 'tracks': SKELETON + style('fb', 'style_futurebass', 'fb') + CATS + EVENTS[:1],
        'sections': [{'title': 'DISCO', 'rules': {
            'groove': [[0, 1]], 'fb_keys': [[0, 0.5]], 'cat_stabs': [[0.5, 1]],
            'bass': [[0.15, 0.8]], 'cat_bass': [[0.8, 1]], 'fb_hook': [[0.3, 0.65]], 'cat_lead': [[0.65, 1]],
            'fb_peak': [[0.45, 1]], 'cat_drums': [[0.15, 1]], 'ev_meow': [[0.9, 1]]}}]},
    2: {'title': 'LEVEL 2',
        'tracks': SKELETON + style('fb', 'style_futurebass', 'fb') + style('euro', 'style_eurobeat', 'A')
        + style('chip', 'style_chip', 'chip') + style('disco', 'style_disco', 'B') + JAZZ + CATS[:1] + CATS[2:3],
        'sections': []},
    3: {'title': 'LEVEL 3', 'tracks': SKELETON + style('fb', 'style_futurebass', 'fb') + CATS + EVENTS, 'sections': []},
    4: {'title': 'LEVEL 4', 'tracks': SKELETON + style('euro', 'style_eurobeat', 'A') + CATS + EVENTS, 'sections': []},
}
# level 2: the eight drawing styles twice; one music style each, the second round a little catty
names2 = ['1 LICK', '2 SHRINK', '3 TRIPLE', '4 ORBIT', '5 CLOCK', '6 RIPPLE', '7 RINGS', '8 MOON']
styles2 = ['fb', 'euro', 'chip', 'disco', 'fb', 'jazz', 'euro', 'chip']
for rnd in range(2):
    for name, st in zip(names2, styles2):
        if st == 'jazz':
            rules = {'jazz_groove': [[0, 1]], 'jazz_piano': [[0, 1]], 'jazz_bass': [[0.25, 1]],
                     'jazz_sax': [[0.5, 1]], 'jazz_shout': [[0.75, 1]]}
        else:
            rules = stack(st)
            if rnd == 1:
                rules['cat_drums'] = [[0.5, 1]]
                rules['cat_lead'] = [[0.75, 1]]
                rules[f'{st}_hook'] = [[0.5, 0.75]]
        SETS[2]['sections'].append({'title': name, 'rules': rules})
mv = ['1 DISC', '2 TAIL', '3 EARTH', '4 BIGCAT', '5 WASHER', '6 UFO']
for lv, key in ((3, 'fb'), (4, 'euro')):
    SETS[lv]['sections'] = [{'title': name, 'rules': more_cat(key, i)} for i, name in enumerate(mv)]
CC = M + 'classics/can_can/can_can_'
SETS[5] = {'title': 'LEVEL 5',
           'tracks': [SKELETON[0], t('cc_keys', CC + 'fb_L0_keys_8b.wav', 'bed'), t('cc_bass', CC + 'L2_bass_8b.wav', 'bass'),
                      t('cc_peak', CC + 'fb_L4_peak_8b.wav', 'peak'), t('cc_pluck', CC + 'L3_pluck_8b.wav', 'hook'),
                      t('cc_cat_flow', CC + 'L3_cat_flow_8b.wav', 'hook'), t('cc_cat', CC + 'L3_cat_8b.wav', 'hook'),
                      t('cc_cat_drums', CC + 'C_drums_8b.wav', 'cat'), t('cc_cat_stabs', CC + 'C_stabs_8b.wav', 'bed'),
                      t('cc_cat_bass', CC + 'C_bass_8b.wav', 'bass')],
           'sections': [{'title': 'PIZZA CAT', 'rules': {
               'groove': [[0, 1]], 'cc_keys': [[0, 0.6]], 'cc_cat_stabs': [[0.6, 1]], 'cc_bass': [[0.15, 0.85]],
               'cc_cat_bass': [[0.85, 1]], 'cc_pluck': [[0.3, 0.55]], 'cc_cat_flow': [[0.55, 0.8]], 'cc_cat': [[0.8, 1]],
               'cc_peak': [[0.5, 1]], 'cc_cat_drums': [[0.2, 1]]}}]}

for n, s in SETS.items():
    path = os.path.join(OUT, f'level_{n}.json')
    if os.path.exists(path) and not FORCE:
        print('kept', path)
        continue
    assert len(s['tracks']) <= 32, (n, len(s['tracks']))
    ids = {tr['id'] for tr in s['tracks']}
    for sec in s['sections']:
        assert set(sec['rules']) <= ids, (n, set(sec['rules']) - ids)
    body = {'title': s['title'], 'bpm': 160, 'use_in_game': False, 'quantize_beats': 4,
            'tracks': s['tracks'], 'sections': s['sections']}
    json.dump(body, open(path, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    print('wrote', path, len(s['tracks']), 'tracks,', len(s['sections']), 'sections')
