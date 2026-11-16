"""Writes the starting music set of every level to levels/music/level_<n>.json (the file the Music
autoload plays and the Music Director panel edits). Run once; after that edit in the panel.

A set is a few tracks ("lanes": rhythm, bass, chords, melody, ...), each holding clips (looping WAVs,
all started together); only one clip of a lane sounds at a time. Per section of the level, each lane
has cues: at this gauge progress (0 = section just started, 1 = gauge full) switch to this clip
("" = silence). The clip of the last cue at or below the current progress is the one that sounds.

  {"title", "bpm", "use_in_game", "quantize_beats",
   "lanes":    [{"id", "name", "gain_db", "clips": [{"id", "file", "gain_db" (optional, on top of the lane's)}]}],
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
        t('cat_lead', S1 + 'cat_band/s1_C_lead_flow_4b.wav', 'hook'),      # every meow rings out
        t('cat_bass', S1 + 'cat_band/s1_C_bass_4b.wav', 'bass')]
# KIAI: the kichiku lead in its own lane, so it can sound on top of the cat lead at the very peak
KIAI = [t('cat_kichiku', S1 + 'cat_band/s1_C_lead_kichiku_4b.wav', 'kiai')]
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
# One layer per stage event, the way its own music did it (gauge 615, lines at 20 40 60 80 | 110 170
# 330 530 | 600; they live in scenes/sections/kisa/disco.tscn, keep E below in step with them). The room is the jazz style, like its own swing-jazz room set (stars = piano, ball =
# brass shout, dancers = sax + meow drums, drift = pad); when the house comes apart the beat turns
# into the club groove with future bass, and the cats take over part by part; the UFO brings the meow
# event track. The disco style stems are in the lanes too, to swap in from the panel.
# Then the abduction section is the all-cat band over the half-time beat.
S120 = M + 'scene1_120/s120_'


def t120(id_, key, group):
    return t(id_, f'{S120}{key}_4b.wav', group)


# NOTE: the level has since changed (gauge 470, lines 20 40 60 80 | 110 140 220 320 | 390, and the abduction part
# now plays inside the DISCO section from 396 to 470), and levels/music/level_1_disco.json was re-aligned by hand.
# Regenerating from this script would undo that: update E and fold the ABDUCTION rules in first.
E = [v / 615 for v in (20, 40, 60, 80, 110, 170, 330, 530, 600)]   # disco.tscn: gauge_max_override and gauge_events
SETS[6] = {'title': 'DISCO', 'bpm': 120, 'use': True,
           'tracks': [t120('jazz_groove', 'J_L1_groove', 'groove'), t120('jazz_bass', 'J_L2_bass', 'bass'),
                      t120('jazz_piano', 'J_L0_piano', 'bed'), t120('jazz_sax', 'J_L3_sax', 'hook'), t120('jazz_shout', 'J_L4_shout', 'peak'),
                      t120('groove', 'L1_groove', 'groove'), t120('club', 'Rclub_L1_groove', 'groove'),
                      t120('half', 'Rhalf_L1_groove', 'groove'),
                      t120('bass', 'L2_bass', 'bass'), t120('club_bass', 'Rclub_L2_bass', 'bass'), t120('cat_bass', 'C_bass', 'bass'),
                      t120('disco_keys', 'B_L0_keys', 'bed'), t120('fb_keys', 'fb_L0_keys', 'bed'), t120('cat_stabs', 'C_stabs', 'bed'),
                      t120('disco_hook', 'B_L3_hook', 'hook'), t120('fb_hook', 'fb_L3_hook', 'hook'),
                      t120('cat_flow', 'C_lead_flow', 'hook'), t120('cat_kichiku', 'C_lead_kichiku', 'kiai'),
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
                   # the cat lead is the 'flow' one (every meow rings out). KIAI: for the finale only (the
                   # UFO, the last 5%), the kichiku lead comes in on top of it.
                   'cat_flow': [[E[3], E[4]], [E[5], 1]], 'fb_hook': [[E[4], E[5]]],              # 4 drift and 6 dance floor: cats sing
                   'cat_kichiku': [[E[8], 1]],                                                    # 9 UFO: kiai
                   'ev_meow': [[E[8], 1]]}},                                                      # 9 UFO
               {'title': 'ABDUCTION', 'rules': {
                   'half': [[0, 1]], 'bass': [[0, 1]], 'fb_keys': [[0, 1]], 'cat_drums': [[0, 1]],
                   'cat_flow': [[1 / 3, 1]], 'cat_kichiku': [[0.85, 1]], 'ev_seal': [[2 / 3, 1]]}}]}
# levels 7-9 at 160 with three different songs, to try the new music on them
SETS[7] = {'title': 'SPACESHIP', 'use': True, 'tracks': SKELETON + style('euro', 'style_eurobeat', 'A') + CATS[:1] + CATS[2:3] + KIAI + EVENTS[:1],
           'sections': [{'title': 'SPACESHIP', 'rules': stack('euro', {
               'euro_hook': [[0.25, 0.5]], 'cat_drums': [[0.25, 1]], 'cat_lead': [[0.5, 1]], 'cat_kichiku': [[0.9, 1]], 'bass': [[0.15, 1]], 'ev_meow': [[0.9, 1]]})}]}
MK = M + 'classics/mountain_king/mountain_king_'
SETS[8] = {'title': 'ABDUCTION', 'use': True,
           'tracks': [SKELETON[0], t('mk_keys', MK + 'fb_L0_keys_8b.wav', 'bed'), t('mk_bass', MK + 'L2_bass_8b.wav', 'bass'),
                      t('mk_pluck', MK + 'L3_pluck_8b.wav', 'hook'), t('mk_kichiku', MK + 'L3_cat_kichiku_8b.wav', 'kiai'),
                      t('mk_cat_flow', MK + 'L3_cat_flow_8b.wav', 'hook'), t('mk_peak', MK + 'fb_L4_peak_8b.wav', 'peak'),
                      t('mk_cat_drums', MK + 'C_drums_8b.wav', 'cat')],
           'sections': [{'title': 'ABDUCTION', 'rules': {
               'groove': [[0, 1]], 'mk_keys': [[0, 1]], 'mk_bass': [[0.15, 1]], 'mk_pluck': [[0.15, 1 / 3]], 'mk_cat_drums': [[0.15, 1]],
               'mk_cat_flow': [[1 / 3, 1]], 'mk_kichiku': [[0.9, 1]], 'mk_peak': [[0.8, 1]]}}]}
SETS[9] = {'title': 'TV WALL', 'use': True, 'tracks': SKELETON + style('chip', 'style_chip', 'chip') + CATS[:1] + CATS[2:3] + KIAI,
           'sections': [{'title': 'TV WALL', 'rules': stack('chip', {
               'chip_hook': [[0.25, 0.5]], 'cat_drums': [[0.25, 1]], 'cat_lead': [[0.5, 1]], 'cat_kichiku': [[0.9, 1]], 'bass': [[0.15, 1]]})}]}

# --- the five tiers ---------------------------------------------------------------------------------
# Every song goes through the same five tiers as the gauge fills (the lines are TIERS):
#   1 weak        drums, bass, chords
#   2 weak meow   + the tune on an instrument; the cats only answer the player: with a 'hit' pattern the
#                 player's hits sing the tune one note per hit (a meow pattern played "by_hit")
#   3 strong      + the peak layer and the meow drums
#   4 all cats    the cats take the tune (the cat lead), the chords and the bass
#   5 kichiku     the kichiku lead on top of the cat lead (the KIAI lane)
# A song that is kichiku by nature (native=True) lets the kichiku lead take the tune from tier 2 on and
# adds the cat lead on top at tier 5 instead.
TIERS = (0.2, 0.45, 0.7, 0.9)
# Going up into these tiers (1 = past the first line) takes a transition bar first: one bar of the fill
# with the beat, bass and chords still under it (only the tune steps out), then the new tier comes in on the next bar line. 3 = when the cats take over.
TRANSITION_TIERS = (3,)
# FEVER is placed by hand per section ("fever": [from, to] in gauge progress): in the template it is the top
# tier; a level made by hand puts it where its big moment is (the disco level: on the plaza).
FEVER = (TIERS[3], 1.0)
# the transition fill (make_fill.py): its lane is never cued, the music manager switches it on for a bar
FILL = [t('fill', S1 + 'events/s1_X_fill_4b.wav', 'fill')]


def pattern(id_, name, group, by_hit=False):
    """A meow pattern (levels/music/patterns/<name>.json) as a clip: played at run time, not a WAV."""
    return {'id': id_, 'pattern': f'res://levels/music/patterns/{name}.json', 'group': group, 'by_hit': by_hit}


def harm(id_, tune):
    """The cats' backing vocals for a tune (a run-time pattern, make_harmony_patterns.py): short off-beat chord
    notes under the cat lead. Cue it where the cats have the tune."""
    return pattern(id_, 'harm_' + tune, 'harm')


def five_tiers(c, native=False):
    """c: clip ids by role (groove bass keys hook peak cat_drums cat_lead cat_stabs cat_bass kichiku, and
    optionally hit = a by_hit pattern clip). Returns the on/off ranges of one section."""
    t1, t2, t3, t4 = TIERS
    r = {c['groove']: [[0, 1]], c['bass']: [[0, t3]], c['keys']: [[0, t3]],
         c['hook']: [[t1, t3]], c['peak']: [[t2, 1]], c['cat_drums']: [[t2, 1]],
         c['cat_lead']: [[t3, 1]], c['cat_stabs']: [[t3, 1]], c['cat_bass']: [[t3, 1]], c['kichiku']: [[t4, 1]]}
    if native:
        r[c['hook']] = []
        r[c['kichiku']] = [[t1, 1]]
        r[c['cat_lead']] = [[t4, 1]]
    if c.get('hit'):
        r[c['hit']] = [[t1, t3]]
    return {k: v for k, v in r.items() if v}


def scene1_song(title, key, folder, prefix):
    """A level on one scene 1 style, five tiers; the player's hits sing the scene 1 riff in tier 2."""
    roles = {'groove': 'groove', 'bass': 'bass', 'keys': f'{key}_keys', 'hook': f'{key}_hook', 'peak': f'{key}_peak',
             'cat_drums': 'cat_drums', 'cat_lead': 'cat_lead', 'cat_stabs': 'cat_stabs', 'cat_bass': 'cat_bass',
             'kichiku': 'cat_kichiku', 'hit': 'hit_riff'}
    return {'title': title, 'use': True,
            'tracks': SKELETON + style(key, folder, prefix) + CATS + KIAI + FILL + [pattern('hit_riff', 'kichiku_riff', 'hit', by_hit=True)],
            'sections': [{'title': title, 'rules': five_tiers(roles), 'tiers': TIERS, 'transition_tiers': TRANSITION_TIERS,
                          'fever': FEVER}]}


