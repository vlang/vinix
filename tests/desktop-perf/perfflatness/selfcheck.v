// SPDX-License-Identifier: GPL-2.0-or-later
module perfflatness

import perfreport

fn fixture() string {
	mut lines := []string{}
	for op in perfreport.general_ops {
		lines << 'PERF-OPS variant=new scenario=ops round=1 op=' + op + ' dir=/tmp count=200 bytes_per_op=0'
	}
	for directory in ['/tmp', '/root'] {
		for op in perfreport.file_ops {
			lines << 'PERF-OPS variant=new scenario=ops round=1 op=' + op + ' dir=' + directory + ' count=200 bytes_per_op=0'
		}
	}
	for program in perfreport.churn_programs {
		lines << 'PERF-CHURN variant=new scenario=churn round=1 program="' + program + '" runs=300 retained_kb=0 per_run_bytes=0'
	}
	lines << 'PERF-CACHE variant=new scenario=cache round=1 written_mb=32 used_mb=32 cached_kb=32768 slab_kb=256'
	for scenario in ['idle', 'apps', 'drag'] {
		lines << 'PERF-RESULT variant=new scenario=' + scenario + ' round=1 seconds=5 processes=4 desktop_cpu=1 apps_cpu=0 total_cpu=1 desktop_mb=2 apps_mb=0 total_mb=2 system_used_mb=20 physical_mb=2'
	}
	lines << perfreport.done
	return lines.join('\n') + '\n'
}

// Explicit conditions and calls remain active in production builds.
pub fn selfcheck() ! {
	base := fixture()
	valid := inspect(base.bytes())!
	if valid.ops != 36 || valid.slab_rows != 0 || valid.observations.len != 5 {
		return error('complete flat fixture or observation preservation failed')
	}
	needle := 'op=stat dir=/tmp count=200 bytes_per_op=0'
	for suffix in [' size-16:+1', ' size-16:-1', ' size-16:+2 size-32:-1',
		' large_pages:+1', ' large_pages:-1', ' size-16:0', ' size-16:+0 size-16:+0',
		' size-0:+0', ' size-16:+x', ' unknown:+0', ' unexpected=0', ' size-16:+9223372036854775808'] {
		mut refused := false
		inspect(base.replace(needle, needle + suffix).bytes()) or { refused = true }
		if !refused { return error('accepted nonflat or malformed OPS suffix: ' + suffix) }
	}
	for suffix in ['class=size-16 objects=+1 pages=+0', 'class=size-16 objects=+0 pages=+1',
		'class=size-16 objects=-1 pages=+0', 'class=large pages=+1',
		'class=large pages=+0 objects=+0', 'class=size-16 objects=+0 objects=+0 pages=+0',
		'class=size-16 pages=+0', 'class=size-16 objects=+0 pages=x'] {
		line := 'PERF-SLAB variant=new scenario=churn round=1 program="/bin/true" ' + suffix + '\n'
		mut refused := false
		inspect((base + line).bytes()) or { refused = true }
		if !refused { return error('accepted nonflat or malformed SLAB row: ' + suffix) }
	}
	for changed in [base.replace(needle, needle.replace('bytes_per_op=0', 'bytes_per_op=1')),
		base.replace(perfreport.done, ''), base.replace('op=stat dir=/tmp', 'op=missing dir=/tmp'),
		base + 'PERF-ERROR fixture failure\n',
		base + 'PERF-OPS\n',
		base + 'PERF-OPS\tvariant=new scenario=ops round=1 op=stat dir=/tmp count=200 bytes_per_op=0 size-16:+1\n',
		base + 'PERF-SLAB\n',
		base + 'PERF-SLAB\tvariant=new scenario=churn round=1 program="/bin/true" class=size-16 objects=+1 pages=+0\n',
		base + 'PERF-SLAB variant=new scenario=churn round=1 program="fake class=size-16 objects=+0 pages=+0" class=large pages=+0\n'] {
		mut refused := false
		inspect(changed.bytes()) or { refused = true }
		if !refused { return error('accepted incomplete, unknown, nonflat or quoted-spoof fixture') }
	}
	zeros := base.replace(needle, needle + ' size-16:+0 large_pages:-0')
		+ 'PERF-SLAB variant=new scenario=churn round=1 program="/bin/sleep 0" class=size-16 objects=+0 pages=-0\n'
		+ 'PERF-SLAB variant=new scenario=churn round=1 program="/bin/true" class=large pages=+0\n'
	if inspect(zeros.bytes())!.slab_rows != 2 { return error('explicit zero or quoted program rejected') }
	mut duplicate_refused := false
	inspect((zeros + 'PERF-SLAB variant=new scenario=churn round=1 program="/bin/true" class=large pages=+0\n').bytes()) or {
		duplicate_refused = true
	}
	if !duplicate_refused { return error('duplicate SLAB row accepted') }
	physical := base.replace('retained_kb=0 per_run_bytes=0', 'retained_kb=4 per_run_bytes=13')
	if !inspect(physical.bytes())!.observations.any(it.contains('retained_kb=4')) {
		return error('physical delta was rejected or omitted from separate interpretation')
	}
	println('PERF FLATNESS explicit checks PASS: complete transcript, 30 refusals, exact zero deltas, preserved cache/physical observations')
}
