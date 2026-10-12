// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module officenative

import cachecli
import hosttest
import os

fn fixture_options() Options {
	return Options{ repo: '/repo', office: '/office', ui2: '/ui2', output: '/out', work: '/work', v: '/vroot/v', arch: 'arm64', clang: '/clang', strip: '/strip', target: 'aarch64-linux-musl', sysroot: '/sysroot', gcclib: '/gcc', cc_shim: '/shim', llvm: '/llvm', jobs: 2 }
}

fn test_compiler_and_linker_recipes_keep_original_order() {
	a := fixture_options()
	assert app_command(a, 'calc') == ['/vroot/v', '-new-compiler', '--no-parallel', '-no-memory-limit',
		'-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-manualfree', '-enable-globals', '-prod',
		'-d', 'glibc', '-d', 'no_backtrace', '-d', 'ui2_headless', '-path', '@vlib|/work/vmodules',
		'-o', '/work/calc.c', '/office/cmd/excel']
	base := ['/clang', '--target=aarch64-linux-musl', '-nostdinc', '-isystem', '/shim', '-isystem',
		'/headers', '-isystem', '/gcc/include', '-isystem', '/sysroot/usr/include', '-I',
		'/vroot/thirdparty/mbedtls/include', '-I', '/vroot/thirdparty/mbedtls/library', '-I',
		'/vroot/thirdparty/mbedtls/3rdparty/everest/include', '-I',
		'/vroot/thirdparty/mbedtls/3rdparty/everest/include/everest', '-I',
		'/vroot/thirdparty/mbedtls/3rdparty/everest/include/everest/kremlib', '-O2',
		'-fno-stack-protector', '-w']
	assert cc_base(a, '/vroot', '/headers') == base
	assert tls_command(a, '/vroot', '/headers', 'library/one.c') == [...base, '-c',
		'/vroot/thirdparty/mbedtls/library/one.c', '-o', '/work/mbedtls/library_one.o']
	assert link_command(a, '/vroot', '/headers', ['/one.o', '/two.o'], 'writer') == [
		base[0],
		'-static',
		'-nostdlib',
		...base[1..],
		'-I',
		'/office',
		'-Wno-error=incompatible-function-pointer-types',
		'/sysroot/usr/lib/crt1.o',
		'/sysroot/usr/lib/crti.o',
		'/gcc/crtbeginT.o',
		'/work/writer.c',
		'/one.o',
		'/two.o',
		'-L/sysroot/usr/lib',
		'-L/gcc',
		'-lgcc_eh',
		'-lc',
		'-lgcc',
		'-lm',
		'/gcc/crtend.o',
		'/sysroot/usr/lib/crtn.o',
		'-fuse-ld=lld',
		'-B/llvm',
		'-o',
		'/work/voffice-writer',
	]
}

fn test_workers_complete_queued_jobs_and_report_first_submission_failure() {
	work := hosttest.work_dir('', 'vinix-office-worker-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	os.mkdir_all(work + '/vlib/net/mbedtls')!
	os.write_file(work + '/vlib/net/mbedtls/mbedtls.c.v', '#flag @VEXEROOT/thirdparty/mbedtls/library/one.o\n#flag @VEXEROOT/thirdparty/mbedtls/library/two.o\n#flag @VEXEROOT/thirdparty/mbedtls/library/three.o\n#flag @VEXEROOT/thirdparty/mbedtls/library/four.o\n')!
	compiler := work + '/cc'
	// This independent tool records every submitted source before failing two.
	os.write_file(compiler, '#!/bin/sh\nsource=\nwhile [ "$#" -gt 0 ]; do if [ "$1" = -c ]; then shift; source=$1; break; fi; shift; done\nprintf called > ' + hosttest.shell_quote(work) + '/$(basename "$source").called\ncase "$source" in */one.c) sleep 0.1; exit 7;; */two.c) exit 8;; esac\nexit 0\n')!
	os.chmod(compiler, 0o755)!
	args := Options{ ...fixture_options(), work: work, clang: compiler }
	guard := cachecli.own_commands()
	defer { guard.close() }
	if _ := build_tls(args, work, '/headers') {
		assert false
	} else {
		assert err.msg().contains('exit 7') && err.msg().contains('/one.c')
	}
	for name in ['one', 'two', 'three', 'four'] {
		assert os.read_file(work + '/' + name + '.c.called')! == 'called'
	}
}

fn test_corrupt_and_old_state_is_rebuilt_and_protected_paths_refuse_reset() {
	work := hosttest.work_dir('', 'vinix-office-state-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for text in ['{bad', '{"version":2,"apps":{}}', '{"version":3,"apps":false}',
		'{"version":3,"apps":{"calc":2}}'] {
		os.write_file(work + '/.vinix-voffice-build-state.json', text)!
		assert load_state(work).apps.len == 0
	}
	args := Options{ ...fixture_options(), work: '/repo', output: work }
	if _ := protect(args, '/vroot') {
		assert false
	}
	nested := Options{ ...fixture_options(), work: work, output: work + '/out' }
	if _ := protect(nested, '/vroot') {
		assert false
	}
}
