// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import hosttest
import os
import policyhost

fn volume_host(args []string) !int {
	hosttest.parse_arguments(args, []hosttest.Option{}, 0, 'Usage: host', 'Run production volume, metrics and extent-reservation tests on the host.') or { return error_with_code(err.msg(), 2) }
	keep := os.getenv('VINIX_VOLUME_HOST_DIR')
	work := hosttest.work_dir(keep, 'vinix-volume-host-')!
	defer { if keep == '' { retire(work) } }
	for source in ['kernel/fs/storage_control.v', 'kernel/fs/storage_health.v', 'kernel/fs/storage_crypt.v', 'kernel/aesxts/core.v',
		'kernel/resource/block_health.v', 'kernel/resource/block_health_arm64.v',
		'kernel/resource/block_health_amd64.v', 'kernel/resource/block_status.v',
		'kernel/resource/block_discard.v', 'kernel/resource/block_identity.v',
		'kernel/security/device_policy.v'] {
		target := work + '/' + source.all_after('/')
		os.mkdir_all(os.dir(target))!
		os.cp(root() + '/' + source, target)!
	}
	hosttest.module_copy_tree(root() + '/tests/storage-volumes/hostfixtures', work + '/templates')!
	for path in os.walk_ext(work + '/templates', '.v') {
		target := work + '/' + path[(work + '/templates/').len..]
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
	}
	write(work + '/v.mod', "Module { name: 'volume_host' }\n")!
	os.cp(root() + '/tests/storage-volumes/volume_test.v', work + '/fs/volume_test.v')!
	os.cp(root() + '/tests/storage-volumes/aesxts_test.v', work + '/aesxts/core_test.v')!
	os.cp(root() + '/tests/storage-volumes/aesxts_vectors.rsp', work + '/aesxts/aesxts_vectors.rsp')!
	v := output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()])!
	mut argv := [v, '-enable-globals', '-cc', 'clang', '-arch', policyhost.caller_arch()]
	if os.getenv('VINIX_HOST_SANITIZE') == '1' {
		argv << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined']
	}
	argv << ['test', 'fs', 'aesxts']
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	result := hosttest.capture_in(argv, work + '/tests.log', -1, env, work)!
	print(result.stdout)
	eprint(result.stderr)
	if result.code != 0 { return error('Volume host tests failed; see ' + work + '/tests.log') }
	return 0
}
