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
fn ordered(source string, tokens []string) ! {
	mut cursor := 0
	for token in tokens { cursor = (source.index_after(token, cursor) or { return error(token) }) + token.len }
}
fn normalize(source string, name string) !string {
	mut result := body(source, name)!
	mut constants := map[string]string{}
	for line in source.split_into_lines() {
		if line.starts_with('_SL(_str_') {
			key := line.all_after('_SL(').all_before(',')
			constants[key] = line.all_after(key + ', ')
		}
	}
	mut bytes := []u8{}
	mut i := 0
	for i < result.len {
		if result[i..].starts_with('_str_') {
			mut end := i + 5
			for end < result.len && result[end].is_digit() { end++ }
			key := result[i..end]; require(key in constants, key)!
			bytes << constants[key].bytes(); i = end
		} else { bytes << result[i]; i++ }
	}
	return bytes.bytestr()
}
fn check_poll(source string, prefix string) ! {
	flush := body(source, prefix + 'GpuManager__flush_g13_uat_range')!
	ordered(flush, ['klock__Lock__acquire(&mgr->fwctl_lock)', 'mmu__UatManager__begin_flush(',
		'channel__TxChannel__enqueue_with_token(', 'mmu__UatManager__abort_unpublished_flush(',
		'GpuManager__send_role_message(', 'while (channel__TxChannel__read_pointer(&mgr->channels.fw_ctrl) != token)',
		'timer__get_ns() - started', '1000000000', 'katomic__sync()', 'mmu__UatManager__complete_flush('])!
	require(flush.count('katomic__sync();') == 1 && !flush.contains('sched__yield('), 'exactly one safe poll barrier and no scheduler handoff')!
	require(flush.count('mmu__UatManager__abort_unpublished_flush(') == 1, 'rollback is confined to unpublished enqueue failure')!
	for token in ['malloc(', 'memdup(', 'vcalloc(', 'array_new(', 'IError'] { require(!flush.contains(token), 'poll must not add allocation: ' + token)! }
	println('UAT C: returning bounded barrier poll, token/handoff completion and unpublished-only rollback verified; no allocation or scheduler call.')
}
fn compare_native(current string, old string) ! {
	prefix := 'gpu__agx__gpu__'
	check_poll(current, prefix)!
	name := prefix + 'GpuManager__flush_g13_uat_range'
	after := normalize(current, name)!
	before := normalize(old, name)!
	require(after.replace('katomic__sync();', 'sched__yield(false);') == before,
		'native UAT body must differ only by the wait primitive')!
	for symbol in ['mmu__UatManager__begin_flush', 'mmu__UatManager__complete_flush', 'mmu__UatManager__abort_unpublished_flush',
		'channel__TxChannel__enqueue_with_token', 'channel__TxChannel__read_pointer',
		prefix + 'GpuManager__flush_g13_file_mapping', prefix + 'GpuManager__invalidate_g13_shared_buffer',
		prefix + 'GpuManager__invalidate_g13_driver_buffer', prefix + 'GpuManager__release_shared_buffer_backing',
		prefix + 'GpuManager__flush_g13_fw_cache_locked', prefix + 'GpuManager__collect_g13_heap_garbage_locked'] {
		require(normalize(current, symbol)! == normalize(old, symbol)!, 'ownership gate changed: ' + symbol)!
	}
	println('Native UAT C: only scheduler call changes to barrier; eleven handoff, ring, backing and cache-GC bodies match baseline.')
}
fn allocations(source string) (map[string]int, []string) {
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
	assert sites.len > 100 && totals.len == 2
	return sites, totals
}
fn main() {
	assert os.args.len in [3, 4]
	source := os.read_file(os.args[2])!
	match os.args[1] {
		'--host' { check_poll(source, 'gpu__')! }
		'--native' { compare_native(source, os.read_file(os.args[3])!)! }
		'--allocations' {
			a, ta := allocations(source); b, tb := allocations(os.read_file(os.args[3])!)
			require(a == b && ta == tb, 'allocation sites or source graph changed')!
			println('Per-file/per-kind sites and source counts match baseline; existing allowance failures remain.')
		}
		'--selftest' {
			check_poll(source, 'gpu__')!
			for pair in [['katomic__sync();', 'sched__yield(false);'], [' != token)', ' == token)'],
				['mmu__UatManager__complete_flush(', 'removed_completion('],
				['katomic__sync();', 'malloc(1); katomic__sync();'], ['1000000000', '0']] {
				changed := source.replace(pair[0], pair[1]); require(changed != source, 'mutation anchor')!
				if _ := check_poll(changed, 'gpu__') { panic('accepted invalid UAT polling C') }
			}
			println('UAT C checker: five scheduler/token/handoff/allocation/timeout mutations rejected.')
		}
		else { panic('usage: check --host|--selftest C or --native|--allocations CURRENT BASELINE') }
	}
}