SETS[7] = scene1_song('SPACESHIP', 'euro', 'style_eurobeat', 'A')
RV = S1 + 'rhythm_variants/s1_'
# --- level 2, TV WALL: one tune per scene (all 160 BPM, all existing loops) ---------------------------------
#   WASHER (the washing machine)   Your Best Friend, one loop from start to finish. It starts innocent
#       (half-time beat, chords; the player's taps sing the tune) and fills up as the machine powers the TVs.
#       This part's gauge never fills: the section script feeds Music its own progress (holds done / holds needed).
#   SLAP (the earth, three parts)  In the Hall of the Mountain King, all three parts: sneaking, louder, everything.
#       The mashing sings its tune (runtime kichiku, in the section script).
#       The last part (POWER) is its climax: break beat, the instrument doubling the cats, the square lead in fever.
# RULE (2026-11-16): a level may change tune, but never with the generic fill: every change of tune has its own
# written one-bar transition ('enter': a variation on the tune that is leaving, walking into the new key;
# tools/music_gen/make_transitions.py). Without one, Mountain King -> Can-Can in the middle of the earth sounded
# like a mistake. A tune's layers are not swapped for another song's (or its own B section) one lane at a time.
# 'own' tells the music manager which kichiku / hit clip belongs to each part (mini kiai, fever).
YB = M + 'classics/your_best_friend/your_best_friend_'
W = (0.12, 0.3, 0.5, 0.7, 0.88)       # the washer's lines, in "holds done" (3 zoom holds, then the TVs)
SETS[9] = {'title': 'TV WALL', 'use': True,
           'tracks': [t('half', RV + 'Rhalf_L1_groove_4b.wav', 'groove'), SKELETON[0],
                      t('ybf_keys', YB + 'fb_L0_keys_8b.wav', 'bed'), t('mk_keys', MK + 'fb_L0_keys_8b.wav', 'bed'),
                      t('break', RV + 'Rbreak_L1_groove_4b.wav', 'groove'),
                      t('mk_double', MK + 'L3_pluck_8b.wav', 'kiai'), t('mk_square', MK + 'L3_square_8b.wav', 'event'),
                      t('ybf_bass', YB + 'L2_bass_8b.wav', 'bass'), t('mk_bass', MK + 'L2_bass_8b.wav', 'bass'),
                      t('ybf_pluck', YB + 'L3_pluck_8b.wav', 'hook'), t('ybf_cats', YB + 'L3_cat_kichiku_8b.wav', 'hook'),
                      t('mk_cats', MK + 'L3_cat_kichiku_8b.wav', 'hook'),
                      t('mka_keys', MK + 'fb_L0_keys_4b.wav', 'bed'), t('mka_bass', MK + 'L2_bass_4b.wav', 'bass'),
                      t('mka_pluck', MK + 'L3_pluck_4b.wav', 'hook'), t('mka_cats', MK + 'L3_cat_kichiku_4b.wav', 'hook'),
                      t('mka_cat_drums', MK + 'C_drums_4b.wav', 'cat'),
                      t('ybf_peak', YB + 'fb_L4_peak_8b.wav', 'peak'), t('mk_peak', MK + 'fb_L4_peak_8b.wav', 'peak'),
                      t('ybf_cat_drums', YB + 'C_drums_8b.wav', 'cat'), t('mk_cat_drums', MK + 'C_drums_8b.wav', 'cat'),
                      t('ybf_double', YB + 'L3_pluck_8b.wav', 'kiai'),
                      pattern('ybf_by_hit', 'your_best_friend', 'hit', by_hit=True),
                      harm('ybf_harm', 'your_best_friend'), harm('mk_harm', 'mountain_king')] + FILL,
           'sections': [
               {'title': 'TV WALL', 'tiers': W, 'transition_tiers': (), 'fever': (W[4], 1.0), 'fever_fill': False,
                'own': {'kiai': '', 'hit': 'ybf_by_hit'}, 'rules': {
                   'half': [[0, W[1]]], 'groove': [[W[1], 1]],
                   'ybf_keys': [[0, 1]], 'ybf_bass': [[W[0], 1]],
                   'ybf_by_hit': [[0, W[1]]], 'ybf_pluck': [[0, W[2]]], 'ybf_cats': [[W[2], 1]], 'ybf_harm': [[W[2], 1]],
                   'ybf_peak': [[W[3], 1]], 'ybf_cat_drums': [[W[1], 1]], 'ybf_double': [[W[4], 1]]}},
               # The washer ends on its high point and the earth is a high point too, so the earth does not start
               # over from a bare beat: after the written transition bar the new tune comes in already singing
               # (cats, drums, bass, chords), and only the extras are left to build (backing vocals, peak layer).
               # The earth's three parts are three steps of one idea:
               #   WARM UP  the theme only (the first half of the tune, a 4-bar loop: 'mka'), with the full rhythm section
               #            from the first bar; the instrument plays it, then (half way) the cats take it
               #   CHARGE   the whole tune, theme + its answer on the dominant (the 8-bar loop: 'mk'), the cats strong,
               #            backing vocals, then the peak layer
               #   POWER    Can-Can
               # 'mka' and 'mk' are two tune groups, so the whole tune starts from its first bar after the fill bar
               # of the section change.
               {'title': 'SLAP / WARM UP', 'tiers': (0.5,), 'transition_tiers': (), 'own': {'kiai': '', 'hit': ''},
                'enter': 'tr_ybf_to_mk', 'rules': {
                   'groove': [[0, 1]], 'mka_keys': [[0, 1]], 'mka_bass': [[0, 1]], 'mka_cat_drums': [[0, 1]],
                   'mka_pluck': [[0, 0.5]], 'mka_cats': [[0.5, 1]]}},
               {'title': 'SLAP / CHARGE', 'tiers': (0.4,), 'transition_tiers': (), 'own': {'kiai': '', 'hit': ''}, 'enter_fill': False, 'carry': 0, 'rules': {
                   'groove': [[0, 1]], 'mk_keys': [[0, 1]], 'mk_bass': [[0, 1]], 'mk_cat_drums': [[0, 1]],
                   'mk_cats': [[0, 1]], 'mk_harm': [[0, 1]], 'mk_peak': [[0.4, 1]]}},
               # POWER: the Mountain King's own climax (Can-Can is kept for the end of the game): the same tune goes on
               # without a break, the drums turn into the 2-step 'break' beat, the instrument doubles the cats, and in
               # fever the square lead joins.
               {'title': 'SLAP / POWER', 'tiers': (0.35, 0.7), 'transition_tiers': (), 'fever': (0.7, 1.0), 'fever_fill': False,
                'enter_fill': False, 'carry': 0, 'own': {'kiai': 'mk_double', 'hit': ''}, 'rules': {   # carry 0: these parts start full
                   # already; carried fullness would switch the extra layers on, off and on again

                   'break': [[0, 1]], 'mk_keys': [[0, 1]], 'mk_bass': [[0, 1]], 'mk_cat_drums': [[0, 1]],
                   'mk_cats': [[0, 1]], 'mk_harm': [[0, 1]], 'mk_peak': [[0, 1]],
                   'mk_double': [[0.35, 1]], 'mk_square': [[0.7, 1]]}}]}

