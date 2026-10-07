// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout
import os
import strconv

pub fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn quoted(text string) string {
	quote := if text.contains("'") && !text.contains('"') { '"' } else { "'" }
	return quote + text.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(quote, '\\' + quote) + quote
}

pub fn read(path string) !string {
	if !os.is_file(path) { return error('missing reference source: ${path}') }
	return os.read_file(path)
}

pub fn section(source string, start string, end string, label string) !string {
	begin := source.index(start) or { return error('${label}: missing ${quoted(start)}') }
	finish := source.index_after(end, begin + start.len) or { return error('${label}: missing terminator ${quoted(end)}') }
	return source[begin..finish]
}

pub fn require_order(source string, tokens []string, label string) ! {
	mut cursor := 0
	for token in tokens {
		found := source.index_after(token, cursor) or { return error('${label}: missing or out-of-order ${quoted(token)}') }
		cursor = found + token.len
	}
}

fn word(ch u8) bool { return ch.is_letter() || ch.is_digit() || ch == `_` }

pub fn integer_constant(source string, name string, label string) !u64 {
	mut position := 0
	for position < source.len {
		found := source.index_after(name, position) or { break }
		end := found + name.len
		position = end
		if (found > 0 && word(source[found - 1])) || (end < source.len && word(source[end])) {
			continue
		}
		equals := source.index_after('=', end) or { break }
		mut value := source[equals + 1..].trim_left(' \t\r\n')
		if value.starts_with('u64(') { value = value[4..].trim_left(' \t\r\n') }
		if !value.starts_with('0x') { continue }
		mut length := 2
		for length < value.len && (value[length].is_hex_digit() || value[length] == `_`) {
			length++
		}
		if length == 2 { continue }
		return strconv.parse_uint(value[2..length].replace('_', ''), 16, 64)!
	}
	return error('${label}: cannot find numeric constant ${name}')
}

pub fn git_revision(path string) string {
	mut process := os.new_process('git')
	process.set_args(['-C', path, 'rev-parse', '--short=12', 'HEAD'])
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	return if code == 0 { output.trim_space() } else { 'unknown' }
}

pub fn check_m1n1(m1n1 string) ![]string {
	return check_m1n1_at(m1n1, g13layout.repo_root())
}

