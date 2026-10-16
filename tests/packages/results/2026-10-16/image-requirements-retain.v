module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string scenario string seconds f64 artifacts []Artifact }
struct Check { name string seconds f64 }
struct HostReceipt { compiler_sha256 string checks []Check }
struct Ledger { format int = 1 scope string compiler Pin sources []Pin artifacts []Pin }
const cache_marker = 'IMAGE REQUIREMENTS CACHE selected/missing/removed paths, same-size restored-time content changes and alternate identical-content inputs invalidate; invalid paths refuse PASS'
fn pin(path string) !Pin { b := os.read_bytes(path)!; defer { unsafe { b.free() } }; return Pin{ path: path, bytes: u64(b.len), sha256: sha256.sum(b).hex() } }
fn assert_markers(output string, sources []string) {
	assert !output.contains('V panic:') && !output.contains('HWTEST FAIL') && !output.contains(': fn test_')
	mut count := 0
	for source in sources {
		for line in os.read_lines(source) or { panic(err) } {
			if line.contains("println('IMAGE ") {
				marker := line.all_after("println('").all_before_last("')")
				assert output.count(marker) == 1, marker
				count++
			}
		}
	}
	assert count == if sources.len == 1 { 8 } else { 13 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); host := work + '/h1'
	prefix := 'tests/packages/results/2026-10-16/image-requirements-'
	mut artifacts := []Pin{}
	checks := json2.decode[HostReceipt](os.read_file(host + '/qualification.json')!)!
	assert checks.checks.len == 30 && checks.compiler_sha256 == pin('build/package-release-work/v-toolchain/v')!.sha256
	assert_markers(os.read_file(host + '/image_applications-run.txt')!, ['tools/packages/pkgcore/image_applications_test.v'])
	assert_markers(os.read_file(host + '/image_applications-sanitize-run.txt')!, ['tools/packages/pkgcore/image_applications_test.v'])
	assert os.read_file(host + '/desktop-cache-run.txt')!.count(cache_marker) == 1
	mut summary := ''
	for check in checks.checks { artifacts << pin(host + '/' + check.name + '.txt')!; summary += check.name + ' PASS (' + check.seconds.str() + ' s)\n' }
	os.write_file(prefix + 'host.txt', summary)!; artifacts << pin(prefix + 'host.txt')!
	for short, architecture in { 'arm': 'aarch64', 'x86': 'x86_64' } {
		guest := os.real_path('build/pireq-' + short + '-1')
		receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.scenario == 'packages-image-requirements' && receipt.artifacts.len == 12
		mut paths := {'kernel': guest + '/kernel', 'guest-init': guest + '/guest/init', 'serial-log': guest + '/packages-image-requirements/serial.log'}
		for name in ['stage-check', 'image-requirements', 'image-check', 'image-repositories', 'image-configuration', 'release', 'catalog', 'deployment', 'resolve']! { paths[name] = guest + '/guest/root/usr/share/package-fixtures/' + name }
		for item in receipt.artifacts { actual := pin(paths[item.role])!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256, item.role; artifacts << actual }
		prior := json2.decode[Receipt](os.read_file('tests/packages/results/2026-10-16/software-installed-' + architecture + '.json')!)!
		assert receipt.artifacts[0].sha256 == prior.artifacts.filter(it.role == 'kernel')[0].sha256
		serial := os.read_file(guest + '/packages-image-requirements/serial.log')!
		assert_markers(serial, ['tools/packages/pkgcore/image_applications_test.v', 'tools/packages/pkgcore/image_check_test.v'])
		assert serial.contains('HWTEST PASS packages-image-requirements') && serial.count('IMAGE REQUIREMENTS PROCESS ') == 8
		qmp := os.read_file(guest + '/packages-image-requirements/qmp.log')!; assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		for suffix, source in { architecture + '.json': guest + '/qualification.json', architecture + '.serial.txt': guest + '/packages-image-requirements/serial.log', architecture + '.qmp.txt': guest + '/packages-image-requirements/qmp.log' } {
			os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
		}
		artifacts << pin(guest + '/guest/init.c')!; artifacts << pin(guest + '/guest/build.log')!
		for index, name in ['stage-check', 'image-requirements', 'image-check', 'image-repositories', 'image-configuration', 'release', 'catalog', 'deployment', 'resolve']! { artifacts << pin(guest + '/guest/program-' + index.str() + '/' + name + '.c')! }
		println(architecture + ' target passed in ' + receipt.seconds.str() + ' seconds')
	}
	for suffix, source in {
		'host.json': host + '/qualification.json', 'core.txt': host + '/image_applications-run.txt', 'asan.txt': host + '/image_applications-sanitize-run.txt', 'cache.txt': host + '/desktop-cache-run.txt',
		'cli.txt': host + '/distribution-cli-run.txt', 'guest.v': work + '/guest.v', 'guards.v': work + '/guards.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
	}
	for name in ['list-aarch64', 'list-x86_64', 'refuse-inputs', 'refuse-existing'] { artifacts << pin(work + '/' + name + '.txt')! }
	for name in ['stage', 'desktop-cache', 'image_applications', 'image_check', 'image_repositories', 'image_configuration', 'deployment', 'resolve_search', 'release', 'mirror', 'policy', 'catalog', 'publisher_schema', 'image-applications-sanitize', 'vinix-package', 'distribution-cli'] { artifacts << pin(host + '/' + name)! }
	for path in [work + '/controller', work + '/host', work + '/guest', 'build/package-launch-transport-work/cross-cc',
		'/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '/opt/homebrew/bin/qemu-system-aarch64', '/opt/homebrew/bin/qemu-system-x86_64'] { artifacts << pin(path)! }
	prior_sources := json2.decode[Ledger](os.read_file('tests/packages/results/2026-10-16/image-applications-toolchain.json')!)!
	mut source_paths := prior_sources.sources.map(it.path)
	for path in ['tests/packages/image-requirements-check.v', 'tests/packages/image-requirements-runtime-check.v', 'tests/packages/image-requirements-guest/main.v', 'tests/packages/image-requirements-check.md',
		'build-support/native-compat-tools/compathost/stage.v', 'build-support/native-compat-tools/compathost/common.v', 'build-support/native-compat-tools/policyhost/core.v', 'examples/package-catalog/README.md'] {
		if path !in source_paths { source_paths << path }
	}
	for path in os.walk_ext('build-support/cachekey', '') { if os.is_file(path) && (path.ends_with('.v') || path.ends_with('.h')) && path !in source_paths { source_paths << path } }
	source_paths.sort(); mut sources := []Pin{}; for path in source_paths { sources << pin(path)! }
	changed := ['tools/packages/pkgcore/image_check.v', 'tools/packages/pkgcore/image_applications_test.v', 'tools/packages/stage.v', 'tools/packages/README.md', 'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', 'examples/package-catalog/README.md', 'build-support/cachekey/desktop.v', 'build-support/cachekey/desktop_test.v']
	for source in prior_sources.sources { if source.path in changed { continue }; actual := pin(source.path)!; assert actual.sha256 == source.sha256 && actual.bytes == source.bytes, source.path }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!; assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'Reviewed release application requirements files: --applications and inherited VINIX_PACKAGE_IMAGE_APPLICATIONS, bounded strict format-1 deployment roots, exact captured-source digests, target schema and format-2 pin-downgrade refusal, nonempty valid app sets, CLI/environment/inline precedence and explicit-form mutual exclusion, normal/check compiler gates, independent canonical signed deployment reports, native desktop cache selection/content invalidation including restored timestamps. Thirty host checks, eleven package suites plus cache suite, ASan/UBSan with leak detection disabled, real staging/package CLIs and signed maintenance; four controller guards; final AArch64/x86-64 twelve-artifact guests with eight runners, thirteen required report markers and guest-initiated shutdown. Kernels match installed-system qualification. Structural payloads never execute. No whole-plan heap, full desktop rebuild, production publisher/catalog migration or graphical/runtime/device/crash acceptance claim.',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified thirty host checks, two twelve-artifact guests, shutdown and ' + sources.len.str() + ' source pins')
}