# --- the sky level (the UFO / abduction level, to become level 2) -----------------------------------
# The cat is pulled up by the beam: through the clouds, into a storm with doom horns, then it suddenly
# turns bright and holy and the Ode to Joy starts; in space the cats take the tune over and it ends in
# FEVER on the way into the UFO. The dark half is in C minor, the light is C major (the Ode stems).
# Lines in gauge progress (one section for now; when the level is built its stages get the real lines):
#   start  CLOUDS   half-time beat, the low C drone, wind with clouds rushing past. Every hit sings one
#                   note of a rising scale
#   SKY[0] STORM    cute death metal: the beat turns into double-kick drums (a kitten on the off-beats), a
#                   galloping distorted riff comes in, and the doom horns with thunder over it
#   SKY[1] LIGHT    everything dark stops on the bar line: the 'holy hit', then the holy pad, the Ode's
#                   chords and bass on the normal beat; now every hit sings the next note of the Ode to Joy
#   SKY[2] SPACE    the tune plays by itself: the cats sing it, with meow drums
#   SKY[3] FEVER    (into the UFO) transition bar, then the peak layer and the kichiku lead on top
SKY = (0.25, 0.5, 0.7, 0.85)
SK = M + 'sky/sky_'
OJ = M + 'classics/ode_to_joy/ode_to_joy_'
SETS[10] = {'title': 'SKY', 'use': True,
            'tracks': [t('half', RV + 'Rhalf_L1_groove_4b.wav', 'groove'), t('blast', SK + 'blast_drums_8b.wav', 'groove'), SKELETON[0],
                       t('drone', SK + 'drone_8b.wav', 'bass'), t('metal', SK + 'metal_riff_8b.wav', 'bed'), t('ode_bass', OJ + 'L2_bass_16b.wav', 'bass'),
                       t('ode_keys', OJ + 'fb_L0_keys_16b.wav', 'bed'),
                       t('ode_cats', OJ + 'L3_cat_flow_16b.wav', 'hook'), harm('ode_harm', 'ode_to_joy'),
                       t('doom_horns', SK + 'doom_horns_8b.wav', 'peak'), t('holy_pad', SK + 'holy_pad_8b.wav', 'peak'),
                       t('ode_cat_drums', OJ + 'C_drums_16b.wav', 'cat'), t('ode_kichiku', OJ + 'L3_cat_kichiku_16b.wav', 'kiai'),
                       pattern('ufo_rise', 'ufo_rise', 'hit', by_hit=True),
                       t('wind', SK + 'wind_8b.wav', 'event'), t('ode_peak', OJ + 'fb_L4_peak_16b.wav', 'event')] + FILL,
            'sections': [{'title': 'SKY', 'exit': 'end_c_major', 'outro': 'out_into_the_ufo', 'fever_fill': False, 'own': {'hit': ''}, 'tiers': SKY, 'fever': (SKY[3], 1.0), 'tier_sfx': {1: 'none', 2: 'sky_holy_hit'}, 'rules': {
                'half': [[0, SKY[0]]], 'blast': [[SKY[0], SKY[1]]], 'groove': [[SKY[1], 1]],
                'metal': [[SKY[0], SKY[1]]],
                'drone': [[0, SKY[1]]], 'ode_bass': [[SKY[1], 1]],
                'ode_keys': [[SKY[1], 1]],
                'ode_cats': [[SKY[1], 1]], 'ode_harm': [[SKY[2], 1]],
                'doom_horns': [[SKY[0], SKY[1]]], 'holy_pad': [[SKY[1], SKY[3]]],
                'ode_cat_drums': [[SKY[2], 1]],
                'ufo_rise': [[0, SKY[1]]],
                'wind': [[0, SKY[2]]], 'ode_peak': [[SKY[3], 1]]}}]}

