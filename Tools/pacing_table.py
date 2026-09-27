import json, sys, statistics as st
from collections import defaultdict

def load(paths):
    rows = []
    for p in paths:
        for line in open(p):
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows

def med(xs):
    xs = [x for x in xs if x is not None and x >= 0]
    return st.median(xs) if xs else float('nan')

def mean(xs):
    xs = [x for x in xs if x is not None and x >= 0]
    return sum(xs) / len(xs) if xs else float('nan')

def summ(rows, label):
    n = len(rows)
    judges = sum(1 for r in rows if r['outcome'] == 'judges')
    ko = sum(1 for r in rows if r['finish'] in ('ko', 'component_kill'))
    hk = sum(1 for r in rows if r['finish'].startswith('hazard_'))
    ro = sum(1 for r in rows if r['finish'] == 'ring_out')
    pit = sum(1 for r in rows if r['finish'] == 'pit')
    bpm = mean([r['bpm'] for r in rows])
    fh = med([r['first_hit_s'] for r in rows])
    stuck = mean([(r['stuck_s'][0] + r['stuck_s'][1]) / 2 * 60 / max(r['at_s'], 1) for r in rows])
    dist = mean([r['mean_dist'] for r in rows])
    hz = mean([r['haz_contacts'] / max(r['at_s'], 1) * 60 for r in rows])
    hzc = mean([r['haz_credited'] / max(r['at_s'], 1) * 60 for r in rows])
    pay = sum(len(r.get('payoffs', [])) for r in rows)
    dur = mean([r['at_s'] for r in rows])
    stages = [[] for _ in range(5)]
    for r in rows:
        for i, v in enumerate(r['bpm_by_stage']):
            if v >= 0:
                stages[i].append(v)
    sb = ' / '.join('%.1f' % mean(s) for s in stages)
    return ('| %s | %d | %d%% | %d | %d | %d | %d | %.1f | %.2f | %s | %.1f | %.0f%% | %.2f | %.2f | %.2f | %d |'
            % (label, n, round(100 * judges / n), ko, hk, ro, pit, dur, bpm, sb, fh, stuck, dist, hz, hzc, pay))

HEAD = ('| set | fights | to judges | KO/core | hazard KO | ring-out | pit | mean length s | blows/min | blows/min by stage (0-45/45-90/90-120/120-155/155+) | first hit s (median) | stuck (% of fight, per machine) | mean dist m | hazard contacts/min | credited hazard/min | payoffs |\n'
        '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')

if __name__ == '__main__':
    rows = load(sys.argv[1:])
    print(HEAD)
    print(summ(rows, 'all'))
    by = defaultdict(list)
    for r in rows:
        by[r['arena']].append(r)
    for a in ['yard', 'grinder', 'drop_zone', 'furnace', 'crush', 'coliseum']:
        if by[a]:
            print(summ(by[a], a))
    byw = defaultdict(list)
    for r in rows:
        byw[r['weapon']].append(r)
    for w in sorted(byw):
        print(summ(byw[w], w))
