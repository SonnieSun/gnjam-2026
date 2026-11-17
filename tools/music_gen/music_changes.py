"""How the music changes at a section change, a tier and the fever: the one description the music manager reads
(scripts/music/music.gd, change_spec), a section's "changes" in levels/music/<level>.json:

    "changes": {"enter": {...}, "tier": {"5": {...}}, "fever": {...}}
    each: "fill" (a generic fill bar first), "written" (a written transition from assets/audio/sfx instead),
          "db", "bars", "replaces" (of the written one), "on_bars" (wait for the tune's phrase line),
          "sfx" (a tier's own sound when it arrives)

make_music_sets.py still writes its sections in the short keys below (one flat dict per section is easier to
read in that table); to_changes() turns them into the description. Run as a script it converts music files that
still have the short keys in them (the hand-maintained level_1_disco.json was converted this way on 2026-11-16):

    python -I music_changes.py <levels/music/x.json> [...]

    short key in make_music_sets.py     ->  in "changes"
    'enter': 'tr_x'                         enter.written
    'enter_db' / 'enter_bars'               enter.db / bars
    'enter_fill': False                     enter.fill
    'transition_tiers': (5,)                tier.5.fill = true
    'tier_enter': {5: 'tr_x'}               tier.5.written
    'tier_on_bars': {2: 8}                  tier.2.on_bars
    'tier_sfx': {2: 'sky_holy_hit'}         tier.2.sfx
    'tier_lead': {2: 4}                     tier.2.lead_beats
    'fever_fill': False                     fever.fill
    'fever_enter': 'tr_x'                   fever.written
    'fever_enter_db' / '_bars' / '_replaces'    fever.db / bars / replaces
    'fever_on_bars': 4                      fever.on_bars
"""
import io
import json
import sys

SHORT = ('enter', 'enter_db', 'enter_bars', 'enter_fill', 'transition_tiers', 'tier_enter', 'tier_on_bars', 'tier_sfx', 'tier_lead', 'fever_fill', 'fever_enter',
         'fever_enter_db', 'fever_enter_bars', 'fever_enter_replaces', 'fever_on_bars')


def to_changes(sec):
    """Take the short keys out of a section dict and return its "changes" ({} if it has none)."""
    enter, fever, tier = {}, {}, {}

    def t(k):
        return tier.setdefault(str(int(k)), {})

    if sec.get('enter'):
        enter['written'] = sec['enter']
    for short, key in (('enter_db', 'db'), ('enter_bars', 'bars')):
        if short in sec:
            enter[key] = sec[short]
    if 'enter_fill' in sec:
        enter['fill'] = bool(sec['enter_fill'])
    for k in sec.get('transition_tiers', ()):
        t(k)['fill'] = True
    for k, v in sec.get('tier_enter', {}).items():
        t(k)['written'] = v
    for k, v in sec.get('tier_on_bars', {}).items():
        t(k)['on_bars'] = int(v)
    for k, v in sec.get('tier_sfx', {}).items():
        t(k)['sfx'] = v
    for k, v in sec.get('tier_lead', {}).items():
        t(k)['lead_beats'] = v
    if 'fever_fill' in sec:
        fever['fill'] = bool(sec['fever_fill'])
    if sec.get('fever_enter'):
        fever['written'] = sec['fever_enter']
    for short, key in (('fever_enter_db', 'db'), ('fever_enter_bars', 'bars'), ('fever_enter_replaces', 'replaces'), ('fever_on_bars', 'on_bars')):
        if short in sec:
            fever[key] = sec[short]
    for k in SHORT:
        sec.pop(k, None)
    out = {}
    if enter:
        out['enter'] = enter
    if tier:
        out['tier'] = {k: tier[k] for k in sorted(tier, key=int)}
    if fever:
        out['fever'] = fever
    return out


if __name__ == '__main__':
    for path in sys.argv[1:]:
        d = json.loads(io.open(path, encoding='utf-8').read())
        n = 0
        for sec in d.get('sections', []):
            if any(k in sec for k in SHORT):
                assert 'changes' not in sec, (path, sec.get('title'))
                ch = to_changes(sec)
                if ch:
                    sec['changes'] = ch
                n += 1
        io.open(path, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, indent=1, ensure_ascii=False) + '\n')
        print(f'{path}: {n} section(s) converted')
