"""Extract a complete G51 log; no test rerun or plotting dependency needed.
Usage: python3 tools/obs4_report.py /tmp/marl-g51.log docs/data/obs4 [diagnostic-log]
"""
import csv
import sys
from pathlib import Path

PREFIX = 'seed,rich,fresh,omega,adaptive'.split(',')
HEADERS = {
    'DIAGNOSTIC': 'seed,keep_updating,checkpoint_train,max_train,max_score,requests,final_eval'.split(','),
    'SENSOR': 'seed,rich,role,window,index,steps,x,y,target_x,target_y'.split(','),
    'REQUEST': 'seed,rich,fresh,omega,window,step,candidate,accepted,prior_candidate_requests,prior_site_requests,repeated_earlier_window,k_before,x,y,sigma,coverage,local_residual_mse,g,h,score'.split(','),
    'HISTORY': PREFIX + 'window,step,k,train_pre,eval_pre,score,requests,denied,repeated_cross_window,coefficient_l1_previous_period,rhs,basis,coefficient_updates_before'.split(','),
    'SPATIAL': PREFIX + ['window', 'step'] + [f'source_residual_sse_{i}' for i in range(17)] + [f'source_count_{i}' for i in range(17)] + [f'path_visits_{i}' for i in range(17)],
    'WINDOW': PREFIX + 'window,k_before,k_after,incoming_rms,train_after,eval_before,eval_after,requests,denied,repeated_cross_window'.split(','),
    'FINAL': PREFIX + 'k,requests,denied,repeated_cross_window,incoming_sse,train,eval,rhs,basis,coefficient_updates,seconds_including_scoring'.split(','),
}

def main():
    rows = {key: [] for key in HEADERS}
    sources = [Path(sys.argv[1])] + [Path(p) for p in sys.argv[3:]]
    lines = [line for source in sources for line in source.read_text().splitlines()]
    for line in lines:
        if not line.startswith('OBS4_') or ',' not in line:
            continue
        tag, *values = next(csv.reader([line]))
        key = tag.removeprefix('OBS4_')
        if key not in HEADERS:
            continue
        if len(values) != len(HEADERS[key]):
            raise ValueError(f'{key}: expected {len(HEADERS[key])} columns, got {len(values)}')
        rows[key].append(values)
    for key, count in {'FINAL': 48, 'WINDOW': 144, 'HISTORY': 1440, 'SPATIAL': 1440, 'SENSOR': 960}.items():
        if len(rows[key]) != count:
            raise ValueError(f'Incomplete G51 sweep: {key} expected {count}, got {len(rows[key])}')
    if len(sources) > 1 and len(rows['DIAGNOSTIC']) != 6:
        raise ValueError('Incomplete G51 diagnostic')
    destination = Path(sys.argv[2])
    destination.mkdir(parents=True, exist_ok=True)
    for key, values in rows.items():
        with (destination / (key.lower() + '.csv')).open('w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(HEADERS[key])
            writer.writerows(values)
        print(key, len(values))

if __name__ == '__main__':
    main()
