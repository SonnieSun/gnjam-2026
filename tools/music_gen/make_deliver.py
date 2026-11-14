"""Copies the finished audio into deliver/, sorted for whoever builds the music system:

  deliver/scene1/<group>/     scene 1 loops, one folder per group (skeleton, styles, cats, ...)
  deliver/classics/<song>/    each classic's stems
  deliver/meows/              the chosen meows + the 21-note meow kit
  deliver/sfx/                one-shots (made by make_sfx.py and make_hit_meows.py)
  deliver/previews/           30 s listening references (not game assets)

usage: python -I make_deliver.py <loops dir> <deliver dir>
"""
import glob
import os
import shutil
import sys

L, D = sys.argv[1], sys.argv[2]
S1 = os.path.join(L, 's1_disc')
GROUPS = {
    'skeleton': ['L1_groove', 'L2_bass'],
    'style_eurobeat': ['A_L0_keys', 'A_L3_hook', 'A_L4_peak'],
    'style_disco': ['B_L0_keys', 'B_L3_hook', 'B_L4_peak'],
    'style_futurebass': ['fb_L0_keys', 'fb_L3_hook', 'fb_L4_peak'],
    'style_chip': ['chip_L0_keys', 'chip_L3_hook', 'chip_L4_peak'],
    'style_jazz': ['J_L0_piano', 'J_L1_groove', 'J_L2_bass', 'J_L3_sax', 'J_L4_shout'],
    'cat_band': ['C_drums', 'C_stabs', 'C_lead', 'C_lead_flow', 'C_lead_kichiku', 'C_bass'],
    'events': ['X_meow', 'X_seal', 'X_vox'],
    'rhythm_variants': ['Rhalf_L1_groove', 'Rhalf_L2_bass', 'Rbreak_L1_groove', 'Rbreak_L2_bass', 'Rclub_L1_groove', 'Rclub_L2_bass'],
    'entertainer_leads': ['ent_fb_L3_lead', 'ent_cat_L3_lead', 'ent_A_L3_lead'],
}
n = 0
for group, names in GROUPS.items():
    os.makedirs(os.path.join(D, 'scene1', group), exist_ok=True)
    for name in names:
        src = glob.glob(os.path.join(S1, f's1_disc_{name}_[0-9]*b.wav'))
        assert len(src) == 1, name
        shutil.copy(src[0], os.path.join(D, 'scene1', group, os.path.basename(src[0]).replace('s1_disc_', 's1_')))
        n += 1
for song in ('can_can', 'turkish_march', 'ode_to_joy', 'mountain_king', 'fur_elise'):
    os.makedirs(os.path.join(D, 'classics', song), exist_ok=True)
    for f in glob.glob(os.path.join(L, 'classics', f'{song}_*b.wav')):
        if 'preview' not in f:
            shutil.copy(f, os.path.join(D, 'classics', song, os.path.basename(f)))
            n += 1
os.makedirs(os.path.join(D, 'meows', 'note_kit'), exist_ok=True)
for f in glob.glob(os.path.join(L, 'meow_kit_kichiku', 'miao_*_[0-9][0-9].wav')):
    shutil.copy(f, os.path.join(D, 'meows', os.path.basename(f)))
    n += 1
for f in glob.glob(os.path.join(L, 'meow_kit', '*')):
    shutil.copy(f, os.path.join(D, 'meows', 'note_kit', os.path.basename(f)))
    n += 1
os.makedirs(os.path.join(D, 'previews'), exist_ok=True)
for f in (glob.glob(os.path.join(S1, '*preview_*')) + glob.glob(os.path.join(L, 'classics', '*preview*'))):
    keep = any(k in f for k in ('_fb_20b', 'catness', 'styletour', 'rhythm_', 'jazz', 'ent_', '_A_20b', 'chip', 'classics'))
    if keep:
        shutil.copy(f, os.path.join(D, 'previews', os.path.basename(f)))
        n += 1
print(n, 'files ->', D)
