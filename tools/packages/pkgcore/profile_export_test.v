// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore
import json2
import os
import time
import tests.packages.applefixture
import tests.packages.elffixture

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.mkfifo(&char, u32) int
struct ProfileExportLimit { current u64 maximum u64 }

fn profile_export_profiles() []string {
	profiles := ['native', 'sqlite', 'ffmpeg', 'wine', 'apple']
	if os.args.len >= 2 && os.args[1] in profiles { return [os.args[1]] }
	return profiles
}

fn profile_export_chunk() int {
	if os.args.len == 3 {
		assert os.args[2] in ['0', '1', '2', '3']!
		return os.args[2].int()
	}
	return -1
}

fn profile_export_grace() {
	$if linux {
		// Vinix retires unlinked nodes after a five-second lookup grace period.
		// Separate bounded stress cohorts so their reservations can return.
		if os.exists('/proc/kernel-resources') { C.sleep(6) }
	}
}

fn profile_export_native_fixture_elf(architecture string, interpreter bool) []u8 {
	mut bytes := elffixture.image(architecture, if interpreter { 'pie' } else { 'static' })
	bytes[16] = 2
	return bytes
}

fn profile_export_native_profile_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-native-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		os.mkdir_all(root + '/bin')!
		os.mkdir_all(root + '/licenses')!
		for path in ['bin/package-hello', 'bin/counter', 'bin/memo'] {
			os.write_file_array(root + '/' + path, profile_export_native_fixture_elf(architecture, false))!
			os.chmod(root + '/' + path, 0o755)!
		}
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt'] { os.write_file(root + '/licenses/' + name, name)! }
	}
	return work
}

fn profile_export_sqlite_fixture_elf(architecture string, pie bool, shared bool) []u8 {
	return elffixture.image(architecture, if pie { 'pie' } else if shared { 'shared' } else { 'static' })
}

fn profile_export_sqlite_profile_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-sqlite-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		for directory in ['bin', 'lib', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
		for path, kind in {'bin/sqlite3': 'pie', 'bin/vinix-linux-runner': 'static',
			'lib/libc.so': 'shared', 'lib/libsqlite3.so.0': 'shared'} {
			os.write_file_array(root + '/' + path, profile_export_sqlite_fixture_elf(architecture, kind == 'pie', kind == 'shared'))!
			os.chmod(root + '/' + path, 0o755)!
		}
		for name in ['sqlite-COPYRIGHT', 'musl-COPYRIGHT', 'vinix-COPYING'] { os.write_file(root + '/licenses/' + name, 'notice ' + name)! }
	}
	return work
}

fn profile_export_ffmpeg_test_elf(architecture string, kind string) []u8 {
	return elffixture.image(architecture, kind)
}

fn profile_export_ffmpeg_test_roots() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-ffmpeg-profile-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		for directory in ['bin', 'lib', 'licenses', 'sources'] { os.mkdir_all(root + '/' + directory)! }
		for path in ['bin/ffmpeg', 'bin/ffprobe', 'bin/vinix-linux-runner', 'lib/libc.so', ...ffmpeg_libraries] {
			os.write_file_array(root + '/' + path, profile_export_ffmpeg_test_elf(architecture, ffmpeg_elf_kind(path)))!
			os.chmod(root + '/' + path, 0o755)!
		}
		for path in ffmpeg_notices { os.write_file(root + '/' + path, 'notice ' + path)! }
		mut file := os.open_file(root + '/sources/ffmpeg.tar.xz', 'w', 0o644)!
		file.seek(i64(ffmpeg_source_bytes) - 1, .start)!
		file.write_string('\x00')!
		file.close()
	}
	return work
}

fn profile_export_wine_put(mut bytes []u8, offset int, value u64, width int) {
	for index in 0 .. width { bytes[offset + index] = u8(value >> (index * 8)) }
}

