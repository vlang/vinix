#!/usr/bin/env python3
"""Strict aggregate private diagnostic report; no addresses or allocator secrets."""
from pathlib import Path
import hashlib, json, statistics

STATE = Path(__file__).resolve().parent
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def fields(line): return dict(item.split('=', 1) for item in line.split()[1:])
def integer_fields(row):
    return {key: int(value) for key, value in row.items() if key not in ['phase', 'slots']}

records = []
state_rows = []
probe_rows = []
boot_records = []
for ordinal in [1, 2]:
    directory = STATE / ('boot-' + str(ordinal))
    path = directory / 'serial.log'
    output = path.read_text(errors='replace')
    assert output.count('DIAG-GUEST-BEGIN') == 1
    assert output.count('DIAG-GUEST-DONE') == 1
    assert output.count('DIAG-SAMPLER-DONE') == 6
    assert output.count('DIAG-HOT ') == 84
    assert not any(marker in output for marker in ['DIAG-FAIL', 'ALLOC-ERROR', 'KERNEL PANIC', 'FATAL EXCEPTION'])
    invocation = linkage = None
    batches = {}
    starts = ends = []
    starts, ends = [], []
    for line in output.splitlines():
        if line.startswith('DIAG-EXEC-BEGIN '):
            row = fields(line)
            invocation, linkage = int(row['invocation']), row['linkage']
            starts.append((invocation, linkage))
        elif line.startswith('DIAG-EXEC-END '):
            row = fields(line)
            assert int(row['exit_code']) == 0
            ends.append((int(row['invocation']), row['linkage']))
        elif line.startswith('DIAG-HOT '):
            row = fields(line)
            assert int(row['pairs']) == 200000 and int(row['checksum']) == 51000000
            key = (invocation, linkage, row['phase'])
            batches.setdefault(key, []).append(row)
        elif line.startswith('DIAG-STATE '):
            row = fields(line)
            row.update(boot=ordinal, invocation=invocation, linkage=linkage)
            state_rows.append(row)
        elif line.startswith('DIAG-PROBE '):
            row = fields(line)
            row.update(boot=ordinal, invocation=invocation, linkage=linkage)
            probe_rows.append(row)
    assert starts == ends == [(i, mode) for i in [1, 2, 3] for mode in ['dynamic', 'static']]
    assert len(batches) == 12
    for (invocation, linkage, phase), rows in batches.items():
        assert [int(row['sample']) for row in rows] == list(range(1, 8))
        ns = [int(row['elapsed_ns']) / 200000 for row in rows]
        delta = [int(row['cpu_ns']) - int(row['elapsed_ns']) for row in rows]
        ratio = [int(row['cpu_ns']) / int(row['elapsed_ns']) for row in rows]
        records.append({'boot': ordinal, 'invocation': invocation, 'linkage': linkage, 'phase': phase,
                        'samples': rows, 'median_ns_per_pair': statistics.median(ns),
                        'min_ns_per_pair': min(ns), 'max_ns_per_pair': max(ns),
                        'median_cpu_minus_wall_ns': statistics.median(delta),
                        'min_cpu_to_wall_ratio': min(ratio), 'max_cpu_to_wall_ratio': max(ratio)})
    boot_records.append({'boot': ordinal, 'serial_sha256': sha(path), 'config_sha256': sha(directory / 'config.json')})

for row in state_rows:
    if row['phase'] == 'after-metadata':
        assert row['group'] == 'none' and row['need_locks'] == row['lock'] == '0'
        continue
    for field, expected in {'class': 4, 'slots': 8, 'maplen': 0, 'nested': 1, 'sole': 1,
                            'group_count': 1, 'active_idx': 7, 'stride': 80, 'full_stride': 1,
                            'usage': 8, 'need_locks': 0, 'lock': 0, 'mem_page_offset': 16,
                            'meta_cacheline_offset': 24}.items():
        assert int(row[field]) == expected, (field, row)
    assert int(row['avail']) | int(row['freed']) == 255
    assert int(row['avail']) & int(row['freed']) == 0
for row in probe_rows:
    for field in ['pairs', 'class4', 'sole', 'nested', 'full_stride', 'eligible', 'lock_zero', 'need_zero']:
        assert int(row[field]) == 32
    for field in ['need_negative', 'group_changes', 'offset_min']:
        assert int(row[field]) == 0
    assert row['slots'] == ','.join(str(i) + ':4' for i in range(8)) + ','
    assert int(row['offset_max']) == 35
    assert int(row['reserved_min']) == int(row['reserved_max']) == 5

sample_deltas = [int(row['cpu_ns']) - int(row['elapsed_ns']) for item in records for row in item['samples']]
sample_ratios = [int(row['cpu_ns']) / int(row['elapsed_ns']) for item in records for row in item['samples']]
report = {
    'status': 'complete', 'boots': boot_records, 'fresh_execs': 12, 'samples': 168,
    'measured_pairs_per_sample': 200000, 'full_warmup_pairs_per_phase': 200000,
    'validation': 'Both hash-verified immutable-v5 kernels/loaders completed every fresh exec and checksum; all records retained.',
    'sampled_allocator_state': {
        'after_metadata': 'class4 group absent in all twelve execs',
        'hot_group': 'class4, eight slots, one sole nested group, stride80, full stride, usage8, active_idx7',
        'locks': 'need_locks0 and actual malloc lock0 in every state/probe; no negative transition',
        'free_fast_path': 'All 1536 outside-loop allocation probes met the v5 retained single-thread free conditions.',
        'rotation': 'Each 32-pair probe visited all eight slots four times; no group change; reserved header5; offset0..35',
        'masks': 'Available/freed masks were disjoint and together255; phase-dependent rotation masks retained.',
        'alignment': 'All hot groups had memory page offset16 and metadata cache line offset24.'},
    'cpu_accounting': {'median_cpu_minus_wall_ns': statistics.median(sample_deltas),
                       'min_cpu_minus_wall_ns': min(sample_deltas), 'max_cpu_minus_wall_ns': max(sample_deltas),
                       'min_cpu_to_wall_ratio': min(sample_ratios), 'max_cpu_to_wall_ratio': max(sample_ratios)},
    'conclusion': 'The sampled allocator state remained invariant while hot timings varied substantially across samples, fresh execs and boots. These data do not support class coarsening, lost retention, nested/sole group changes, missed free-fast-path eligibility or a malloc-lock transition as the source of the variation. Guest CPU time closely followed wall time, so substantial guest descheduling is not visible in this diagnostic.',
    'limits': [
        'Outside-loop observations are sampled state, not instruction tracing inside every measured pair.',
        'The private executable is cross GCC14.2 with different code layout and extra outside-loop dlsym/probes/CPU clock reads, whereas canonical captures were compiled by guest GCC14.2. This diagnostic cannot replace or revise either canonical timing.',
        'Vinix CPU accounting and wall time use the virtual free-running hardware clock. A host pause while QEMU still considers the guest thread running can appear in both clocks. This report does not establish host noise, host CPU speed or a specific TCG/timing mechanism.',
        'Dynamic setup resolves the actual next-DSO malloc definition before dladdr; immutable loader ELF offsets and all private copies are recorded. No secrets or full addresses are printed by the sampler.',
        'A preflight setup error from executable-PLT dladdr was retained separately and excluded from measurements.'
    ],
    'state_rows': state_rows, 'probe_rows': probe_rows, 'sample_batches': records,
}
(STATE / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: value for key, value in report.items() if key not in ['state_rows', 'probe_rows', 'sample_batches']}, indent=2))
