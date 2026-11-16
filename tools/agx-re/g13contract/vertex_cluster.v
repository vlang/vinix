// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_vertex_cluster_local(local string, microseq string) ! {
	prepare := section(local, 'pub fn (mut mgr GpuManager) prepare_g13_render_job(',
		'fn (mut mgr GpuManager) publish_g13_render_job_locked(', 'Native single-cluster vertex start')!
	require_order(prepare, ['mgr.hw_config.num_clusters != 1', 'return none',
		'v13_5 :=', 'vertex_start := fw.G13MicroseqStartVertex{',
		'unk_178: if v13_5 { u32(1) } else { u32(0) }',
		'write_g13_start_vertex(', 'v13_5, unsafe { &vertex_start }'], 'Native versioned non-clustered marker')!
	writer := section(local, 'fn write_g13_start_vertex(', 'fn write_g13_finalize_vertex(', 'Native vertex writer')!
	require_order(writer, ['if v13_5 {', 'fw.g13_microseq_start_vertex_v13_5(',
		'value_ptr := unsafe { voidptr(&value) }', 'C.memcpy(destination, value_ptr, sizeof(fw.G13MicroseqStartVertexV135))',
		'C.memcpy(destination, legacy, sizeof(fw.G13MicroseqStartVertex))'],
		'Native old and new vertex writer')!
	convert := section(microseq, 'pub fn g13_microseq_start_vertex_v13_5(',
		'pub fn g13_microseq_finalize_vertex_v13_5(', 'Native marker translation')!
	require_order(convert, ['0, voidptr(legacy), 0, 0x178)', '0x178, counter)',
		'0x180, event_control_buffer)', '0x188, voidptr(legacy), 0x178, 4)'], 'Native shifted marker')!
}

fn check_vertex_cluster_reference(render string, microseq string) ! {
	require_order(render, ['let nclusters = gpu.get_dyncfg().id.num_clusters;',
		'let mut clustering = nclusters > 1;', 'clustering = false;',
		'builder.add(microseq::StartVertex::ver {', '#[ver(V < V13_0B4)]',
		'unk_178: 0x0,', '#[ver(V >= V13_0B4)]', 'unk_178: (!clustering) as u32,'],
		'Asahi versioned non-clustered vertex marker')!
	record := section(microseq, 'pub(crate) struct StartVertex', "impl<'a> Operation for StartVertex", 'Asahi StartVertex layout')!
	require_order(record, ['pub(crate) padding: u32,', '#[ver(V >= V13_0B4)]',
		'pub(crate) counter: U64,', '#[ver(V >= V13_0B4)]',
		'pub(crate) notifier_buf:', 'pub(crate) unk_178: u32,'], 'Asahi inserted counter and notifier')!
}