// Structural fixtures only: neither this PE nor the ELF launcher is executed.
fn profile_export_wine_fixture_pe() []u8 {
	mut bytes := []u8{len: 1024}
	bytes[0] = `M`; bytes[1] = `Z`
	profile_export_wine_put(mut bytes, 60, 128, 4)
	bytes[128] = `P`; bytes[129] = `E`
	profile_export_wine_put(mut bytes, 132, 0x8664, 2)
	profile_export_wine_put(mut bytes, 134, 1, 2)
	profile_export_wine_put(mut bytes, 148, 240, 2)
	profile_export_wine_put(mut bytes, 150, 2, 2)
	profile_export_wine_put(mut bytes, 152, 0x20b, 2)
	profile_export_wine_put(mut bytes, 168, 0x1000, 4)
	profile_export_wine_put(mut bytes, 208, 0x2000, 4)
	profile_export_wine_put(mut bytes, 212, 512, 4)
	profile_export_wine_put(mut bytes, 220, 3, 2)
	profile_export_wine_put(mut bytes, 400, 512, 4)
	profile_export_wine_put(mut bytes, 404, 0x1000, 4)
	profile_export_wine_put(mut bytes, 408, 512, 4)
	profile_export_wine_put(mut bytes, 412, 512, 4)
	profile_export_wine_put(mut bytes, 428, 0x60000020, 4)
	bytes[512] = 0xc3
	return bytes
}

fn profile_export_wine_fixture_recipe(architecture string, application bool) RootRecipe {
	return if application {
		RootRecipe{ manifest: Package{ id: 'org.example.win64', version: '1.0.0', architecture: architecture,
			name: 'Reviewed Win64 application', description: 'Explicit publisher-supplied compatibility closure.',
			license: 'Example-EULA', proprietary: true, kind: 'windows', runtime: 'org.example.wine',
			entrypoint: 'bin/wine-runner', arguments: ['@APP@/bin/program.exe', 'literal ; $ argument'],
			permissions: ['files', 'process'], associations: ['text/plain'],
			dependencies: [Dependency{ id: 'org.example.wine', minimum: '1.0.0', before: '2.0.0' }] },
			entries: [RootEntry{ source: 'app/program.exe', path: 'bin/program.exe' },
				RootEntry{ source: 'licenses/application-LICENSE.txt', path: wine_application_notice }] }
	} else {
		RootRecipe{ manifest: Package{ id: 'org.example.wine', version: '1.0.0', architecture: architecture,
			name: 'Reviewed Wine closure', license: 'LGPL-2.1-or-later', kind: 'runtime' },
			entries: [RootEntry{ source: 'runtime/runner', path: 'bin/wine-runner' },
				RootEntry{ source: 'runtime/closure.txt', path: 'share/closure.txt' },
				RootEntry{ source: 'licenses/runtime-LICENSE.txt', path: wine_runtime_notice }] }
	}
}

fn profile_export_wine_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-wine-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		for directory in ['app', 'runtime', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
		os.write_file_array(root + '/app/program.exe', profile_export_wine_fixture_pe())!
		os.write_file_array(root + '/runtime/runner', elffixture.image(architecture, 'static'))!
		os.chmod(root + '/runtime/runner', 0o755)!
		os.write_file(root + '/runtime/closure.txt', 'publisher enumerated runtime resources ' + architecture)!
		os.write_file(root + '/licenses/application-LICENSE.txt', 'Fixture license; not permission to distribute a commercial application.')!
		os.write_file(root + '/licenses/runtime-LICENSE.txt', 'Fixture runtime license.')!
		os.mkdir_all(work + '/recipes/' + architecture)!
		for role in ['application', 'runtime'] {
			os.write_file(work + '/recipes/' + architecture + '/' + role + '.json',
				json2.encode(profile_export_wine_fixture_recipe(architecture, role == 'application')))!
		}
	}
	return work
}

fn profile_export_apple_fixture_info(id string) string {
	return '<plist><dict><key>CFBundleIdentifier</key><string>' + id + '</string><key>CFBundleExecutable</key><string>Example</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>'
}

