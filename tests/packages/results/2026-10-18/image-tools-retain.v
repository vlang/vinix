// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import json2
import os

const work = 'build/package-image-tools-work'
const host_work = 'build/image-tools-host-2'
const prefix = 'tests/packages/results/2026-10-18/image-tools-'
struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct HostReceipt { format int baseline_commit string inputs []Pin checks []Check }
struct GuestArtifact { role string path string sha256 string }
struct GuestReceipt { format int architecture string seconds f64 artifacts []GuestArtifact }
struct FilePin { path string bytes u64 sha256 string }
struct Ledger { format int = 1 baseline_commit string = '82e0ce3eb' scope string artifacts []FilePin }

fn pin(path string) !FilePin {
	data := os.read_bytes(path)!; defer { unsafe { data.free() } }
	return FilePin{ path: path, bytes: u64(data.len), sha256: sha256.sum(data).hex() }
}
fn save(source string, name string) ! { os.cp(source, prefix + name)! }
fn verify() ! {
	ledger := json2.decode[Ledger](os.read_file(prefix + 'toolchain.json')!)!
	for item in ledger.artifacts { assert pin(item.path)! == item, item.path }
	println('IMAGE TOOLS verified ' + ledger.artifacts.len.str() + ' source, compiler, artifact and evidence hashes PASS')
}

