// SPDX-License-Identifier: GPL-2.0-or-later
import os
import g13contract

fn section(source string, start string, end string) string {
	begin := source.index(start) or { panic(start) }
	finish := source.index_after(end, begin) or { panic(end) }
	return source[begin..finish]
}

fn main() {
	mut options := map[string]string{}
	for i := 1; i < os.args.len; i += 2 { assert i + 1 < os.args.len && os.args[i] in ['--asahi-linux', '--native-source']; options[os.args[i]] = os.args[i + 1] }
	assert '--asahi-linux' in options
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	base := options['--asahi-linux'] + '/drivers/gpu/drm/asahi/fw/'
	microseq := os.read_file(base + 'microseq.rs')!
	pair := g13contract.timestamp_pair_model(microseq, os.read_file(base + 'vertex.rs')!, os.read_file(base + 'fragment.rs')!, os.read_file(base + 'compute.rs')!, os.read_file(base + 'job.rs')!)!
	native := os.read_file(options['--native-source'] or { repo + '/kernel/gpu/agx/gpu/g13.v' })!
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-timestamp-inputs-${os.getpid()}')
	os.mkdir_all(scratch + '/gpu')!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp(repo + '/tests/agx-timestamp-inputs/check.v', scratch + '/gpu/check.v')!
	mut generated := 'module gpu\nimport gpu.agx.fw\nimport gpu.agx.hw\n' + section(native, 'fn write_g13_timestamp_pair(', 'fn write_g13_timestamp(')
	generated += 'fn render_sizes(legacy bool, v13_5 bool, vertex_user_timestamps [2]u64, fragment_user_timestamps [2]u64) [2]u64 {\ninput := Input{legacy}\n' + section(native, 'vertex_timestamps :=', 'job.vertex_microsequence =') + 'return [vertex_microsequence_size, fragment_microsequence_size]!\n}\n'
	generated += 'fn compute_size(legacy bool, v13_5 bool, user_timestamps [2]u64) u64 {\ninput := Input{legacy}\n' + section(native, 'compute_timestamps :=', 'job.explicit_barriers.offset = g13_barrier_tail_offset(logical_microsequence_size)') + 'return logical_microsequence_size\n}\n'
	generated += g13contract.timestamp_input_sizes_v(microseq, pair)!
	generated += 'const reference_offsets = [\n'
	for kind in ['vertex', 'fragment', 'compute'] {
		for command in pair.commands { if command.kind == kind { generated += '[int(${command.old_user}), ${command.new_user}]!,\n' } }
	}
	generated += ']\n'
	for kind in ['vertex', 'fragment', 'compute'] {
		command := if kind == 'compute' { 'command' } else { kind }
		mut calls := []string{}
		for line in native.split_into_lines() { if line.trim_space().starts_with('write_g13_timestamp_pair(') && line.contains('job.' + command + '.cpu_address()') { calls << line } }
		assert calls.len == 1
		generated += 'fn populate_${kind}(data voidptr, modern bool, pair [2]u64) {\nabi := if modern { hw.FirmwareAbi.v13_5_partial } else { hw.FirmwareAbi.v12_3 }\n'
		generated += 'job := Job{Buffer{u64(data)}, Buffer{u64(data)}, Buffer{u64(data)}}\n'
		generated += '${kind}_user_ts_offset := fw.g13_timestamp_user_ts_offset_for(abi, fw.g13_useq_pipe_${kind}) or { panic("offset") }\n'
		generated += (if kind == 'compute' { 'user_timestamps' } else { kind + '_user_timestamps' }) + ' := pair\n' + calls[0] + '\n}\n'
	}
	os.write_file(scratch + '/gpu/production.v', generated)!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.run_checks() }\n')!
	if output := os.getenv_opt('AGX_TIMESTAMP_INPUT_MODEL') { os.write_file(output, generated)! }
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-path', scratch + '|' + repo + '/kernel|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined', '-o', scratch + '/test', scratch + '/main.v']
	mut build := os.new_process(os.getenv_opt('V') or { 'v' }); build.set_args(flags); build.run(); build.wait(); if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_TIMESTAMP_INPUT_BINARY') { os.cp(scratch + '/test', output)! }
	if output := os.getenv_opt('AGX_TIMESTAMP_INPUT_C') { flags[flags.len - 2] = output; mut c := os.new_process(os.getenv_opt('V') or { 'v' }); c.set_args(flags); c.run(); c.wait(); if c.code != 0 { exit(c.code) } }
	mut check := os.new_process(scratch + '/test'); check.run(); check.wait(); exit(check.code)
}
