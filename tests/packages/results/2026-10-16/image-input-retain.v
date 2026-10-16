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
const image_markers = [
	'IMAGE INPUT CHECK reproducible both-host trust/policy, exact signed digests, architecture/license/firmware counts and deduplicated bytes without image publication PASS',
	'IMAGE INPUT CHECK preserved literal existing configuration and consumer history; no-bundle scope and zero bundle estimate PASS',
	'IMAGE INPUT CHECK capture corruption, unrelated plans, appeared consumer state and replaced roots refuse with unchanged targets; stable capture survives source removal PASS',
	'IMAGE INPUT CHECK CLI flag placement, literal paths, environment/explicit selection and reproducible compiler-free reports; normal staging and invalid-input refusals PASS',
	'IMAGE INPUT CHECK publish/preserve/none decisions, occupied configuration, aliased/special/shared-write/damaged bundles refuse without overwriting destinations PASS',
]
fn pin(path string) !Pin { b := os.read_bytes(path)!; defer { unsafe { b.free() } }; return Pin{ path: path, bytes: u64(b.len), sha256: sha256.sum(b).hex() } }
fn assert_image(output string) {
	assert !output.contains('V panic:') && !output.contains('HWTEST FAIL')
	for marker in image_markers { assert output.count(marker) == 1, marker }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); host := work + '/h2'
	prefix := 'tests/packages/results/2026-10-16/image-input-'
	mut artifacts := []Pin{}
	checks := json2.decode[HostReceipt](os.read_file(host + '/qualification.json')!)!
	assert checks.checks.len == 22 && checks.compiler_sha256 == pin('build/package-release-work/v-toolchain/v')!.sha256
	assert_image(os.read_file(host + '/image_check-run.txt')!)
	assert_image(os.read_file(host + '/image_check-sanitize-run.txt')!)
	mut summary := ''
	for check in checks.checks { artifacts << pin(host + '/' + check.name + '.txt')!; summary += check.name + ' PASS (' + check.seconds.str() + ' s)\n' }
	os.write_file(prefix + 'host.txt', summary)!; artifacts << pin(prefix + 'host.txt')!
	for short, architecture in { 'arm': 'aarch64', 'x86': 'x86_64' } {
		guest := os.real_path('build/picheck-' + short + '-2')
		receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.scenario == 'packages-image-input' && receipt.artifacts.len == 9
		mut paths := {'kernel': guest + '/kernel', 'guest-init': guest + '/guest/init', 'serial-log': guest + '/packages-image-input/serial.log'}
		for name in ['stage-check', 'image-check', 'image-repositories', 'image-configuration', 'release', 'catalog']! { paths[name] = guest + '/guest/root/usr/share/package-fixtures/' + name }
		for item in receipt.artifacts { actual := pin(paths[item.role])!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256, item.role; artifacts << actual }
		prior := json2.decode[Receipt](os.read_file('tests/packages/results/2026-10-16/software-installed-' + architecture + '.json')!)!
		assert receipt.artifacts[0].sha256 == prior.artifacts.filter(it.role == 'kernel')[0].sha256
		serial := os.read_file(guest + '/packages-image-input/serial.log')!
		assert_image(serial)
		assert serial.contains('HWTEST PASS packages-image-input') && serial.count('IMAGE INPUT PROCESS ') == 5
		qmp := os.read_file(guest + '/packages-image-input/qmp.log')!; assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		for suffix, source in { architecture + '.json': guest + '/qualification.json', architecture + '.serial.txt': guest + '/packages-image-input/serial.log', architecture + '.qmp.txt': guest + '/packages-image-input/qmp.log' } {
			os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
		}
		artifacts << pin(guest + '/guest/init.c')!; artifacts << pin(guest + '/guest/build.log')!
		for index, name in ['stage-check', 'image-check', 'image-repositories', 'image-configuration', 'release', 'catalog']! { artifacts << pin(guest + '/guest/program-' + index.str() + '/' + name + '.c')! }
		first := os.real_path('build/picheck-' + short + '-1')
		assert os.read_file(first + '/packages-image-input/serial.log')!.contains('normal_code != 0')
		for suffix, source in { architecture + '.first.serial.txt': first + '/packages-image-input/serial.log', architecture + '.first.txt': work + '/guest-' + architecture + '-1.txt' } {
			os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
		}
		println(architecture + ' target passed in ' + receipt.seconds.str() + ' seconds')
	}
	for suffix, source in {
		'host.json': host + '/qualification.json', 'core.txt': host + '/image_check-run.txt', 'asan.txt': host + '/image_check-sanitize-run.txt',
		'cli.txt': host + '/distribution-cli-run.txt', 'guest.v': work + '/guest.v', 'guards.v': work + '/guards.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
	}
	for name in ['list-aarch64', 'list-x86_64', 'refuse-inputs', 'refuse-existing'] { artifacts << pin(work + '/' + name + '.txt')! }
	for name in ['stage', 'image_check', 'image_repositories', 'image_configuration', 'release', 'mirror', 'policy', 'catalog', 'publisher_schema',
		'image-check-sanitize', 'vinix-package', 'distribution-cli'] { artifacts << pin(host + '/' + name)! }
	for path in [work + '/controller', work + '/host', work + '/guest', 'build/package-launch-transport-work/cross-cc',
		'/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '/opt/homebrew/bin/qemu-system-aarch64', '/opt/homebrew/bin/qemu-system-x86_64'] { artifacts << pin(path)! }
	prior_sources := json2.decode[Ledger](os.read_file('tests/packages/results/2026-10-16/import-lookup-toolchain.json')!)!
	mut source_paths := prior_sources.sources.map(it.path)
	source_paths << ['tools/packages/pkgcore/image_check.v', 'tools/packages/pkgcore/image_check_test.v', 'tests/packages/image-input-check.v',
		'tests/packages/image-input-runtime-check.v', 'tests/packages/image-input-guest/main.v', 'tests/packages/image-input-check.md']
	source_paths.sort(); mut sources := []Pin{}; for path in source_paths { sources << pin(path)! }
	changed := ['tools/packages/stage.v', 'tools/packages/README.md', 'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md']
	for source in prior_sources.sources { if source.path in changed { continue }; actual := pin(source.path)!; assert actual.sha256 == source.sha256 && actual.bytes == source.bytes, source.path }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!; assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'Compiler-free release image package preflight: reproducible effective trust/policy and exact configuration/index digests, signed full-bundle architecture/proprietary/firmware counts, unique payload bytes and conservative disk budget; publish/preserve/none decisions, existing-state preservation, unsafe/corrupt/changed destination refusals and independent reports. Real staging CLI option/environment selection, literal paths, compiler bypass and normal missing/non-executable compiler diagnostics. Twenty-two host checks including eight assertion suites, sanitizer with leak detection disabled and signed CLI maintenance; four controller guards; final AArch64/x86-64 nine-artifact guests with real staging CLI, all five runners and guest poweroff. First diagnostic-gap failures retained separately. Kernels match installed-root qualification. No whole-plan memory, full image-build, production publisher/catalog or graphical/runtime/device acceptance claim.',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified twenty-two host checks, two nine-artifact guests, shutdown and ' + sources.len.str() + ' source pins')
}