fn retain() ! {
	host := json2.decode[HostReceipt](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.baseline_commit == '82e0ce3eb' && host.checks.len == 20
	mut paths := []string{}
	mut summary := []string{}
	for item in host.inputs { assert pin(item.path)!.sha256 == item.sha256; paths << item.path }
	for check in host.checks {
		assert check.argv.len > 0 && check.seconds >= 0 && check.artifacts.len == 2
		for item in check.artifacts { assert pin(item.path)!.sha256 == item.sha256; paths << item.path }
		save(host_work + '/' + check.name + '.txt', check.name + '.txt')!
		summary << check.name + ' PASS (' + check.seconds.str() + 's)'
	}
	assert os.read_file(prefix + 'core-run.txt')!.contains('IMAGE TOOLS 58')
	assert os.read_file(prefix + 'sanitize-run.txt')!.contains('IMAGE TOOLS 58')
	assert os.read_file(prefix + 'cli-run.txt')!.contains('IMAGE TOOLS CLI 28')
	assert os.read_file(prefix + 'baseline-reproduces.txt')!.contains('c-2 replaced vinix-package')
	os.write_file(prefix + 'host.txt', summary.join('\n') + '\nIMAGE TOOLS twenty host checks PASS; baseline reproduces mixed tool versions\n')!
	save(host_work + '/qualification.json', 'host.json')!; save(host_work + '/baseline-stage.v', 'baseline-stage.v')!
	mut git := os.new_process('git'); git.set_args(['show', '82e0ce3eb:tools/packages/stage.v']); git.set_redirect_stdio_merged()
	git.run(); original := git.stdout_slurp(); git.wait(); code := git.code; git.close()
	assert code == 0 && original == os.read_file(prefix + 'baseline-stage.v')!
	mut table := '| Target | Result | Native guest time | Evidence |\n| --- | --- | --- | --- |\n'
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		state := 'build/itb-' + short + '-2'
		receipt := json2.decode[GuestReceipt](os.read_file(state + '/qualification.json')!)!
		assert receipt.format == 1 && receipt.architecture == architecture && receipt.artifacts.len == 10
		for artifact in receipt.artifacts {
			assert pin(artifact.path)!.sha256 == artifact.sha256; paths << artifact.path
			if artifact.role == 'host-stage' { assert artifact.sha256 == pin(host_work + '/stage')!.sha256 }
		}
		kernel := if architecture == 'aarch64' { 'cfa3788c594b308c6009bee49d9e08a92feb5c23fe3b710ab5142427fc1f2d7e' } else { 'a989a9b1aff3db4260fe435336d3fba6120450992a96ab0fccbab27c38dce5b1' }
		assert pin(state + '/kernel')!.sha256 == kernel
		serial := os.read_file(state + '/packages-image-tools/serial.log')!.replace('\r', '')
		assert serial.contains('HWTEST PASS packages-image-tools') && !serial.contains('HWTEST FAIL') && !serial.contains('V panic:')
		assert serial.contains('IMAGE TOOLS 58') && serial.contains('IMAGE TOOLS native production-staged package/session/Linux-runner execution PASS')
		mut denied := 0
		for line in serial.split_into_lines() { if line.starts_with('Denied') { assert line.all_after(': ') == '0'; denied++ } }
		assert denied == 14
		for pair in [['qualification.json', architecture + '.json'], ['stage.log', architecture + '.stage.txt'],
			['packages-image-tools/serial.log', architecture + '.serial.txt'], ['packages-image-tools/qmp.log', architecture + '.qmp.txt']] {
			save(state + '/' + pair[0], pair[1])!; paths << state + '/' + pair[0]
		}
		save(work + '/guest-' + architecture + '-2.txt', architecture + '.txt')!
		paths << state + '/guest/build.log'; paths << state + '/guest/program-0/build.log'
		paths << os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!
		table += '| ' + architecture + ' | PASS | ' + receipt.seconds.str() + ' s | [receipt](results/2026-10-18/image-tools-' + architecture + '.json), [serial](results/2026-10-18/image-tools-' + architecture + '.serial.txt), [production staging](results/2026-10-18/image-tools-' + architecture + '.stage.txt) |\n'
	}
	for name in ['guest.v', 'legacy-media.v']! { save(work + '/' + name, name)! }
	document := 'tests/packages/image-tools-check.md'; text := os.read_file(document)!
	if !text.contains('## Recorded results') {
		os.write_file(document, text + '\n## Recorded results, 2026-10-18\n\n' + table + '\nAll **20 host checks passed**, including 58 core cases, 28 real CLI staging\ninvocations, ASan/UBSan and the prior-version failure demonstration. The\n[host receipt](results/2026-10-18/image-tools-host.json) retains exact input and\nartifact hashes, commands and timings; the\n[summary](results/2026-10-18/image-tools-host.txt) lists every check. The\n[baseline log](results/2026-10-18/image-tools-baseline-reproduces.txt) and\n[original source](results/2026-10-18/image-tools-baseline-stage.v) show the mixed\ntool versions after a late compiler failure.\n\nEach native guest passed all 58 cases, executed the three real production-staged\ntools and powered off cleanly. All 14 resource-denial samples per guest were zero;\nthese bounded samples do not establish kernel allocation freedom. Existing\nkernels are pinned. The x86_64 guest uses a V plain-USTAR media adapter for its\npre-gzip kernel; production boot-media tooling and kernel code are unchanged.\n\nThe [retention helper](results/2026-10-18/image-tools-retain.v) verifies receipt\nhashes, the source anchor, failure/preservation markers and native results. Its\n[ledger](results/2026-10-18/image-tools-toolchain.json) pins inputs, compilers,\nbinaries, logs, the media adapter and documentation. Builds use `-nocache`,\ncompiler fallback disabled, and V 0.5.2 `826e96f` with SHA-256\n`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.\n')!
	}
	for path in [@FILE, document, 'tools/packages/SDK.md', 'tools/packages/README.md', 'docs/application-distribution.md', 'roadmap.md',
		'tests/packages/image-tools-runtime-check.v', 'tests/packages/image-tools-guest/main.v',
		host_work + '/baseline-stage.v', host_work + '/inputs.json', work + '/host-controller', work + '/guest-controller',
		work + '/guest', work + '/guest.v', work + '/legacy-media', work + '/legacy-media.v',
		'build/package-launch-transport-work/cross-cc', 'build-support/build-amd64-iso.sh', 'build-support/limine.conf'] { paths << path }
	for path in os.walk_ext('tests/hardware-platform/hwhost', '.v') { if !path.ends_with('_test.v') { paths << path } }
	for name in ['limine', 'limine-uefi-cd.bin', 'limine-bios-cd.bin', 'limine-bios.sys', 'BOOTX64.EFI']! { paths << 'build/alloc-bench-kernel-before-schema2-1/iso-build/limine/' + name }
	for name in os.ls(os.dir(prefix))! { if name.starts_with(os.file_name(prefix)) && name != 'image-tools-toolchain.json' { paths << os.dir(prefix) + '/' + name } }
	mut unique := map[string]bool{}
	mut files := []FilePin{}
	for path in paths {
		absolute := os.abs_path(path); root := os.getwd() + '/'
		name := if absolute.starts_with(root) { absolute[root.len..] } else { absolute }
		if name in unique { continue }; unique[name] = true; files << pin(name)!
	}
	files.sort(a.path < b.path)
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ scope: 'Captured production image tool compilation/publication: 20 host checks, 58 core cases, 28 real CLI invocations, ASan/UBSan, prior-version mixed-tools reproduction; both guests repeat 58 cases and execute all three tools built through the production stager; controlled single-filesystem image parents, bounded captured static ELF, complete-output preflight, atomic per-file publication and checked recovery; no complete-image transaction, kernel allocation freedom or full roadmap 14 acceptance claim', artifacts: files }).replace('},{', '},\n{') + '\n')!
	verify()!
}

fn main() { if os.args.len == 2 && os.args[1] == '--verify' { verify()! } else { retain()! } }
