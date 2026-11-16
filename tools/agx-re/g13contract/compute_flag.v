// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

// Normalize only the selected Rust wire records. Packed GPU pointers and
// their optional nonzero form use the source's eight-byte representation.
// Unknown active field types are rejected by the existing layout engine.
fn compute_flag_record(source string, name string) !string {
	marker := 'pub(crate) struct ' + name
	start := source.index(marker) or { return error('missing Rust record ' + name) }
	mut lines := ['struct ' + name + ' {']
	mut fields := 0
	for raw in source[start..].split_into_lines()[1..] {
		line := raw.all_before('//').trim_space()
		if line == '}' { lines << '}'; require(fields > 0, 'empty Rust record ' + name)!; return lines.join('\n') + '\n' }
		if line == '' { continue }
		if line.starts_with('#[ver(') { lines << line; continue }
		require(line.starts_with('pub(crate) ') && line.ends_with(',') && line.contains(':'), 'unrecognized Rust field ' + line)!
		field := line.all_after('pub(crate) ').all_before(':')
		mut kind := line.all_after(':').trim_string_right(',').trim_space()
		if kind.starts_with('GpuPointer<') || kind.starts_with('GpuWeakPointer<')
			|| kind.starts_with('Option<GpuPointer<') || kind.starts_with('Option<GpuWeakPointer<') {
			kind = 'U64'
		} else if kind in ['op::FinalizeCompute', 'workqueue::CommandType', 'EventValue'] {
			kind = 'u32'
		} else { kind = kind.replace('job::raw::', '').replace('::ver', '').replace("<'a>", '') }
		lines << field + ': ' + kind + ','
		fields++
	}
	return error('unterminated Rust record ' + name)
}

fn compute_flag_member(layout g13layout.Layout, name string) !i64 {
	for member in layout.fields { if member.name == name { return member.offset } }
	return error('missing wire field ' + name)
}

fn check_compute_flag_local(local string, microseq string, compute string) ! {
	prepare := section(local, 'pub fn (mut mgr GpuManager) prepare_g13_compute_job(',
		'pub fn (mut mgr GpuManager) release_g13_compute_job(', 'Native compute flag')!
	require_order(prepare, ['write_g13_start_compute(',
		'job.command.va + fw.g13_compute_v13_5_flag_offset, compute_counter,',
		'write_g13_finalize_compute(',
		'v13_5, &finalize, job.command.va + fw.g13_compute_v13_5_flag_offset)'], 'Native shared compute flag')!
	require(prepare.count('job.command.va + fw.g13_compute_v13_5_flag_offset') == 2, 'Native start/finalize must share one flag field')!
	writer := section(local, 'fn write_g13_finalize_compute(', 'struct G13EventResources {', 'Native finalize writer')!
	require_order(writer, ['flag_address u64', 'if v13_5 {',
		'fw.g13_microseq_finalize_compute_v13_5(legacy, flag_address)',
		'sizeof(fw.G13MicroseqFinalizeComputeV135)',
		'C.memcpy(destination, legacy, sizeof(fw.G13MicroseqFinalizeCompute))'], 'Native versioned finalize writer')!
	convert := section(microseq, 'pub fn g13_microseq_finalize_compute_v13_5(',
		'pub fn g13_wait_for_idle_header(', 'Native finalize flag conversion')!
	require_order(convert, ['flag_address u64', '0, voidptr(legacy), 0, 0x18)',
		'0x18, voidptr(legacy), 0x1c, 0x48)', 'g13_put_u64(voidptr(&out), 0x6d, flag_address)', 'return out'], 'Native unaligned finalize flag')!
	require(integer_constant(compute, 'g13_compute_v13_5_flag_offset', 'Native compute flag offset')! == 0x305, 'Native compute flag offset changed')!
}

fn check_compute_flag_reference(queue string, microseq string, compute string, job string,
	object string, event string, types string, workqueue string, local_compute string) ! {
	require(object.contains("#[repr(C, packed(1))]\npub(crate) struct GpuPointer<'a, T: ?Sized>(NonZeroU64, PhantomData<&'a T>);"), 'Asahi strong pointer representation changed')!
	require(object.contains('#[repr(C, packed(1))]\npub(crate) struct GpuWeakPointer<T: ?Sized>(NonZeroU64, PhantomData<*const T>);'), 'Asahi weak pointer representation changed')!
	require(event.contains('#[repr(transparent)]\npub(crate) struct EventValue(u32);'), 'Asahi event representation changed')!
	require(types.contains('#[repr(C, packed(1))]\npub(crate) struct U64(pub(crate) u64);')
		&& types.contains('#[repr(C, packed(1))]\npub(crate) struct U32(pub(crate) u32);'), 'Asahi packed integer representation changed')!
	require(workqueue.contains('#[repr(u32)]\npub(crate) enum CommandType'), 'Asahi command tag representation changed')!
	require(microseq.contains('#[repr(transparent)]\npub(crate) struct OpHeader(u32);')
		&& microseq.contains('simple_op!(FinalizeCompute);'), 'Asahi finalize opcode representation changed')!
	require_order(queue, ['builder.add(microseq::StartCompute::ver {', 'unk_flag: inner_weak_ptr!(ptr, unk_flag)',
		'builder.add(microseq::FinalizeCompute::ver {', 'unk_flag: inner_weak_ptr!(ptr, unk_flag)'], 'Asahi shared start/finalize flag')!
	mut normalized := compute_flag_record(microseq, 'FinalizeCompute')!
	for name in ['JobParameters1', 'JobParameters2', 'RunCompute'] { normalized += compute_flag_record(compute, name)! }
	for name in ['EncoderParams', 'JobMeta', 'TimestampPointers'] { normalized += compute_flag_record(job, name)! }
	defs := g13layout.parse(normalized)!
	old := g13layout.Target{ version: 'V12_3' }
	newer := g13layout.Target{ version: 'V13_5' }
	old_finalize := defs.lay_out('FinalizeCompute', old)!
	new_finalize := defs.lay_out('FinalizeCompute', newer)!
	require(old_finalize.size == 0x64 && new_finalize.size == 0x7c, 'Asahi finalize sizes changed')!
	if _ := compute_flag_member(old_finalize, 'unk_flag') { return error('Asahi old finalize unexpectedly contains flag') }
	require(compute_flag_member(new_finalize, 'unk_flag')! == 0x6d, 'Asahi unaligned finalize flag moved')!
	command := defs.lay_out('RunCompute', newer)!
	flag := compute_flag_member(command, 'unk_flag')!
	require(flag == i64(integer_constant(local_compute, 'g13_compute_v13_5_flag_offset', 'Native compute flag')!), 'Asahi/native compute flag offset mismatch')!
	bound := i64(integer_constant(local_compute, 'g13_compute_v13_5_size', 'Native compute command bound')!)
	require(flag + 4 <= command.size && command.size <= bound, 'Asahi flag exceeds command backing')!
}
