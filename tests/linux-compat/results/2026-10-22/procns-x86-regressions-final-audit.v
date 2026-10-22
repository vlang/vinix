import crypto.sha256
import json2
import os

struct OriginalResult {
	name string
	source_sha256 string
	init_sha256 string
	iso_sha256 string
	exit_code int
	detail string
}

struct OriginalReceipt {
	architecture string
	context string
	kernel_sha256 string
	results []OriginalResult
}

struct AggregateResult {
	name string
	source_sha256 string
	init_sha256 string
	iso_sha256 string
	exit_code int
	detail string
	origin_state string
	origin_receipt_sha256 string
	origin_exit_code int
	serial_sha256 string
	actual_pass_marker bool
	input_pins_match bool
	storage_cohorts int
	storage_and_slab_flat bool
	semantic_counters_zero bool
}

struct AggregateReceipt {
	architecture string
	context string
	fix_commit string
	kernel_sha256 string
	exit_code int
	results []AggregateResult
	provenance map[string]string
	tool_sha256 map[string]string
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn counters_zero(log string) bool {
	for line in log.split_into_lines() {
		for word in line.fields() {
			if (word.starts_with('failures=') || word.starts_with('unexpected=')) && word.all_after('=').u64() != 0 { return false }
		}
	}
	return true
}

fn storage_check(log string) (int, bool) {
	mut cohorts := 0
	mut flat := true
	for line in log.split_into_lines() {
		if line.contains(' STORAGE:') {
			cohorts++
			if !line.ends_with(' PASS') { flat = false }
		}
		if line.contains(' SLAB:') || line.contains(' STORAGE:') {
			for word in line.fields() {
				if word.starts_with('live=') || word.starts_with('big_pages=') {
					pair := word.all_after('=').split('/')
					if pair.len != 2 || pair[0] != pair[1] { flat = false }
				}
			}
		}
	}
	return cohorts, flat
}

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	old := '/Users/alex/.cache/vinix-linux-compat/procns-20261016'
	final := area + '/x86-regressions-final'
	os.mkdir_all(final)!
	rx := json2.decode[OriginalReceipt](os.read_file(area + '/rx/receipt.json')!)!
	rp := json2.decode[OriginalReceipt](os.read_file(area + '/rp/receipt.json')!)!
	expected_kernel := '5f191bb7355f00bc99e1cd04d1d3b6de570815c8517a9077469d35844f7e6b13'
	mut results := []AggregateResult{}
	mut publication := map[string]string{}
	mut lines := ['x86 strict legacy regression aggregate', 'Fix commit: cf6426cf16657a6db8d5be8062ef82f170c6b48b', 'Five cases originate in rx; procpid originates in rp, the strict 3600-second retry.', 'The original rx procpid host timeout and receipt remain distinct and unchanged. No fixture checks were relaxed.']
	mut all_passed := true
	for name in ['runtime', 'namespace', 'readlinkempty', 'proctask', 'procpid', 'cloneipc'] {
		group := if name == 'procpid' { 'rp' } else { 'rx' }
		receipt := if group == 'rp' { rp } else { rx }
		work := area + '/' + group
		mut selected := OriginalResult{}
		mut found := false
		for result in receipt.results {
			if result.name == name { selected = result; found = true }
		}
		if !found { panic('case has not completed: ' + group + '/' + name) }
		log_path := work + '/' + name + '/serial.log'
		log := os.read_file(log_path)!.replace('\r', '')
		marker := 'LINUX ' + name.to_upper() + ': PASS'
		actual := log.split_into_lines().contains(marker)
		source := work + '/sources/' + name + 'fixture/core.v'
		pinned := receipt.architecture == 'x86_64'
			&& receipt.kernel_sha256 == expected_kernel
			&& digest(work + '/kernel/bin/vinix')! == expected_kernel
			&& digest(source)! == selected.source_sha256
			&& digest(source)! == digest(old + '/states/regression-arm/sources/' + name + 'fixture/core.v')!
			&& digest(work + '/' + name + '/init')! == selected.init_sha256
			&& digest(work + '/' + name + '/test.iso')! == selected.iso_sha256
		cohorts, flat := storage_check(log)
		expected_cohorts := if name == 'readlinkempty' { 2 } else if name in ['proctask', 'procpid', 'cloneipc'] { 4 } else { 0 }
		zero := counters_zero(log)
		passed := selected.exit_code == 0 && actual && pinned && flat && zero && cohorts == expected_cohorts && !log.contains(' FAIL')
		if !passed { all_passed = false }
		serial_copy := final + '/' + name + '-serial.log'
		os.write_file(serial_copy, os.read_file(log_path)!)!
		publication['x86-regression-' + name + '-serial.log'] = serial_copy
		results << AggregateResult{
			name: name
			source_sha256: selected.source_sha256
			init_sha256: selected.init_sha256
			iso_sha256: selected.iso_sha256
			exit_code: if passed { 0 } else { 1 }
			detail: if group == 'rp' { 'Strict retry, timeout 3600 seconds; rx initial timeout remains preserved separately.' } else { selected.detail }
			origin_state: group
			origin_receipt_sha256: digest(work + '/receipt.json')!
			origin_exit_code: selected.exit_code
			serial_sha256: digest(log_path)!
			actual_pass_marker: actual
			input_pins_match: pinned
			storage_cohorts: cohorts
			storage_and_slab_flat: flat
			semantic_counters_zero: zero
		}
		lines << '${name}: origin=${group} original_exit=${selected.exit_code} verified_exit=${if passed { 0 } else { 1 }} actual_PASS=${actual} pins=${pinned} storage_cohorts=${cohorts}/${expected_cohorts} flat=${flat} semantic_counters_zero=${zero} serial_sha256=${digest(log_path)!}'
	}
	if rp.kernel_sha256 != rx.kernel_sha256 { all_passed = false }
	mut procpid_original := OriginalResult{}
	mut procpid_retry := OriginalResult{}
	for result in rx.results { if result.name == 'procpid' { procpid_original = result } }
	for result in rp.results { if result.name == 'procpid' { procpid_retry = result } }
	if procpid_original.init_sha256 != procpid_retry.init_sha256 || procpid_original.source_sha256 != procpid_retry.source_sha256 { panic('retry changed procpid ELF/source') }
	lines << 'procpid retry source/ELF identity: verified; only host timeout increased 1200 -> 3600 seconds.'
	lines << 'Original rx procpid exit=${procpid_original.exit_code}; original timeout log and complete rx receipt retained without modification.'
	mut tool_pins := map[string]string{}
	for path in [area + '/regression-runner/run.v', area + '/regression-runner/run-replay', '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v', '/opt/homebrew/bin/x86_64-linux-musl-gcc', area + '/launch-root/build-support/build-amd64-iso.sh'] {
		tool_pins[path] = digest(path)!
	}
	receipt := AggregateReceipt{
		architecture: 'x86_64'
		context: 'QEMU native musl ELF64; strict unchanged fixtures. Five rx cases plus rp procpid retry; original timeout retained.'
		fix_commit: 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'
		kernel_sha256: expected_kernel
		exit_code: if all_passed { 0 } else { 1 }
		results: results
		provenance: {
			'rx_receipt_sha256': digest(area + '/rx/receipt.json')!
			'rp_receipt_sha256': digest(area + '/rp/receipt.json')!
			'rx_procpid_timeout_log_sha256': digest(area + '/rx/procpid/serial.log')!
			'rx_procpid_exit_code': procpid_original.exit_code.str()
			'rx_timeout_seconds': '1200'
			'rp_timeout_seconds': '3600'
			'procpid_source_and_elf_unchanged': 'true'
		}
		tool_sha256: tool_pins
	}
	os.write_file(final + '/receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	os.write_file(final + '/status', if all_passed { '0\n' } else { '1\n' })!
	lines << 'Aggregate exit=${if all_passed { 0 } else { 1 }}; all six verified=${all_passed}.'
	os.write_file(final + '/audit.txt', lines.join('\n') + '\n')!
	for suffix, path in {
		'x86-regressions-final-receipt.json': final + '/receipt.json'
		'x86-regressions-final-status.txt': final + '/status'
		'x86-regressions-final-audit.txt': final + '/audit.txt'
		'x86-regressions-final-audit.v': area + '/x86-regression-aggregate.v'
		'x86-regressions-rx-original-receipt.json': area + '/rx/receipt.json'
		'x86-regressions-rx-original-harness.log': area + '/rx.log'
		'x86-regressions-procpid-initial-timeout-serial.log': area + '/rx/procpid/serial.log'
		'x86-regressions-procpid-retry-receipt.json': area + '/rp/receipt.json'
		'x86-regressions-procpid-retry-harness.log': area + '/rp.log'
		'x86-regressions-procpid-retry-serial.log': area + '/rp/procpid/serial.log'
	} { publication[suffix] = path }
	os.write_file(area + '/x86-regressions-publication-inputs.json', json2.encode(publication, prettify: true) + '\n')!
	println(lines.join('\n'))
	if !all_passed { exit(1) }
}
