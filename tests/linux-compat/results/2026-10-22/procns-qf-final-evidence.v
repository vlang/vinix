import os
import json2
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn add(mut files map[string]string, alias string, path string) {
	assert os.is_file(path), path
	assert alias !in files, alias
	files[alias] = path
}

fn small(path string) bool {
	return os.file_size(path) < 4 * 1024 * 1024
}

fn pinned(path string) map[string]json2.Any {
	assert os.is_file(path), path
	return {'path': json2.Any(path), 'sha256': sha256.sum(os.read_bytes(path) or { panic(err) }).hex()}
}

fn observed(log string, status string, expected int) map[string]json2.Any {
	code := (os.read_file(status) or { panic(err) }).trim_space()
	assert code == expected.str(), status + ': ' + code
	return {'log': json2.Any(pinned(log)), 'status': pinned(status), 'exit_code': expected}
}

fn guest(group string) map[string]json2.Any {
	assert (os.read_file(area + '/' + group + '.status') or { panic(err) }).trim_space() == '0'
	return {
		'producer': json2.Any(observed(area + '/' + group + '-producer.log', area + '/' + group + '-producer.log.status', 0))
		'serial': pinned(area + '/' + group + '/serial.log')
		'json': pinned(area + '/' + group + '.json')
		'status': pinned(area + '/' + group + '.status')
		'exit_code': 0
	}
}

