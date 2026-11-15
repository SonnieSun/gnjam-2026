import json, glob, os, re
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))  # the project folder
LEAD = re.compile(r'L3_cat|C_lead|kichiku|L3_pluck|L3_hook|ask_answer|QA_')
CATCH = re.compile(r'C_stabs|C_bass')
for j in sorted(glob.glob('levels/music/*.json')):
    d = json.load(open(j, encoding='utf-8'))
    files = {}
    for lane in d['lanes']:
        for c in lane['clips']:
            files[(lane['id'], c['id'])] = c.get('file', c.get('pattern', ''))
    print('==', os.path.basename(j), d['bpm'], 'BPM')
    for sec in d['sections']:
        cues = sec['cues']
        pts = sorted({0.0} | {p for seq in cues.values() for p, _ in seq})
        fever = sec.get('fever')
        own = sec.get('own', {})
        for i, p in enumerate(pts):
            on = []
            for lane, seq in cues.items():
                cur = ''
                for q, clip in seq:
                    if q <= p + 1e-9:
                        cur = clip
                if cur:
                    on.append((lane, cur))
            in_fever = fever and fever[0] - 1e-9 <= p < fever[1]
            if in_fever:
                k = own.get('kiai', next((c['id'] for l in d['lanes'] if l['id'] == 'kiai' for c in l['clips']), ''))
                if k and ('kiai', k) not in on:
                    on = [x for x in on if x[0] != 'kiai'] + [('kiai', k)]
            leads = [c for l, c in on if LEAD.search(files.get((l, c), '')) or 'patterns/' in files.get((l, c), '')]
            catch = [c for l, c in on if CATCH.search(files.get((l, c), ''))]
            flag = ''
            if len(leads) > 1:
                flag = '   <-- %d tunes at once' % len(leads)
            print('  %-16s %4.0f%%%s  leads: %-28s cat chords/bass: %-18s all: %s%s' % (
                sec['title'][:16] if i == 0 else '', p * 100, ' F' if in_fever else '  ', ' '.join(leads) or '-', ' '.join(catch) or '-',
                ' '.join(c for _, c in on), flag))
