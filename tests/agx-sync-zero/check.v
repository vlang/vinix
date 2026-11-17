// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn body(source string) string {
	signature := 'multi_return_i64_submission__SyncArray_submission__SyncArray submission__stage_packet_syncs(u64 owner, u64 pointer, u32 in_count, u32 out_count) {'
	start := source.index(signature) or { panic('native stager missing') }
	end := source.index_after('\n}\n', start) or { panic('native stager end missing') }
	return source[start..end + 3]
}

fn matches_at(source string, offset int, prefix string) bool {
	if offset + prefix.len > source.len { return false }
	for index, value in prefix {
		if source[offset + index] != value { return false }
	}
	return true
}

// Same normalization as the existing strict x86 checker: only V-generated
// discard-variable path hashes, never executable statements or other names.
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
	before := body(old)
	after := body(current)
	assert before != after
	assert after.contains('if (timeline && (item.timeline_value != 0))')
	assert after.count('syncobj__get_fence(object)') == 1
	assert after.count('syncobj__get_timeline_fence(object, item.timeline_value)') == 1
	assert after.contains('inputs.fences[v_fixed_index_u64(v_index, 64)] = fence;')
	for forbidden in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_', 'array_clone(',
		'string__substr(', 'int__str(', 'u64__str('] {
		assert !after.contains(forbidden), 'implicit allocation: ' + forbidden
	}
	assert discard_paths(old.replace(before, 'STAGER_BODY')) ==
		discard_paths(current.replace(after, 'STAGER_BODY')), 'unexpected generated C change outside the stager'
	println('Native ARM C: only the modern sync stager changes after discard-path normalization; captured fence is installed and no implicit allocation appears.')
}
