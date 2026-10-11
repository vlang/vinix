// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost
import strconv

fn filesystem_tools() !string {
	for name in ['debugfs', '/opt/homebrew/opt/e2fsprogs/sbin/debugfs', '/usr/local/opt/e2fsprogs/sbin/debugfs', '/sbin/debugfs', '/usr/sbin/debugfs'] {
		tool := os.find_abs_path_of_executable(name) or { continue }
		if os.is_executable(os.dir(tool) + '/mke2fs') && os.is_executable(os.dir(tool) + '/e2fsck') { return tool }
	}
	return error('e2fsprogs debugfs, mke2fs and e2fsck are required')
}

fn filesystem_blocks(value string) ![]int {
	mut blocks := []int{}
	for item in value.split(',') {
		size := strconv.atoi(item) or { return error_with_code('use 1024 or 4096 byte blocks', 2) }
		if size !in [1024, 4096] { return error_with_code('use 1024 or 4096 byte blocks', 2) }
		blocks << size
	}
	return blocks
}

fn filesystem_sparse_stat(text string, block_size int) ! {
	p := i64(block_size / 4)
	capacity := (12 + p + p * p + p * p * p) * block_size
	if !text.contains('Size: ' + capacity.str()) { return error('wrong persisted high size: ' + text) }
	field := text.all_after('Blockcount:').trim_left(' \t\r\n').all_before(' ').all_before('\n').all_before('\t')
	count := strconv.parse_uint(field, 10, 64) or { return error('file is not sparse: ' + text) }
	if count >= u64(64 * (block_size / 512)) { return error('file is not sparse: ' + text) }
}

fn filesystem_format(tool string, disk string, seed string, block_size int, sparse bool) ![]string {
	os.write_file(disk, '')!
	if unsafe { C.truncate(disk.str, i64(64 * 1024 * 1024)) } < 0 { return error('Cannot size disposable ext2 image') }
	features := 'filetype,sparse_super,' + if sparse { '^large_file,' } else { '' }
		+ '^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum'
	argv := [os.dir(tool) + '/mke2fs', '-q', '-F', '-t', 'ext2', '-b', block_size.str(), '-I', '128',
		'-O', features, '-d', seed, disk]
	run(argv)!
	return argv
}

fn filesystem_debugfs(tool string, disk string, request string, log string) !string {
	result := fixturehost.capture_both_preferred([tool, '-R', request, disk], policyhost.environment(), policyhost.caller_arch())!
	write(log, result.stdout + result.stderr)!
	return result.stdout + result.stderr
}

fn filesystem_check(tool string, disk string, log string) ! {
	result := fixturehost.capture_both_preferred([os.dir(tool) + '/e2fsck', '-f', '-n', disk], policyhost.environment(), policyhost.caller_arch())!
	write(log, result.stdout + result.stderr)!
	if result.status != 0 { return error('EXT2 consistency after guest:\n' + result.stdout + '\n' + result.stderr) }
}