fn profile_export_apple_fixture_recipe(application bool) RootRecipe {
	return if application {
		RootRecipe{ manifest: Package{ id: 'org.example.apple', version: '1.0.0', architecture: 'aarch64',
			name: 'Reviewed Apple application', description: 'Publisher-supplied iOS bundle and isolated runtime.',
			license: 'Example-EULA', proprietary: true, kind: 'apple', runtime: 'org.example.ios-runtime',
			entrypoint: 'bin/run-ios', arguments: ['@APP@/Example.app/Example', 'literal ; $ argument'],
			permissions: ['files', 'process'], associations: ['text/plain'],
			dependencies: [Dependency{ id: 'org.example.ios-runtime', minimum: '1.0.0', before: '2.0.0' }] },
			entries: [RootEntry{ source: 'app/Example', path: 'Example.app/Example' },
				RootEntry{ source: 'app/Info.plist', path: 'Example.app/Info.plist' },
				RootEntry{ source: 'licenses/application-LICENSE.txt', path: apple_application_notice }] }
	} else {
		RootRecipe{ manifest: Package{ id: 'org.example.ios-runtime', version: '1.0.0', architecture: 'aarch64',
			name: 'Reviewed iOS runtime closure', license: 'GPL-2.0-or-later AND MIT', kind: 'runtime' },
			entries: [RootEntry{ source: 'runtime/runner', path: 'bin/run-ios' },
				RootEntry{ source: 'runtime/closure.txt', path: 'share/closure.txt' },
				RootEntry{ source: 'licenses/runtime-LICENSE.txt', path: apple_runtime_notice }] }
	}
}

fn profile_export_apple_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-apple-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/roots/aarch64'
	for directory in ['app', 'runtime', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
	os.write_file_array(root + '/app/Example', applefixture.image(23))!
	os.write_file(root + '/app/Info.plist', profile_export_apple_fixture_info('org.example.apple'))!
	os.write_file_array(root + '/runtime/runner', elffixture.image('aarch64', 'static'))!
	os.chmod(root + '/runtime/runner', 0o755)!
	os.write_file(root + '/runtime/closure.txt', 'enumerated runtime resources')!
	os.write_file(root + '/licenses/application-LICENSE.txt', 'Fixture only; no commercial redistribution rights.')!
	os.write_file(root + '/licenses/runtime-LICENSE.txt', 'Fixture runtime license.')!
	os.mkdir_all(work + '/recipes/aarch64')!
	for role in ['application', 'runtime'] { os.write_file(work + '/recipes/aarch64/' + role + '.json', json2.encode(profile_export_apple_fixture_recipe(role == 'application')))! }
	return work
}


fn profile_export_fixture(kind string) !string {
	work := match kind {
		'native' { profile_export_native_profile_fixture()! }
		'sqlite' { profile_export_sqlite_profile_fixture()! }
		'ffmpeg' { profile_export_ffmpeg_test_roots()! }
		'wine' { profile_export_wine_fixture()! }
		else { profile_export_apple_fixture()! }
	}
	if kind == 'ffmpeg' {
		archive := os.getenv_opt('VINIX_PROFILE_EXPORT_SOURCE') or { '/usr/share/package-fixtures/ffmpeg.tar.xz' }
		// Early refusal baselines need only the ordinary source size. Complete
		// publication tests require the retained, hash-verified upstream bytes.
		if os.is_file(archive) {
			assert os.file_size(archive) == ffmpeg_source_bytes && hash_file(archive)! == ffmpeg_source_digest
			for arch in ['aarch64', 'x86_64']! { os.cp(archive, work + '/roots/' + arch + '/sources/ffmpeg.tar.xz')! }
		}
	}
	return work
}

fn profile_export_run(kind string, work string, target string, options CatalogOptions) ! {
	match kind {
		'native' { mut info := native_catalog_with('1.0.0', work + '/roots', target, options)!; info.close() }
		'sqlite' { mut info := sqlite_catalog_with('3.53.4', '1.0.0', work + '/roots', target, options)!; info.close() }
		'ffmpeg' { mut info := ffmpeg_catalog_with('1.0.0', work + '/roots', target, options)!; info.close() }
		'wine' { mut info := wine_catalog_with(work + '/recipes', work + '/roots', target, options)!; info.close() }
		else { mut info := apple_catalog_with(work + '/recipes', work + '/roots', target, options)!; info.close() }
	}
}

