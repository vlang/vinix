// SPDX-License-Identifier: GPL-2.0-or-later
module copycore

import hosttest
import os

fn test_missing_imports_are_copied_without_unfiltering_existing_modules() {
	work := hosttest.work_dir('', 'vinix-copy-source-test-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	kernel := work + '/kernel'
	destination := work + '/scratch'
	contents := {
		'v.mod':               "Module { name: 'kernel' }\n"
		'main.v':              'import drm.simple as simpledrm\nimport proc\n'
		'drm/simple/simple.v': 'module simple\nimport drm.gem\n'
		'drm/gem/gem.v':       'module gem\nimport drm.simple\n'
		'proc/proc.v':         'module proc\n'
		'proc/proc_arm64.v':   'module proc\n'
	}
	for name, text in contents {
		path := kernel + '/' + name
		os.mkdir_all(os.dir(path))!
		os.write_file(path, text)!
	}
	os.write_file(work + '/files', 'main.v\nproc/proc.v\n')!
	copied := copy_sources(kernel, work + '/files', destination)!
	assert copied == ['drm/gem/gem.v', 'drm/simple/simple.v', 'main.v', 'proc/proc.v']
	assert !os.exists(destination + '/proc/proc_arm64.v')
	assert os.read_file(destination + '/v.mod')! == contents['v.mod']
	for name in copied {
		assert os.read_file(destination + '/' + name)! == contents[name]
		assert os.stat(destination + '/' + name)!.mtime == os.stat(kernel + '/' + name)!.mtime
	}
}

fn test_import_parser_aliases_line_endings_and_whitespace() {
	assert imports('module main\r\n\timport foo.bar as baz\r\nimport\n_test\nimport\u2000c2\n// import ignored\nimportant bad\n') == [
		'foo.bar',
		'_test',
		'c2',
	]
}

fn test_relative_destinations_and_literal_unix_backslashes() {
	work := hosttest.work_dir('', 'vinix-copy-relative-test-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	previous := os.getwd()
	os.chdir(work)!
	defer { os.chdir(previous) or { panic(err) } }
	os.mkdir('kernel')!
	os.mkdir('kernel/literal\\backslash')!
	os.write_file('kernel/literal\\backslash/main.v', 'module main\n')!
	os.write_file('kernel/v.mod', "Module { name: 'kernel' }\n")!
	os.write_file('files', 'literal\\backslash/main.v\n')!
	assert copy_sources('kernel', 'files', 'out')! == ['literal\\backslash/main.v']
	assert os.read_file('out/literal\\backslash/main.v')! == 'module main\n'
	assert !os.exists('out/literal/backslash')
}

fn test_report_requires_both_architectures_and_update_preserves_complete_baseline() {
	work := hosttest.work_dir('', 'vinix-allocation-runner-test-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	tool := work + '/copy-sources'
	hosttest.command([@VEXE, '-cc', 'cc', '-o', tool,
		hosttest.root() + '/tests/kernel-allocs/copy_sources.v'], '', -1, os.environ())!
	for index, failed_arch in ['', 'arm64', 'amd64', 'amd64'] {
		root := work + '/case-' + index.str()
		test_path := root + '/tests/kernel-allocs'
		os.mkdir_all(test_path)!
		os.cp(hosttest.root() + '/tests/kernel-allocs/run.sh', test_path + '/run.sh')!
		os.mkdir_all(root + '/build-support')!
		os.cp(hosttest.root() + '/build-support/find-v.sh', root + '/build-support/find-v.sh')!
		os.mkdir(root + '/kernel')!
		os.write_file(root + '/kernel/main.v', 'module main\n')!
		os.write_file(root + '/kernel/v.mod', "Module { name: 'kernel' }\n")!
		baseline := 'main.v array initialization\t1\n'
		os.write_file(test_path + '/allowed.txt', baseline)!
		commands := root + '/commands'
		os.mkdir(commands)!
		os.write_file(commands + '/make', "#!/bin/sh\nprintf '%s\\n' 'for f in main.v; do :; done'\n")!
		os.write_file(commands + '/v', '#!/bin/sh\nif [ "$1" = version ]; then echo "V 0.5.2 test"; exit 0; fi\narch=\nprevious=\nsource=\nfor argument in "$@"; do\n if [ "$previous" = -arch ]; then arch=$argument; fi\n previous=$argument\n source=$argument\ndone\nprintf "%s/main.v:1:1: warning: allocation (array initialization)\\n" "$source"\nif [ "$FAILED_ARCH" = "$arch" ]; then echo "builder error: preserved compiler diagnostic" >&2; exit 7; fi\n')!
		os.chmod(commands + '/make', 0o755)!
		os.chmod(commands + '/v', 0o755)!
		mut environment := os.environ()
		environment['PATH'] = commands + ':' + environment['PATH']
		environment['V'] = commands + '/v'
		environment['FAILED_ARCH'] = failed_arch
		environment['VINIX_KERNEL_ALLOCS_COPY_TOOL'] = tool
		mut argv := ['sh', test_path + '/run.sh']
		if index == 3 { argv << '--update' }
		result := hosttest.capture(argv, '', -1, environment)!
		if failed_arch == '' {
			assert result.code == 0, result.stderr
			assert result.stderr.contains('aarch64: 1 source files')
			assert result.stderr.contains('x86_64: 1 source files')
		} else {
			assert result.code != 0
			assert result.stderr.contains('preserved compiler diagnostic')
			assert result.stderr.contains('allocation report is incomplete')
			assert !result.stderr.contains('OK:')
		}
		assert os.read_file(test_path + '/allowed.txt')! == baseline
	}
}
