module main
import crypto.sha256
import json2
import os
import time

struct Pin { path string bytes u64 sha256 string }
struct Check { name string code int seconds f64 }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string seconds f64 artifacts []Artifact }
struct Ledger { format int = 1 baseline string = '0e20fd6bf' completed_at i64 compiler Pin sources []Pin evidence []Pin scope string }
const work = 'build/package-deployment-form-work'
const prefix = 'tests/packages/results/2026-10-17/deployment-form-'
const owned = ['desktop/software_app.v', 'desktop/software_deployment.v', 'desktop/software_deployment_navigation.v',
	'desktop/software_deployment_form.v', 'tests/packages/software_deployment_form_fixture.v',
	'tests/packages/software_deployment_navigation_fixture.v', 'tests/packages/software_fixture.v',
	'tests/packages/software_image_fixture.v', 'tests/packages/native-catalog-check.v', 'tests/packages/distribution-check.v',
	'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md',
	'tests/packages/software-deployment-navigation-check.md', 'tests/packages/software-deployment-form-check.md']
const marker = 'SOFTWARE IMAGE compact-deployment 320x240 keyboard paging visible release review and audit separate approval PASS'
const memory_marker = 'Software compact deployment: 1000 seven-action render/edit/rejected-paste/keyboard/full/compact/tiny/retirement cycles retain zero tracked bytes PASS'