# file = the level file it goes with (levels/<name>.tres -> levels/music/<name>.json). The level list was
# reordered several times; now the menu has 1 DISCO (set 6), 2 TV WALL (set 9: its sections are edited by
# hand, so it is kept and not regenerated) and 3 SPACESHIP (set 7). A name starting with '../' is written
# relative to levels/music: PIZZA (set 5) is parked in levels/alternates/. The sky level (set 10) is an
# interlude: levels/interludes/after_level_1_disco.tres, played after level 1 in a run, not on the menu.
# --- level 3, SPACESHIP: the last level. The shooter has its own tune; the pizza is Can-Can ----------
#   SPACESHIP (shooting planets)   Turkish March, the one tune not heard yet: fast, a chase. Five tiers as usual.
#   SPACE PIZZA (the last part of the game): all Can-Can, see the comment on the section below.
#   The lines 50% / 75% are the stage's camera cues (level_3_spaceship.tres: fx_cues grid3 0.5, kaleido 0.75).
TM = M + 'classics/turkish_march/turkish_march_'
CCA = M + 'classics/can_can_a/can_can_a_'             # Can-Can's opening strain (D major), the first half of the pizza
CCB = M + 'classics/can_can_b/can_can_b_'             # Can-Can's second strain, "the four steps down" (D major)
TMB = M + 'classics/turkish_march_b/turkish_march_b_'   # its second section (A major), the fever of the shooter
OJ = M + 'classics/ode_to_joy/ode_to_joy_'
T3 = TIERS
R = (0.25, 0.5, 0.625, 0.75)
SETS[7] = {'title': 'SPACESHIP', 'use': True,
           'tracks': [t('half', RV + 'Rhalf_L1_groove_4b.wav', 'groove'), SKELETON[0],
                      t('tm_keys', TM + 'fb_L0_keys_16b.wav', 'bed'), t('cc_keys', CC + 'fb_L0_keys_8b.wav', 'bed'),
                      t('tm_bass', TM + 'L2_bass_16b.wav', 'bass'), t('cc_bass', CC + 'L2_bass_8b.wav', 'bass'),
                      t('tm_pluck', TM + 'L3_pluck_16b.wav', 'hook'),
                      t('cc_lead', CC + 'L3_cat_kichiku_8b.wav', 'hook'), t('cc_square', CC + 'L3_square_dark_8b.wav', 'event', -3.0),   # dark and down: the cats stay on top
                      t('cca_keys', CCA + 'fb_L0_keys_8b.wav', 'bed'), t('cca_bass', CCA + 'L2_bass_8b.wav', 'bass'),
                      t('cca_square', CCA + 'L3_square_8b.wav', 'hook'), t('cca_cats', CCA + 'L3_cat_kichiku_8b.wav', 'hook'),
                      harm('cca_harm', 'can_can_a'),
                      t('ccb_keys', CCB + 'fb_L0_keys_8b.wav', 'bed'), t('ccb_bass', CCB + 'L2_bass_8b.wav', 'bass'),
                      t('ccb_cats', CCB + 'L3_cat_kichiku_8b.wav', 'hook'), t('ccb_square', CCB + 'L3_square_8b.wav', 'event', -5.0),
                      t('ccb_choir', CCB + 'C_choir_8b.wav', 'harm', 6.0), t('ccb_peak', CCB + 'fb_L4_peak_8b.wav', 'peak'),
                      harm('tm_harm', 'turkish_march'), harm('cc_harm', 'can_can'),
                      t('tmb_peak', TMB + 'fb_L4_peak_8b.wav', 'peak'), t('cc_peak', CC + 'fb_L4_peak_8b.wav', 'peak'),
                      CATS[0], t('cc_cat_drums', CC + 'C_drums_8b.wav', 'cat'),
                      t('tm_kichiku', TM + 'L3_cat_kichiku_16b.wav', 'kiai'), t('tmb_kichiku', TMB + 'L3_cat_kichiku_8b.wav', 'kiai'),
                      t('tmb_keys', TMB + 'fb_L0_keys_8b.wav', 'bed'), t('tmb_bass', TMB + 'L2_bass_8b.wav', 'bass'),
                      harm('tmb_harm', 'turkish_march_b'),
                      t('cc_double', CC + 'L3_pluck_8b.wav', 'kiai')] + FILL,
           'sections': [
               {'title': 'SPACESHIP', 'tiers': T3, 'transition_tiers': (), 'fever': (T3[3], 1.0), 'fever_fill': False, 'fever_on_bars': 4,
                'own': {'kiai': 'tm_kichiku', 'hit': ''}, 'rules': {
                   'half': [[0, T3[0]]], 'groove': [[T3[0], 1]], 'cat_drums': [[T3[1], 1]],
                   'tm_keys': [[0, T3[3]]], 'tm_bass': [[T3[0], T3[3]]],
                   'tm_pluck': [[0, T3[3]]], 'tm_kichiku': [[T3[2], T3[3]]], 'tm_harm': [[T3[2], T3[3]]],
                   # FEVER: the march's second section, the loud A major tune, all of it at once, on a 4-bar line of
                   # the first section (no fill bar: the tune must not stop in the middle of a scene)
                   'tmb_keys': [[T3[3], 1]], 'tmb_bass': [[T3[3], 1]], 'tmb_kichiku': [[T3[3], 1]],
                   'tmb_harm': [[T3[3], 1]], 'tmb_peak': [[T3[3], 1]]}},
               # The pizza is all Can-Can, in the order the galop itself goes:
               #   the transition bar   the vamp on the dominant that leads into the galop (tr_tm_to_cc)
               #   0      the opening strain ('cca', D major): the instrument plays it with drums, bass, chords
               #   25%    the cats take it, backing vocals
               #   50%    THE FOUR STEPS DOWN ('ccb', still D major), the strain that comes right before the famous
               #          tune in the galop, on the opening strain's 8-bar line: the cats sing it, the square
               #          lead 5 dB under them                                              <- the 3x3 grid camera
               #   62%    + THE CAT CHOIR (held meows on the chords and a third below on the long notes:
               #          make_choir_stems.py; the choir is only here, on the fast famous tune it is clutter)
               #          and the peak layer
               #   75%    FEVER: THE FAMOUS TUNE ('cc', G major: D -> G is a V -> I), heard here for the first time
               #          and kept for the climax, with everything (cats, the square lead without its top and
               #          3 dB down so it does not cover them, pluck doubling, Can-Can's own cat drums), on the
               #          descent's 8-bar line. The last bar of that phrase is swapped for tr_ccb_to_cc: the same
               #          band (cut from the descent's own stems), the run climbing on to a hammered high D,
               #          and an urgent drum fill. In fever the whole mix goes into a
               #          hall ('fever_reverb')                                             <- the kaleidoscope
               # Every change is a strain of the same galop in the galop's own order, on a phrase line, full band on
               # both sides: the tune never stops.
               {'title': 'SPACE PIZZA', 'tiers': R, 'transition_tiers': (), 'fever': (R[3], 1.0), 'fever_enter': 'tr_ccb_to_cc', 'fever_enter_db': 10.0, 'fever_reverb': 0.2,
                'carry': 0,   # must start on the opening strain: carried fullness would jump straight to the famous tune
                'tier_on_bars': {2: 8}, 'fever_on_bars': 8, 'own': {'kiai': '', 'hit': ''}, 'enter': 'tr_tm_to_cc',   # no mini kiai: it would be the other strain's tune
                'exit': 'end_g_major', 'rules': {
                   'groove': [[0, 1]], 'cat_drums': [[0, R[3]]], 'cc_cat_drums': [[R[3], 1]],
                   'cca_keys': [[0, R[1]]], 'cca_bass': [[0, R[1]]], 'cca_square': [[0, R[0]]], 'cca_cats': [[R[0], R[1]]],
                   'cca_harm': [[R[0], R[1]]],
                   'ccb_keys': [[R[1], R[3]]], 'ccb_bass': [[R[1], R[3]]], 'ccb_cats': [[R[1], R[3]]], 'ccb_square': [[R[1], R[3]]],
                   'ccb_choir': [[R[2], R[3]]], 'ccb_peak': [[R[2], R[3]]],
                   'cc_keys': [[R[3], 1]], 'cc_bass': [[R[3], 1]], 'cc_lead': [[R[3], 1]], 'cc_harm': [[R[3], 1]], 'cc_peak': [[R[3], 1]],
                   'cc_square': [[R[3], 1]], 'cc_double': [[R[3], 1]]}}]}