fn profile_export_baseline_checkpoint(phase string, stage string) ! {
	if phase != 'created' { return }
	parent := os.dir(stage)
	os.write_file(parent + '/stage-path', stage)!
	os.rename(stage, parent + '/saved-stage')!
	os.mkdir(stage)!
	os.write_file(stage + '/keep', 'preserved')!
	return error('injected profile refusal')
}

fn test_profile_export_failed_cleanup_preserves_replacements() {
	if profile_export_chunk() > 0 { return }
	mut preserved := 0
	for kind in profile_export_profiles() {
		work := if kind == 'ffmpeg' { profile_export_ffmpeg_test_roots()! } else { profile_export_fixture(kind)! }
		defer { os.rmdir_all(work) or {} }
		mut refused := false
		profile_export_run(kind, work, work + '/output/export', CatalogOptions{ checkpoint: profile_export_baseline_checkpoint }) or { refused = err.msg().contains('injected profile refusal') }
		stage := os.read_file(work + '/output/stage-path')!
		keep := os.read_file(stage + '/keep') or { '' }
		println('PROFILE EXPORT baseline ' + kind + ' refused=' + refused.str() + ' replacement-preserved=' + (keep == 'preserved').str())
		if refused && keep == 'preserved' { preserved++ }
	}
	assert preserved == profile_export_profiles().len
}

fn profile_export_snapshot(directory string) !string {
	mut paths := os.walk_ext(directory, ''); paths.sort()
	mut text := ''
	for path in paths {
		if os.is_file(path) { text += path[directory.len..] + ':' + os.stat(path)!.mode.str() + ':' + hash_file(path)! + '\n' }
	}
	return text
}

fn profile_export_substitute(phase string, stage string) ! {
	if phase != os.getenv('VINIX_PROFILE_EXPORT_PHASE') { return }
	work := os.getenv('VINIX_PROFILE_EXPORT_CASE')
	if os.exists(work + '/stage-path') { return }
	os.write_file(work + '/stage-path', stage)!
	site := os.getenv('VINIX_PROFILE_EXPORT_SITE')
	path := stage + if site == 'root' { '' } else { '/' + site }
	os.write_file(work + '/replaced-path', path)!
	os.write_file(work + '/inode', os.stat(path)!.inode.str())!
	os.write_file(work + '/snapshot', profile_export_snapshot(path)!)!
	kind := os.getenv('VINIX_PROFILE_EXPORT_KIND')
	if kind == 'parent' { os.rename(os.dir(stage), work + '/saved-parent')!; os.mkdir(os.dir(stage))! }
	else { os.rename(path, work + '/saved-tree')! }
	match kind {
		'directory', 'parent' { os.mkdir(path)!; os.write_file(path + '/keep', 'preserved')! }
		'alias' { os.symlink(work + '/outside', path)! }
		'dangling' { os.symlink(work + '/absent', path)! }
		'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
		'file' { os.write_file(path, 'preserved')! }
		'missing' {}
		'clone' { os.cp_all(work + '/saved-tree', path, true)! }
		else { panic(kind) }
	}
	if os.getenv('VINIX_PROFILE_EXPORT_FAIL') == 'yes' { return error('injected profile refusal') }
}

