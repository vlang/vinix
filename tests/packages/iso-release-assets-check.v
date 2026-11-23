// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os

const x11 = 'vinix-x11-amd64.tar.gz'
const arm_x11 = 'vinix-x11-arm64.tar.gz'
const ios = 'vinix-ios-runtime-arm64'
const upload_changes = ['vinix-amd64.iso', x11, 'SHA256SUMS', 'RELEASE_NOTES.md']
const changed_during_upload = 'changed during upload\n'

fn command(program string, args []string, root string, environment map[string]string) (int, string) {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.set_work_folder(root)
	child.set_environment(environment)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	return child.code, output
}

fn git(root string, args []string) ! {
	code, output := command(os.find_abs_path_of_executable('git')!, args, root, os.environ())
	if code != 0 { return error('fixture git: ' + output) }
}

fn checksum_line(path string) !string {
	return '${sha256.hexhash(os.read_file(path)!)}  ${os.file_name(path)}'
}

fn fixture_bundle(path string) ! {
	os.write_file(path, 'fixture bundle\n')!
	checksum := if os.getenv('VINIX_ASSET_TEST_CASE') == 'bad-build-sidecar' {
		'${'0'.repeat(64)}  ${os.file_name(path)}'
	} else { checksum_line(path)! }
	os.write_file(path + '.sha256', checksum + '\n')!
}

fn fixture_runtime() ! {
	path := os.getenv('VINIX_IOS_BUILD_DIR') + '/staging/usr/bin/run-ios'
	os.mkdir_all(os.dir(path))!
	mut header := []u8{len: 128}
	for index, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { header[index] = byte }
	header[16] = 2 // ET_EXEC
	header[18] = 183 // EM_AARCH64
	header[20] = 1 // EV_CURRENT
	header[32] = 64 // Program table offset
	header[52] = 64 // ELF header size
	header[54] = 56 // Program header size
	header[56] = 1 // One program header
	header[64] = 1 // PT_LOAD
	os.write_file_array(path, header)!
	os.chmod(path, 0o755)!
}

fn capture_upload(out string, scenario string) ! {
	args := os.args[1..]
	files := args.filter(it.starts_with('/'))
	notes_option := args.index('--notes-file')
	if notes_option < 0 || notes_option + 1 >= args.len || files.len < 2 {
		return error('release handoff is missing upload files or notes')
	}
	notes := args[notes_option + 1]
	stage := os.dir(notes)
	if stage == out || notes != stage + '/RELEASE_NOTES.md' || files.any(os.dir(it) != stage) {
		return error('release handoff did not use a common private staging directory')
	}
	os.cp(out + '/SHA256SUMS', out + '/fixture-original-manifest')!
	os.cp(out + '/RELEASE_NOTES.md', out + '/fixture-original-notes')!
	if scenario == 'output-change-during-upload' {
		for name in upload_changes {
			os.write_file(out + '/' + name, changed_during_upload)!
		}
	}
	os.write_file(out + '/fixture-upload-digests', files.map(checksum_line(it)!).join('\n') + '\n')!
	os.write_file(out + '/fixture-upload', args.join('\n') + '\n')!
}

fn run_stub(name string) !int {
	out := os.getenv('VINIX_ASSET_TEST_OUT')
	scenario := os.getenv('VINIX_ASSET_TEST_CASE')
	match name {
		'get-deps', 'build-aarch64.sh' {}
		'build-desktop-amd64.sh' {
			os.cp(os.getenv('VINIX_ASSET_TEST_AMD64_ISO'), os.getenv('VINIX_AMD64_DESKTOP_ISO'))!
			fixture_bundle(os.getenv('VINIX_AMD64_X11_BUNDLE'))!
		}
		'build-desktop-aarch64.sh' { fixture_bundle(os.getenv('VINIX_X11_BUNDLE'))! }
		'build-ios-aarch64.sh' { fixture_runtime()! }
		'build-aarch64-iso.sh' {
			os.cp(os.getenv('VINIX_ASSET_TEST_ARM64_ISO'), os.getenv('VINIX_AARCH64_ISO'))!
		}
		'test-iso.sh' {
			os.write_file(out + '/fixture-boot', 'boot test ran\n')!
			match scenario {
				'x11-after-boot' { os.write_file(out + '/' + x11, 'changed X11 fixture\n')! }
				'ios-pair-after-boot' {
					path := out + '/' + ios
					os.write_file(path, 'changed iOS fixture\n')!
					os.write_file(path + '.sha256', checksum_line(path)! + '\n')!
				}
				'receipt-after-boot' { os.write_file(out + '/vinix-packages-amd64.json', 'changed receipt\n')! }
				else {}
			}
			println('  PASS  qemu-amd64-bios')
		}
		'human-size' {
			if scenario == 'sidecar-at-handoff' {
				os.write_file(out + '/' + x11 + '.sha256', 'changed sidecar\n')!
			} else if scenario == 'manifest-at-handoff' {
				os.write_file(out + '/SHA256SUMS', 'changed checksum list\n')!
			}
			println('fixture size')
		}
		'gh' {
			if os.args[1] in ['auth', 'api']! { return 0 }
			upload := out + '/fixture-upload'
			if os.args[1..3] == ['release', 'view'] {
				if !os.exists(upload) { return 1 }
				println('https://example.invalid/fixture')
			} else if os.args[1..3] == ['release', 'create'] {
				capture_upload(out, scenario)!
			} else { return error('unexpected fixture gh invocation') }
		}
		else { return error('unknown release fixture program: ' + name) }
	}
	return 0
}

