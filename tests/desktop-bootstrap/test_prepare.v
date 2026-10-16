// SPDX-License-Identifier: GPL-2.0-only
// Run the real desktop preparation script with native offline builders.
import bootstraptest as bt
import hosttest
import os

const layer_names = {
	'network': 'network-tools'
	'x11':     'x11'
}

fn build(root string, label string) ! {
	bt.record(root, bt.Event{ builder: label, base_only: os.getenv('VINIX_ALPINE_BASE_ONLY'), args: os.args[1..] })!
	if label == 'git' {
		assert os.args[1..os.args.len - 1] == ['clone', '--depth', '1', 'https://github.com/vlang/ui2']
		for name in ['v.mod', 'ui/vml_compiled.v', 'examples/calculator/calculator.vml'] {
			bt.write(os.args.last() + '/' + name, 'fixture\n', false)!
		}
		return
	}
	if label == 'userland' {
		stage := os.getenv_opt('VINIX_AARCH64_USERLAND_BUILD_DIR') or { root + '/build-aarch64-userland' } + '/staging'
		if os.exists(stage) { os.rmdir_all(stage)! }
		bt.write(stage + '/usr/bin/vim', 'fixture\n', true)!
		for name in ['usr/lib/libc.a', 'usr/lib/gcc/aarch64-alpine-linux-musl/14/libgcc.a',
			'usr/include/stdio.h'] {
			bt.write(stage + '/' + name, 'fixture\n', false)!
		}
		if os.getenv('VINIX_ALPINE_BASE_ONLY') == '0' {
			for label_, layer in layer_names {
				variable := match label_ {
					'network' { 'VINIX_NETWORK_TOOLS_STAGING' }
					else { 'VINIX_X11_STAGING' }
				}
				overlay := os.getenv_opt(variable) or { root + '/build-aarch64-' + layer + '/staging' }
				if os.is_dir(overlay) { os.cp_all(overlay, stage, true)! }
			}
		}
		bt.pack(stage, os.getenv('VINIX_AARCH64_INITRAMFS'))!
		return
	}
	assert label in layer_names
	if os.getenv('TEST_BROKEN_LAYER') == label { return }
	stage := root + '/build-aarch64-' + layer_names[label] + '/staging'
	files := match label {
		'network' { ['usr/bin/pkg', 'sbin/apk', 'usr/bin/curl'] }
		else {
			['usr/bin/Xorg', 'usr/bin/Xvfb', 'usr/bin/startx', 'usr/bin/vinix-xinput',
				'usr/bin/vinix-wine-host']
		}
	}
	for name in files { bt.write(stage + '/' + name, 'fixture\n', true)! }
	if label == 'network' { bt.write(stage + '/etc/vinix-pkg/base-world', 'fixture\n', false)! }
}

fn fixture(root string) !map[string]string {
	bt.write(root + '/build-support/prepare-desktop-aarch64.sh', os.read_file(hosttest.root() + '/build-support/prepare-desktop-aarch64.sh')!, true)!
	for label, name in {
		'userland': 'build-userland-aarch64.sh'
		'network':  'build-network-tools-aarch64.sh'
		'x11':      'build-x11-aarch64.sh'
	} {
		assert label != ''
		os.mkdir_all(root + '/scripts')!
		os.symlink(os.executable(), root + '/scripts/' + name)!
	}
	os.mkdir(root + '/fake-bin')!
	os.symlink(os.executable(), root + '/fake-bin/git')!
	mut env := bt.environment()
	env['PATH'] = root + '/fake-bin:' + os.getenv('PATH')
	env['VINIX_PREPARE_TEST_ROOT'] = root
	return env
}

fn run(root string, env map[string]string) !hosttest.Result {
	return hosttest.capture_in(['bash', root + '/build-support/prepare-desktop-aarch64.sh'], '', 30, env, root)
}

fn bootstrap(root string, env map[string]string) ! {
	result := run(root, env)!
	assert result.code == 0, result.stdout + result.stderr
}

