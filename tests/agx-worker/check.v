// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn body(source string, name string) !string {
	for line in source.split_into_lines() {
		if line.len == 0 || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') { continue }
		start := source.index(line) or { return error(name) }
		end := source.index_after('\n}\n', start) or { return error(name) }
		return source[start..end + 3]
	}
	return error('missing C definition: ' + name)
}
fn normalized(source string, name string) !string {
	code := body(source, name)!
	mut strings := map[string]string{}
	for line in source.split_into_lines() {
		if line.starts_with('_SL(_str_') {
			key := line.all_after('_SL(').all_before(','); strings[key] = line.all_after(key + ', ')
		}
	}
	mut out := []u8{}; mut i := 0
	for i < code.len {
		if code[i..].starts_with('__discard_') && i + 10 < code.len && code[i + 10].is_digit() {
			mut end := i + 10; for end < code.len && code[end].is_digit() { end++ }
			require(end < code.len && code[end] == `_`, 'discard-variable path hash')!
			out << '__discard_PATH'.bytes(); i = end
		} else if code[i..].starts_with('_str_') {
			mut end := i + 5; for end < code.len && code[end].is_digit() { end++ }
			key := code[i..end]; require(key in strings, key)!
			out << strings[key].bytes(); i = end
		} else { out << code[i]; i++ }
	}
	return out.bytestr()
}
fn check_workers(source string, prefix string) ! {
	for name in [prefix + 'event_worker', prefix + 'g17_event_worker', 'fake__wait_staged_syncs'] {
		code := body(source, name)!
		require(code.count('sched__reschedule();') == 1 && !code.contains('sched__yield('), 'active worker must have one returning reschedule: ' + name)!
		for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new('] { require(!code.contains(token), 'worker loop introduces no allocation: ' + token)! }
	}
	println('Worker C: three returning reschedule sites and no scheduler-yield or allocation calls in active loops.')
}
fn compare_native(current string, old string) ! {
	prefix := 'gpu__agx__gpu__'
	check_workers(current, prefix)!
	for name in [prefix + 'event_worker', prefix + 'g17_event_worker', 'fake__wait_staged_syncs'] {
		require(normalized(current, name)!.replace('sched__reschedule();', 'sched__yield(false);') == normalized(old, name)!, 'only wait primitive may change: ' + name)!
	}
	for name in ['sched__reschedule', 'syncobj__wait', 'fake__fake_completion_worker',
		prefix + 'GpuManager__shutdown', prefix + 'GpuManager__reap_g13_render_jobs', prefix + 'GpuManager__reap_g13_compute_jobs',
		prefix + 'GpuManager__reap_file_resources', prefix + 'GpuManager__handle_g17_akf_callback',
		prefix + 'GpuManager__dispatch_g17_role_message'] {
		require(normalized(current, name)! == normalized(old, name)!, 'lifetime or service gate changed: ' + name)!
	}
	println('Native worker C: exactly three wait-primitive changes; nine scheduler, fence, termination, service and cleanup bodies match baseline.')
}
fn counts(source string) (map[string]int, []string) {
	mut sites := map[string]int{}; mut totals := []string{}
	for line in source.split_into_lines() {
		if line.starts_with('aarch64: ') || line.starts_with('x86_64: ') { totals << line }
		if line.starts_with('NEW: ') { continue }
		position := line.index('.v:') or { continue }
		tail := line[position + 3..]; space := tail.index(' ') or { continue }
		location := tail[..space].split(':')
		if location.len != 2 || location[0].int() <= 0 || location[1].int() <= 0 { continue }
		sites[line[..position + 2] + ' ' + tail[space + 1..]]++
	}
	assert sites.len > 100 && totals.len == 2; return sites, totals
}
fn main() {
	assert os.args.len in [3, 4]
	source := os.read_file(os.args[2])!
	match os.args[1] {
		'--host' { check_workers(source, 'gpu__')! }
		'--native' { compare_native(source, os.read_file(os.args[3])!)! }
		'--allocations' {
			a, ta := counts(source); b, tb := counts(os.read_file(os.args[3])!)
			require(a == b && ta == tb, 'allocation sites or source graph changed')!
			println('Per-file/per-kind sites and source counts match baseline; existing allowance failures remain.')
		}
		'--selftest' {
			check_workers(source, 'gpu__')!
			for name in ['gpu__event_worker', 'gpu__g17_event_worker', 'fake__wait_staged_syncs'] {
				original := body(source, name)!
				for replacement in ['sched__yield(false);', '', 'malloc(1); sched__reschedule();'] {
					changed := source.replace(original, original.replace('sched__reschedule();', replacement))
					require(changed != source, 'mutation anchor')!
					if _ := check_workers(changed, 'gpu__') { panic('accepted invalid worker C') }
				}
			}
			println('Worker C checker: nine scheduler/progress/allocation mutations rejected.')
		}
		else { panic('usage: check --host|--selftest C or --native|--allocations CURRENT BASELINE') }
	}
}
