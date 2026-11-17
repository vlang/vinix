// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

pub fn packet_input_auxiliary_reference(queue string, common string) ! {
	require_order(queue, ['fn build_attachments(', 'if att.flags != 0 || att.pad != 0',
		'let unk_e = 1;', 'let cache_lines = (att.size + 127) >> 7;',
		'address: U64(att.pointer)', 'size: cache_lines.try_into()?', 'unk_e: unk_e as u16'], 'modern attachment input contract')!
	require_order(common, ['fn get_timestamp_object(', 'if timestamp.handle == 0',
		'return Ok(None);', 'let offset = timestamp.offset;', 'offset.checked_add(8)'], 'timestamp null-handle semantics')!
	require_order(queue, ['last_render = nr_commands;', 'last_compute = nr_commands;', 'cmdbuf.rewind();',
		'command_index == last_render,', 'command_index == last_compute,'],
		'Final render and compute commands request a stamp flush')!
}

// Select firmware initializers from the reference, not the native adapter.
// This deliberately small translator refuses expressions it cannot account for.
fn packet_initializer(source string, member string) !string {
	mut found := []string{}
	for line in source.split_into_lines() {
		text := line.all_before('//').trim_space()
		if text.starts_with(member + ': ') {
			found << text[member.len + 2..].trim_string_right(',').trim_space()
		}
	}
	require(found.len == 1, 'ambiguous/missing packet initializer ' + member)!
	return found[0]
}

fn packet_expression(raw string) !string {
	mut text := raw
	if text.starts_with('U64(') || text.starts_with('F32::from_bits(') {
		require(text.ends_with(')'), 'incomplete packet wrapper')!
		text = text.all_after('(')[..text.all_after('(').len - 1]
	}
	text = text.replace(' as u64', '').replace(' as u32', '')
	text = text.replace('cmdbuf.', 'input.').replace('self.usc_exec_base', 'usc')
	text = text.replace('sample_size_B', 'sample_size_b').replace('u32', '')
	if text == '(input.sampler_count) + 1' { return '(u32(input.sampler_count) + u32(1))' }
	if text == 'usc' { return text }
	if text.starts_with('input.') {
		require(text.bytes().all(it.is_letter() || it.is_digit() || it in [`_`, `.`]), 'unsupported packet input expression ' + text)!
		return text
	}
	require(text.len > 0 && (if text.starts_with('0x') { text[2..].bytes().all(it.is_hex_digit()) } else { text.bytes().all(it.is_digit()) }), 'unsupported packet initializer ' + raw)!
	return text
}

fn packet_fields(source string) !map[string]string {
	body := section(source, 'pub struct Command {', '\n}', 'native command fields')!
	mut fields := map[string]string{}
	for line in body.split_into_lines()[1..] {
		parts := line.trim_space().fields()
		if parts.len == 0 || parts[0] == 'pub:' { continue }
		require(parts.len == 2, 'unexpected native command field')!
		fields[parts[0]] = parts[1]
	}
	return fields
}

fn packet_expected(source string, member string) !string {
	return packet_expression(packet_initializer(source, member)!)!
}

fn packet_attachment_field(kind string, name string) bool {
	return if kind == 'compute' { name in ['attachments', 'attachment_count'] }
		else { name in ['vertex_attachments', 'fragment_attachments', 'vertex_attachment_count', 'fragment_attachment_count'] }
}

