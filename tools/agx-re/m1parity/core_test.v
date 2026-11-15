// SPDX-License-Identifier: GPL-2.0-or-later
module m1parity

import os

fn test_constant_readers_ignore_spoofs_and_reject_unknowns() {
	source := '/* pub const target = 999 */\n// pub const target = 100\npub const target = u32(0x40) + 2 // measured\n'
	assert expression(declaration(source, 'target', false)!, map[string]u64{}, 0)! == 66
	assert declaration("const text = '\npub const target = 999\n'\npub const target = 2", 'target', false)! == '2'
	assert expression('1L << 2 + 1', map[string]u64{}, 0)! == 8
	assert expression('(0xFFFFu)', map[string]u64{}, 0)! == 65535
	assert declaration("pub(crate) const LIMIT: u32 = 64;\nfn f(_: X<'_>) {}", 'LIMIT', true)! == '64'
	assert define_value('/* #define VALUE 9 */\n#define VALUE (1UL << 3)', 'VALUE')! == 8
	for invalid in ['mystery(2)', 'MISSING', '(1', '1)', '1 << 64', '0xffffffffffffffff + 1',
		'u16(65536)', 'u32(0x100000000)', ''] {
		if _ := expression(invalid, map[string]u64{}, 0) {
			assert false, 'accepted ${invalid}'
		}
	}
	if _ := declaration(source + '\npub const target = 2', 'target', false) {
		assert false
	}
	if _ := declaration('// const absent = 2', 'absent', false) {
		assert false
	}
	if _ := uncomment('/* never closed', false) {
		assert false
	}
	if _ := uncomment('r#"raw string"#', true) {
		assert false
	}
	if _ := declaration('pub const target = \npub const target = 2', 'target', false) {
		assert false
	}
}

fn test_enum_reader_handles_implicit_values_and_rejects_unsupported_entries() {
	values := enum_values('enum sample { FIRST = 0, SECOND, THIRD = (1L << 4), FOURTH, };', 'sample')!
	assert values == {
		'FIRST':  u64(0)
		'SECOND': 1
		'THIRD':  16
		'FOURTH': 17
	}
	for invalid in ['enum sample { FIRST, FIRST };', 'enum sample { X = call() };',
		'enum sample { X = 0xffffffffffffffff };', 'enum sample { };'] {
		if _ := enum_values(invalid, 'sample') {
			assert false, 'unsupported enum accepted'
		}
	}
}

fn test_scalar_layout_models_padding_and_fails_on_unknown_fields() {
	c := layout('struct sample { __u32 a; __u64 b; __u16 c; };', 'sample', true)!
	v := layout('pub struct Sample {\npub mut:\na u32\nb u64\nc u16\n}', 'Sample', false)!
	assert c == v && c.size == 24
	assert c.fields[1].offset == 8 && c.fields[2].offset == 16
	for invalid in ['struct sample { __u32 a[2]; };', 'struct sample { mystery a; };',
		'struct sample { __u32 a, b; };', 'struct sample { union { __u32 a; }; };',
		'struct sample { __u32 a; } __packed;', 'struct sample { __u32 a; __u32 a; };'] {
		if _ := layout(invalid, 'sample', true) {
			assert false, 'unknown layout accepted'
		}
	}
	if _ := layout('@[packed]\npub struct Sample {\na u32\n}', 'Sample', false) {
		assert false
	}
	if _ := layout('struct sample { __u32 a; }; struct sample { __u64 a; };', 'sample', true) {
		assert false
	}
}

fn abi_fixture() (string, string) {
	mut local := 'pub const drm_asahi_base = u32(0x40)\n'
	mut reference := 'enum drm_asahi_ioctl_id {\n'
	for index, name in ['get_params', 'get_time', 'vm_create', 'vm_destroy', 'vm_bind', 'gem_create',
		'gem_mmap_offset', 'gem_bind_object', 'queue_create', 'queue_destroy', 'submit', 'gem_madvise'] {
		reference += 'DRM_ASAHI_${name.to_upper()} = ${index},\n'
		local += 'pub const drm_asahi_${name} = drm_asahi_base + u32(${index})\n'
	}
	reference += '}\n#define DRM_ASAHI_BARRIER_NONE (0xFFFFu)\nenum drm_asahi_bind_flags { DRM_ASAHI_BIND_READ = (1L << 1), DRM_ASAHI_BIND_WRITE = (1L << 2) };\n'
	local += 'pub const asahi_barrier_none = u32(0xFFFF)\npub const asahi_bind_read = u32(1) << 1\npub const asahi_bind_write = u32(1) << 2\n'
	for names in [['DrmAsahiGetParams', 'drm_asahi_get_params'],
		['DrmAsahiSubmit', 'drm_asahi_submit'], ['DrmAsahiGemBind', 'drm_asahi_vm_bind']] {
		local += 'pub struct ${names[0]} {\npub mut:\nfirst u32\nsecond u64\n}\n'
		reference += 'struct ${names[1]} { __u32 first; __u64 second; };\n'
	}
	return local, reference
}