fn profile_export_assert_recovery(work string, kind string) ! {
	path := os.read_file(work + '/replaced-path')!
	snapshot := os.read_file(work + '/snapshot')!
	match kind {
		'directory', 'parent' { assert os.read_file(path + '/keep')! == 'preserved' }
		'alias' { assert os.readlink(path)! == work + '/outside' }
		'dangling' { assert os.readlink(path)! == work + '/absent' }
		'fifo' { assert os.lstat(path)!.mode & 0o170000 == 0o010000 }
		'file' { assert os.read_file(path)! == 'preserved' }
		'missing' { assert !os.exists(path) && !os.is_link(path) }
		'clone' { assert profile_export_snapshot(path)! == snapshot }
		else { panic(kind) }
	}
	if kind == 'parent' { assert os.ls(work + '/saved-parent')!.len == 0 }
	else {
		assert profile_export_snapshot(work + '/saved-tree')! == snapshot
		assert os.stat(work + '/saved-tree')!.inode.str() == os.read_file(work + '/inode')!
	}
	assert os.read_file(work + '/outside/keep')! == 'preserved'
	assert os.stat(work + '/outside')!.mode & 0o777 == 0o700 && os.stat(work + '/outside/keep')!.mode & 0o777 == 0o600
}

fn test_profile_export_captured_roots_children_parent_and_exact_retry() {
	mut original := ProfileExportLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limit := ProfileExportLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	defer { for name in ['CASE', 'PHASE', 'SITE', 'KIND', 'FAIL']! { os.unsetenv('VINIX_PROFILE_EXPORT_' + name) } }
	mut cases := 0
	mut executed := 0
	for profile in profile_export_profiles() {
		profile_export_grace()
		work := profile_export_fixture(profile)!; defer { os.rmdir_all(work) or {} }
		inputs := profile_export_snapshot(work + '/roots')!
		profile_export_run(profile, work, work + '/baseline', CatalogOptions{})!
		expected := os.read_file(work + '/baseline/catalog.json')!
		for site in ['root', 'inventory', 'lock']! {
			for phase in if site == 'root' { ['created', 'packed', 'ready'] } else if site == 'inventory' { ['packed'] } else { ['ready'] } {
				for replacement in if site == 'root' { ['directory', 'alias', 'dangling', 'fifo', 'file', 'missing', 'clone', 'parent'] } else { ['directory', 'alias', 'fifo', 'clone'] } {
					for fail in ['yes', 'no']! {
						current := cases; cases++
						if profile_export_chunk() >= 0 && (current % 64) / 16 != profile_export_chunk() { continue }
						case := work + '/case-' + current.str()
						os.mkdir_all(case + '/output')!; os.mkdir(case + '/outside')!; os.chmod(case + '/outside', 0o700)!
						os.write_file(case + '/outside/keep', 'preserved')!; os.chmod(case + '/outside/keep', 0o600)!
						for name, value in {'CASE': case, 'PHASE': phase, 'SITE': site, 'KIND': replacement, 'FAIL': fail} { os.setenv('VINIX_PROFILE_EXPORT_' + name, value, true) }
						mut message := ''
						profile_export_run(profile, work, case + '/output/export', CatalogOptions{ checkpoint: profile_export_substitute }) or { message = err.msg() }
						assert message != '' && !os.exists(case + '/output/export'), profile + '/' + site + '/' + phase + '/' + replacement + '/' + fail
						if fail == 'yes' { assert message.contains('injected profile refusal') }
						if replacement != 'parent' { assert message.contains('cleanup refused') }
						profile_export_assert_recovery(case, replacement)!
						profile_export_run(profile, work, case + '/output/export', CatalogOptions{}) or {
							println('PROFILE EXPORT retry failure ' + profile + '/' + site + '/' + phase + '/' + replacement + '/' + fail + ' case=' + cases.str() + ' errno=' + C.errno.str())
							for resource in ['/proc/kernel-resources', '/proc/meminfo']! {
								observation := os.read_file(resource) or { '' }
								println(resource + '\n' + observation)
							}
							println('PROFILE EXPORT open descriptors ' + (os.ls('/proc/self/fd') or { []string{} }).str())
							panic(err)
						}
						assert os.ls(case + '/output/export')! == ['catalog.json'] && os.read_file(case + '/output/export/catalog.json')! == expected
						profile_export_assert_recovery(case, replacement)!
						os.rmdir_all(case)!; executed++
					}
				}
			}
		}
		assert profile_export_snapshot(work + '/roots')! == inputs
		assert os.ls(work)!.all(!it.starts_with('.vinix-'))
		if profile_export_chunk() < 0 {
			println('PROFILE EXPORT ' + profile + ' 64 root/inventory/lock/parent substitutions preserve recovery, source pins and exact retry under 32 descriptors PASS')
		} else { println('PROFILE EXPORT ' + profile + ' cohort ' + profile_export_chunk().str() + ' 16 substitutions recovery source pins exact retry 32 descriptors PASS') }
	}
	assert cases == 64 * profile_export_profiles().len
	assert executed == if profile_export_chunk() < 0 { cases } else { 16 * profile_export_profiles().len }
}

