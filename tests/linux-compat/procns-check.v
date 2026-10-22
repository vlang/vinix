// Compile without -prod: the assertion control must execute.
import crypto.sha256
import json2
import os

struct Evidence {
	kernel_commit      string
	candidate_commit   string
	integration_commit string
	baseline_commit    string
	files              map[string]string
	source_inputs      map[string]string
}

fn digest(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn object(path string) map[string]json2.Any {
	return (json2.decode[json2.Any](os.read_file(path) or { panic(err) }) or { panic(err) }).as_map()
}

fn numbers(field string) []u64 {
	parts := field.all_after('=').split('/')
	assert parts.len == 2 && parts.all(it != '' && it.bytes().all(it.is_digit()))
	return parts.map(it.u64())
}

fn readers(log string, reference bool) {
	prefix := if reference { 'LINUX PROCNS REFERENCE READER:' } else { 'LINUX PROCNS READER:' }
	mut seen := map[int]bool{}
	for line in log.split_into_lines().filter(it.starts_with(prefix)) {
		fields := line.all_after(prefix).fields()
		assert fields.len == 2 && fields[0].starts_with('index=') && fields[1].starts_with('calls=')
		index := fields[0].all_after('=').int()
		assert index in [0, 1, 2, 3] && index !in seen && fields[1].all_after('=').int() > 0
		seen[index] = true
	}
	assert seen.len == 4
}

fn storage(log string, arch string, baseline bool) {
	assert arch in ['aarch64', 'x86_64']
	assert log.contains('LINUX PROCNS HELD: O_PATH symlink=1 cwd=1 parent=1 inherited=1 grace_seconds=13')
	assert !log.contains('Kernel panic')
	mut slabs := [4]int{}
	mut summaries := [4]int{}
	mut growing := [4]bool{}
	mut classes := map[string]bool{}
	mut first_classes := map[u64]bool{}
	for line in log.split_into_lines() {
		if line.starts_with('LINUX PROCNS SLAB:') {
			fields := line.fields()
			assert fields.len == 7 && fields[3].starts_with('kind=') && fields[4].starts_with('size=') && fields[5].starts_with('live=') && fields[6] == 'cycles=200'
			kind := fields[3].all_after('=').int()
			size := fields[4].all_after('=').u64()
			assert kind in [0, 1, 2, 3] && size > 0
			key := fields[3] + '/' + fields[4]
			assert key !in classes
			classes[key] = true
			if kind == 0 {
				first_classes[size] = true
			} else {
				assert size in first_classes
			}
			pair := numbers(fields[5])
			if baseline && kind >= 2 {
				assert pair[1] >= pair[0]
				growing[kind] = growing[kind] || pair[1] > pair[0]
			} else {
				assert pair[0] == pair[1], line
			}
			slabs[kind]++
		} else if line.starts_with('LINUX PROCNS STORAGE:') {
			fields := line.fields()
			assert fields.len == 9 && fields[3].starts_with('kind=') && fields[4] == 'cycles=200' && fields[5].starts_with('big_pages=') && fields[6] == 'written_after_free=0/0' && fields[7] == 'errors=0'
			kind := fields[3].all_after('=').int()
			assert kind in [0, 1, 2, 3]
			pair := numbers(fields[5])
			if baseline && kind >= 2 {
				assert fields[8] == 'FAIL' && pair[1] >= pair[0]
			} else {
				assert fields[8] == 'PASS' && fields[7] == 'errors=0' && pair[0] == pair[1], line
			}
			summaries[kind]++
		}
	}
	for kind in 0 .. 4 {
		assert slabs[kind] == if arch == 'aarch64' { 18 } else { 14 }
		assert summaries[kind] == 1
	}
	readers(log, false)
	if baseline {
		assert growing[2] && growing[3], 'baseline must retain proc trees'
		assert log.contains('LINUX PROCNS FAIL: retained proc namespace tree or concurrent lookup')
		assert !log.contains('LINUX PROCNS: PASS')
	} else {
		assert log.contains('LINUX PROCNS: PASS') && !log.contains('LINUX PROCNS FAIL')
	}
}

fn control(args []string, marker string) {
	mut p := os.new_process(os.executable())
	p.set_args(args)
	p.set_redirect_stdio()
	p.run()
	output := p.stdout_slurp() + p.stderr_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 1 || !output.contains(marker) {
		panic('audit negative control did not execute: ' + output)
	}
}

fn regressions(out string, suffix string, kernel string) ! {
	receipt := object(out + 'procns-' + suffix + '-regressions.json')
	assert receipt['kernel_sha256']!.str() == kernel
	mut seen := map[string]bool{}
	for item in receipt['results']!.as_array() {
		result := item.as_map()
		name := result['name']!.str()
		assert name in ['runtime', 'namespace', 'readlinkempty', 'proctask', 'procpid', 'cloneipc'] && name !in seen
		assert result['exit_code']!.int() == 0
		log := os.read_file(out + 'procns-' + suffix + '-regression-' + name + '.log') or { panic(err) }
		assert log.contains('LINUX ' + name.to_upper() + ': PASS') && !log.contains('Kernel panic')
		mut cohorts := 0
		mut slabs := 0
		for line in log.split_into_lines().filter(it.starts_with('LINUX ' + name.to_upper())) {
			if line.contains(' STORAGE:') {
				assert line.trim_space().ends_with(' PASS'), line
				cohorts++
			}
			if line.contains(' SLAB:') { slabs++ }
			for field in line.fields() {
				if field.starts_with('big_pages=') || field.starts_with('live=') {
					pair := numbers(field)
					assert pair[0] == pair[1], line
				}
				if field.starts_with('failures=') || field.starts_with('errors=') || field.starts_with('unexpected=') {
					assert field.all_after('=') == '0', line
				}
			}
		}
		expected := if name == 'readlinkempty' {
			2
		} else if name in ['proctask', 'procpid', 'cloneipc'] {
			4
		} else {
			0
		}
		assert cohorts == expected
		assert slabs == expected * if suffix == 'arm' { 18 } else { 14 }
		seen[name] = true
	}
	assert seen.len == 6
}

fn queue_inputs(out string, evidence Evidence) ! {
	inputs := object(out + 'procns-queue-candidate-inputs.json')
	assert inputs['kernel_commit']!.str() == evidence.candidate_commit
	assert inputs['base_commit']!.str() == evidence.kernel_commit
	for suffix in ['arm', 'x86'] {
		after := object(out + 'procns-' + suffix + '-after.json')
		for flavor in ['track', 'prod'] {
			key := suffix + '-' + flavor
			assert inputs[key + ':build_status']!.str() == '0'
			assert inputs[key + ':kernel_sha256']!.str().len == 64
			assert inputs[key + ':blob_sha256']!.str().len == 64
			if flavor == 'track' {
				assert after['kernel_sha256']!.str() == inputs[key + ':kernel_sha256']!.str()
			}
		}
	}
}

fn attribution(out string, evidence Evidence) ! {
	data := object(out + 'procns-queue-attribution.json')
	assert data['kernel_commit']!.str() == evidence.kernel_commit
	assert data['audit']!.str() == 'PASS'
	assert data['all_14_slab_classes_unchanged']!.str() == 'true'
	before := data['guest_big_pages_before']!.str().u64()
	after := data['guest_big_pages_after_and_four_extended_idle_snapshots']!.str().u64()
	assert before == 201 && after == 251
	entry := data['queue_element_size']!.str().u64()
	old_capacity := data['queue_cap_during_measure']!.str().u64()
	new_capacity := data['queue_cap_after_and_idle']!.str().u64()
	old_request := data['queue_request_bytes_before_from_exact_allocator_geometry']!.str().u64()
	new_request := data['queue_request_bytes_after_from_live_metadata']!.str().u64()
	assert entry == 200 && old_capacity == 1024 && new_capacity == 2048
	assert old_request == old_capacity * entry + 31
	assert new_request == new_capacity * entry + 31
	old_pages := (old_request + 4095) / 4096 + 1
	new_pages := (new_request + 4095) / 4096 + 1
	assert old_pages == data['queue_total_pages_before_from_exact_allocator_geometry']!.str().u64()
	assert new_pages == data['queue_total_pages_after_from_live_metadata']!.str().u64()
	assert after - before == new_pages - old_pages && new_pages - old_pages == 50
}

fn proof(out string, log string, status string, marker string) {
	assert (os.read_file(out + 'procns-' + status) or { panic(err) }).trim_space() == '0', status
	assert (os.read_file(out + 'procns-' + log) or { panic(err) }).contains(marker), log
}

fn qualification(out string) {
	for name in ['baseline', 'candidate'] {
		assert (os.read_file(out + 'procns-qf2-allocs-' + name + '.log.status') or { panic(err) }).trim_space() == '1'
	}
	proof(out, 'qf2-allocs-comparison.log', 'qf2-allocs-comparison.log.status', 'no new allocation group')
	proof(out, 'queue-source-audit.log', 'queue-source-audit.log.status', 'PASS: Q2 aggregate one-file drain ownership and annotation-only followup.')
	for name in ['x86-track', 'arm-track', 'x86-prod', 'arm-prod'] {
		proof(out, 'queue-generated-review-' + name + '.log', 'queue-generated-review-' + name + '.log.status', 'PASS generated full-drain header transfer')
	}
	for name in ['before-audit', 'audit'] {
		proof(out, 'qf-perf-inputs-' + name + '.log', 'qf-perf-inputs-' + name + '.log.status', 'Queue-fix perf verify: PASS ')
	}
	proof(out, 'qf-perf-results-audit.log', 'qf-perf-results-audit.log.status', 'Perf raw-result audit: PASS (two negative controls rejected)')
	proof(out, 'qf-perf-drag-audit.log', 'qf-perf-drag-audit.log.status', 'Queue-fix ARM fresh drag: PASS ')
	proof(out, 'queue-x86-inputs-verify.log', 'queue-x86-inputs-verify.status', 'PASS')
	proof(out, 'queue-x86-audit.log', 'queue-x86-audit-status.txt', 'Two strict negative controls rejected; all receipt/input pins and raw/JSON desktop rows verified.')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--assertion-control' {
		assert false, 'procns forced assertion control'
		return
	}
	if os.args.len == 4 && os.args[1] == '--growth-control' {
		storage(os.read_file(os.args[2])!, os.args[3], true)
		return
	}
	if os.args.len == 3 && os.args[1] == '--queue-growth-control' {
		storage(os.read_file(os.args[2])!, 'x86_64', false)
		return
	}
	assert os.args.len == 1
	root := os.real_path(os.dir(@FILE) + '/../..')
	out := root + '/tests/linux-compat/results/2026-10-22/'
	evidence := json2.decode[Evidence](os.read_file(out + 'procns-evidence.json')!)!
	assert evidence.kernel_commit == 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'
	assert evidence.candidate_commit == 'bd9aa1bc1d04eac1ce31e02ce8914969294566ff'
	assert evidence.integration_commit == 'd0e230dd7b56bf68ea55d418c142ed45aca08fd6'
	assert evidence.baseline_commit == 'f3a29a7aa558d0325d5602f39f503d3449e5b56f'
	assert evidence.files.len >= 12 && evidence.source_inputs.len >= 3
	for path, expected in evidence.files {
		assert digest(out + path) == expected, path
	}
	for path, expected in evidence.source_inputs {
		assert digest(root + '/' + path) == expected, path
	}
	queue_inputs(out, evidence)!
	attribution(out, evidence)!
	qualification(out)
	baseline := object(out + 'procns-baseline-inputs.json')
	assert baseline['baseline_commit']!.str() == evidence.baseline_commit
	assert baseline['audit_base_head']!.str() == evidence.baseline_commit
	assert baseline['audit_base_tracked_status']!.str() == ''
	assert digest(out + 'procns-baseline-base.txt') == baseline['base_sha256']!.str()
	assert digest(out + 'procns-baseline-manage.v') == baseline['controller_sha256']!.str()
	baseline_kernels := baseline['kernels']!.as_map()
	for suffix in ['arm', 'x86'] {
		arch := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
		before := object(out + 'procns-' + suffix + '-before.json')
		after := object(out + 'procns-' + suffix + '-after.json')
		for phase, receipt in {
			'before': before
			'after':  after
		} {
			assert receipt['architecture']!.str() == arch
			assert receipt['profile']!.str() == if phase == 'after' {
				'candidate-track'
			} else {
				'baseline-track'
			}
			assert receipt['detail']!.str() == ''
			assert receipt['source_sha256']!.str() == digest(root + '/tests/linux-compat/procnsfixture/core.v')
			manifest := if phase == 'after' {
				'procns-source-manifest3.json'
			} else {
				'procns-source-manifest2.json'
			}
			assert receipt['manifest_sha256']!.str() == digest(out + manifest)
			assert receipt['kernel_sha256']!.str() == receipt['input_kernel_sha256']!.str()
			assert receipt['kernel_sha256']!.str() == receipt['input_kernel_sha256_after']!.str()
			assert receipt['serial_sha256']!.str() == digest(out + 'procns-' + suffix + '-' + phase + '.log')
			assert receipt['exit_code']!.int() == if phase == 'after' { 0 } else { 1 }
			storage(os.read_file(out + 'procns-' + suffix + '-' + phase + '.log')!, arch, phase == 'before')
		}
		assert after['kernel_commit']!.str() == evidence.candidate_commit
		assert after['candidate_inputs_sha256']!.str() == digest(out + 'procns-queue-candidate-inputs.json')
		assert after['controller_source_sha256']!.str() == digest(out + 'procns-qualify3.v')
		pinned_before := baseline_kernels[suffix]!.as_map()
		assert pinned_before['architecture']!.str() == arch
		assert pinned_before['profile']!.str() == 'baseline-track'
		assert pinned_before['worktree_head']!.str() == evidence.baseline_commit
		assert pinned_before['build_status']!.int() == 0
		assert before['kernel_sha256']!.str() == pinned_before['kernel_sha256']!.str()
		build_name := if suffix == 'arm' {
			'build-before-arm-track-mp.log'
		} else {
			'build-before-x86-track.log'
		}
		assert digest(out + 'procns-baseline-' + build_name) == pinned_before['build_log_sha256']!.str()
		assert digest(out + 'procns-baseline-' + build_name + '.status') == pinned_before['build_status_sha256']!.str()
		assert before['kernel_sha256']!.str() != after['kernel_sha256']!.str()
		assert before['init_sha256']!.str() == after['init_sha256']!.str()
		reference := object(out + 'procns-' + suffix + '-reference.json')
		artifacts := reference['artifacts']!.as_map()
		assert reference['architecture']!.str() == arch && reference['passed']!.bool() && reference['finished']!.bool() && reference['status']!.int() == 0
		assert artifacts['probe']!.str() == after['init_sha256']!.str()
		assert artifacts['serial']!.str() == digest(out + 'procns-' + suffix + '-reference.log')
		log := os.read_file(out + 'procns-' + suffix + '-reference.log')!
		assert log.contains('Linux version ') && log.contains('LINUX PROCNS REFERENCE: PASS') && log.contains('LINUX PROCNS REFERENCE RACE: errors=0 workers=4') && log.contains('LINUX PROCNS HELD: O_PATH symlink=1 cwd=1 parent=1 inherited=1 grace_seconds=13') && !log.contains('LINUX PROCNS FAIL') && !log.contains('Kernel panic')
		readers(log, true)
		original_kernel := if suffix == 'arm' {
			'5515b47a413f57ee7e69b943f153def6359b68378dd3a8b8b8d404685cecbb90'
		} else {
			'5f191bb7355f00bc99e1cd04d1d3b6de570815c8517a9077469d35844f7e6b13'
		}
		regressions(out, suffix, original_kernel)!
		for flavor in ['track', 'prod'] {
			assert os.read_file(out + 'procns-build-' + suffix + '-' + flavor + '.status')!.trim_space() == '0'
			assert os.read_file(out + 'procns-queue-build-' + suffix + '-' + flavor + '.status')!.trim_space() == '0'
		}
	}
	assert os.read_file(out + 'procns-allocs.log.status')!.trim_space() == '1'
	assert os.read_file(out + 'procns-allocs-base.log.status')!.trim_space() == '1'
	control(['--assertion-control'], 'procns forced assertion control')
	control(['--growth-control', out + 'procns-arm-after.log', 'aarch64'], 'Assertion failed')
	control(['--queue-growth-control', out + 'procns-x86-original-queue-growth.log'], 'Assertion failed')
	println('Proc namespace reclamation evidence: PASS (three negative controls rejected)')
}