fn test_audit_distinguishes_equal_facts_mismatch_and_unreadable_source() {
	local, reference := abi_fixture()
	submission := 'pub const max_commands = u32(64)'
	file := 'pub(crate) const MAX_COMMANDS_PER_SUBMISSION: u32 = 64;'
	matching := compare_abi(local, reference, submission, file)!
	assert matching.len == 17 && matching.all(it.matches)
	assert Report{ comparisons: matching }.exit_code() == 1, 'partial matching facts cannot certify whole parity'
	assert !Report{}.full_parity_certified && !Report{}.native_gpu_executed
	changed := compare_abi(local.replace('asahi_barrier_none = u32(0xFFFF)',
		'asahi_barrier_none = u32(0xffffffff)'), reference, submission, file)!
	assert changed.filter(!it.matches).len == 1
	assert changed.filter(!it.matches)[0].area == 'no-barrier sentinel'
	if _ := compare_abi(local, reference.replace('DRM_ASAHI_SUBMIT', 'REMOVED'), submission, file) {
		assert false
	}
	if _ := compare_abi(local, reference, 'pub const max_commands = unknown()', file) {
		assert false
	}
	assert Report{ protocol_gates: [Gate{ name: 'changed reference', error: 'not checked' }] }.exit_code() == 2
}

fn test_package_pin_and_retention_refuse_unbound_or_overwritten_evidence() {
	pin := 'a'.repeat(40)
	assert package_pin('# _commit=comment\n_commit=${pin}\n')! == pin
	for invalid in ['_commit=branch', '_commit=${pin}\n_commit=${pin}', '_commit="${pin}"'] {
		if _ := package_pin(invalid) {
			assert false
		}
	}
	root := os.join_path(os.temp_dir(), 'vinix-m1parity-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or { panic(err) } }
	inputs := Inputs{
		vinix:    '${root}/vinix'
		asahi:    '${root}/asahi'
		packages: '${root}/packages'
		omarchy:  '${root}/omarchy'
		m1n1:     '${root}/m1n1'
	}
	os.mkdir_all(inputs.vinix)!
	os.write_file('${inputs.vinix}/input.v', 'original')!
	report := Report{ sources: [Source{ role: 'vinix', path: 'input.v', sha256: hash_file('${inputs.vinix}/input.v')! }] }
	retain(inputs, report, '${root}/bundle')!
	assert os.read_file('${root}/bundle/source/vinix/input.v')! == 'original'
	if _ := retain(inputs, report, '${root}/bundle') {
		assert false
	}
	if _ := retain(inputs, report, '${inputs.vinix}/forbidden') {
		assert false
	}
	os.write_file('${inputs.vinix}/input.v', 'changed')!
	if _ := retain(inputs, report, '${root}/changed-bundle') {
		assert false
	}
}

fn test_reference_inputs_must_be_clean() {
	root := os.join_path(os.temp_dir(), 'vinix-m1parity-git-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or { panic(err) } }
	git(root, ['init', '-q'])!
	os.write_file('${root}/input.v', 'original')!
	git(root, ['add', 'input.v'])!
	git(root, ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c',
		'commit.gpgsign=false', 'commit', '-q', '-m', 'reference fixture'])!
	require_clean(root, ['input.v'])!
	os.write_file('${root}/input.v', 'modified')!
	if _ := require_clean(root, ['input.v']) {
		assert false, 'dirty reference accepted'
	}
}

fn test_scheduler_c_inputs_are_hashed_and_retained() {
	root := os.join_path(os.temp_dir(), 'vinix-m1parity-scheduler-${os.getpid()}')
	os.mkdir_all('${root}/asahi')!
	defer { os.rmdir_all(root) or { panic(err) } }
	os.write_file('${root}/asahi/sched_entity.c', 'dependency source fixture')!
	mut sources := []Source{}
	snapshot('asahi', '${root}/asahi', 'sched_entity.c', mut sources)!
	assert sources.len == 1 && sources[0].sha256 == hash_file('${root}/asahi/sched_entity.c')!
	inputs := Inputs{ asahi: '${root}/asahi', vinix: '${root}/vinix', packages: '${root}/packages',
		omarchy: '${root}/omarchy', m1n1: '${root}/m1n1' }
	retain(inputs, Report{ sources: sources }, '${root}/evidence')!
	assert os.read_file('${root}/evidence/source/asahi/sched_entity.c')! == 'dependency source fixture'
}