fn summary() ! {
	mut generated := []json2.Any{}
	for profile in ['x86-track', 'arm-track', 'x86-prod', 'arm-prod'] {
		mut review := observed(area + '/queue-fix/generated-review-' + profile + '.log', area + '/queue-fix/generated-review-' + profile + '.status', 0)
		review['profile'] = profile
		generated << review
	}
	mut comparison := observed(area + '/qf2-allocs-comparison.log', area + '/qf2-allocs-comparison.status', 0)
	comparison['no_new_groups'] = true
	mut result := map[string]json2.Any{}
	result['schema_version'] = 1
	queue_commit := (os.read_file(area + '/queue-fix/commit.txt')!).trim_space()
	result['queue_commit'] = queue_commit
	result['build_inputs'] = pinned(area + '/queue-candidate-inputs.json')
	result['review'] = {
		'source': json2.Any(observed(area + '/queue-source-audit.log', area + '/queue-source-audit.log.status', 0))
		'generated': generated
		'independent': pinned(area + '/q2-independent-root-lifetime-review.md')
	}
	result['allocation_inventory'] = {
		'baseline': json2.Any(observed(area + '/qf2-allocs-baseline.log', area + '/qf2-allocs-baseline.status', 1))
		'candidate': observed(area + '/qf2-allocs-candidate.log', area + '/qf2-allocs-candidate.status', 1)
		'comparison': comparison
	}
	result['arm_perf'] = {
		'inputs_manifest': json2.Any(pinned(area + '/qf2-perf-inputs.sha256'))
		'input_before_audit': observed(area + '/qf-perf-inputs-before-audit.log', area + '/qf-perf-inputs-before-audit.log.status', 0)
		'input_after_audit': observed(area + '/qf-perf-inputs-audit.log', area + '/qf-perf-inputs-audit.status', 0)
		'raw_audit': observed(area + '/qf-perf-results-audit.log', area + '/qf-perf-results-audit.status', 0)
		'drag_audit': observed(area + '/qf-perf-drag-audit.log', area + '/qf-perf-drag-audit.status', 0)
		'ops_churn_cache': guest('qf-perf-compat-ops')
		'desktop': guest('qf-perf-compat-desktop')
		'actual_drag': guest('qf-perf-drag-desktop')
		'visual_review': pinned(area + '/qf-perf-drag-visual-review.md')
		'notes': pinned(area + '/qf-qualification-notes.md')
	}
	result['preserved_first_failures'] = {
		'q1_commit': json2.Any('ec5631d664a8148c063b1ef9ac3f9657a3a0386a')
		'q1_archive': pinned(area + '/queue-fix/q1-ec5631d664a8/archive.sha256')
		'q1_inventory_comparison': observed(area + '/qf-allocs-initial-comparison.log', area + '/qf-allocs-initial-comparison.status', 1)
		'initial_ready_host_failure': observed(area + '/q2-ready-initial.log', area + '/q2-ready-initial.log.status', 1)
		'x86_initial_missing_curl': observed(area + '/qf-x86-initial-missing-curl/qf-x86-qxo.log', area + '/qf-x86-initial-missing-curl/qf-x86-qxo.status', 1)
		'x86_initial_inputs': pinned(area + '/qf-x86-initial-missing-curl/records.json')
		'x86_auditor_json_correction': pinned(area + '/qf-x86-audit-json-correction/records.json')
	}
	// The architecture-specific producers remain authoritative for their
	// receipts. The final x86 and native paths are supplied explicitly.
	assert os.args.len == 4, 'summary requires x86 summary and native summary paths'
	assert (os.read_file(area + '/qf-x86-audit.txt')!).contains('Two strict negative controls rejected; all receipt/input pins and raw/JSON desktop rows verified.')
	result['x86_perf'] = pinned(os.args[2])
	result['x86_audits'] = {
		'results': json2.Any(observed(area + '/qf-x86-audit.log', area + '/qf-x86-audit-status.txt', 0))
		'inputs': observed(area + '/qf-x86-inputs-verify.log', area + '/qf-x86-inputs-verify.status', 0)
		'inputs_manifest': pinned(area + '/qf-x86-inputs.sha256')
		'curl_closure': pinned(area + '/qf-x86-curl/provenance.json')
	}
	result['native_qualification'] = pinned(os.args[3])
	result['selected_native_runs'] = pinned(area + '/selected-runs.json')
	os.write_file(area + '/qf-validation-summary.json', json2.encode(result, prettify: true) + '\n')!
	os.write_file(area + '/qf-validation-summary.md', '# Queue-buffer followup validation\n\nQualified isolated revision: `' + queue_commit + '`. Exact paths, observed exit statuses and SHA-256 pins are recorded in `qf-validation-summary.json`; native cohort selection and earlier failures are recorded in `qualification-summary.json`.\n\nBoth architectures passed all four strict native procfs cohorts with flat slab classes and big pages, zero errors/taint, and held-link/cwd protections. Both Linux reference fixtures passed. All four tracking/production kernel builds and generated-C reviews passed. Source ownership review and an independent reviewer found no new lifetime blocker; the existing timed grace period and permanent mount protections remain limits.\n\nThe allocation inventory exits 1 for both baseline and candidate because of the same inherited excess groups. The comparison exits 0 with no new groups. The Q1 missing-annotation inventory failure is preserved separately; final Q2 changes that annotation without changing the built binaries.\n\nARM and x86 performance audits each passed 36 operations repeated 200 times and four short-program cohorts repeated 300 times, with zero retained bytes per operation/run and no slab deltas. Cache checks passed their declared bounds. Idle/apps and separate fresh actual-drag scenarios completed five-second measurements. Independent full-image review confirmed window movement on both architectures. Input and raw-result audits passed, and strict negative controls were rejected. These are bounded functional/retention checks with cached desktop images, not release-performance or long-soak qualification.\n\nThe initial x86 run failed when the cached image lacked curl. Its logs, status 1, receipts, manifest and tooling remain preserved. The full final replay uses the same Q2 kernel and workload with a pinned genuine curl/dependency closure. The initial auditor JSON-filter correction and other host/diagnostic failures remain preserved. No failed run is selected as the final qualification.\n')!
	println('Queue-fix validation summary: observed statuses and hashes recorded')
}

fn drag_review() ! {
	path := area + '/qf-perf-drag-visual-review.md'
	assert !os.exists(path), 'preserve earlier review'
	mut text := '# ARM Q2 fresh-drag visual review\n\nReviewer: /root/lifetime_review, 2026-10-22. I viewed both complete PNG screenshots after the strict raw/JSON/input-marker/full-PPM audit passed with status 0.\n\nThe System window moves from the upper center to the lower left. Its visible frame counter advances from 6 to 245. The window remains rendered, with the same System content and one open window. This confirms actual window movement for the fresh drag scenario; changed pixels alone were not used as the motion oracle.\n\nThis is a five-second functional check with the cached desktop and exact Q2 allocation-tracking kernel, not a release-performance comparison or a long soak.\n\n'
	for name in ['before-drag.ppm', 'new-drag-1.ppm', 'before-drag.png', 'new-drag-1.png'] {
		input := area + '/qf-perf-drag-shots/' + name
		text += sha256.sum(os.read_bytes(input)!).hex() + '  ' + input + '\n'
	}
	os.write_file(path, text)!
	println('ARM Q2 visual review recorded actual System window movement')
}