NAMES = {6: 'level_1_disco', 9: 'level_2_tv_wall', 7: 'level_3_spaceship',
         10: 'after_level_1_disco', 5: '../alternates/pizza_cat_level_5_music'}
LANES = [('beat', '节奏', 'groove'), ('bass', '低音', 'bass'), ('bed', '和声', 'bed'), ('lead', '旋律', 'hook'),
         ('peak', '高潮', 'peak'), ('meow', '猫鼓', 'cat'), ('harm', '猫和声', 'harm'), ('kiai', 'KIAI 鬼畜', 'kiai'), ('hit', '打中唱', 'hit'),
         ('fx', '事件', 'event'), ('fill', '过门', 'fill')]
# Clips whose id starts with one of these belong to that tune ("tune" in the level file): the music manager
# plays a tune's clips from their own player and starts the tune FROM ITS FIRST BAR on the bar line it comes
# in on (in one shared stream every clip would join wherever the loop happened to be, e.g. from bar 2).
# RULES FOR A STAGE CHANGE INSIDE A SCENE (2026-11-16, after playtesting). A scene = what the player sees as one
# place; a change of scene has its own written transition ('enter') or the cut-scene's fill.
#   1. The tune is there from the first bar of a scene: a lead (instrument or cats) is cued from progress 0
#      wherever a tune starts. Building up means adding things UNDER and AROUND the tune, not waiting for it.
#   2. Once the tune is playing it never stops inside the scene: no cue takes the lead away, no fill bar
#      ('transition_tiers' empty, 'fever_fill': False, 'enter_fill': False between parts of one scene).
#   3. The lead may change hands (instrument -> cats, cats -> kichiku): it is handed over, never dropped.
#   4. A stage that takes things away (a quiet ending) drops chords, drums or the peak layer and keeps the tune.
# tools/music_gen/check_music_sets.py prints every stage of every level and flags a tune that stops.
TUNES = ('ybf', 'mk', 'mka', 'cc', 'cca', 'ccb', 'tm', 'tmb', 'ode', 'ent')
LANE_GAIN = {'kiai': -2.0, 'harm': -5.0}   # kiai: stacked on the cat lead, so a little under it; harm: the backing vocals, well under the lead