// Every generation-neutral field must be accounted for, including fields that
// modern Asahi fixes or no longer exposes. A newly added native field fails.
pub fn packet_input_reference_v(compute string, render string, native_compute string,
	native_render string) !string {
	mut out := 'module main\nimport drm.asahi\nimport gpu.agx.compute as agxcompute\nimport gpu.agx.render as agxrender\n'
	for kind in ['compute', 'render'] {
		source := if kind == 'compute' { compute } else { render }
		fields := packet_fields(if kind == 'compute' { native_compute } else { native_render })!
		mut expected := map[string]string{}
		if kind == 'compute' {
			p1 := section(source, 'job_params1 <-', '\n                    }),', 'compute parameters1')!
			p2 := section(source, 'job_params2 <-', '\n                    }),', 'compute parameters2')!
			encoder := section(source, 'encoder_params <-', '\n                    }),', 'compute encoder')!
			for target, member in {'encoder_ptr': 'cdm_ctrl_stream_base', 'usc_base': 'usc_exec_base_cp', 'helper_program': 'helper_program', 'helper_cfg': 'helper_cfg', 'helper_arg': 'helper_arg', 'iogpu_unk_40': 'iogpu_unk_40'} { expected[target] = packet_expected(p1, member)! }
			expected['encoder_end'] = packet_expected(p2, 'cdm_ctrl_stream_end')!
			for name in ['encoder_id', 'unk_mask', 'sampler_array', 'sampler_count', 'sampler_max'] { expected[name] = packet_expected(encoder, name)! }
			require(source.contains('let uuid = 0;') && source.contains('no_preemption: 0,'), 'compute modern defaults')!
			expected['command_id'] = '0'
			expected['flags'] = '0'
		} else {
			p1 := section(source, 'job_params1 <- try_init!(fw::fragment', '\n                    }),', 'fragment parameters1')!
			p2 := section(source, 'job_params2 <- try_init!(fw::fragment', '\n                    }),', 'fragment parameters2')!
			p3 := section(source, 'job_params3 <-', '\n                    }),', 'fragment parameters3')!
			vertex := section(source, 'job_params1 <- try_init!(fw::vertex', 'job_params2 <- try_init!(fw::vertex', 'vertex parameters1')!
			for target, member in {'scissor_array': 'isp_scissor_base', 'depth_bias_array': 'isp_dbias_base', 'visibility_result_buffer': 'isp_oclqry_base', 'fragment_usc_base': 'usc_exec_base_isp', 'fragment_helper_program': 'helper_program', 'fragment_helper_arg': 'helper_arg', 'zls_control': 'zls_ctrl', 'ppp_multisamplectl': 'ppp_multisamplectl', 'depth_dimensions': 'isp_zls_pixels'} { expected[target] = packet_expected(p1, member)! }
			for target, member in {'merge_upper_x': 'isp_merge_upper_x', 'merge_upper_y': 'isp_merge_upper_y', 'store_pipeline': 'eot_usc', 'store_pipeline_bind': 'eot_rsrc_spec', 'fragment_helper_cfg': 'helper_cfg'} { expected[target] = packet_expected(p2, member)! }
			for target, member in {'encoder_ptr': 'vdm_ctrl_stream_base', 'vertex_usc_base': 'usc_exec_base_ta', 'vertex_helper_program': 'helper_program', 'vertex_helper_arg': 'helper_arg'} { expected[target] = packet_expected(vertex, member)! }
			for plane, prefix in {'depth': 'z', 'stencil': 's'} {
				for phase in ['load', 'store', 'partial'] {
					block := if phase == 'partial' { p3 } else { p1 }
					for meta in [false, true] {
						for stride in [false, true] {
							target := plane + (if meta { '_meta' } else { '' }) + '_buffer_' + phase + (if stride { '_stride' } else { '' })
							member := prefix + '_' + phase + (if meta { '_comp' } else { '' }) + (if stride { '_stride' } else { '' })
							expected[target] = packet_expected(block, member)!
						}
					}
				}
			}
			bg := section(p1, '\n                        bg: fw::fragment::raw::BackgroundProgram {', '\n                        },', 'background pipeline')!
			partial_bg := section(p3, '\n                        partial_bg: fw::fragment::raw::BackgroundProgram {', '\n                        },', 'partial background pipeline')!
			for target, block in {'load_pipeline': bg, 'partial_reload_pipeline': partial_bg} {
				expected[target] = packet_expected(block, 'address')!
				expected[target + '_bind'] = packet_expected(block, 'rsrc_spec')!
			}
			require(p3.contains('\n                        partial_eot: fw::fragment::raw::EotProgram::new(\n                            cmdbuf.partial_eot.rsrc_spec,\n                            cmdbuf.partial_eot.usc\n                        )'), 'partial EOT argument order')!
			expected['partial_store_pipeline'] = 'input.partial_eot.usc'
			expected['partial_store_pipeline_bind'] = 'input.partial_eot.rsrc_spec'
			for name in ['sample_size', 'isp_bgobjdepth', 'isp_bgobjvals'] { expected[name] = packet_expected(p3, name)! }
			encoder := section(source, 'encoder_params <-', '\n                    }),', 'fragment encoder')!
			for stage in ['vertex', 'fragment'] {
				for suffix in ['array', 'count', 'max'] { expected[stage + '_sampler_' + suffix] = packet_expected(encoder, 'sampler_' + suffix)! }
			}
			expected['encoder_id'] = packet_expected(encoder, 'encoder_id')!
			require(source.contains('let uuid_3d = 0;') && source.contains('let uuid_ta = 0;') && source.contains('let no_preemption = false;') && source.contains('no_clear_pipeline_textures: 1,') && source.contains('msaa_zs: 0,'), 'render modern defaults')!
			for target in ['vertex_command_id', 'fragment_command_id', 'tib_blocks'] { expected[target] = '0' }
			for target, member in {'framebuffer_width': 'width_px', 'framebuffer_height': 'height_px', 'utile_width': 'utile_width_px', 'utile_height': 'utile_height_px', 'layers': 'layers', 'samples': 'samples', 'ppp_control': 'ppp_ctrl', 'vertex_helper_cfg': 'vertex_helper.cfg'} {
				require(source.contains('cmdbuf.' + member), 'missing geometry input ' + member)!
				expected[target] = 'input.' + member
			}
			require(source.contains('let isp_ctl = 0xc000u32\n            | (cmdbuf.flags & uapi::drm_asahi_render_flags_DRM_ASAHI_RENDER_DBIAS_IS_INT as u32);'), 'ISP control formula')!
			expected['iogpu_unk_214'] = '(u32(0xc000) | (input.flags & asahi.render_dbias_is_int))'
			for flag in ['VERTEX_SCRATCH', 'PROCESS_EMPTY_TILES', 'NO_VERTEX_CLUSTERING'] { require(source.contains('uapi::drm_asahi_render_flags_DRM_ASAHI_RENDER_' + flag), 'missing render flag ' + flag)! }
			expected['flags'] = '(agxrender.no_clear_pipeline_textures | (if input.flags & asahi.render_vertex_scratch != 0 { agxrender.vertex_spills } else { u64(0) }) | (if input.flags & asahi.render_process_empty_tiles != 0 { agxrender.process_empty_tiles } else { u64(0) }) | (if input.flags & asahi.render_no_vertex_clustering != 0 { agxrender.no_vertex_clustering } else { u64(0) }))'
		}
		require(source.contains('flush_stamps: flush_stamps as u32,'), 'flush stamps constructor input')!
		expected['has_result'] = 'false' // modern timestamps are separate object handles
		expected['flush_stamps'] = 'flush'
		input_type := if kind == 'compute' { 'CmdCompute' } else { 'CmdRender' }
		out += 'fn expect_${kind}(actual &agx${kind}.Command, input &asahi.${input_type}, usc u64, flush bool) {\n'
		mut names := fields.keys(); names.sort()
		for name in names {
			if packet_attachment_field(kind, name) { continue }
			require(name in expected, 'unaccounted native packet field ' + kind + '.' + name)!
			type_name := fields[name]
			out += '\tassert actual.${name} == ${type_name}(${expected[name]}), "${kind}.${name}"\n'
		}
		for name in expected.keys() { require(name in fields, 'stale packet field ' + name)! }
		out += '}\n'
	}
	return out
}
