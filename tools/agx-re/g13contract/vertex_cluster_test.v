// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import os

fn test_vertex_cluster_marker_requires_single_cluster_version_and_shifted_wire_field() {
	repo := os.real_path(os.join_path(os.dir(@FILE), '../../..'))
	local := read(repo + '/kernel/gpu/agx/gpu/g13.v')!
	microseq := read(repo + '/kernel/gpu/agx/fw/microseq.v')!
	check_vertex_cluster_local(local, microseq)!
	for token in ['mgr.hw_config.num_clusters != 1', 'unk_178: if v13_5 { u32(1) } else { u32(0) }', 'unsafe { voidptr(&value) }', 'unsafe { &vertex_start }'] {
		if _ := check_vertex_cluster_local(local.replace(token, ''), microseq) { assert false, token }
	}
	if _ := check_vertex_cluster_local(local.replace('if v13_5 { u32(1) } else { u32(0) }', 'u32(1)'), microseq) { assert false }
	if _ := check_vertex_cluster_local(local, microseq.replace('0x188, voidptr(legacy), 0x178, 4)', '0x178, voidptr(legacy), 0x178, 4)')) { assert false }
}

fn test_vertex_cluster_reference_requires_versioned_zero_and_inverse_clustering() {
	render := 'let nclusters = gpu.get_dyncfg().id.num_clusters; let mut clustering = nclusters > 1; clustering = false; ' +
		'builder.add(microseq::StartVertex::ver { #[ver(V < V13_0B4)] unk_178: 0x0, #[ver(V >= V13_0B4)] unk_178: (!clustering) as u32,'
	record := 'pub(crate) struct StartVertex pub(crate) padding: u32, #[ver(V >= V13_0B4)] pub(crate) counter: U64, ' +
		"#[ver(V >= V13_0B4)] pub(crate) notifier_buf: pointer, pub(crate) unk_178: u32, impl<'a> Operation for StartVertex"
	check_vertex_cluster_reference(render, record)!
	for token in ['nclusters > 1', '#[ver(V < V13_0B4)]', '(!clustering) as u32'] {
		if _ := check_vertex_cluster_reference(render.replace(token, ''), record) { assert false, token }
	}
	if _ := check_vertex_cluster_reference(render, record.replace('pub(crate) counter: U64,', '')) { assert false }
}
