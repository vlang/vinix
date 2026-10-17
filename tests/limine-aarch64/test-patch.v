// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import os

const label = 'Limine 12.9.3 (aarch64, UEFI)'
const guard = 'Base revision %u is no longer supported for aarch64'
const patch = '12.9.3-vinix-base-revision-2.patch'
const upstream = 'void limine_load(char *config, char *cmdline) {
    if (base_rev_p2_ptr != NULL) {
        *base_rev_p2_ptr = 0;
    }

#if defined (__aarch64__)
    if (base_revision < 6) {
        panic(true, "limine: Base revision %u is no longer supported for aarch64 (minimum: 6)", base_revision);
    }
#endif

    // Load requests
    requests_top = physical_base + image_size_before_bss;
    uint64_t *limine_reqs = NULL;
}
'

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

struct Fixture {
	root   string
	driver string
	env    map[string]string
}

fn setup(root string, delegate string) !Fixture {
	os.mkdir_all(os.join_path(root, 'scripts'))!
	hosttest.module_copy_file(os.join_path(hosttest.root(), 'scripts/build-limine-aarch64.sh'), os.join_path(root, 'scripts/build-limine-aarch64.sh'))!
	os.mkdir_all(os.join_path(root, 'build-support/limine'))!
	hosttest.module_copy_file(os.join_path(hosttest.root(), 'build-support/limine', patch), os.join_path(root, 'build-support/limine', patch))!
	source := os.join_path(root, 'boot-image/limine-src-12.9.3')
	driver := os.join_path(source, 'common/protos/limine.c')
	os.mkdir_all(os.dir(driver))!
	os.write_file(driver, upstream)!
	hosttest.module_copy_file(delegate, os.join_path(source, 'configure'))!
	os.chmod(os.join_path(source, 'configure'), 0o755)!
	commands := os.join_path(root, 'fake-bin')
	os.mkdir(commands)!
	for name in ['llvm-objcopy', 'sysctl', 'make', 'curl'] {
		os.symlink(delegate, os.join_path(commands, name))!
	}
	mut env := os.environ()
	env['PATH'] = commands + ':' + (env['PATH'] or { '' })
	env['GIT_CONFIG_GLOBAL'] = '/dev/null'
	env['GIT_CONFIG_NOSYSTEM'] = '1'
	env['LC_ALL'] = 'C'
	return Fixture{root, driver, env}
}

fn (fixture Fixture) builder(arguments []string) !hosttest.Result {
	mut command := ['bash', os.join_path(fixture.root, 'scripts/build-limine-aarch64.sh')]
	command << arguments
	return hosttest.capture_in(command, '', 10, fixture.env, fixture.root)
}

fn verify(work string, delegate string) ! {
	fresh := setup(os.join_path(work, 'fresh'), delegate)!
	first := fresh.builder([]string{})!
	require(first.code == 0, first.stdout + first.stderr)!
	require(first.stdout.contains('applying ' + patch), 'fresh source was not patched')!
	require(!os.read_file(fresh.driver)!.contains(guard), 'fresh source still rejects base revision 2')!
	installed := os.join_path(fresh.root, 'boot-image/limine-bin/BOOTAA64.EFI')
	require(os.read_file(installed)!.contains(label), 'expected loader fixture was not installed')!
	require(fresh.builder(['--check'])!.stdout.contains('Vinix base revision 2 compatibility'), 'installed compatibility report is missing')!
	println('PASS Limine fresh source: real patch applied before build and installed loader checked')

	idempotent := setup(os.join_path(work, 'idempotent'), delegate)!
	initial := idempotent.builder([]string{})!
	require(initial.code == 0, initial.stdout + initial.stderr)!
	before := os.read_bytes(idempotent.driver)!
	second := idempotent.builder([]string{})!
	require(second.code == 0, second.stdout + second.stderr)!
	require(second.stdout.contains('already applied'), 'second build did not detect the applied patch')!
	require(os.read_bytes(idempotent.driver)! == before, 'second build changed the patched source')!
	println('PASS Limine rerun: patch is recognized and source bytes remain identical')

	incompatible := setup(os.join_path(work, 'incompatible'), delegate)!
	changed := upstream.replace('requests_top =', 'other_top =')
	os.write_file(incompatible.driver, changed)!
	rejected := incompatible.builder([]string{})!
	require(rejected.code == 1, rejected.stdout + rejected.stderr)!
	require(rejected.stderr.contains('error: cannot apply'), 'incompatible source did not report patch failure')!
	require(!rejected.stdout.contains('==> building'), 'incompatible source reached the build')!
	require(os.read_file(incompatible.driver)! == changed, 'rejected source changed')!
	println('PASS Limine incompatible source: rejected before build without changing source')
}

fn run() ! {
	work := hosttest.work_dir('', 'vinix-limine-patch-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	configured := os.getenv('VINIX_LIMINE_FIXTURE')
	delegate := if configured != '' {
		hosttest.module_resolve(configured)!
	} else {
		selected := hosttest.capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
			'find-v', hosttest.root()], '', 30, os.environ())!
		require(selected.code == 0, selected.stderr)!
		binary := os.join_path(work, 'fixture')
		compiled := hosttest.capture([selected.stdout, '-nocache', '-cc', 'cc', '-arch',
			if os.uname().machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }, '-o', binary,
			os.join_path(hosttest.root(), 'tests/limine-aarch64/commandfixture')], '', 120, os.environ())!
		require(compiled.code == 0, compiled.stdout + compiled.stderr)!
		binary
	}
	verify(work, delegate)!
}

fn main() {
	if os.args[1..] in [['--help'], ['-h']] {
		println('Usage: tests/limine-aarch64/test-patch\nCheck Limine compatibility patching with native fixtures and real Git, without downloads.')
		return
	}
	if os.args.len != 1 {
		eprintln('Usage: tests/limine-aarch64/test-patch')
		exit(2)
	}
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}