fn prepare_driver(repository string, root string) ! {
	for directory in ['scripts', 'build-support/isoboot', 'build-support/init-aarch64', 'kernel',
		'ui2', 'fake-bin', 'build-amd64-x11/staging', 'build-amd64-network-tools/staging',
		'build-aarch64-userland/staging', 'build-aarch64-x11/staging', 'build-aarch64-network-tools/staging']! {
		os.mkdir_all(root + '/' + directory)!
	}
	for path in ['scripts/deploy-iso.sh', 'build-support/find-v.sh', 'build-support/isoboot/release-assets.v',
		'build-support/isoboot/package-receipt.v']! {
		os.cp(repository + '/' + path, root + '/' + path)!
	}
	os.write_file(root + '/ui2/v.mod', 'module fixture')!
	os.write_file(root + '/build-support/init-aarch64/initramfs.tar', 'fixture input')!
	for path in ['tools', 'build-support/tarstream', 'build-support/tarcore']! {
		os.symlink(repository + '/' + path, root + '/' + path)!
	}
	for path in ['kernel/get-deps', 'build-support/human-size', 'fake-bin/gh', 'scripts/build-desktop-amd64.sh',
		'scripts/build-desktop-aarch64.sh', 'scripts/build-aarch64.sh', 'scripts/build-ios-aarch64.sh',
		'build-support/build-aarch64-iso.sh', 'scripts/test-iso.sh']! {
		os.symlink(os.executable(), root + '/' + path)!
	}
	git(root, ['init', '-q'])!
	git(root, ['add', 'scripts', 'build-support', 'kernel'])!
	git(root, ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
		'-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Release fixture'])!
}

fn verify_handoff(out string, with_packages bool, mutated bool) ! {
	mut names := ['vinix-amd64.iso', 'vinix-arm64.iso', x11, x11 + '.sha256', arm_x11,
		arm_x11 + '.sha256', ios, ios + '.sha256']
	if with_packages { names << ['vinix-packages-amd64.json', 'vinix-packages-arm64.json'] }
	manifest := os.read_file(out + '/fixture-original-manifest')!
	notes := os.read_file(out + '/fixture-original-notes')!
	mut listed := manifest.trim_right('\n').split('\n')
	mut listed_names := listed.map(it.all_after('  '))
	listed_names.sort()
	names.sort()
	if listed_names != names { return error('release checksum list names the wrong assets') }
	for line in listed {
		name := line.all_after('  ')
		if mutated && name in upload_changes { continue }
		if line != checksum_line(out + '/' + name)! {
			return error('release checksum differs from its asset: ' + name)
		}
	}
	if mutated {
		for name in upload_changes {
			if os.read_file(out + '/' + name)! != changed_during_upload {
				return error('release output was not changed during upload: ' + name)
			}
		}
	}
	listed << ['${sha256.hexhash(manifest)}  SHA256SUMS',
		'${sha256.hexhash(notes)}  RELEASE_NOTES.md']
	mut uploaded := os.read_lines(out + '/fixture-upload-digests')!
	listed.sort()
	uploaded.sort()
	if uploaded != listed { return error('release handoff bytes differ from the verified assets') }
}

