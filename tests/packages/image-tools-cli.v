// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tests.packages.elffixture

fn invoke(program string, arguments []string) (int, string) {
	mut child := os.new_process(program); child.set_args(arguments); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	return code, output
}

fn main() {
	assert os.args.len in [4, 5]
	stage := os.real_path(os.args[1]); compiler := os.real_path(os.args[2]); work := os.abs_path(os.args[3])
	assert !os.exists(work); os.mkdir(work)!
	os.setenv('V', compiler, true)
	for name in ['CONFIG', 'REPOSITORIES', 'APPLICATIONS']! { os.unsetenv('VINIX_PACKAGE_IMAGE_' + name) }
	mut cases := 0
	for architecture in ['aarch64', 'x86_64']! {
		for mode in ['complete', 'v-0', 'v-1', 'v-2', 'c-0', 'c-1', 'c-2', 'wrong-0', 'wrong-1', 'wrong-2',
			'corrupt-previous', 'workspace-replaced', 'root-replaced', 'unsafe-parent']! {
			if os.args.len == 5 && os.args[4] != mode { continue }
			directory := work + '/' + architecture + '-' + mode
			root := directory + '/image'; os.mkdir_all(root)!
			os.mkdir(directory + '/outside')!; os.write_file(directory + '/outside/keep', 'outside data')!
			parents := ['/usr/bin', '/usr/sbin', '/usr/libexec/vinix']!
			names := ['vinix-package', 'vinix-session', 'vinix-linux-runner']!
			for i, name in names {
				os.mkdir_all(root + parents[i])!; os.write_file(root + parents[i] + '/' + name, 'previous ' + name)!
				os.chmod(root + parents[i] + '/' + name, 0o755)!
				os.symlink(directory + '/outside/keep', root + parents[i] + '/' + name + '.new')!
			}
			if mode == 'unsafe-parent' {
				os.rename(root + '/usr/libexec', directory + '/saved-libexec')!
				os.symlink(directory + '/outside', root + '/usr/libexec')!
			}
			os.setenv('VINIX_IMAGE_TOOL_CLI_WORK', directory, true); os.setenv('VINIX_IMAGE_TOOL_FAULT', mode, true)
			literal := 'compiler argument ; $literal `kept` 空'
			code, output := invoke(stage, ['--arch', architecture, '--staging', root, '--cc-argv', json2.encode([compiler, literal])])
			os.write_file(directory + '/stage.txt', output)!
			if mode == 'complete' { assert code == 0, output }
			else { assert code != 0, output }
			if mode.starts_with('c-') || mode.starts_with('v-') { assert output.contains('injected compiler failure') && output.contains('failed (37)'), output }
			if mode == 'workspace-replaced' { assert output.contains('cleanup refused') && os.read_file(directory + '/saved-workspace/vinix-package.c')! == architecture, output }
			if mode == 'root-replaced' { assert output.contains('image root changed') && os.read_file(root + '/keep')! == 'replacement image', output }
			for i, name in names {
				parent := if mode == 'root-replaced' { directory + '/saved-image' + parents[i] }
					else if mode == 'unsafe-parent' && i == 2 { directory + '/saved-libexec/vinix' } else { root + parents[i] }
				if mode == 'complete' {
					mut data := elffixture.image(architecture, 'static'); data[400] = u8(i + 1)
					assert os.read_bytes(parent + '/' + name)! == data && os.stat(parent + '/' + name)!.mode & 0o7777 == 0o755
				} else { assert os.read_file(parent + '/' + name)! == 'previous ' + name, mode + ' replaced ' + name }
				assert os.is_link(parent + '/' + name + '.new') && !os.ls(parent)!.any(it.starts_with('.package-'))
			}
			assert os.read_file(directory + '/outside/keep')! == 'outside data'
			calls := os.read_lines(directory + '/calls.jsonl')!
			for call in calls {
				args := json2.decode[[]string](call)!
				assert args.any(it.contains('/.vinix-package-build-')) && !args.any(it.contains('/vinix-package-stage-'))
				if literal in args { assert '-static' in args }
			}
			if mode == 'complete' { assert calls.len == 6 && os.exists(root + '/etc/vinix-packages/config.json') }
			else { assert !os.exists(root + '/etc') && !os.exists(root + '/var') }
			if mode == 'workspace-replaced' {
				path := os.read_file(directory + '/replacement-path')!
				assert os.read_file(path + '/keep')! == 'replacement compiler workspace'; os.rmdir_all(path)!
			}
			cases++
		}
	}
	println('IMAGE TOOLS CLI ' + cases.str() + ' real staging orchestration cases preserve tools on compiler/target/identity refusal; literal arguments, private workspaces and unrelated aliases PASS')
}