fn notes() ! {
	for kind in ['results', 'drag', 'inputs'] {
		assert (os.read_file(area + '/qf-perf-' + kind + '-audit.status')!).trim_space() == '0'
	}
	mut text := '# Q2 queue-drain qualification notes\n\nExact isolated source: bd9aa1bc1d04eac1ce31e02ce8914969294566ff. The ARM measurements use its allocation-tracking kernel. Both production and tracking profiles build on both architectures. Their complete kernel and generated-C hashes are recorded in queue-candidate-inputs.json. All four final kernel binaries and generated-C files are byte-identical to Q1; Q2 adds only the verified-freed annotation to the existing partial-drain allocation.\n\nThe full-drain fix moves the detached queue buffer under the queue lock, resets the global header, and frees that buffer after callbacks. Independent root review and generated-C checks cover the ownership transfer. Existing timed-reader and permanent mount-pin limits remain; this is not a quiescence-based RCU proof.\n\nThe first Q1 allocation comparison rejected a newly unattributed partial-drain array assignment. Its raw inventory failures and complete historical build records remain under queue-fix/q1-ec5631d664a8 and are pinned by archive.sha256. The final Q2 inventories both exit1 for the unchanged 178 inherited excess groups; their comparison exits0 with identical per-file/kind counts and no new allocation group. The initial readiness helper also failed on a private status filename mismatch; q2-ready-initial.log/status preserve that host-only failure.\n\nThe ARM performance driver, both frozen module copies, existing measure source, selected cached desktop, 710437376-byte raw initramfs, firmware, exact kernel, V compiler and host launch dependencies are pinned before the guests run in qf2-perf-inputs.sha256 and verified again afterwards. The original qf-perf-inputs.sha256 is the earlier Q1 preparation manifest and remains historical. The cached image setup uses the existing private od/install compatibility substitutions. Automatic shared-checkout pruning is disabled. Each group runs in a separate process and distinct workfolder/QMP socket; the short desktop groups overlap the intentional grace waits in the ops guest.\n\nThe strict raw-result auditor requires 36 unique 200-cycle operation cohorts, every bytes_per_op=0 with no class deltas; four expected 300-execution churn cohorts with zero retained bytes and no PERF-SLAB rows; exactly one bounded 32MiB cache result; and exact five-second idle/apps/drag raw/JSON equality, expected native app processes, one START/DONE pair, and no PERF-ERROR or panic. It also requires the native ARM ext2 /root mount marker, so the persistent filesystem operations cannot silently run on tmpfs. Two negative controls must reject disabled assertions and a substituted desktop log.\n\nThe cache bounds were declared before completion: used_mb 0..64, cached_kb 0..65536 and at most1MiB skew between separate slab probes. Cache retention is reported separately from zero-leak operation and churn results.\n\nObserved final raw rows:\n\n```text\n'
	for group in ['qf-perf-compat-ops', 'qf-perf-compat-desktop', 'qf-perf-drag-desktop'] {
		log := (os.read_file(area + '/' + group + '/serial.log')!).replace('\r', '')
		text += group + '\n'
		for line in log.split_into_lines() {
			if line.starts_with('PERF-CHURN ') || line.starts_with('PERF-CACHE ') || line.starts_with('PERF-MEMINFO ') || line.starts_with('PERF-RESULT ') {
				text += line + '\n'
			}
		}
	}
	text += '```\n\nAn additional fresh drag-only guest has its own strict raw/JSON/marker/full-PPM audit and complete before/after screenshots. Visual review confirms the System window moving from the upper center to the lower left, with Frames6→245. These are one-round functional and bounded-retention checks using cached desktop images and five-second desktop measurements. They do not establish release performance or a long-term soak. The x86 results and native retention cohorts have separate authoritative summaries, audits, receipts and input pins, linked from qf-validation-summary.json.\n'
	os.write_file(area + '/qf-qualification-notes.md', text)!
	println('Queue-fix qualification notes: actual audited ARM rows recorded')
}

