// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os

fn invoke(program string, args []string) (int, string) {
	mut child := os.new_process(program); child.set_args(args); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	return code, output
}

fn main() {
	assert os.args.len in [4, 5]
	stage := os.real_path(os.args[1]); compiler := os.real_path(os.args[2]); work := os.abs_path(os.args[3])
	assert !os.exists(work); os.mkdir_all(work)!
	repository := os.dir(os.dir(os.dir(@FILE)))
	os.setenv('V', compiler, true)
	for name in ['CONFIG', 'REPOSITORIES', 'APPLICATIONS']! { os.unsetenv('VINIX_PACKAGE_IMAGE_' + name) }
	mut cases := 0
	for architecture in ['aarch64', 'x86_64']! {
		for mode in ['complete', 'leaf-alias', 'license-parent-alias', 'action-parent-alias', 'registration-parent-alias',
			'overrides', 'state-private', 'destination-directory', 'software-alias']! {
			if os.args.len == 5 && os.args[4] != mode { continue }
			directory := work + '/' + architecture + '-' + mode
			root := directory + '/image'; os.mkdir_all(root)!
			outside := directory + '/outside'; os.mkdir(outside)!; os.write_file(outside + '/keep', 'outside preserved')!; os.chmod(outside + '/keep', 0o600)!
			for parent in ['usr/share/licenses/vinix-packages', 'usr/bin', 'usr/share/vinix/actions', 'usr/share/applications']! { os.mkdir_all(root + '/' + parent)! }
			if mode == 'leaf-alias' { os.symlink(outside + '/keep', root + '/usr/share/licenses/vinix-packages/ed25519-MIT.txt')! }
			if mode == 'software-alias' { os.symlink(outside, root + '/usr/bin/vinix-software')! }
			if mode.ends_with('-parent-alias') {
				path := root + match mode { 'license-parent-alias' { '/usr/share/licenses' } 'action-parent-alias' { '/usr/share/vinix/actions' } else { '/usr/share/applications' } }
				os.rename(path, directory + '/saved-parent')!; os.symlink(outside, path)!
			}
			if mode == 'overrides' {
				os.write_file(root + '/usr/share/vinix/actions/packages-change', 'administrator action')!
				os.symlink(outside + '/keep', root + '/usr/share/vinix/actions/packages-launch')!
				os.symlink('/administrator/registration', root + '/usr/share/applications/vinix-packages')!
			}
			if mode == 'state-private' { os.mkdir_all(root + '/var/lib/vinix-packages')!; os.chmod(root + '/var/lib/vinix-packages', 0o700)! }
			if mode == 'destination-directory' { os.mkdir(root + '/usr/bin/vinix-software')! }
			os.setenv('VINIX_IMAGE_TOOL_CLI_WORK', directory, true); os.setenv('VINIX_IMAGE_TOOL_FAULT', 'complete', true)
			code, output := invoke(stage, ['--arch', architecture, '--staging', root, '--cc-argv', json2.encode([compiler])])
			os.write_file(directory + '/stage.txt', output)!
			// The original stager follows this license alias and changes both the
			// outside bytes and their mode. Keep this assertion for reproduction.
			assert os.read_file(outside + '/keep')! == 'outside preserved' && os.stat(outside + '/keep')!.mode & 0o7777 == 0o600, 'outside license target changed'
			assert os.ls(outside)! == ['keep'], 'image publication escaped into an outside directory'
			if mode.ends_with('-parent-alias') || mode == 'destination-directory' {
				assert code != 0 && output.contains('image integration incomplete'), output
				assert !os.exists(root + '/etc')
			} else {
				assert code == 0, output
				assert os.read_file(root + '/usr/share/licenses/vinix-packages/ed25519-MIT.txt')! == os.read_file(repository + '/tools/packages/signing/LICENSE')!
				assert os.read_file(root + '/usr/share/licenses/vinix-packages/application-sdk-MIT.txt')! == os.read_file(repository + '/tools/packages/appsdk/LICENSE')!
				assert os.is_link(root + '/usr/bin/vinix-software') && os.is_link(root + '/usr/share/applications/vinix-packages')
				if mode == 'overrides' { assert os.read_file(root + '/usr/share/vinix/actions/packages-change')! == 'administrator action'; assert os.is_link(root + '/usr/share/vinix/actions/packages-launch') }
				else { for name in ['packages-change', 'packages-launch']! { assert os.read_file(root + '/usr/share/vinix/actions/' + name)! == os.read_file(repository + '/tools/accounts/actions/' + name)! } }
				if mode == 'state-private' { assert os.stat(root + '/var/lib/vinix-packages')!.mode & 0o7777 == 0o700 }
				assert os.exists(root + '/etc/vinix-packages/config.json') && os.ls(root + '/var/lib/vinix-packages')!.len == 0
			}
			assert os.read_lines(directory + '/calls.jsonl')!.len == 6
			cases++
		}
	}
	println('IMAGE INTEGRATION CLI ' + cases.str() + ' real staging cases preserve outside bytes/modes and administrator overrides PASS')
}
