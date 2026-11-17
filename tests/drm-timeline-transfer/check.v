// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn body(source string, name string) string {
	for line in source.split_into_lines() {
		if line == '' || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') { continue }
		start := source.index(line) or { panic(name) }
		end := source.index_after('\n}\n', start) or { panic(name) }
		return source[start..end + 3]
	}
	panic('missing C function ' + name)
}

fn normalize(source string) string {
	mut out := []u8{cap: source.len}
	mut index := 0
	for index < source.len {
		if source[index..].starts_with('__discard_') && index + 10 < source.len && source[index + 10].is_digit() {
			mut end := index + 10
			for end < source.len && source[end].is_digit() { end++ }
			assert source[end] == `_`
			out << '__discard_PATH'.bytes(); index = end
		} else { out << source[index]; index++ }
	}
	return out.bytestr()
}

fn ordered(source string, tokens []string) {
	mut offset := 0
	for token in tokens { offset = (source.index_after(token, offset) or { panic(token) }) + token.len }
}

fn no_hidden(source string, names []string) {
	for name in names {
		code := body(source, name)
		for token in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_', 'array_clone(', 'string__substr(', 'int__str(', 'u64__str('] {
			assert !code.contains(token), name + ': hidden allocation ' + token
		}
	}
}

fn main() {
	assert os.args.len == 3
	for arch in ['aarch64', 'x86_64'] {
		old := os.read_file(os.args[1] + '/blob-' + arch + '.c')!
		assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' { 'f37d8a02b498f354cb246b65ebe9e2027b724e6311790245d7c1e062109bdb6d' } else { 'f179d4110e7c05234285c8656765ae8767732159ec183e3c125249ae76594e55' }
		current := os.read_file(os.args[2] + '/blob-' + arch + '.c')!
		no_hidden(current, ['syncobj__unwrap_merge', 'syncobj__new_merge_array', 'syncobj__merge_stub', 'syncobj__merge_before', 'syncobj__merge_sift',
			'syncobj__merge_dedup', 'syncobj__unwrap_first', 'syncobj__unwrap_next', 'syncobj__array_ready', 'syncobj__array_leaf_ready',
			'syncobj__array_child_complete', 'syncobj__complete_array', 'syncobj__enable_array', 'syncobj__release_merge_reservation',
			'drm__ioctl_syncobj_transfer', 'drm__sync_file_info_ioctl', 'syncobj__chain_previous', 'syncobj__chain_prefix_ready',
			'syncobj__DmaFence__notify_chains_locked', 'syncobj__drain_chain_notifications', 'katomic__cas_T_i64', 'katomic__load_T_i64', 'katomic__dec_T_u32'])
		assert body(current, 'syncobj__unwrap_merge').count('memory__malloc_packed_fallible(') == 1
		assert body(current, 'syncobj__new_merge_array').count('memory__malloc_packed_fallible(') == 1
		ordered(body(current, 'drm__ioctl_syncobj_transfer'), ['syncobj__unwrap_merge(', 'syncobj__reserve_chain()', 'syncobj__release_merge_reservation(', 'syncobj__add_chain_point('])
		assert body(current, 'syncobj__complete_array').contains('katomic__load_T_i64(&f->array_error)')
		assert body(current, 'syncobj__array_child_complete').contains('katomic__cas_T_i64(&f->array_error,')
		if arch == 'aarch64' { assert body(current, 'katomic__load_T_i64').contains('vinix_ldar64') }
		ordered(body(current, 'syncobj__initialize_chain'), ['if (payload->merge_reserved)', 'payload->merge_reserved = false', 'syncobj__register_chain_waiter('])
		ordered(body(current, 'syncobj__add_chain_point'), ['klock__Lock__release(&o->lock)', 'syncobj__drain_chain_notifications()'])
		for name in ['drm__find_syncobj_fence', 'drm__ioctl_syncobj_wait', 'drm__ioctl_syncobj_query', 'drm__ioctl_syncobj_timeline_wait',
			'drm__ioctl_syncobj_timeline_signal', 'syncobj__snapshot', 'syncobj__prepare_timeline_capture',
			'syncobj__arm_timeline_capture', 'syncobj__captured_timeline_fence', 'syncobj__release_timeline_capture', 'syncobj__find_chain_fence'] {
			assert normalize(body(old, name)) == normalize(body(current, name)), name
		}
		if arch == 'aarch64' { assert normalize(body(old, 'syncobj__get_error')) == normalize(body(current, 'syncobj__get_error')) }
		println(arch + ': merge/array/unwrap/atomic/transfer/info C rejects hidden allocations; two explicit fallible owners and private unwind visible; i64 error CAS/load, conditional reservation handoff and drain-after-unlock verified; eleven shared lookup/wait/query/signal/capture bodies match baseline, plus ARM error getter (old x86 pruned).')
	}
}