fn run() ! {
	if os.args.len != 5 { return error('usage: iso-release-assets-check VINIX_REPO NEW_STATE AMD64_MATCH_CASE ARM64_MATCH_CASE') }
	repository := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	am := os.real_path(os.args[3])
	arm := os.real_path(os.args[4])
	os.mkdir(work, mode: 0o700)!
	root := work + '/driver'
	prepare_driver(repository, root)!
	mut base := os.environ()
	for symbol in base.keys() {
		if symbol.starts_with('VINIX_PACKAGE_IMAGE_') || symbol.starts_with('VINIX_IOS_RELEASE_RUNTIME')
			|| symbol.starts_with('BASH_FUNC_') || symbol == 'BASH_ENV' {
			base.delete(symbol)
		}
	}
	base['PATH'] = root + '/fake-bin:' + os.getenv('PATH')
	base['VINIX_UI2_SOURCE'] = root + '/ui2'
	base['VINIX_ASSET_TEST_AMD64_ISO'] = am + '/image.iso'
	base['VINIX_ASSET_TEST_ARM64_ISO'] = arm + '/image.iso'
	for scenario in ['legacy', 'packages', 'output-change-during-upload', 'bad-build-sidecar',
		'x11-after-boot', 'ios-pair-after-boot', 'receipt-after-boot', 'sidecar-at-handoff',
		'manifest-at-handoff', 'build-only']! {
		with_packages := scenario in ['packages', 'receipt-after-boot', 'output-change-during-upload']!
		mut environment := base.clone()
		if with_packages {
			for arch, dir in {'X86_64': am, 'AARCH64': arm} {
				environment['VINIX_PACKAGE_IMAGE_CONFIG_' + arch] = dir + '/root/etc/vinix-packages/config.json'
				environment['VINIX_PACKAGE_IMAGE_REPOSITORIES_' + arch] = dir + '/root/usr/share/vinix-packages/repositories'
				environment['VINIX_PACKAGE_IMAGE_APPLICATIONS_' + arch] = dir + '/root/usr/share/vinix-packages/applications.json'
			}
		}
		out := root + '/build-release/fixture-' + scenario
		environment['VINIX_ASSET_TEST_OUT'] = out
		environment['VINIX_ASSET_TEST_CASE'] = scenario
		mut args := [root + '/scripts/deploy-iso.sh', '--tag=fixture-' + scenario, '--yes',
			'--repo=local/fixture']
		if scenario == 'build-only' { args << ['--arch=amd64', '--no-publish'] }
		code, log := command('/bin/bash', args, root, environment)
		os.write_file(work + '/' + scenario + '.log', log)!
		if os.ls(root + '/build-release/work')!.any(it.starts_with('release-assets.')) {
			return error('release left a private staging directory: ' + scenario)
		}
		if scenario in ['legacy', 'packages', 'output-change-during-upload']! {
			if code != 0 { return error('release fixture failed: ' + scenario + '\n' + log) }
			verify_handoff(out, with_packages, scenario == 'output-change-during-upload')!
		} else if scenario == 'build-only' {
			if code != 0 || os.exists(out + '/fixture-upload') || !os.exists(out + '/RELEASE_NOTES.md') {
				return error('build-only fixture failed\n' + log)
			}
			expected := ['vinix-amd64.iso', x11, x11 + '.sha256'].map(checksum_line(out + '/' + it)!)
			if expected != os.read_lines(out + '/SHA256SUMS')! {
				return error('build-only checksums differ from the output assets')
			}
		} else {
			diagnostic := match scenario {
				'bad-build-sidecar' { 'release bundle checksum differs from its payload' }
				'manifest-at-handoff' { 'SHA256SUMS changed after verification' }
				else { 'release asset changed after verification' }
			}
			if code == 0 || !log.contains(diagnostic) || os.exists(out + '/fixture-upload') {
				return error('release refusal fixture failed: ' + scenario + '\n' + log)
			}
			if os.exists(out + '/fixture-boot') != (scenario != 'bad-build-sidecar') {
				return error('unexpected boot test handoff: ' + scenario)
			}
		}
		println('ISO release assets ${scenario} PASS')
	}
}

fn main() {
	name := os.file_name(os.args[0])
	if name in ['get-deps', 'human-size', 'gh', 'test-iso.sh', 'build-desktop-amd64.sh',
		'build-desktop-aarch64.sh', 'build-aarch64.sh', 'build-ios-aarch64.sh', 'build-aarch64-iso.sh']! {
		exit(run_stub(name) or { eprintln(err); 2 })
	}
	run() or { eprintln(err); exit(1) }
}
