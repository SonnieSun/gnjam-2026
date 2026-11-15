"""Keep unused music out of the exported game.

Lists every loop under assets/audio/music that no active level uses (levels/music/*.json; the parked ones
in levels/alternates do not count) and that no script or scene names, and writes them into the
exclude_filter of export_presets.cfg. The files stay in the project (the jukebox and the Meow Studio
still list them in the editor); they are only left out of the build.

    python tools/music_gen/make_export_excludes.py          (run from anywhere; re-run after changing a level's music)
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
os.chdir(ROOT)
BASE = 'tools/*, docs/*, tests/*, *.md, *.py, *.mjs'

used = set()
for root, dirs, fs in os.walk('.'):
    r = root.replace(os.sep, '/')
    if r.startswith(('./.godot', './tools', './levels/alternates', './docs')):
        continue
    for f in fs:
        if f.endswith(('.gd', '.tscn', '.tres', '.json')):
            try:
                text = open(os.path.join(root, f), encoding='utf-8', errors='ignore').read()
            except OSError:
                continue
            for m in re.findall(r'res://assets/audio/[^"\']+?\.(?:wav|ogg|mp3)', text):
                used.add(m[6:])

unused, kept, size = [], 0, 0
for root, _, fs in os.walk('assets/audio/music'):
    for f in sorted(fs):
        if f.endswith(('.wav', '.ogg', '.mp3')):
            p = os.path.join(root, f).replace(os.sep, '/')
            if p in used:
                kept += 1
            else:
                unused.append(p)
                size += os.path.getsize(p)

cfg = open('export_presets.cfg', encoding='utf-8').read()
new = 'exclude_filter="%s"' % ', '.join([BASE] + unused)
cfg, n = re.subn(r'exclude_filter="[^"]*"', lambda _m: new, cfg, count=1)
assert n == 1
open('export_presets.cfg', 'w', encoding='utf-8', newline='\n').write(cfg)
print('left out of the build: %d music files, %.0f MB; kept %d' % (len(unused), size / 1e6, kept))
