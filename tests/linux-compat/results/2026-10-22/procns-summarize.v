import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn digest(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn pair(field string) []i64 {
	return field.all_after('=').split('/').map(it.i64())
}

struct Cohort {
mut:
	kind int
	classes int
	changed_classes int
	bytes_delta i64
	class_object_delta map[string]i64
	storage_line string
}

struct Result {
	state string
	complete bool
	receipt_sha256 string
	serial_sha256 string
	receipt map[string]json2.Any
	cohorts []Cohort
	reader_lines []string
	unexpected_lines []string
}

fn result(tag string) Result {
	state := area + '/states/' + tag
	if !os.is_file(state + '/receipt.json') || !os.is_file(state + '/serial.log') {
		return Result{ state: state }
	}
	receipt := (json2.decode[json2.Any](os.read_file(state + '/receipt.json') or { panic(err) }) or { panic(err) }).as_map()
	log := os.read_file(state + '/serial.log') or { panic(err) }
	mut cohorts := []Cohort{len: 4}
	mut reader_lines := []string{}
	mut unexpected_lines := []string{}
	for i in 0 .. 4 { cohorts[i].kind = i }
	for raw in log.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX PROCNS SLAB:') {
			fields := line.fields()
			kind := fields[3].all_after('=').int()
			size := fields[4].all_after('=').i64()
			values := pair(fields[5])
			assert kind >= 0 && kind < 4 && values.len == 2
			delta := values[1] - values[0]
			mut cohort := cohorts[kind]
			cohort.classes++
			cohort.bytes_delta += size * delta
			if delta != 0 {
				cohort.changed_classes++
				cohort.class_object_delta[size.str()] = delta
			}
			cohorts[kind] = cohort
		} else if line.starts_with('LINUX PROCNS STORAGE:') {
			kind := line.fields()[3].all_after('=').int()
			cohorts[kind].storage_line = line
		} else if line.starts_with('LINUX PROCNS READER:') || line.starts_with('LINUX PROCNS REFERENCE READER:') {
			reader_lines << line
		} else if line.starts_with('LINUX PROCNS UNEXPECTED:') {
			unexpected_lines << line
		}
	}
	return Result{
		state: state
		complete: true
		receipt_sha256: digest(state + '/receipt.json')
		serial_sha256: digest(state + '/serial.log')
		receipt: receipt
		cohorts: cohorts.filter(it.classes > 0)
		reader_lines: reader_lines
		unexpected_lines: unexpected_lines
	}
}

struct Summary {
	complete bool
	completion_meaning string
	source_path string
	source_sha256 string
	manifest_path string
	manifest_sha256 string
	candidate_manifest_path string
	candidate_manifest_sha256 string
	candidate_commit string
	integration_commit string
	candidate_inputs_sha256 string
	baseline_inputs_path string
	baseline_inputs_sha256 string
	final_runs map[string]Result
	second_runs map[string]Result
	third_runs map[string]Result
	initial_runs map[string]Result
	diagnostic Result
	queue_attribution map[string]string
}

fn main() {
	mut final_runs := map[string]Result{}
	mut initial_runs := map[string]Result{}
	mut second_runs := map[string]Result{}
	mut third_runs := map[string]Result{}
	selected := json2.decode[map[string]string](os.read_file(area + '/selected-runs.json')!)!
	mut complete := true
	mut lines := ['# Proc namespace qualification', '', 'Final fixture accepts EACCES only during concurrent task-exit lookups; stable namespace identity checks remain strict.', '']
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after', 'reference'] {
			key := suffix + '-' + phase
			state := selected[key]!
			item := result(os.base(state))
			final_runs[key] = item
			second_runs[key] = result('final2-' + phase + '-' + suffix)
			initial_runs[key] = result('final-' + phase + '-' + suffix)
			if suffix == 'x86' && phase in ['before', 'after'] { third_runs[key] = result('final3-' + phase + '-' + suffix) }
			complete = complete && item.complete
			if !item.complete {
				lines << key + ': pending'
				continue
			}
			status := if phase == 'reference' { item.receipt['status'] or { json2.Any(-1) } } else { item.receipt['exit_code'] or { json2.Any(-1) } }
			lines << key + ': exit=' + status.str() + ', state=' + item.state
			for cohort in item.cohorts {
				lines << '- kind=' + cohort.kind.str() + ' classes=' + cohort.classes.str() + ' changed=' + cohort.changed_classes.str() + ' retained_bytes=' + cohort.bytes_delta.str() + ' bytes_per_operation=' + (cohort.bytes_delta / 200).str()
				lines << '  ' + cohort.storage_line
			}
			lines << ''
		}
	}
	source := area + '/frozen2/procnsfixture/core.v'
	manifest := area + '/source-manifest2.json'
	baseline_inputs := area + '/baseline-inputs.json'
	candidate_manifest := area + '/source-manifest3.json'
	candidate_inputs := area + '/queue-candidate-inputs.json'
	candidate_commit := if os.exists(candidate_inputs) {
		(json2.decode[map[string]string](os.read_file(candidate_inputs)!)!)['kernel_commit']!
	} else { 'not sealed' }
	integration_commit := if os.exists(area + '/integration-commit.txt') { os.read_file(area + '/integration-commit.txt')!.trim_space() } else { 'unavailable' }
	attribution := if os.exists(area + '/queue-attribution.json') { json2.decode[map[string]string](os.read_file(area + '/queue-attribution.json')!)! } else { map[string]string{} }
	lines << 'Source SHA256: ' + digest(source)
	lines << 'Manifest SHA256: ' + digest(manifest)
	if os.exists(candidate_manifest) { lines << 'Candidate manifest SHA256: ' + digest(candidate_manifest) }
	lines << 'Candidate commit: ' + candidate_commit
	lines << 'Integration commit: ' + integration_commit
	lines << 'Baseline provenance: ' + baseline_inputs
	lines << 'Original cf642 x86 final3 failed strict big-heap flatness (kind2 201→251 pages); it is preserved and never promoted. Queue attribution measured the retained queue capacity1024→2048 with200-byte elements, exactly50 extra pages; four extended idle snapshots stayed251.'
	lines << 'Initial six attempts, second six attempts, third x86 attempts, diagnostic EACCES experiment, and allocation attribution are preserved in qualification-summary.json. complete records receipt availability; the independent strict evidence checker determines qualification.'
	os.write_file(area + '/qualification-summary.json', json2.encode(Summary{
		complete: complete
		completion_meaning: 'All selected receipt/log files exist; qualification requires the independent strict evidence checker'
		source_path: source
		source_sha256: digest(source)
		manifest_path: manifest
		manifest_sha256: digest(manifest)
		candidate_manifest_path: candidate_manifest
		candidate_manifest_sha256: if os.exists(candidate_manifest) { digest(candidate_manifest) } else { '' }
		candidate_commit: candidate_commit
		integration_commit: integration_commit
		candidate_inputs_sha256: if os.exists(candidate_inputs) { digest(candidate_inputs) } else { '' }
		baseline_inputs_path: baseline_inputs
		baseline_inputs_sha256: digest(baseline_inputs)
		final_runs: final_runs
		second_runs: second_runs
		third_runs: third_runs
		initial_runs: initial_runs
		diagnostic: result('diagnostic-reference-x86')
		queue_attribution: attribution
	}, prettify: true) + '\n')!
	os.write_file(area + '/qualification-summary.md', lines.join('\n') + '\n')!
	println('Qualification summary complete=' + complete.str())
}
