"""Writes the starting music set of every level to levels/music/level_<n>.json (the file the Music
autoload plays and the Music Director panel edits). Run once; after that edit in the panel.

A set is a few tracks ("lanes": rhythm, bass, chords, melody, ...), each holding clips (looping WAVs,
all started together); only one clip of a lane sounds at a time. Per section of the level, each lane
has cues: at this gauge progress (0 = section just started, 1 = gauge full) switch to this clip
("" = silence). The clip of the last cue at or below the current progress is the one that sounds.

  {"title", "bpm", "use_in_game", "quantize_beats",
   "lanes":    [{"id", "name", "gain_db", "clips": [{"id", "file"}]}],
   "sections": [{"title", "cues": {lane id: [[progress, clip id], ...]}}]}

The sets below are written as overlapping on/off ranges per clip (easier to write by hand) and turned
into lanes and cues at the end.

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


# --- Kisa's levels -------------------------------------------------------------------------------
# level 6, the disco litter box, stays at its own 120 BPM: the 120 render of scene 1 (scene1_120).
# One layer per stage event, the way its own music did it (gauge 315, lines at 20 40 60 80 | 110 150
# 190 230 | 300). The room is the jazz style, like its own swing-jazz room set (stars = piano, ball =
# brass shout, dancers = sax + meow drums, drift = pad); when the house comes apart the beat turns
# into the club groove with future bass, and the cats take over part by part; the UFO brings the meow
# event track. The disco style stems are in the lanes too, to swap in from the panel.
# Then the abduction section is the all-cat band over the half-time beat.
S120 = M + 'scene1_120/s120_'


def t120(id_, key, group):
    return t(id_, f'{S120}{key}_4b.wav', group)


E = [v / 315 for v in (20, 40, 60, 80, 110, 150, 190, 230, 300)]
SETS[6] = {'title': 'DISCO', 'bpm': 120, 'use': True,
           'tracks': [t120('jazz_groove', 'J_L1_groove', 'groove'), t120('jazz_bass', 'J_L2_bass', 'bass'),
                      t120('jazz_piano', 'J_L0_piano', 'bed'), t120('jazz_sax', 'J_L3_sax', 'hook'), t120('jazz_shout', 'J_L4_shout', 'peak'),
                      t120('groove', 'L1_groove', 'groove'), t120('club', 'Rclub_L1_groove', 'groove'),
                      t120('half', 'Rhalf_L1_groove', 'groove'),
                      t120('bass', 'L2_bass', 'bass'), t120('club_bass', 'Rclub_L2_bass', 'bass'), t120('cat_bass', 'C_bass', 'bass'),
                      t120('disco_keys', 'B_L0_keys', 'bed'), t120('fb_keys', 'fb_L0_keys', 'bed'), t120('cat_stabs', 'C_stabs', 'bed'),
                      t120('disco_hook', 'B_L3_hook', 'hook'), t120('fb_hook', 'fb_L3_hook', 'hook'),
                      t120('cat_flow', 'C_lead_flow', 'hook'), t120('cat_kichiku', 'C_lead_kichiku', 'hook'), t120('cat_lead', 'C_lead', 'hook'),
                      t120('disco_peak', 'B_L4_peak', 'peak'), t120('fb_peak', 'fb_L4_peak', 'peak'),
                      t120('cat_drums', 'C_drums', 'cat'), t120('ev_meow', 'X_meow', 'event'), t120('ev_seal', 'X_seal', 'event')],
           'sections': [
               {'title': 'DISCO', 'rules': {
                   # The usual sound is the music with meow drums and the cats singing the tune: the meow
                   # drums come in first, then the cat lead. Cat chords and cat bass are rare: only the
                   # last stretch (the plaza).
                   'jazz_groove': [[0, E[4]]], 'club': [[E[4], 1]],                               # 5 road: club beat
                   'jazz_bass': [[0, E[4]]], 'club_bass': [[E[4], E[7]]], 'cat_bass': [[E[7], 1]],   # 8 plaza: all cats
                   'jazz_piano': [[E[0], E[4]]], 'fb_keys': [[E[4], E[7]]], 'cat_stabs': [[E[7], 1]],   # 1 stars: piano
                   'jazz_shout': [[E[1], E[4]]], 'fb_peak': [[E[6], 1]],                          # 2 ball: brass; 7 grid
                   'cat_drums': [[E[2], 1]],                                                      # 3 dancers: meow drums
                   # the cat lead is the 'flow' one (every meow rings out); the kichiku one takes the plaza
                   'cat_flow': [[E[3], E[4]], [E[5], E[7]]], 'fb_hook': [[E[4], E[5]]],           # 4 drift and 6 dance floor: cats sing
                   'cat_kichiku': [[E[7], 1]],
                   'ev_meow': [[E[8], 1]]}},                                                      # 9 UFO
               {'title': 'ABDUCTION', 'rules': {
                   'half': [[0, 1]], 'bass': [[0, 1]], 'fb_keys': [[0, 1]], 'cat_drums': [[0, 1]],
                   'cat_kichiku': [[1 / 3, 1]], 'ev_seal': [[2 / 3, 1]]}}]}
# levels 7-9 at 160 with three different songs, to try the new music on them
SETS[7] = {'title': 'SPACESHIP', 'use': True, 'tracks': SKELETON + style('euro', 'style_eurobeat', 'A') + CATS[:1] + CATS[2:3] + EVENTS[:1],
           'sections': [{'title': 'SPACESHIP', 'rules': stack('euro', {
               'euro_hook': [[0.25, 0.5]], 'cat_drums': [[0.25, 1]], 'cat_lead': [[0.5, 1]], 'bass': [[0.15, 1]], 'ev_meow': [[0.9, 1]]})}]}
MK = M + 'classics/mountain_king/mountain_king_'
SETS[8] = {'title': 'ABDUCTION', 'use': True,
           'tracks': [SKELETON[0], t('mk_keys', MK + 'fb_L0_keys_4b.wav', 'bed'), t('mk_bass', MK + 'L2_bass_4b.wav', 'bass'),
                      t('mk_pluck', MK + 'L3_pluck_4b.wav', 'hook'), t('mk_kichiku', MK + 'L3_cat_kichiku_4b.wav', 'hook'),
                      t('mk_cat_flow', MK + 'L3_cat_flow_4b.wav', 'hook'), t('mk_peak', MK + 'fb_L4_peak_4b.wav', 'peak'),
                      t('mk_cat_drums', MK + 'C_drums_4b.wav', 'cat')],
           'sections': [{'title': 'ABDUCTION', 'rules': {
               'groove': [[0, 1]], 'mk_keys': [[0, 1]], 'mk_bass': [[0.15, 1]], 'mk_pluck': [[0.15, 1 / 3]], 'mk_cat_drums': [[0.15, 1]],
               'mk_cat_flow': [[1 / 3, 2 / 3]], 'mk_kichiku': [[2 / 3, 1]], 'mk_peak': [[0.8, 1]]}}]}
SETS[9] = {'title': 'TV WALL', 'use': True, 'tracks': SKELETON + style('chip', 'style_chip', 'chip') + CATS[:1] + CATS[2:3],
           'sections': [{'title': 'TV WALL', 'rules': stack('chip', {
               'chip_hook': [[0.25, 0.5]], 'cat_drums': [[0.25, 1]], 'cat_lead': [[0.5, 1]], 'bass': [[0.15, 1]]})}]}

# file = the level file it goes with (levels/<name>.tres)
NAMES = {n: f'level_{n}' for n in range(1, 6)}
NAMES.update({6: 'level_6_disco', 7: 'level_7_spaceship', 8: 'level_8_abduction', 9: 'level_9_tv_wall'})
LANES = [('beat', '节奏', 'groove'), ('bass', '低音', 'bass'), ('bed', '和声', 'bed'), ('lead', '旋律', 'hook'),
         ('peak', '高潮', 'peak'), ('meow', '猫鼓', 'cat'), ('fx', '事件', 'event')]


def to_lanes(s):
    lanes, cues_of = [], []
    for lane_id, name, group in LANES:
        clips = [{'id': tr['id'], 'file': tr['file']} for tr in s['tracks'] if tr['group'] == group]
        if clips:
            lanes.append({'id': lane_id, 'name': name, 'gain_db': 0.0, 'clips': clips})
    sections = []
    for sec in s['sections']:
        cues = {}
        for lane in lanes:
            ids = [c['id'] for c in lane['clips']]
            points = sorted({0.0} | {float(e) for i in ids for r in sec['rules'].get(i, []) for e in r if e < 1.0})
            seq, last = [], None
            for p in points:
                on = next((i for i in ids for r in sec['rules'].get(i, []) if r[0] <= p + 1e-9 < r[1]), '')
                if on != last:
                    if not (on == '' and last is None):
                        seq.append([round(p, 3), on])
                    last = on
            if seq:
                cues[lane['id']] = seq
        sections.append({'title': sec['title'], 'cues': cues})
    return lanes, sections


for n, s in SETS.items():
    path = os.path.join(OUT, NAMES[n] + '.json')
    if os.path.exists(path) and not FORCE:
        print('kept', path)
        continue
    assert len(s['tracks']) <= 32, (n, len(s['tracks']))
    ids = {tr['id'] for tr in s['tracks']}
    for sec in s['sections']:
        assert set(sec['rules']) <= ids, (n, set(sec['rules']) - ids)
    lanes, sections = to_lanes(s)
    body = {'title': s['title'], 'bpm': s.get('bpm', 160), 'use_in_game': s.get('use', False), 'quantize_beats': 4,
            'lanes': lanes, 'sections': sections}
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(body, f, indent=1, ensure_ascii=False)
    print('wrote', path, len(lanes), 'lanes,', sum(len(l['clips']) for l in lanes), 'clips,', len(sections), 'sections')
