// SPDX-License-Identifier: GPL-2.0-only
// Exercise live recovery functions with native fixtures and a real ARM ELF.
import bootstraptest as bt
import encoding.binary
import hosttest
import os
import tarcore
import tarstream

fn runner_function(text string, name string) !string {
	marker := name + '() {\n'
	start := text.index('\n' + marker) or { return error('runner function missing: ' + name) }
	body := text[start + 1..]
	end := body.index('\n}\n') or { return error('unclosed runner function: ' + name) }
	return body[..end + 3]
}

fn fake(root string, name string) ! {
	args := os.args[1..]
	if name == 'compile-init' {
		assert args.len == 2 && args[0] == 'shell'
		bt.write(args[1], 'fixture translation unit', false)!
		if os.getenv('TEST_FAIL_TOOL') == name { exit(23) }
		return
	}
	assert name in ['clang', 'ld.lld']
	index := args.index('-o')
	assert index >= 0 && index + 1 < args.len
	bt.record(root, bt.Event{ builder: name, args: args, init_published: os.exists(root + '/init/init') })!
	bt.write(args[index + 1], 'fixture ' + name, false)!
	if os.getenv('TEST_FAIL_TOOL') == name { exit(23) }
}

fn fixture(root string) !map[string]string {
	os.mkdir_all(root + '/init')!
	for name in ['bin/clang', 'bin/ld.lld', 'build-support/init-aarch64/compile-init'] {
		os.mkdir_all(os.dir(root + '/' + name))!
		os.symlink(os.executable(), root + '/' + name)!
	}
	bt.write(root + '/full.tar', 'full desktop payload', false)!
	text := os.read_file(hosttest.root() + '/scripts/run-aarch64.sh')!
	// Bash is the production boundary; fixture implementations are native V.
	script := 'set -euo pipefail\n' +
		'INIT_DIR="$TEST_INIT_DIR"\nSCRIPT_DIR="$TEST_REPO_DIR"\nINITRAMFS="$TEST_FULL_IMAGE"\n' +
		'INITRAMFS_COMPRESSED=1\nDISK_ROOT_FALLBACK="\${TEST_FALLBACK:-recovery}"\nRECOVERY_DIR=""\nNO_BUILD=1\n' +
		runner_function(text, 'vinix_build_minimal_init')! + '\n' +
		runner_function(text, 'vinix_select_disk_root_payload')! + '\n' +
		'if [ "\${TEST_ACTION:-select}" = build ]; then\n    vinix_build_minimal_init\nelse\n    vinix_select_disk_root_payload\nfi\n' +
		'printf "%s\\n" "$INITRAMFS" "$INITRAMFS_COMPRESSED" "$RECOVERY_DIR" > "$TEST_STATE"\n'
	bt.write(root + '/runner-fixture.sh', script, false)!
	mut env := bt.environment()
	env['PATH'] = root + '/bin:' + os.getenv('PATH')
	env['TMPDIR'] = root
	env['VINIX_RECOVERY_TEST_ROOT'] = root
	env['TEST_INIT_DIR'] = root + '/init'
	env['TEST_REPO_DIR'] = root
	env['TEST_FULL_IMAGE'] = root + '/full.tar'
	env['TEST_STATE'] = root + '/state'
	return env
}

fn run(root string, env map[string]string) !hosttest.Result {
	return hosttest.capture_in(['bash', root + '/runner-fixture.sh'], '', 120, env, root)
}

fn no_temps(root string) ! {
	assert os.ls(root + '/init')!.filter(it.starts_with('.init')).len == 0
}

fn recovery_archive(path string, expected []u8) ! {
	assert os.file_size(path) < 128 * 1024
	mut reader := tarstream.open_plain(path)!
	defer { reader.close() }
	mut files := []string{}
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		if !member.regular() { continue }
		files << member.name
		assert member.mode & 0o777 == 0o755 && member.size == expected.len
		mut contents := []u8{len: expected.len}
		mut index := 0
		for index < contents.len {
			count := reader.read(mut contents[index..])!
			assert count > 0
			index += count
		}
		assert contents == expected
	}
	assert files == ['./sbin/init']
}

