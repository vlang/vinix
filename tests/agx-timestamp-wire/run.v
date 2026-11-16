// SPDX-License-Identifier: GPL-2.0-or-later
import os
import g13contract

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut options := map[string]string{}
	mut index := 1
	for index < os.args.len {
		key := os.args[index]
		assert key in ['--asahi-linux', '--native-source'] && index + 1 < os.args.len, 'expected --asahi-linux PATH [--native-source PATH]'
		options[key] = os.args[index + 1]; index += 2
	}
	assert '--asahi-linux' in options
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	reference := os.real_path(options['--asahi-linux'])
	_ = g13contract.check_queue_recovery_reference(reference, repo)!
	base := reference + '/drivers/gpu/drm/asahi/fw/'
	model := g13contract.timestamp_pair_model(os.read_file(base + 'microseq.rs')!, os.read_file(base + 'vertex.rs')!,
		os.read_file(base + 'fragment.rs')!, os.read_file(base + 'compute.rs')!, os.read_file(base + 'job.rs')!)!
	native := os.read_file(options['--native-source'] or { repo + '/kernel/gpu/agx/gpu/g13.v' })!
	writer_start := native.index('fn write_g13_timestamp(') or { panic('missing writer') }
	writer_end := native.index_after('fn write_g13_start_vertex(', writer_start) or { panic('missing writer end') }
	mut generated := 'module gpu\nimport gpu.agx.fw\nimport gpu.agx.hw\n' + native[writer_start..writer_end]
	mut cases := []string{}
	for command in model.commands {
		kind := command.kind
		names := if kind == 'compute' { ['start_timestamp', 'end_timestamp'] } else { [kind + '_ts_start', kind + '_ts_end'] }
		for phase, name in names {
			start := native.index(name + ' := fw.G13MicroseqTimestamp{') or { panic('missing initializer') }
			end := native.index_after('\n\t\t\t}', start) or { panic('missing initializer end') }
			initializer := native[start..end + '\n\t\t\t}'.len]
			generated += 'fn encode_${name}(sample Sample, v13_5 bool, destination voidptr) u64 {\n'
			generated += '\tabi := if v13_5 { hw.FirmwareAbi.v13_5_partial } else { hw.FirmwareAbi.v12_3 }\n'
			generated += if kind == 'compute' { '\tjob := ComputeJob{Buffer{sample.command}}\n' }
				else { '\tjob := RenderJob{Buffer{sample.command}, Buffer{sample.command}}\n' }
			generated += '\t${kind}_queue := Queue{Buffer{sample.queue}}\n\tinput := Input{sample.uuid, sample.uuid, sample.uuid}\n'
			for field in ['cur_ts', 'start_ts', 'end_ts'] {
				generated += '\t${kind}_${field}_offset := fw.g13_${kind}_${field}_offset_for(abi) or { panic("unsupported ABI") }\n'
			}
			generated += '\t${kind}_user_ts_offset := fw.g13_timestamp_user_ts_offset_for(abi, fw.g13_useq_pipe_${kind}) or { panic("unsupported ABI/pipe") }\n'
			generated += '\t' + initializer + '\n'
			generated += '\treturn write_g13_timestamp(destination, v13_5, &${name}, sample.command + u64(${command.scratch}))\n}\n'
			cases << '\tReference{"${kind}", ${phase == 1}, ${command.old_time}, ${command.new_time}, ${command.old_kernel}, ${command.new_kernel}, ${command.old_user}, ${command.new_user}, ${command.scratch}}'
		}
	}
	generated += 'const references = [\n' + cases.join(',\n') + '\n]\n'
	generated += 'fn encode(index int, sample Sample, v13_5 bool, destination voidptr) u64 {\n\treturn match index {\n'
	mut case_index := 0
	for command in model.commands {
		names := if command.kind == 'compute' { ['start_timestamp', 'end_timestamp'] } else { [command.kind + '_ts_start', command.kind + '_ts_end'] }
		for name in names { generated += '\t\t${case_index} { encode_${name}(sample, v13_5, destination) }\n'; case_index++ }
	}
	generated += '\t\telse { panic("invalid initializer") }\n\t}\n}\n'
	generated += 'const old_size = ${model.old_size}\nconst new_size = ${model.new_size}\n'
	generated += 'fn expected_image(reference Reference, sample Sample, modern bool) [0x3c]u8 {\n\tmut out := [0x3c]u8{}\n'
	for field in model.fields {
		value := match field.name {
			'header' { 'u64(0x19) | if reference.end { u64(0) } else { u64(1) << 31 }' }
			'command_time' { 'sample.command + u64(if modern { reference.new_time } else { reference.old_time })' }
			'ts_pointers' { 'sample.command + u64(if modern { reference.new_kernel } else { reference.old_kernel })' }
			'update_ts' { 'sample.command + u64(if modern { reference.new_kernel } else { reference.old_kernel }) + if reference.end { u64(8) } else { u64(0) }' }
			'work_queue' { 'sample.queue' }
			'user_ts_pointers' { 'sample.command + u64(if modern { reference.new_user } else { reference.old_user })' }
			'unk_ts' { 'sample.command + u64(reference.scratch)' }
			'uuid' { 'u64(sample.uuid)' }
			'unk_30_padding' { 'u64(0)' }
			else { panic('unknown timestamp field ' + field.name) }
		}
		generated += if field.old_offset < 0 { '\tif modern { put(mut out, ${field.new_offset}, ${field.size}, ${value}) }\n' }
			else { '\tput(mut out, if modern { ${field.new_offset} } else { ${field.old_offset} }, ${field.size}, ${value})\n' }
	}
	generated += '\treturn out\n}\n'
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-timestamp-wire-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-timestamp-wire/fixture', scratch, false)!
	os.write_file(scratch + '/gpu/native.v', generated)!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.run_checks() }\n')!
	if output := os.getenv_opt('AGX_TIMESTAMP_WIRE_MODEL') { os.write_file(output, generated)! }
	if output := os.getenv_opt('AGX_TIMESTAMP_WIRE_REPORT') { os.write_file(output, g13contract.timestamp_pair_report(model))! }
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals']
	$if arm64 { flags << ['-exclude', repo + '/kernel/klock/klock_amd64.v', '-exclude', repo + '/kernel/katomic/katomic_amd64.v'] }
	$else $if amd64 { flags << ['-exclude', repo + '/kernel/klock/klock_arm64.v', '-exclude', repo + '/kernel/katomic/katomic_arm64.v'] }
	$else { panic('unsupported host architecture') }
	flags << ['-path', '${scratch}|${repo}/kernel|@vlib|@vmodules',
		'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined',
		'-o', scratch + '/test', scratch + '/main.v']
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(flags); build.run(); build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_TIMESTAMP_WIRE_C') {
		assert output.ends_with('.c')
		mut cflags := flags.clone(); cflags[cflags.len - 2] = output
		mut c := os.new_process(os.getenv_opt('V') or { 'v' })
		c.set_args(cflags); c.run(); c.wait()
		if c.code != 0 { exit(c.code) }
	}
	if output := os.getenv_opt('AGX_TIMESTAMP_WIRE_BINARY') { os.cp(scratch + '/test', output)! }
	mut check := os.new_process(scratch + '/test')
	check.run(); check.wait(); exit(check.code)
}
