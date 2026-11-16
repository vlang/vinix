// SPDX-License-Identifier: GPL-2.0-or-later
import os
import g13contract

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut options := {'--kind': 'all'}
	mut index := 1
	for index < os.args.len {
		key := os.args[index]
		assert key in ['--asahi-linux', '--kind', '--fw-overlay'] && index + 1 < os.args.len
		options[key] = os.args[index + 1]; index += 2
	}
	assert '--asahi-linux' in options, 'expected --asahi-linux PATH [--kind KIND] [--fw-overlay FILE]'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	reference := os.real_path(options['--asahi-linux'])
	_ = g13contract.check_queue_recovery_reference(reference, repo)!
	microseq := os.read_file(reference + '/drivers/gpu/drm/asahi/fw/microseq.rs')!
	contracts := g13contract.microseq_field_contracts(microseq)!
	attachments := g13contract.microseq_attachment_layout(microseq)!
	mut generated := 'module gpu\nimport gpu.agx.fw\n'
	mut kinds := []string{}
	mut sizes := []string{}
	mut validate := 'fn validate_layouts() {\n\tassert sizeof(fw.G13MicroseqAttachment) == ${attachments.size}\n\tassert sizeof(fw.G13MicroseqAttachments) == ${attachments.list_size}\n'
	for member in attachments.members { validate += '\tassert __offsetof(fw.G13MicroseqAttachment, ${member.native}) == ${member.offset}\n' }
	validate += '\tassert __offsetof(fw.G13MicroseqAttachments, list) == ${attachments.list_offset}\n\tassert __offsetof(fw.G13MicroseqAttachments, count) == ${attachments.count_offset}\n'
	for contract in contracts {
		kinds << contract.kind
		sizes << '\tRecord{"${contract.kind}", ${contract.old_size}, ${contract.new_size}}'
		validate += '\tassert sizeof(fw.G13Microseq${contract.name}) == ${contract.old_size}\n\tassert sizeof(fw.G13Microseq${contract.name}V135) == ${contract.new_size}\n'
		for member in contract.members { validate += '\tassert __offsetof(fw.G13Microseq${contract.name}, ${member.native}) == ${member.offset}, "${contract.name}.${member.name} offset differs"\n' }
		generated += 'fn expected_${contract.kind}(source [0x240]u8, start int, counter u64, notifier u64, flag u64) [0x200]u8 {\n\tmut out := [0x200]u8{}\n'
		for field in contract.fields {
			assert field.old_offset >= 0 && field.old_offset + field.size <= contract.old_size
			assert field.new_offset >= 0 && field.new_offset + field.size <= contract.new_size
			generated += '\tfor i in 0 .. ${field.size} { out[${field.new_offset} + i] = source[start + ${field.old_offset} + i] } // ${field.name}\n'
		}
		for field in contract.insertions {
			assert field.offset >= 0 && field.offset + field.size <= contract.new_size
			if field.name in ['counter', 'notifier_buf', 'unk_flag'] {
				value := if field.name == 'counter' { 'counter' } else if field.name == 'notifier_buf' { 'notifier' } else { 'flag' }
				assert field.size == 8
				generated += '\tfor i in 0 .. 8 { out[${field.offset} + i] = u8(${value} >> (i * 8)) } // ${field.name}\n'
			}
		}
		generated += '\treturn out\n}\n'
		args := match contract.kind {
			'start_vertex', 'start_fragment' { ', counter, notifier' }
			'start_compute' { ', flag, counter, notifier' }
			'finalize_compute' { ', flag' }
			else { '' }
		}
		generated += 'fn convert_${contract.kind}(source voidptr, destination voidptr, counter u64, notifier u64, flag u64) int {\n'
		generated += '\tactual := fw.g13_microseq_${contract.kind}_v13_5(unsafe { &fw.G13Microseq${contract.name}(source) }${args})\n'
		generated += '\tunsafe { C.memcpy(destination, &actual, sizeof(fw.G13Microseq${contract.name}V135)) }\n\treturn sizeof(fw.G13Microseq${contract.name}V135)\n}\n'
	}
	assert options['--kind'] == 'all' || options['--kind'] in kinds
	generated += validate + '}\nconst records = [\n' + sizes.join(',\n') + '\n]\n'
	generated += 'fn expected(kind string, source [0x240]u8, start int, counter u64, notifier u64, flag u64) [0x200]u8 {\n\treturn match kind {\n'
	for kind in kinds { generated += '\t\t"${kind}" { expected_${kind}(source, start, counter, notifier, flag) }\n' }
	generated += '\t\telse { panic("unknown kind") }\n\t}\n}\n'
	generated += 'fn convert(kind string, source voidptr, destination voidptr, counter u64, notifier u64, flag u64) int {\n\treturn match kind {\n'
	for kind in kinds { generated += '\t\t"${kind}" { convert_${kind}(source, destination, counter, notifier, flag) }\n' }
	generated += '\t\telse { panic("unknown kind") }\n\t}\n}\n'
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-microseq-fields-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-microseq-fields/fixture', scratch, false)!
	if overlay := options['--fw-overlay'] {
		os.mkdir_all(scratch + '/gpu/agx')!
		os.cp_all(repo + '/kernel/gpu/agx/fw', scratch + '/gpu/agx/fw', false)!
		os.cp(overlay, scratch + '/gpu/agx/fw/microseq.v')!
	}
	os.write_file(scratch + '/gpu/reference.v', generated)!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.run_checks("${options['--kind']}") }\n')!
	if output := os.getenv_opt('AGX_MICROSEQ_FIELDS_MODEL') { os.write_file(output, generated)! }
	if output := os.getenv_opt('AGX_MICROSEQ_FIELDS_REPORT') { os.write_file(output, g13contract.microseq_field_report(contracts))! }
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals']
	$if arm64 { flags << ['-exclude', repo + '/kernel/klock/klock_amd64.v', '-exclude', repo + '/kernel/katomic/katomic_amd64.v'] }
	$else $if amd64 { flags << ['-exclude', repo + '/kernel/klock/klock_arm64.v', '-exclude', repo + '/kernel/katomic/katomic_arm64.v'] }
	$else { panic('unsupported host architecture') }
	flags << ['-path', '${scratch}|${repo}/kernel|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', scratch + '/test', scratch + '/main.v']
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(flags); build.run(); build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_MICROSEQ_FIELDS_C') {
		assert output.ends_with('.c')
		mut cflags := flags.clone(); cflags[cflags.len - 2] = output
		mut c := os.new_process(os.getenv_opt('V') or { 'v' })
		c.set_args(cflags); c.run(); c.wait()
		if c.code != 0 { exit(c.code) }
	}
	if output := os.getenv_opt('AGX_MICROSEQ_FIELDS_BINARY') { os.cp(scratch + '/test', output)! }
	mut check := os.new_process(scratch + '/test')
	check.run(); check.wait(); exit(check.code)
}
