// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn body(source string, name string) string {
	for line in source.split_into_lines() {
		if line == '' || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') {
			continue
		}
		start := source.index(line) or { panic(name) }
		end := source.index_after('\n}\n', start) or { panic(name) }
		return source[start..end + 3]
	}
	panic('missing C body: ' + name)
}

fn ordered(source string, tokens []string) {
	mut position := 0
	for token in tokens {
		position = (source.index_after(token, position) or { panic('missing/out-of-order ' + token) }) + token.len
	}
}

fn matches_at(source string, offset int, prefix string) bool {
	if offset + prefix.len > source.len { return false }
	for index, value in prefix { if source[offset + index] != value { return false } }
	return true
}

fn discard_paths(source string) string {
	mut out := []u8{cap: source.len}
	mut i := 0
	for i < source.len {
		if matches_at(source, i, '__discard_') && i + 10 < source.len && source[i + 10].is_digit() {
			mut end := i + 10
			for end < source.len && source[end].is_digit() { end++ }
			assert source[end] == `_`
			out << '__discard_PATH'.bytes()
			i = end
		} else {
			out << source[i]
			i++
		}
	}
	return out.bytestr()
}

fn main() {
	assert os.args.len == 3, 'usage: check BASELINE_ARM_C CURRENT_ARM_C'
	old := os.read_file(os.args[1])!
	current := os.read_file(os.args[2])!
	mut stripped_old := old
	mut stripped_current := current
	prefix := 'gpu__agx__file__GpuFile__'
	for name in ['create_queue', 'ioctl_queue_create', 'ioctl_modern_queue_create'] {
		before := body(old, prefix + name)
		after := body(current, prefix + name)
		assert before != after
		stripped_old = stripped_old.replace(before, 'QUEUE_BODY_' + name)
		stripped_current = stripped_current.replace(after, 'QUEUE_BODY_' + name)
		if name == 'create_queue' {
			stripped_old = stripped_old.replace(before.all_before(' {') + ';', 'QUEUE_PROTOTYPE;')
			stripped_current = stripped_current.replace(after.all_before(' {') + ';', 'QUEUE_PROTOTYPE;')
		}
		for forbidden in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_', 'array_clone(',
			'string__substr(', 'int__str(', 'u64__str('] {
			assert !after.contains(forbidden), name + ': hidden allocation ' + forbidden
		}
	}
	assert discard_paths(stripped_old) == discard_paths(stripped_current), 'unexpected change outside three constructor bodies and their changed prototype'
	adapter := body(current, prefix + 'ioctl_modern_queue_create')
	assert !adapter.contains('if (') && adapter.contains('data->render_scs_layout')
	queue := body(current, prefix + 'create_queue')
	ordered(queue, ['GpuManager__create_g13_queue_resources(',
		'bool released = gpu__agx__gpu__GpuManager__release_g13_queue_resources(', 'if (!released)',
		'.resources = g13_resources', 'workqueue__WorkQueue__destroy(logical)',
		'workqueue__free_workqueue(logical)', 'if (released)',
		'gpu__agx__gpu__free_g13_queue_record(g13_resources)', '-22;', 'klock__Lock__release(&f->lock)',
		'return ', 'array_push(&f->queues'])
	println('Native ARM C: only three constructor bodies and the helper prototype change; late rollback adopts or releases ownership, destroys logical metadata before G13 disposal, and introduces no hidden allocation.')
}
