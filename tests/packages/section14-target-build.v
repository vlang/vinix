// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hosttest
import json2
import os
import workflowbuild

fn sha(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn capture(argv []string, log string) ! {
	result := hosttest.capture(argv, log, 1800, os.environ())!
	if result.code != 0 { return error('command failed: ' + log + '\n' + result.stdout + result.stderr) }
}

fn module_capture(argv []string, _ string, _ int, env map[string]string) !hosttest.Result {
	return hosttest.capture(argv, os.getenv('VINIX_TARGET_MODULE_LOG'), 1800, env)
}

fn inventory(root string) !map[string]string {
	mut result := map[string]string{}
	for path in os.walk_ext(root, '') {
		if os.is_file(path) { result[path[root.len + 1..]] = sha(path)! }
	}
	return result
}

fn unchanged(before map[string]string, after map[string]string) ! {
	if before.len != after.len { return error('input count changed') }
	for path, expected in before {
		if after[path] != expected { return error('input changed: ' + path) }
	}
}

fn write_json(path string, value map[string]string) ! {
	os.write_file(path, json2.encode(value) + '\n')!
}

fn production_names(scope string) ![]string {
	mut names := ['software_snapshot.v', 'software_policy_navigation.v', 'packagecore/release.c.v', 'app_selection_migration.v', 'session_hub.v']
	if scope == 'release-save-policy-repository' {
		names << 'software_repository_navigation.v'
	} else if scope != 'release-save-policy' {
		return error('unknown production source scope')
	}
	return names
}

fn elf(path string, machine u16) ! {
	data := os.read_bytes(path)!
	if data.len < 64 || data[..4] != [u8(0x7f), `E`, `L`, `F`] || data[4] != 2 || data[5] != 1
		|| data[16] != 2 || data[17] != 0
		|| (u16(data[18]) | (u16(data[19]) << 8)) != machine { return error('unexpected ELF64 executable architecture: ' + path) }
	mut offset := u64(0)
	for index in 0 .. 8 { offset |= u64(data[32 + index]) << (8 * index) }
	size := int(data[54]) | (int(data[55]) << 8)
	count := int(data[56]) | (int(data[57]) << 8)
	if count == 0 || size < 56 || offset > u64(data.len) || u64(count) * u64(size) > u64(data.len) - offset {
		return error('invalid ELF program headers')
	}
	mut load := false
	for index in 0 .. count {
		start := int(offset) + index * size
		kind := u32(data[start]) | (u32(data[start + 1]) << 8) | (u32(data[start + 2]) << 16) | (u32(data[start + 3]) << 24)
		if kind == 3 { return error('unexpected ELF interpreter') }
		if kind == 1 { load = true }
	}
	if !load { return error('missing ELF load segment') }
}

fn seal(work string) !string {
	mut paths := os.walk_ext(work, '')
	paths.sort()
	mut lines := []string{}
	for path in paths {
		if os.is_file(path) && path != work + '/bundle.sha256' { lines << sha(path)! + '\t' + path[work.len + 1..] }
	}
	os.write_file(work + '/bundle.sha256', lines.join('\n') + '\n')!
	return sha(work + '/bundle.sha256')!
}

fn check(work string) ! {
	mut expected := map[string]string{}
	for line in os.read_file(work + '/bundle.sha256')!.split_into_lines() {
		fields := line.split('\t')
		if fields.len != 2 || fields[0].len != 64 || fields[1].starts_with('/') || '..' in fields[1].split('/')
			|| fields[1] in expected { return error('invalid manifest') }
		expected[fields[1]] = fields[0]
	}
	mut actual := inventory(work)!
	actual.delete('bundle.sha256')
	unchanged(expected, actual)!
	// The first five-source bundle predates the explicit scope receipt.
	scope := if 'production-scope.txt' in actual { os.read_file(work + '/production-scope.txt')!.trim_space() } else { 'release-save-policy' }
	names := production_names(scope)!
	for name in ['runner', 'runner.v', 'repository-head.log', 'production.patch.log', 'v-version.log',
		'clang-version.log', 'lld-version.log', 'source-before.json', 'source-after.json', 'tools-before.json', 'tools-after.json',
		'production-before.json', 'production-after.json', 'tool-executables/v', 'tool-executables/clang', 'tool-executables/ld.lld'] {
		if name !in actual { return error('missing required artifact: ' + name) }
	}
	for prefix in ['source', 'tools', 'production'] {
		before := json2.decode[map[string]string](os.read_file(work + '/' + prefix + '-before.json')!)!
		after := json2.decode[map[string]string](os.read_file(work + '/' + prefix + '-after.json')!)!
		if before.len == 0 { return error('empty input receipt') }
		unchanged(before, after)!
		if prefix == 'source' { unchanged(before, inventory(work + '/source')!)! }
		if prefix == 'tools' {
			for name in ['v', 'clang', 'ld.lld'] {
				if sha(work + '/tool-executables/' + name)! !in before.values() { return error('tool executable copy mismatch') }
			}
		}
		if prefix == 'production' {
			if before.len != names.len { return error('incomplete production source receipt') }
			for name in names {
				mut matches := 0
				for path, expected_hash in before {
					if path.ends_with('/desktop/' + name) {
						matches++
						if sha(work + '/source/desktop/' + name)! != expected_hash { return error('production source mismatch') }
					}
				}
				if matches != 1 { return error('missing or duplicate production source: ' + name) }
			}
		}
	}
	for arch in ['aarch64', 'x86_64'] {
		for name in ['generate-command.log', 'clang-command.log', 'gpucore-command.log', 'execinfocore-command.log',
			'generated-before.json', 'generated-after.json', 'app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
			if arch + '/' + name !in actual { return error('missing required architecture artifact: ' + arch + '/' + name) }
		}
		before := json2.decode[map[string]string](os.read_file(work + '/' + arch + '/generated-before.json')!)!
		after := json2.decode[map[string]string](os.read_file(work + '/' + arch + '/generated-after.json')!)!
		unchanged(before, after)!
		for name in ['desktop.c', 'execinfo.c', 'presenter.c'] {
			if before[name] != sha(work + '/' + arch + '/app/' + name)! { return error('generated C mismatch') }
		}
		if 'source/tests/packages/software_image_fixture.v' in actual {
			for name in ['software-image', 'image-generated.json', 'image-generate-command.log', 'image-clang-command.log', 'image-app/software-image.c'] {
				if arch + '/' + name !in actual { return error('missing supplementary image artifact') }
			}
			image := json2.decode[map[string]string](os.read_file(work + '/' + arch + '/image-generated.json')!)!
			if image['software-image.c'] != sha(work + '/' + arch + '/image-app/software-image.c')! { return error('image generated C mismatch') }
			elf(work + '/' + arch + '/software-image', if arch == 'aarch64' { u16(183) } else { u16(62) })!
		}
	}
	for name in names {
		if 'source/desktop/' + name !in actual { return error('missing combined production source') }
	}
	elf(work + '/aarch64/vinix-desktop', 183)!
	elf(work + '/x86_64/vinix-desktop', 62)!
	println('SECTION14 TARGET bundle verified ' + sha(work + '/bundle.sha256')!)
}

fn build(options map[string]string) ! {
	root := os.real_path(@DIR + '/../..')
	work := os.abs_path(options['--out'] or { return error('--out is required') })
	if os.exists(work) { return error('output directory must be new') }
	dependencies := os.real_path(options['--dependencies'] or { root })
	ui := os.real_path(options['--ui'] or { root + '/../ui2' })
	compiler := os.real_path(os.getenv_opt('V') or { return error('set V to the selected compiler') })
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	clang := os.real_path(llvm + '/clang')
	// Keep argv[0]: ld.lld is a symlink to the generic multi-call lld driver.
	lld := os.find_abs_path_of_executable('ld.lld')!
	scope := options['--scope'] or { 'release-save-policy' }
	names := production_names(scope)!
	os.mkdir_all(work)!
	os.write_file(work + '/production-scope.txt', scope + '\n')!
	os.cp(@FILE, work + '/runner.v')!
	os.cp(os.executable(), work + '/runner')!
	mut pins := map[string]string{}
	for path in [compiler, clang, lld] { pins[path] = sha(path)! }
	os.mkdir(work + '/tool-executables')!
	for name, path in {'v': compiler, 'clang': clang, 'ld.lld': lld} {
		os.cp(path, work + '/tool-executables/' + name)!
		if sha(work + '/tool-executables/' + name)! != pins[path] { return error('compiler executable copy mismatch') }
	}
	mut production := map[string]string{}
	for name in names {
		production[root + '/desktop/' + name] = sha(root + '/desktop/' + name)!
	}
	write_json(work + '/production-before.json', production)!
	write_json(work + '/tools-before.json', pins)!
	capture([compiler, 'version'], work + '/v-version.log')!
	capture([clang, '--version'], work + '/clang-version.log')!
	capture([lld, '--version'], work + '/lld-version.log')!
	capture(['git', '-C', root, 'rev-parse', 'HEAD'], work + '/repository-head.log')!
	capture(['git', '-C', root, 'diff', '--', 'desktop'], work + '/production.patch.log')!
	source := work + '/source'
	os.mkdir_all(source + '/tools')!
	for name in ['desktop', 'tools/packages', 'tools/accounts', 'compat', 'build-support/aarch64-cc-shim'] {
		os.mkdir_all(os.dir(source + '/' + name))!
		os.cp_all(root + '/' + name, source + '/' + name, true)!
	}
	for name in ['ui', 'linux', 'uikit', 'windows', 'assets', 'examples/calculator'] {
		os.mkdir_all(os.dir(source + '/ui2/' + name))!
		os.cp_all(ui + '/' + name, source + '/ui2/' + name, true)!
	}
	os.cp(ui + '/v.mod', source + '/ui2/v.mod')!
	if fixtures := options['--fixtures'] {
		os.mkdir_all(source + '/tests/packages')!
		for name in ['software_image_fixture.v', 'software_terminal_fixture.v', 'software_hosted_fixture.v'] {
			os.cp(fixtures + '/' + name, source + '/tests/packages/' + name)!
		}
	}
	before := inventory(source)!
	write_json(work + '/source-before.json', before)!
	for arch in ['aarch64', 'x86_64'] {
		version := if arch == 'aarch64' { 'arm64' } else { 'amd64' }
		sysroot := dependencies + if arch == 'aarch64' { '/build-aarch64-userland/staging' } else { '/build/session-amd64-sysroot' }
		mut versions := os.ls(sysroot + '/usr/lib/gcc/' + arch + '-alpine-linux-musl')!
		versions.sort()
		if versions.len == 0 { return error('missing GCC runtime') }
		gcc := sysroot + '/usr/lib/gcc/' + arch + '-alpine-linux-musl/' + versions.last()
		for suffix in ['/usr/lib/crt1.o', '/usr/lib/crti.o', '/usr/lib/crtn.o', '/usr/lib/libc.a', '/usr/lib/libm.a'] { pins[sysroot + suffix] = sha(sysroot + suffix)! }
		for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { pins[gcc + '/' + name] = sha(gcc + '/' + name)! }
		write_json(work + '/tools-before.json', pins)!
		arch_work := work + '/' + arch
		app := arch_work + '/app'
		os.mkdir_all(arch_work)!
		workflowbuild.stage(source, source + '/ui2', app, true)!
		for name in ['gpucore', 'execinfocore'] {
			os.setenv('VINIX_TARGET_MODULE_LOG', arch_work + '/' + name + '-command.log', true)
			hosttest.generate_module_with_capture(source + '/desktop/' + name,
				app + if name == 'gpucore' { '/presenter.c' } else { '/execinfo.c' }, version, [], module_capture)!
		}
		hosttest.emit_module_header(source + '/desktop/gpucore', app + '/presenter.c', app + '/gpu_present.h')!
		capture([compiler, '-new-compiler', '-nocache', '-w', '-prod', '-os', 'linux', '-arch', version,
			'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'no_segfault_handler', '-d', 'ui2_headless',
			'-path', '@vlib|' + app + '/modules|' + source + '|' + source + '/tools/accounts|@vmodules',
			'-o', app + '/desktop.c', app], arch_work + '/generate-command.log')!
		mut generated := map[string]string{}
		for name in ['desktop.c', 'execinfo.c', 'presenter.c'] { generated[name] = sha(app + '/' + name)! }
		write_json(arch_work + '/generated-before.json', generated)!
		link_args := [clang, '--target=' + arch + '-linux-musl', '-static', '-nostdinc', '-nostdlib',
			'-isystem', source + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include',
			'-isystem', sysroot + '/usr/include', '-I', app, '-D_GNU_SOURCE', '-O2', '-fno-stack-protector', '-w',
			sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o', gcc + '/crtbeginT.o',
			app + '/desktop.c', app + '/execinfo.c', app + '/presenter.c', '-L' + sysroot + '/usr/lib',
			'-L' + gcc, '-lgcc_eh', '-lc', '-lgcc', '-lm', gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o',
			'-fuse-ld=lld', '--ld-path=' + lld, '-B' + llvm, '-o', arch_work + '/vinix-desktop']
		capture(link_args, arch_work + '/clang-command.log')!
		elf(arch_work + '/vinix-desktop', if arch == 'aarch64' { u16(183) } else { u16(62) })!
		mut after_generated := map[string]string{}
		for name, _ in generated { after_generated[name] = sha(app + '/' + name)! }
		write_json(arch_work + '/generated-after.json', after_generated)!
		unchanged(generated, after_generated)!
		if '--fixtures' in options {
			image := arch_work + '/image-app'
			os.mkdir(image)!
			for name in os.ls(source + '/desktop')! {
				if name.starts_with('software_') && name.ends_with('.v') { os.cp(source + '/desktop/' + name, image + '/' + name)! }
			}
			for name in ['software_image_fixture.v', 'software_terminal_fixture.v', 'software_hosted_fixture.v'] {
				os.cp(source + '/tests/packages/' + name, image + '/' + if name == 'software_image_fixture.v' { 'main.v' } else { name })!
			}
			capture([compiler, '-new-compiler', '-nocache', '-w', '-prod', '-os', 'linux', '-arch', version,
				'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'no_segfault_handler', '-d', 'ui2_headless',
				'-path', '@vlib|' + app + '/modules|' + source + '|' + source + '/tools/accounts|@vmodules',
				'-o', image + '/software-image.c', image], arch_work + '/image-generate-command.log')!
			mut image_link := link_args.clone()
			for index, value in image_link {
				if value == app + '/desktop.c' { image_link[index] = image + '/software-image.c' }
				if value == arch_work + '/vinix-desktop' { image_link[index] = arch_work + '/software-image' }
			}
			image_before := sha(image + '/software-image.c')!
			capture(image_link, arch_work + '/image-clang-command.log')!
			if image_before != sha(image + '/software-image.c')! { return error('image generated C changed') }
			write_json(arch_work + '/image-generated.json', {'software-image.c': image_before})!
			elf(arch_work + '/software-image', if arch == 'aarch64' { u16(183) } else { u16(62) })!
			println('SECTION14 TARGET supplementary Software image cross-linked ' + arch)
		}
		println('SECTION14 TARGET cross-linked ' + arch)
	}
	after := inventory(source)!
	write_json(work + '/source-after.json', after)!
	unchanged(before, after)!
	mut after_tools := map[string]string{}
	for path, _ in pins { after_tools[path] = sha(path)! }
	write_json(work + '/tools-after.json', after_tools)!
	unchanged(pins, after_tools)!
	mut after_production := map[string]string{}
	for path, _ in production { after_production[path] = sha(path)! }
	write_json(work + '/production-after.json', after_production)!
	unchanged(production, after_production)!
	println('SECTION14 TARGET manifest ' + seal(work)!)
	check(work)!
}

fn main() {
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') { eprintln('use --out=NEW_DIRECTORY --dependencies=CHECKOUT --ui=SOURCE, or --check=BUNDLE'); exit(1) }
		options[argument.all_before('=')] = argument.all_after('=')
	}
	if work := options['--check'] { check(os.abs_path(work)) or { eprintln(err); exit(1) } }
	else { build(options) or { eprintln(err); exit(1) } }
}
