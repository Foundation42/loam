"""Extract OBS-3 histories from a G50 stderr log into portable CSV files.

Usage: python3 tools/obs3_report.py /tmp/marl-g50.log docs/data/obs3
No analysis dependency or test rerun required.
"""
import csv
import sys
from pathlib import Path

HEADERS = {
    'HISTORY': 'seed,omega,adaptive,step,k_before,k_after,train_pre,heldout_pre,born,requests,denied,best_gain,coefficient_l1_previous_window,rhs,basis,coefficient_updates_before'.split(','),
    'BIRTH': 'seed,omega,step,candidate,x,y,sigma,coverage_before,local_residual_mse_before,g,h,predicted_gain'.split(','),
    'SPATIAL': ['seed', 'omega', 'adaptive', 'step'] + [f'source_residual_sse_{i}' for i in range(17)] + [f'path_visits_{i}' for i in range(17)],
    'FINAL': 'seed,omega,adaptive,k,late_births,requests,denied,train,heldout,rhs,basis,coefficient_updates,seconds_including_scoring'.split(','),
}

def main():
    source, destination = Path(sys.argv[1]), Path(sys.argv[2])
    rows = {key: [] for key in HEADERS}
    for line in source.read_text().splitlines():
        if not line.startswith('OBS3_') or ',' not in line:
            continue
        tag, *values = next(csv.reader([line]))
        key = tag.removeprefix('OBS3_')
        if key not in HEADERS:
            continue
        if len(values) != len(HEADERS[key]):
            raise ValueError(f'{key}: expected {len(HEADERS[key])} columns, got {len(values)}')
        rows[key].append(values)
    if len(rows['FINAL']) != 12 or len(rows['HISTORY']) != 360 or len(rows['SPATIAL']) != 360:
        raise ValueError('Incomplete G50 sweep; refusing to publish partial results')
    destination.mkdir(parents=True, exist_ok=True)
    for key, values in rows.items():
        with (destination / (key.lower() + '.csv')).open('w', newline='') as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(HEADERS[key])
            writer.writerows(values)
        print(key, len(values))

if __name__ == '__main__':
    main()