def to_lanes(s):
    lanes, cues_of = [], []
    for lane_id, name, group in LANES:
        clips = [({'id': tr['id'], 'pattern': tr['pattern'], 'by_hit': tr['by_hit']} if 'pattern' in tr
                  else {'id': tr['id'], 'file': tr['file'], **({'gain_db': tr['gain_db']} if tr.get('gain_db') else {})})
                 for tr in s['tracks'] if tr['group'] == group]
        for c in clips:                                   # the tune a clip belongs to, from its id (see TUNES)
            if c['id'].split('_')[0] in TUNES:
                c['tune'] = c['id'].split('_')[0]
        if clips:
            lanes.append({'id': lane_id, 'name': name, 'gain_db': LANE_GAIN.get(lane_id, 0.0), 'clips': clips})
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
        out = {'title': sec['title'], 'cues': cues}
        if 'tiers' in sec:
            out['tiers'] = list(sec['tiers'])          # the tier lines (else every cue position is one)
        if 'transition_tiers' in sec:
            out['transition_tiers'] = list(sec['transition_tiers'])
        if 'fever' in sec:
            out['fever'] = list(sec['fever'])
        for k in ('exit', 'outro', 'fever_enter', 'fever_enter_db', 'fever_reverb', 'carry', 'fever_on_bars', 'fever_fill', 'enter_fill'):
            if k in sec:
                out[k] = sec[k]
        if 'tier_on_bars' in sec:                        # going up into these tiers waits for the tune's phrase line
            out['tier_on_bars'] = {str(k): v for k, v in sec['tier_on_bars'].items()}
        if 'enter' in sec:
            out['enter'] = sec['enter']               # a designed one-bar transition into this section (a new tune)
        if 'own' in sec:
            out['own'] = dict(sec['own'])              # which clip of a lane is this section's own (a medley level)
        if 'tier_sfx' in sec:
            out['tier_sfx'] = {str(k): v for k, v in sec['tier_sfx'].items()}
        sections.append(out)
    return lanes, sections


for n, s in SETS.items():
    if n not in NAMES:
        continue
    path = os.path.join(OUT, NAMES[n] + '.json')
    if os.path.exists(path) and not FORCE:
        print('kept', path)
        continue
    assert len([tr for tr in s['tracks'] if 'file' in tr]) <= 32, (n, len(s['tracks']))
    ids = {tr['id'] for tr in s['tracks']}
    for sec in s['sections']:
        assert set(sec['rules']) <= ids, (n, set(sec['rules']) - ids)
    lanes, sections = to_lanes(s)
    body = {'title': s['title'], 'bpm': s.get('bpm', 160), 'use_in_game': s.get('use', False), 'quantize_beats': 4,
            'lanes': lanes, 'sections': sections}
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(body, f, indent=1, ensure_ascii=False)
    print('wrote', path, len(lanes), 'lanes,', sum(len(l['clips']) for l in lanes), 'clips,', len(sections), 'sections')