fn check(name string) ! {
	work := hosttest.work_dir('', 'vinix-desktop-prepare-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	root := work + '/checkout'
	mut env := fixture(root)!
	image := root + '/build-support/init-aarch64/initramfs.tar'
	if name == 'custom-incomplete' {
		for variable in ['VINIX_AARCH64_SYSROOT', 'VINIX_NETWORK_TOOLS_STAGING', 'VINIX_X11_STAGING'] {
			custom := root + '/' + variable
			bt.write(custom + '/keep', 'caller owned', false)!
			mut selected := env.clone()
			selected[variable] = custom
			result := run(root, selected)!
			assert result.code != 0 && result.stderr.contains('custom')
			assert os.read_file(custom + '/keep')! == 'caller owned' && bt.events(root)!.len == 0
		}
		return
	}
	if name == 'custom-ui2' {
		os.mkdir_all(root + '/custom-ui2')!
		env['VINIX_UI2_SOURCE'] = root + '/custom-ui2'
		result := run(root, env)!
		assert result.code != 0 && result.stderr.contains('ui2')
		assert bt.events(root)!.len == 0 && !os.exists(root + '/third_party/ui2')
		return
	}
	if name == 'broken-layer' {
		env['TEST_BROKEN_LAYER'] = 'x11'
		result := run(root, env)!
		assert result.code != 0 && result.stderr.contains('X11 builder left incomplete staging')
		assert bt.events(root)!.map(it.builder) == ['git', 'userland', 'network', 'x11']
		return
	}
	bootstrap(root, env)!
	initial := bt.events(root)!
	assert initial.map(it.builder) == ['git', 'userland', 'network', 'x11', 'userland']
	assert initial.map(it.base_only) == ['', '1', '', '', '0']
	for path in ['./usr/bin/vim', './usr/bin/Xorg', './usr/bin/Xvfb', './usr/bin/pkg'] {
		assert path in bt.archive_files(image)!
		contents := hosttest.capture(['tar', '-xOf', image, path], '', 30, os.environ())!
		assert contents.code == 0 && contents.stdout == 'fixture\n'
	}
	// Firefox is optional: the first-run app page installs it with pkg.
	assert './usr/lib/firefox-esr/firefox-esr' !in bt.archive_files(image)!
	bt.clear(root)!
	match name {
		'fresh' { return }
		'warm' {
			before := os.read_bytes(image)!
			bootstrap(root, env)!
			assert bt.events(root)!.len == 0 && os.read_bytes(image)! == before
		}
		'missing-x11' {
			bt.omit(image, './usr/bin/Xorg')!
			assert './usr/bin/Xorg' !in bt.archive_files(image)!
			bootstrap(root, env)!
			assert bt.events(root)!.map(it.builder) == ['userland'] && bt.events(root)![0].base_only == '0'
		}
		'custom-complete' {
			custom := root + '/custom-x11'
			os.rename_dir(root + '/build-aarch64-x11/staging', custom)!
			env['VINIX_X11_STAGING'] = custom
			bootstrap(root, env)!
			assert bt.events(root)!.len == 0 && os.is_file(custom + '/usr/bin/Xorg')
		}
		'missing-network' {
			os.rmdir_all(root + '/build-aarch64-network-tools/staging')!
			bootstrap(root, env)!
			assert bt.events(root)!.map(it.builder) == ['network', 'userland']
			assert './usr/bin/pkg' in bt.archive_files(image)!
		}
		else { return error('unknown prepare case: ' + name) }
	}
}

fn main() {
	if root := os.getenv_opt('VINIX_PREPARE_TEST_ROOT') {
		name := os.file_name(os.args[0])
		label := if name == 'git' {
			name
		} else {
			name.all_after('build-').all_before('-aarch64.sh').replace('network-tools', 'network')
		}
		build(root, label)!
		return
	}
	for name in ['fresh', 'warm', 'missing-x11', 'custom-incomplete', 'custom-ui2', 'custom-complete',
		'missing-network', 'broken-layer'] {
		check(name)!
	}
	println('PASS native desktop preparation checks')
}
