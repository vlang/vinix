// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn validation_package() Package {
	return Package{ id: 'editor', version: '123456789.0.999999999', architecture: 'aarch64',
		kind: 'native', name: 'Editor', description: 'd'.repeat(4096), license: 'MIT',
		entrypoint: 'bin/editor', arguments: ['--literal', 'a'.repeat(4096)],
		permissions: ['files', 'display'], associations: ['text/plain'],
		dependencies: [Dependency{ id: 'library', minimum: '0.0.0', before: '999999999.0.0' }],
		files: [Payload{ path: 'bin/editor', executable: true, sha256: 'a'.repeat(64) },
			Payload{ path: 'share/editor/data', sha256: 'b'.repeat(64) }] }
}

fn validation_config() Config {
	return Config{ architecture: 'aarch64', launch_user: 'alex', repositories: [
		Repository{ id: 'offline', url: 'file:///srv/packages', public_key: 'a'.repeat(64) },
		Repository{ id: 'online', url: 'https://example.invalid/packages', public_key: 'b'.repeat(64) }],
		policy: Policy{ allowed: ['editor', 'library'], licenses: ['MIT', 'Explicit license'],
			pins: [Dependency{ id: 'editor', minimum: '1.0.0', before: '999999999.0.0' }] } }
}

fn test_repeated_model_validation_retires_all_scratch_and_preserves_borrowed_inputs() {
	p := validation_package(); config := validation_config()
	p.validate()!; config.validate()!
	for _ in 0 .. 64 {
		$if track_heap ? { C.vinix_heap_begin() }
		p.validate()!; config.validate()!
		$if track_heap ? {
			kept := C.vinix_heap_end(); count := C.vinix_heap_count()
			assert kept == 0 && count == 0, '${kept} bytes / ${count} allocations retained'
		}
	}
	assert p.description == 'd'.repeat(4096) && p.arguments[1] == 'a'.repeat(4096)
	assert p.files[1].path == 'share/editor/data' && p.dependencies[0].minimum == '0.0.0'
	assert config.repositories[0].url == 'file:///srv/packages' && config.policy.licenses[1] == 'Explicit license'
	println('VALIDATION 64 manifest/configuration admissions release all scratch and preserve caller fields PASS')
}

fn test_validation_map_growth_and_deep_parent_checks_retire_scratch() {
	p := validation_package()
	mut files := [p.files[0]]
	mut dependencies := []Dependency{}
	for i in 0 .. 256 { files << Payload{ path: 'share/tree/' + i.str() + '/data', sha256: p.files[0].sha256 } }
	for i in 0 .. 128 { dependencies << Dependency{ id: 'library-' + i.str(), minimum: '1.0.0' } }
	files << Payload{ path: 'x/'.repeat(510) + 'data', sha256: p.files[0].sha256 }
	large := Package{ ...p, dependencies: dependencies, files: files }
	large.validate()!
	mut repositories := []Repository{}
	mut allowed := []string{}
	for i in 0 .. 128 {
		id := 'library-' + i.str(); allowed << id
		repositories << Repository{ id: id, url: 'file:///srv/packages', public_key: p.files[0].sha256 }
	}
	config := Config{ architecture: 'x86_64', repositories: repositories,
		policy: Policy{ allowed: allowed, pins: dependencies, licenses: allowed } }
	for _ in 0 .. 16 {
		$if track_heap ? { C.vinix_heap_begin() }
		large.validate()!; config.validate()!
		$if track_heap ? {
			kept := C.vinix_heap_end(); count := C.vinix_heap_count()
			assert kept == 0 && count == 0, '${kept} bytes / ${count} allocations retained during growth'
		}
	}
	assert large.files.last().path.len == 1024 && large.dependencies.last().id == 'library-127'
	println('VALIDATION growing duplicate maps and 1024-byte nested paths release scratch PASS')
}