fn check(name string) ! {
	root := hosttest.resolve_path(hosttest.work_dir('', 'vinix-recovery-test-')!)!
	defer { hosttest.remove_work_dir(root) or { panic(err) } }
	mut env := fixture(root)!
	init := root + '/init/init'
	minimal := root + '/init/initramfs-minimal.tar'
	mut expected := 'fixture ld.lld'.bytes()
	if name in ['existing-init', 'failed-rebuild'] {
		bt.write(init, 'previous init', true)!
		expected = 'previous init'.bytes()
	}
	if name == 'existing-archive' {
		mut writer := tarcore.create_stream(minimal)!
		writer.add(tarcore.Member{ name: './sbin/init', mode: 0o755, size: 13 }, 'archived init'.bytes())!
		writer.finish()!
		writer.close_checked()!
	}
	before := if os.exists(minimal) { os.read_bytes(minimal)! } else { []u8{} }
	if name.starts_with('fail-') || name == 'failed-rebuild' {
		env['TEST_FAIL_TOOL'] = if name == 'failed-rebuild' {
			'ld.lld'
		} else {
			name.all_after('fail-')
		}
		if name == 'failed-rebuild' { env['TEST_ACTION'] = 'build' }
		result := run(root, env)!
		assert result.code != 0 && !os.exists(root + '/state')
		expected_tools := match env['TEST_FAIL_TOOL'] {
			'compile-init' { []string{} }
			'clang' { ['clang'] }
			else { ['clang', 'clang', 'ld.lld'] }
		}
		assert bt.events(root)!.map(it.builder) == expected_tools
		assert os.ls(root)!.filter(it.starts_with('vinix-recovery.')).len == 0
		no_temps(root)!
		if name == 'failed-rebuild' {
			assert os.read_bytes(init)! == expected && os.is_executable(init)
		} else {
			assert !os.exists(init)
		}
		return
	}
	if name == 'image' { env['TEST_FALLBACK'] = 'image' }
	if name == 'real-elf' {
		if os.find_abs_path_of_executable('clang') == none || os.find_abs_path_of_executable('ld.lld') == none {
			println('SKIP recovery ARM ELF: clang and ld.lld are required')
			return
		}
		env['PATH'] = os.getenv('PATH')
		env['TEST_REPO_DIR'] = hosttest.root()
		// Native generation must be selected before the copied bash functions run.
		env.delete('VINIX_RECOVERY_TEST_ROOT')
	}
	result := run(root, env)!
	assert result.code == 0, result.stdout + result.stderr
	state := os.read_file(root + '/state')!.split_into_lines()
	assert state.len == 3
	if name == 'image' {
		assert state == [root + '/full.tar', '1', '']
		assert os.read_file(root + '/full.tar')! == 'full desktop payload'
		assert bt.events(root)!.len == 0 && !os.exists(init)
		return
	}
	assert state[1] == '0'
	if name == 'existing-archive' {
		assert state[0] == minimal && state[2] == '' && os.read_bytes(minimal)! == before
		assert bt.events(root)!.len == 0 && !os.exists(init)
		return
	}
	assert os.dir(state[0]) == state[2]
	if name == 'real-elf' {
		expected = os.read_bytes(init)!
		assert expected[..6] == [u8(0x7f), `E`, `L`, `F`, 2, 1]
		assert binary.little_endian_u16(expected[16..18]) == 2
		assert binary.little_endian_u16(expected[18..20]) == 183
		assert binary.little_endian_u64(expected[24..32]) != 0
		assert bt.events(root)!.len == 0
	} else if name == 'fresh' {
		events := bt.events(root)!
		assert events.map(it.builder) == ['clang', 'clang', 'ld.lld']
		assert events.all(!it.init_published) && os.is_executable(init)
	} else {
		assert bt.events(root)!.len == 0
	}
	recovery_archive(state[0], expected)!
	no_temps(root)!
}

fn main() {
	if root := os.getenv_opt('VINIX_RECOVERY_TEST_ROOT') {
		fake(root, os.file_name(os.args[0]))!
		return
	}
	for name in ['fresh', 'existing-init', 'existing-archive', 'fail-compile-init', 'fail-clang',
		'fail-ld.lld', 'failed-rebuild', 'image', 'real-elf'] {
		check(name)!
	}
	println('PASS native disk-root recovery checks')
}
