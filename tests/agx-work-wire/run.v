// SPDX-License-Identifier: GPL-2.0-or-later
import os
import g13contract

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut options := {'--kind': 'all'}
	mut index := 1
	for index < os.args.len {
		key := os.args[index]
		assert key in ['--asahi-linux', '--kind', '--fw-overlay'] && index + 1 < os.args.len, 'expected --asahi-linux PATH [--kind all|both|vertex|compute|fragment] [--fw-overlay PATH]'
		options[key] = os.args[index + 1]
		index += 2
	}
	assert '--asahi-linux' in options && options['--kind'] in ['all', 'both', 'vertex', 'compute', 'fragment']
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	reference := os.real_path(options['--asahi-linux'])
	_ = g13contract.check_queue_recovery_reference(reference, repo)!
	base := reference + '/drivers/gpu/drm/asahi/fw/'
	vertex := os.read_file(base + 'vertex.rs')!
	compute := os.read_file(base + 'compute.rs')!
	job := os.read_file(base + 'job.rs')!
	fragment := os.read_file(base + 'fragment.rs')!
	render := os.read_file(reference + '/drivers/gpu/drm/asahi/queue/render.rs')!
	mut contracts := g13contract.work_tail_contracts(vertex, compute, job)!
	contracts << g13contract.fragment_work_contract(fragment, job, render)!
	mut generated := 'module gpu\n'
	for contract in contracts {
		assert contract.old_size < 0x9a0 && contract.new_size < 0x9a0 && contract.counter_offset == 4
		generated += 'const ${contract.kind}_old_size = ${contract.old_size}\nconst ${contract.kind}_new_size = ${contract.new_size}\n'
		generated += 'const ${contract.kind}_fields = [\n'
		for field in contract.fields {
			assert field.old_offset >= 0 && field.old_offset + field.size <= contract.old_size
			assert field.new_offset >= 0 && field.new_offset + field.size <= contract.new_size
			generated += '\t[int(${field.old_offset}), ${field.new_offset}, ${field.size}]!, // ${field.name}\n'
		}
		generated += ']\n'
	}
	generated += 'fn set_reference_defaults(kind string, mut out [0x9a0]u8) {\n'
	for contract in contracts {
		for field in contract.defaults {
			assert field.offset >= 0 && field.size == 8 && field.offset + field.size <= contract.new_size
			generated += '\tif kind == "${contract.kind}" { for i in 0 .. ${field.size} { out[${field.offset} + i] = u8(u64(${field.value}) >> (i * 8)) } } // ${field.name}\n'
		}
	}
	generated += '}\n'
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-work-wire-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-work-wire/fixture', scratch, false)!
	// The expected map always comes from the selected reference. Overlays let
	// the same test reject exact old converter bodies or old record extents.
	if overlay := options['--fw-overlay'] {
		os.mkdir_all(scratch + '/gpu/agx')!
		os.cp_all(repo + '/kernel/gpu/agx/fw', scratch + '/gpu/agx/fw', false)!
		mut copied := 0
		for name in ['vertex.v', 'compute.v', 'fragment.v'] {
			if os.is_file(overlay + '/' + name) {
				os.cp(overlay + '/' + name, scratch + '/gpu/agx/fw/' + name)!
				copied++
			}
		}
		assert copied > 0
	}
	os.write_file(scratch + '/gpu/reference.v', generated)!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.run_checks("${options['--kind']}") }\n')!
	if output := os.getenv_opt('AGX_WORK_WIRE_MODEL') { os.write_file(output, generated)! }
	if output := os.getenv_opt('AGX_WORK_WIRE_REPORT') { os.write_file(output, g13contract.work_tail_report(contracts))! }
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
	if output := os.getenv_opt('AGX_WORK_WIRE_C') {
		assert output.ends_with('.c')
		mut cflags := flags.clone(); cflags[cflags.len - 2] = output
		mut c := os.new_process(os.getenv_opt('V') or { 'v' })
		c.set_args(cflags); c.run(); c.wait()
		if c.code != 0 { exit(c.code) }
	}
	if output := os.getenv_opt('AGX_WORK_WIRE_BINARY') { os.cp(scratch + '/test', output)! }
	mut check := os.new_process(scratch + '/test')
	check.run(); check.wait(); exit(check.code)
}