fn filesystem_command(args []string, family string) !int {
	sparse := family == 'ext2-sparse'
	accounting := family == 'resource-accounting'
	mut options := [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--state-dir', value: true }, hosttest.Option{ name: '--prebuilt-init', value: true },
		hosttest.Option{ name: '--kernel', value: true }, hosttest.Option{ name: '--build-only' }]
	if sparse { options << hosttest.Option{ name: '--blocks', value: true } }
	if accounting { options << hosttest.Option{ name: '--retention-only' } }
	parsed := hosttest.parse_arguments(args, options, 0,
		'Usage: run [--arch aarch64|amd64] [--state-dir FRESH-DIR] [--prebuilt-init ELF] [--kernel DIR|ELF] [--build-only]',
		if sparse { 'Sparse ext2: [--blocks 1024,4096], three hard-stop/restart steps per disk.' } else if accounting {
			'Resource accounting: [--retention-only], physical ext2 root and on-disk consistency.'
		} else { 'Read-ahead: physical ext2 root and on-disk consistency.' }) or { return error_with_code(err.msg(), 2) }
	arch := if parsed.options['--arch'] == 'amd64' { 'x86_64' } else { 'aarch64' }
	blocks := if sparse { filesystem_blocks(parsed.options['--blocks'] or { '1024,4096' })! } else { [4096] }
	timeout := environment_timeout(300)!
	tool := filesystem_tools()!
	repo := resolve(os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() })!
	work := hosttest.work_dir(parsed.options['--state-dir'] or { '' }, 'vinix-' + family + '-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	private_kernel := snapshot_kernel_input(work, parsed.options['--kernel'] or {
		if arch == 'aarch64' { os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' } } else {
			os.getenv_opt('VINIX_AMD64_KERNEL') or { root() + '/kernel/bin/vinix' }
		}
	}, arch)!
	mut cc := []string{}
	if arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		cc = [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk,
			'-L' + sdk + '/lib', '-fuse-ld=lld']
	} else { cc = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }] }
	init := work + '/init'
	mut compile := []string{}
	mut source := ''
	if '--prebuilt-init' in parsed.options {
		source = resolve(parsed.options['--prebuilt-init'])!
		elf_arch(source, arch)!
		hosttest.module_copy_file_preserving_stat(source, init)!
	} else if accounting {
		source = root() + '/tests/resource-accounting/guest.c'
		compile = [...cc, '-static', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-pthread',
			...if '--retention-only' in parsed.options { ['-DACCOUNTING_RETENTION_ONLY'] } else { []string{} }, source, '-o', init]
		run(compile)!
	} else {
		source = root() + '/tests/' + if sparse { 'ext2-sparse/sparsefixture' } else { 'pagecache/cachefixture' }
		flags := [...cc, '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector']
		guesthost.compile_module(source, work + '/fixture.o', arch, flags)!
		compile = [...cc, '-static', work + '/fixture.o', '-o', init]
		run(compile)!
	}
	elf_arch(init, arch)!
	for name in ['root', 'sbin'] { os.mkdir_all(work + '/rootfs/' + name)! }
	write(work + '/rootfs/no-sync-step', if sparse { 'run\n' } else { 'pass\n' })!
	hosttest.module_copy_file_preserving_stat(init, work + '/rootfs/sbin/init')!
	archive := native_archive(work)!
	seed := work + '/seed'
	if arch == 'x86_64' {
		hosttest.module_copy_tree(work + '/rootfs', seed)!
		for name in ['dev', 'proc', 'tmp', 'run', 'root'] { os.mkdir_all(seed + '/' + name)! }
		write(seed + '/.vinix-image-id', hosttest.sha(archive)![..16] + '\n')!
	} else { os.mkdir(seed)! }
	mut receipt := { 'family': json2.Any(family), 'arch': json2.Any(arch), 'timeout': json2.Any(timeout),
		'memory': json2.Any(if arch == 'aarch64' { 2048 } else { 1024 }),
		'compile_command': json2.Any(hosttest.strings(compile)), 'source': json2.Any(source),
		'init_sha256': json2.Any(hosttest.sha(init)!), 'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!),
		'archive_sha256': json2.Any(hosttest.sha(archive)!), 'blocks': json2.Any(blocks.map(json2.Any(it))),
		'retention_only': json2.Any('--retention-only' in parsed.options), 'power_cut': json2.Any(true), 'kernel_rebuilt': json2.Any(false) }
	if os.is_file(source) { receipt['source_sha256'] = hosttest.sha(source)! }
	if os.is_dir(source) {
		mut hashes := map[string]string{}
		for name in os.ls(source)! { if os.is_file(source + '/' + name) { hashes[name] = hosttest.sha(source + '/' + name)! } }
		receipt['source_files_sha256'] = hosttest.string_map(hashes)
	}
	hosttest.write_json(work + '/inputs.json', receipt)!
	mut configured := guesthost.Launch{}
	if '--build-only' !in parsed.options { configured = guesthost.launch_from(init, archive, work, private_kernel, arch, false, repo)! }
	for block_size in blocks {
		disk := work + if sparse { '/root-' + block_size.str() + '.ext2' } else { '/root.ext2' }
		format := filesystem_format(tool, disk, seed, block_size, sparse)!
		hosttest.write_json(work + '/format-' + block_size.str() + '.json', { 'command': json2.Any(hosttest.strings(format)),
			'initial_disk_sha256': json2.Any(hosttest.sha(disk)!), 'size': json2.Any(64 * 1024 * 1024) })!
		if '--build-only' in parsed.options { continue }
		mut argv := configured.command.clone()
		if arch == 'aarch64' {
			argv[argv.index('-m') + 1] = '2048'
			argv = guesthost.arm_persist_launch(argv, disk, work, repo)!
		} else {
			argv[argv.index('-serial') + 1] = 'stdio'
			argv[argv.index('-accel') + 1] = os.getenv_opt('VINIX_QEMU_ACCEL') or { 'tcg' }
			firmware := os.getenv_opt('VINIX_OVMF_CODE_AMD64') or { os.dir(os.dir(argv[0])) + '/share/qemu/edk2-x86_64-code.fd' }
			argv[argv.index('-drive') + 1] = 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware
			argv << ['-drive', 'if=ide,format=raw,file=' + disk + ',cache=writeback']
		}
		receipt['command'] = hosttest.strings(argv)
		hosttest.write_json(work + '/inputs.json', receipt)!
		for step in if sparse { ['create', 'shrink', 'cleanup'] } else { ['pass'] } {
			println('==> ' + if arch == 'aarch64' { 'aarch64' } else { 'amd64' } + ' ' + family + ' block=' + block_size.str() + ' ' + step)
			epoch := work + '/' + block_size.str() + '-' + step
			os.mkdir(epoch)!
			prefix := if sparse { 'EXT2 SPARSE' } else if accounting { 'ACCOUNTING' } else { 'READAHEAD' }
			policy := guesthost.PowercutPolicy{ start: prefix + ' START', done: prefix + ' DONE', phase: step,
				failures: ['FAIL END', 'FATAL EXCEPTION', 'KERNEL PANIC'], lookback: if arch == 'aarch64' { 8192 } else { 0 },
				failure_newline: arch != 'aarch64' }
			code := guesthost.boot_powercut(argv, configured.env, epoch, policy, timeout, arch != 'aarch64', true) or {
				if err.msg() == 'Guest run interrupted' { return 130 }
				return err
			}
			if code != 0 { return code }
			if sparse && step == 'create' {
				path := if arch == 'aarch64' { '/sparse-persist' } else { '/root/sparse-persist' }
				text := filesystem_debugfs(tool, disk, 'stat ' + path, epoch + '/stat.log')!
				filesystem_sparse_stat(text, block_size)!
				stats := filesystem_debugfs(tool, disk, 'stats', epoch + '/stats.log')!
				if !stats.contains('large_file') { return error('LARGE_FILE feature did not persist') }
			}
			filesystem_check(tool, disk, epoch + '/e2fsck.log')!
			println('PASS ' + if arch == 'aarch64' { 'aarch64' } else { 'amd64' } + ' ' + family + ' block=' + block_size.str() + ' ' + step + ': actual disk and e2fsck after power cut')
		}
	}
	return 0
}