// The explicit repository argument lets regression fixtures test source drift
// without modifying the production tree or the upstream reference checkout.
pub fn check_m1n1_at(m1n1 string, repo string) ![]string {
	mut results := []string{}
	raw_rs := os.join_path(m1n1, 'rust/src/gpu/raw.rs')
	generated := g13layout.generate(raw_rs)!
	checked_in := read(os.join_path(repo, 'kernel/gpu/agx/fw/g13_initdata_layout.v'))!
	require(generated == checked_in, 'Vinix G13 InitData layout is stale against m1n1')!
	results << 'InitData 12.3/13.5 generated layouts'
	fw_channels := read(os.join_path(m1n1, 'proxyclient/m1n1/fw/agx/channels.py'))!
	normal_state := section(fw_channels, 'class ChannelStateFields', 'class FWControlStateFields', 'm1n1 channels')!
	require_order(normal_state, ['_SIZE = 0x30', 'READ_PTR = 0x00', 'WRITE_PTR = 0x20'], 'm1n1 normal channel state')!
	fwctl_state := section(fw_channels, 'class FWControlStateFields', 'class Channel(', 'm1n1 channels')!
	require_order(fwctl_state, ['_SIZE = 0x20', 'READ_PTR = 0x00', 'WRITE_PTR = 0x10'], 'm1n1 firmware-control channel state')!
	require(fw_channels.contains('[(FWCtlMsg, 0x14, 0x100)]'), 'm1n1 FwCtl ring ABI changed')!
	results << 'channel state offsets and FwCtl ring geometry'
	runtime_channels := read(os.join_path(m1n1, 'proxyclient/m1n1/agx/channels.py'))!
	send_inval := section(runtime_channels, '    def send_inval(self, ctx, addr=0):', 'class GPUEventChannel', 'm1n1 FwCtl')!
	require_order(send_inval, ['msg.addr = addr', 'msg.unk_8 = 0', 'msg.context_id = ctx',
		'msg.unk_10 = 1', 'msg.unk_12 = 2', 'self.send_message(msg)'], 'm1n1 FwCtl invalidate')!
	vinix_channels := read(os.join_path(repo, 'kernel/gpu/agx/fw/channels.v'))!
	vinix_inval := section(vinix_channels, 'pub fn make_g13_fwctl_invalidate', '// Firmware log channel message', 'Vinix FwCtl')!
	require_order(vinix_inval, ['addr: addr', 'slot: slot', 'unk_10: 1', 'unk_12: 2'], 'Vinix FwCtl invalidate')!
	results << 'FwCtl invalidate opcode and handoff-slot message'
	m1n1_initdata := read(os.join_path(m1n1, 'proxyclient/m1n1/agx/initdata.py'))!
	require(m1n1_initdata.contains('initdata.regionA = agx.kshared.new_buf(0x4000, "InitData_RegionA")'), 'm1n1 RegionA allocation contract changed')!
	vinix_gpu := read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!
	require(vinix_gpu.contains('graph.unknown_buffer = mgr.alloc_g13_shared_buffer(0x4000)'), 'Vinix RegionA is no longer firmware-writable shared memory')!
	results << 'firmware-writable InitData RegionA'
	m1n1_initdata_rs := read(os.join_path(m1n1, 'rust/src/gpu/initdata.rs'))!
	vinix_alloc := read(os.join_path(repo, 'kernel/gpu/agx/alloc/alloc.v'))!
	reference_timestamp := integer_constant(m1n1_initdata_rs, 'IOVA_KERN_TIMESTAMP_RANGE_START', 'm1n1 timestamp aperture')!
	vinix_timestamp := integer_constant(vinix_alloc, 'g13_timestamp_start', 'Vinix timestamp aperture')!
	require(reference_timestamp == vinix_timestamp, 'timestamp aperture mismatch: m1n1=0x${reference_timestamp:x}, Vinix=0x${vinix_timestamp:x}')!
	require(vinix_gpu.contains('mmu.uat_unknown_page, alloc.g13_timestamp_start'), 'Vinix no longer publishes the timestamp aperture to HwDataB')!
	results << 'timestamp aperture address and HwDataB publication'
	m1n1_objects := read(os.join_path(m1n1, 'proxyclient/m1n1/agx/object.py'))!
	allocator_start := m1n1_objects.index('class GPUAllocator') or { return error('m1n1 allocator: missing GPUAllocator') }
	allocator := m1n1_objects[allocator_start..]
	free_block := section(allocator, '    def free(self, obj):', '        if self.verbose:', 'm1n1 free')!
	require_order(free_block, ['flags2["AttrIndex"] = MemoryAttr.Shared', 'self.agx.uat.iomap_at',
		'self.agx.uat.flush_dirty()', 'prepare_cacheflush', 'send_inval', 'wait_cacheflush', 'VALID=0',
		'self.agx.uat.flush_dirty()', 'complete_cacheflush'], 'm1n1 cache-safe unmap')!
	vinix_shared := section(vinix_gpu, 'fn (mut mgr GpuManager) invalidate_g13_shared_buffer', 'fn (mut mgr GpuManager) invalidate_g13_driver_buffer', 'Vinix shared-buffer teardown')!
	require_order(vinix_shared, ['reprotect_kernel', 'flush_g13_uat_range',
		'cache_flush_pending = false', 'unmap_shared_buffer', 'flush_g13_uat_range'], 'Vinix shared-buffer teardown')!
	vinix_driver := section(vinix_gpu, 'fn (mut mgr GpuManager) invalidate_g13_driver_buffer', 'fn (mut mgr GpuManager) release_shared_buffer_backing', 'Vinix driver-buffer teardown')!
	require_order(vinix_driver, ['reprotect_driver_buffer_uncached', 'flush_g13_uat_range',
		'complete_driver_buffer_cache_flush', 'unmap_driver_buffer', 'flush_g13_uat_range'], 'Vinix driver-buffer teardown')!
	results << 'retry-safe reprotect/invalidate/unmap/invalidate teardown'
	vinix_channel := read(os.join_path(repo, 'kernel/gpu/agx/channel/channel.v'))!
	enqueue := section(vinix_channel, 'pub fn (mut ch TxChannel) enqueue_with_token', 'pub fn (ch &TxChannel) read_pointer', 'Vinix TX channel')!
	require_order(enqueue, ['C.memcpy', 'katomic.sync()', 'katomic.store(mut write_ptr'], 'Vinix TX channel publication')!
	results << 'TX ring entry barrier before write-pointer publication'
	return results
}

pub fn check_asahi(asahi_linux string) ![]string {
	mmu := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/mmu.rs'))!
	drop := section(mmu, 'impl Drop for KernelMapping', '/// Shared UAT global', 'Asahi MMU')!
	require_order(drop, ['is_cached_noncoherent', 'remap_uncached_and_flush', 'unmap_pages',
		'tlbi_range'], 'Asahi cache-safe unmap')!
	channel := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/channel.rs'))!
	put := section(channel, '    pub(crate) fn put', '    /// Wait for', 'Asahi TX channel')!
	require_order(put, ['self.ring.ring[self.wptr as usize] = *msg', 'mem::sync()', 'T::set_wptr'], 'Asahi TX channel publication')!
	return ['Asahi KernelMapping cache-safe teardown order',
		'Asahi TX ring barrier before write-pointer publication']
}