fn publish() ! {
	mut files := map[string]string{}
	for name in os.ls(area)! {
		if name.starts_with('qf-x86-') { continue }
		if !(name.starts_with('qf-') || name.starts_with('qf2-') || name.starts_with('q2-ready-initial.') || name in ['queue-source-audit.v', 'queue-source-audit.log', 'queue-source-audit.log.status', 'qf-final-evidence.v', 'qf-validation-summary.json']) { continue }
		path := area + '/' + name
		if os.is_file(path) && small(path) { add(mut files, name, path) }
	}
	for prefix in ['qf2-allocs-baseline', 'qf2-allocs-candidate', 'qf2-allocs-comparison'] {
		// The checker uses a common .log.status naming convention. Keep the
		// observed private status file unchanged and publish an explicit alias.
		add(mut files, prefix + '.log.status', area + '/' + prefix + '.status')
	}
	for kind in ['results', 'drag', 'inputs'] {
		add(mut files, 'qf-perf-' + kind + '-audit.log.status', area + '/qf-perf-' + kind + '-audit.status')
	}
	for group in ['qf-perf-compat-ops', 'qf-perf-compat-desktop', 'qf-perf-drag-desktop'] {
		add(mut files, group + '-serial.log', area + '/' + group + '/serial.log')
	}
	for group in ['qf-frozen-perf-compat', 'qf-frozen-perf-drag'] {
		mut paths := os.walk_ext(area + '/' + group, '.v')
		paths << os.walk_ext(area + '/' + group, '.h')
		paths << area + '/' + group + '/measure.c'
		paths << area + '/' + group + '/perf-init.sh'
		for path in paths {
			add(mut files, path.all_after(area + '/').replace('/', '-'), path)
		}
	}
	for name in ['before-drag.ppm', 'new-drag-1.ppm', 'before-drag.png', 'new-drag-1.png'] {
		add(mut files, 'qf-perf-drag-' + name, area + '/qf-perf-drag-shots/' + name)
	}
	for profile in ['x86-track', 'arm-track', 'x86-prod', 'arm-prod'] {
		for suffix in ['.log', '.sha256'] {
			add(mut files, 'queue-generated-review-' + profile + suffix, area + '/queue-fix/generated-review-' + profile + suffix)
		}
		add(mut files, 'queue-generated-review-' + profile + '.log.status', area + '/queue-fix/generated-review-' + profile + '.status')
		add(mut files, 'queue-generated-reaper-' + profile + '.c', area + '/queue-fix/generated-reaper-' + profile + '.c')
	}
	add(mut files, 'queue-lifetime-source-review.md', area + '/queue-fix/source-review.md')
	q1 := area + '/queue-fix/q1-ec5631d664a8'
	for path in os.walk_ext(q1, '') {
		if !os.is_file(path) || !small(path) { continue }
		if path.ends_with('/blob.c') || path.ends_with('/vinix') { continue }
		add(mut files, 'queue-q1-' + path.all_after(q1 + '/').replace('/', '-'), path)
	}
	for name in ['queue-fix-build.v', 'queue-fix-review.v', 'queue-fix-q2.v', 'queue-q2-ready.v', 'q2-independent-root-lifetime-review.md'] {
		add(mut files, name, area + '/' + name)
	}
	// All status aliases are resolved before writing the map. No absent or
	// guessed result can become an evidence record through this helper.
	os.write_file(area + '/queue-perf-publication-inputs.json', json2.encode(files, prettify: true) + '\n')!
	println('Queue-fix performance/static publication sources: ' + files.len.str())
}

fn main() {
	assert os.args.len >= 2 && os.args[1] in ['summary', 'publish', 'drag-review', 'notes']
	if os.args[1] == 'summary' { summary()! } else if os.args[1] == 'drag-review' { drag_review()! } else if os.args[1] == 'notes' { notes()! } else { publish()! }
}