fn test_late_validation_failures_release_scratch_and_keep_exact_diagnostics() {
	p := validation_package(); c := validation_config()
	packages := [
		Package{ ...p, dependencies: [p.dependencies[0], p.dependencies[0]] },
		Package{ ...p, files: []Payload{} },
		Package{ ...p, files: [p.files[0], Payload{ ...p.files[1], path: '../escape' }] },
		Package{ ...p, files: [p.files[0], p.files[0]] },
		Package{ ...p, files: [p.files[0], Payload{ ...p.files[1], path: 'bin' }] },
		Package{ ...p, entrypoint: 'bin/missing' },
		Package{ ...p, dependencies: [Dependency{ id: 'library', minimum: '01.2.3' }] },
	]
	messages := ['editor: duplicate dependency ID', 'editor: invalid file count',
		'editor: invalid or duplicate payload path: ../escape', 'editor: invalid or duplicate payload path: bin/editor',
		'editor: file/directory collision: bin/editor', 'editor: executable entrypoint missing from payload', 'invalid version: 01.2.3']
	for i, candidate in packages {
		$if track_heap ? { C.vinix_heap_begin() }
		if _ := candidate.validate() { assert false } else {
			message := err.msg(); assert message == messages[i]
			unsafe { message.free(); err.free() }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); count := C.vinix_heap_count(); assert kept == 0 && count == 0, '${messages[i]}: ${kept} bytes / ${count} allocations' }
	}
	configs := [
		Config{ ...c, repositories: [c.repositories[0], c.repositories[0]] },
		Config{ ...c, repositories: [c.repositories[0], Repository{ ...c.repositories[1], url: 'file:///a/../b' }] },
		Config{ ...c, policy: Policy{ ...c.policy, allowed: ['editor', 'editor'] } },
		Config{ ...c, policy: Policy{ ...c.policy, permissions: ['files', 'files'] } },
		Config{ ...c, policy: Policy{ ...c.policy, licenses: ['MIT', 'MIT'] } },
		Config{ ...c, policy: Policy{ ...c.policy, pins: [c.policy.pins[0], c.policy.pins[0]] } },
		Config{ ...c, policy: Policy{ ...c.policy, pins: [Dependency{ id: 'editor', minimum: '2.0.0', before: '1.0.0' }] } },
	]
	config_messages := ['invalid or duplicate repository: offline', 'invalid or duplicate repository: online',
		'invalid or duplicate organization allowlist entry: editor', 'invalid or duplicate organization permissions entry: files',
		'invalid or duplicate organization licenses entry: MIT', 'duplicate organization version pin: editor', 'empty dependency range for editor']
	for i, candidate in configs {
		$if track_heap ? { C.vinix_heap_begin() }
		if _ := candidate.validate() { assert false } else {
			message := err.msg(); assert message == config_messages[i]
			unsafe { message.free(); err.free() }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); count := C.vinix_heap_count(); assert kept == 0 && count == 0, '${config_messages[i]}: ${kept} bytes / ${count} allocations' }
	}
	p.validate()!; c.validate()!
	println('VALIDATION late manifest/repository/policy rejection releases scratch and preserves diagnostics PASS')
}

fn test_scalar_admission_preserves_byte_domains_and_path_boundaries() {
	for n in 0 .. 256 {
		byte := u8(n); value := [byte].bytestr()
		id := 'a' + value
		assert identifier(id) == ((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [u8(`.`), `-`, `_`])
		assert printable(value, 1) == (byte >= 32 && byte != 127)
		assert digest_valid('a'.repeat(63) + value) == ((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`))
		assert relative_path('a/' + value + '/b') == (byte >= 32 && byte != 127 && byte !in [u8(`/`), `\\`, `.`])
	}
	for accepted in ['a', '.hidden', '...', 'a..b', 'é/文件', 'a b/c', 'x'.repeat(1024)] { assert relative_path(accepted) }
	for refused in ['', '/', '/a', 'a/', 'a//b', '.', '..', 'a/./b', 'a/../b', 'x'.repeat(1025)] { assert !relative_path(refused) }
	assert identifier('a' + 'z'.repeat(127)) && !identifier('a' + 'z'.repeat(128))
	assert !identifier('') && !identifier('A') && !identifier('1a')
	assert !digest_valid('a'.repeat(63)) && !digest_valid('a'.repeat(65))
	assert printable('', 0) && !printable('a', 0)
	println('VALIDATION all 256 byte values and identifier/digest/path boundaries preserve admission PASS')
}

fn test_version_parser_preserves_public_result_and_error_categories() {
	for version in ['0.0.0', '1.2.3', '999999999.999999999.999999999'] {
		$if track_heap ? { C.vinix_heap_begin() }
		parts := version_parts(version)!
		assert parts.len == 3
		if version == '1.2.3' { assert parts[0] == 1 && parts[1] == 2 && parts[2] == 3 }
		if version.starts_with('999') { assert parts[0] == 999999999 && parts[1] == 999999999 && parts[2] == 999999999 }
		unsafe { parts.free() }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 && C.vinix_heap_count() == 0 }
	}
	for version in ['', '1', '1.2', 'x.2', '01.2.3.4', '1.2.3.'] {
		expected := 'version must contain three numeric components: ' + version
		$if track_heap ? { C.vinix_heap_begin() }
		if _ := version_parts(version) { assert false } else {
			message := err.msg(); assert message == expected
			unsafe { message.free(); err.free() }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 && C.vinix_heap_count() == 0 }
	}
	for version in ['.1.2', '1..2', '1.2.', '01.2.3', '1.02.3', '1.2.03', '1000000000.2.3', '-1.2.3', '1.x.3', '1.2.3-beta'] {
		expected := 'invalid version: ' + version
		$if track_heap ? { C.vinix_heap_begin() }
		if _ := version_parts(version) { assert false } else {
			message := err.msg(); assert message == expected
			unsafe { message.free(); err.free() }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 && C.vinix_heap_count() == 0 }
	}
	println('VALIDATION version component ownership, numeric limits and diagnostic precedence PASS')
}
