// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

fn report_rejected(text string, family string, arch string) bool {
	inspection_report(text, family, arch) or { return true }
	return false
}

fn resource_report(classes int) string {
	mut text := ''
	for window in 0 .. 2 {
		for index in 0 .. classes {
			text += 'RESOURCE-OPEN window=' + window.str() + ' class=' + index.str() + ' objects=0\n'
		}
		text += 'RESOURCE-OPEN window=' + window.str() + ' large_pages=0 written_after_free=0 flat=1\n'
	}
	return text
}

fn map_report(classes int) string {
	mut text := ''
	for index in 0 .. classes { text += 'PROC-MAP-RETENTION class=' + index.str() + ' live=0 pages=0\n' }
	text += 'PROC-MAP-RETENTION large=0 uaf=0\n'
	for cohort in 1 .. 5 { text += 'proc map lookup: completed growth cohort ' + cohort.str() + ' children=12\n' }
	return text + 'proc map lookup: 100 lookups, 100 directory snapshots\n'
}

fn test_original_retention_rows_counts_progress_and_unbounded_integers() {
	for arch in ['aarch64', 'x86_64'] {
		classes := if arch == 'aarch64' { 18 } else { 14 }
		resource := resource_report(classes)
		inspection_report(resource, 'resource-open', arch) or { panic(err) }
		inspection_report(resource.replace('objects=0', 'objects=-000').replace('flat=1', 'flat=0001'), 'resource-open', arch) or { panic(err) }
		for regression in [resource.replace_once('objects=0', 'objects=18446744073709551616'),
			resource.replace_once('objects=0', 'objects=-1'), resource.replace_once('large_pages=0', 'large_pages=1'),
			resource.replace_once('written_after_free=0', 'written_after_free=1'), resource.replace_once('flat=1', 'flat=0'),
			resource + 'RESOURCE-OPEN window=0 class=0 objects=0\n', resource.replace_once('objects=0', 'objects=')] {
			assert report_rejected(regression, 'resource-open', arch)
		}
		maps := map_report(classes)
		inspection_report(maps, 'proc-map-lookup', arch) or { panic(err) }
		inspection_report(maps.replace('100 lookups', '184467440737095516160 lookups'), 'proc-map-lookup', arch) or { panic(err) }
		for regression in [maps.replace_once('live=0', 'live=1'), maps.replace_once('pages=0', 'pages=-1'),
			maps.replace('large=0', 'large=-0'), maps.replace('uaf=0', 'uaf=1'), maps.replace('children=12', 'children=11'),
			maps.replace('100 lookups', '99 lookups'), maps.replace('100 directory', '99 directory'),
			maps + 'proc map lookup: 100 lookups, 100 directory snapshots\n', maps.replace_once('class=0 live=0 pages=0', 'class=0 live=0 pages=')] {
			assert report_rejected(regression, 'proc-map-lookup', arch)
		}
	}
	text := 'proc thread lock: 100 snapshots, 10 process CPU clocks\nPASS: process inspection completes during sibling thread churn\nVINIX PROC THREAD LOCK: PASS\n'
	inspection_report(text, 'proc-thread-lock', 'aarch64') or { panic(err) }
	for regression in [text.replace('100 snapshots', '99 snapshots'), text.replace('10 process', '9 process'),
		text + 'VINIX PROC THREAD LOCK: PASS', text + 'proc thread lock: 100 snapshots, 10 process CPU clocks',
		text.replace('PASS: process inspection completes during sibling thread churn', '')] {
		assert report_rejected(regression, 'proc-thread-lock', 'aarch64')
	}
}

fn test_append_actions_and_forwarding_preserve_order_and_last_option() {
	append := appended_options(['--fail', 'first', '--source', '/tmp/c', '--define=A=1', '--def', 'B=2',
		'--build-only', '--f=second', '--timeout', '2'], ['--define', '--fail'])
	assert append['--fail'] == ['first', 'second']
	assert append['--define'] == ['A=1', 'B=2']
	assert appended_options(['--', '--define=A'], ['--define']).len == 0
	arm := configure_process_launch(['qemu', '-m', '1024', '-smp', '2', '-cpu', 'host'], 'aarch64', 8192, 4, 'max')
	assert arm == ['qemu', '-m', '8192', '-smp', '4', '-cpu', 'host']
	x86 := configure_process_launch(arm, 'x86_64', 4096, 6, 'max,-pcid')
	assert x86 == ['qemu', '-m', '4096', '-smp', '6', '-cpu', 'max,-pcid']
}