fn pin(path string) !Pin {
	data := os.read_bytes(path)!; defer { unsafe { data.free() } }
	return Pin{ path: path, bytes: u64(data.len), sha256: sha256.sum(data).hex() }
}
fn good(text string) {
	for forbidden in ['V panic:', 'HWTEST FAIL', 'ERROR: AddressSanitizer', 'runtime error:']! { assert !text.contains(forbidden), forbidden }
}
fn matching(path string, artifact Artifact) !Pin {
	actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
	return actual
}
fn retain() ! {
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	mut checks := json2.decode[[]Check](os.read_file(work + '/ui-results.json')!)!
	checks << json2.decode[[]Check](os.read_file(work + '/asan-results.json')!)!
	assert checks.len == 16 && checks.all(it.code == 0)
	mut evidence := []Pin{}
	for check in checks { good(os.read_file(work + '/' + check.name + '.txt')!); evidence << pin(work + '/' + check.name + '.txt')! }
	driver := os.read_file(work + '/distribution.txt')!; good(driver)
	assert driver.contains('Software distribution checks passed') && driver.contains(memory_marker)
	ui := os.read_file(work + '/ui-functional.txt')!
	assert ui.contains('Software compact deployment: complete bounded help and controls at 320x240')
	memory := os.read_file(work + '/ui-form-memory.txt')! + os.read_file(work + '/ui-navigation-memory.txt')! + os.read_file(work + '/ui-memory.txt')! + os.read_file(work + '/ui-release-memory.txt')!
	assert memory.contains(memory_marker)
	os.write_file(prefix + 'host.json', json2.encode(checks) + '\n')!
	os.write_file(prefix + 'ui.txt', ui)!
	os.write_file(prefix + 'memory.txt', memory)!
	os.write_file(prefix + 'driver.txt', driver)!
	os.write_file(prefix + 'asan.txt', 'ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1\nSoftware controller instrumented; session broker compiled normally.\n\n'
		+ os.read_file(work + '/asan-functional.txt')! + os.read_file(work + '/asan-form-memory.txt')! + os.read_file(work + '/asan-navigation-memory.txt')! + os.read_file(work + '/asan-memory.txt')! + os.read_file(work + '/asan-release-memory.txt')!)!
	mut summary := '16 focused Software compile/run checks passed, including ASan/UBSan with leak detection disabled. Maintained Software functional suite, all 28 allocation modes, both full Linux desktop target typechecks and launcher checks passed.\n'
	mut artifacts := 0
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		base := 'build/pform-software-' + short + '-1'; root := base + '/guest/root'
		receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.artifacts.len > 40
		for artifact in receipt.artifacts {
			path := match artifact.role {
				'kernel' { base + '/kernel' }
				'guest-init' { base + '/guest/init' }
				'input-build-record' { 'build/package-native-catalog-work/inputs/build.json' }
				'serial-log' { base + '/native/serial.log' }
				'qmp-log' { base + '/native/qmp.log' }
				else {
					if artifact.role.starts_with('input/') { base + '/verified-inputs/usr/share/native-catalog/' + artifact.role[6..] }
					else if artifact.role.starts_with('image/') { root + '/' + artifact.role[6..] }
					else { root + '/' + artifact.role }
				}
			}
			evidence << matching(path, artifact)!; artifacts++
		}
		kernel := receipt.artifacts.filter(it.role == 'kernel')[0]
		assert kernel.sha256 == if short == 'arm' { 'cfa3788c594b308c6009bee49d9e08a92feb5c23fe3b710ab5142427fc1f2d7e' }
			else { 'a989a9b1aff3db4260fe435336d3fba6120450992a96ab0fccbab27c38dce5b1' }
		serial := os.read_file(base + '/native/serial.log')!; good(serial)
		assert serial.contains(marker) && serial.contains('HWTEST PASS packages-software-image')
		assert serial.contains('SOFTWARE RELEASE audit standard-account installed=1.0.0')
		for secret in ['alex has a password', 'sam has another', 'incorrect fixture password']! { assert !serial.contains(secret) }
		qmp := os.read_file(base + '/native/qmp.log')!; assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		for suffix, source in {'.json': base + '/qualification.json', '.serial.txt': base + '/native/serial.log', '.qmp.txt': base + '/native/qmp.log', '.stage.txt': base + '/stage.log'} { os.cp(source, prefix + architecture + suffix)! }
		assert os.read_file(base + '/publisher/image-config.json')! == os.read_file(root + '/etc/vinix-packages/config.json')!
		for file in os.ls(base + '/software-source')! {
			original := if file == 'main.v' { 'tests/packages/software_image_fixture.v' } else if file == 'terminal_fixture.v' { 'tests/packages/software_terminal_fixture.v' } else { 'desktop/' + file }
			assert pin(base + '/software-source/' + file)!.sha256 == pin(original)!.sha256
			evidence << pin(base + '/software-source/' + file)!
		}
		for file in ['publisher/image-config.json', 'publisher/image-applications.json', 'package-stage', 'software-build/software-image.c']! { evidence << pin(base + '/' + file)! }
		summary += architecture + ' Software guest PASS ' + receipt.seconds.str() + 's, ' + receipt.artifacts.len.str() + ' artifacts\n'
	}
	os.write_file(prefix + 'summary.txt', summary)!
	os.write_file(prefix + 'attempts.txt', 'The first UI functional run passed the new complete-help/geometry/action-routing assertions and zero-retention form check, then failed an older navigation assertion requiring Failure details to stay on the initial compact screen. That fixture now opens diagnostics through the visible pager and keeps its worker, error, Back and protected-transaction assertions. Final UI, sanitizers, maintained driver and both guest runs passed with unchanged final product/fixture sources.\n\nInitial functional output:\n' + os.read_file(work + '/first-ui-functional.txt')!)!
	for file in ['checks.v', 'guest.v', 'retain.v']! { os.cp(work + '/' + file, prefix + file)! }
	mut paths := owned.clone()
	for directory in ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring', 'desktop/workflowcore', 'desktop/packagecore', 'desktop/sessioncore', 'desktop/sessionipc', 'desktop/sessiondaemon', 'desktop/serviceprocess', 'tests/accounts/guest', 'tests/hardware-platform/hwhost']! {
		for extension in ['.v', '.h', '.c']! { paths << os.walk_ext(directory, extension).filter(!it.contains('.v3cc.') && !it.contains('/.cache/')) }
	}
	for file in os.ls('desktop')! { if file.ends_with('.v') || file.ends_with('.h') || file.ends_with('.vml') { paths << 'desktop/' + file } }
	for file in os.ls('tests/packages')! { if file.starts_with('software_') && file.ends_with('_fixture.v') { paths << 'tests/packages/' + file } }
	paths << os.walk_ext('build/package-view-reader-work/desktop/modules', '.v')
	paths << ['desktop/tools/tests/heap_tracker.h', work + '/checks.v', work + '/guest.v', work + '/retain.v']
	for stage in ['ui-sources-final', 'asan-sources-final']! {
		for file in os.ls(work + '/' + stage)! {
			original := if file == 'main.v' { 'tests/packages/software_fixture.v' } else if file.ends_with('_fixture.v') { 'tests/packages/' + file } else { 'desktop/' + file }
			actual := work + '/' + stage + '/' + file
			assert pin(actual)!.sha256 == pin(original)!.sha256; evidence << pin(actual)!
		}
	}
	for file in ['checks', 'guest', 'software-controller', 'distribution', 'ui', 'asan', 'ui-results.json', 'asan-results.json', 'distribution.txt', 'first-ui-functional.txt']! { evidence << pin(work + '/' + file)! }
	paths.sort(); mut sources := []Pin{}; mut seen := map[string]bool{}
	for path in paths { if path !in seen { seen[path] = true; sources << pin(path)! } }
	mut commit_paths := owned.clone()
	for file in os.ls(os.dir(prefix))! { if file.starts_with('deployment-form-') && !file.ends_with('toolchain.json') { path := os.dir(prefix) + '/' + file; commit_paths << path; evidence << pin(path)! } }
	commit_paths << prefix + 'toolchain.json'
	os.write_file(work + '/owned-paths.json', json2.encode(commit_paths) + '\n')!
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ completed_at: time.now().unix(), compiler: compiler, sources: sources, evidence: evidence,
		scope: 'Compact idle Deployment forms at 320x240: complete bounded help/geometry, literal path editing, visible paged existing actions, optional release/failure availability, keyboard and resize anchors, late picker retirement, status/failure and read-only workflow routing. Existing full review/approval and pending/approved worker guards retained. Sixteen focused host checks, ASan/UBSan with leak detection disabled, maintained complete Software functional and 28 allocation modes, both full Linux desktop typechecks and launchers. Two real Software TCG guests use unchanged qualified kernels, actual compact release review/audit, separate administrator approval, standard-account audit, native apps/isolated data and existing maintenance. Initramfs and headless UI trees; no new installed-root, full compositor/firmware/production-catalog/foreign-runtime/device/crash acceptance or whole-service allocation claim.' }) + '\n')!
	println(summary + 'Verified ' + artifacts.str() + ' receipt artifacts, ' + sources.len.str() + ' source pins and ' + evidence.len.str() + ' evidence pins')
}
fn main() { retain() or { eprintln(err); exit(1) } }