fn profile_export_observe(phase string, stage string) ! {
	if phase == 'ready' { os.write_file(os.getenv('VINIX_PROFILE_EXPORT_SAVED') + '/stage-path', stage)! }
}

fn profile_export_saved_failure(fd int) int {
	work := os.getenv('VINIX_PROFILE_EXPORT_SAVED')
	mode := os.getenv('VINIX_PROFILE_EXPORT_SAVED_MODE')
	if mode == 'flush' { return -1 }
	if mode == 'parent' {
		os.rename(work + '/output', work + '/saved-parent') or { return -1 }
		os.mkdir(work + '/output') or { return -1 }
		os.write_file(work + '/output/keep', 'replacement parent') or { return -1 }
	} else {
		stage := os.read_file(work + '/stage-path') or { return -1 }
		os.rename(stage + '/inventory', stage + '/saved-inventory') or { return -1 }
		os.mkdir(stage + '/inventory') or { return -1 }
		os.write_file(stage + '/inventory/keep', 'replacement inventory') or { return -1 }
	}
	return C.fsync(fd)
}

fn test_profile_export_saved_output_survives_flush_parent_and_inventory_cleanup_failure() {
	if profile_export_chunk() > 0 { return }
	defer { os.unsetenv('VINIX_PROFILE_EXPORT_SAVED'); os.unsetenv('VINIX_PROFILE_EXPORT_SAVED_MODE') }
	for profile in profile_export_profiles() {
		profile_export_grace()
		work := profile_export_fixture(profile)!; defer { os.rmdir_all(work) or {} }
		profile_export_run(profile, work, work + '/baseline', CatalogOptions{})!
		expected := os.read_file(work + '/baseline/catalog.json')!
		for mode in ['flush', 'parent', 'cleanup']! {
			case := work + '/' + mode; os.mkdir_all(case + '/output')!
			os.setenv('VINIX_PROFILE_EXPORT_SAVED', case, true); os.setenv('VINIX_PROFILE_EXPORT_SAVED_MODE', mode, true)
			mut message := ''
			profile_export_run(profile, work, case + '/output/export', CatalogOptions{ checkpoint: profile_export_observe, flush: profile_export_saved_failure }) or { message = err.msg() }
			assert message.contains('published') && message.contains(match mode { 'flush' { 'directory flush failed' } 'parent' { 'parent path changed' } else { 'cleanup refused' } })
			saved := case + if mode == 'parent' { '/saved-parent/export' } else { '/output/export' }
			assert os.ls(saved)! == ['catalog.json'] && os.read_file(saved + '/catalog.json')! == expected
			if mode == 'parent' { assert os.ls(case + '/output')! == ['keep'] && os.read_file(case + '/output/keep')! == 'replacement parent' && os.ls(case + '/saved-parent')! == ['export'] }
			if mode == 'cleanup' {
				stage := os.read_file(case + '/stage-path')!
				assert os.read_file(stage + '/inventory/keep')! == 'replacement inventory' && os.is_dir(stage + '/saved-inventory/objects')
			} else if mode == 'flush' { assert os.ls(case + '/output')! == ['export'] }
			profile_export_run(profile, work, case + '/retry', CatalogOptions{})!
			assert os.read_file(case + '/retry/catalog.json')! == expected
		}
	}
	println('PROFILE EXPORT selected profiles retain canonical saved locks after flush, moved-parent and replaced-inventory cleanup failures PASS')
}
