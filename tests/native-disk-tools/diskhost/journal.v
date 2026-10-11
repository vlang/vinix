// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import guesthost
import hosttest
import os

struct JournalRun {
	arch       string
	work       string
	kernel_dir string
	executable string
	seconds    int
	format     bool
}

fn (job JournalRun) fresh() ! {
	disk := job.work + '/root.vjfs'
	if job.format {
		sparse_file(disk, i64(4) * 1024 * 1024 * 1024)!
	} else {
		journal_fixture(disk, job.work + '/seed' + if job.arch == 'amd64' { '' } else { '/root' }, job.executable, 64)!
	}
}

fn (job JournalRun) boot(mode int, stage int) ! {
	prior := os.getenv_opt('VINIX_CMDLINE')
	os.setenv('VINIX_CMDLINE', if job.format { 'vinix.disk=auto ' } else { '' } + 'vinix.journal_mode=' + mode.str(), true)
	defer {
		if value := prior {
			os.setenv('VINIX_CMDLINE', value, true)
		} else {
			os.unsetenv('VINIX_CMDLINE')
		}
	}
	configured := launch_mode(job.work + '/init', job.work + '/initramfs.tar', job.work, job.kernel_dir,
		job.arch, 1024, job.work + '/root.vjfs', false, true, false)!
	println('==> ' + job.arch + ' mode=' + mode.str() + ' cut=' + stage.str())
	if cut(configured, job.work + '/epochs/' + mode.str(), guesthost.PowercutPolicy{
		start:           'JOURNAL START'
		done:            if stage > 0 { 'JOURNAL CUT' } else { 'JOURNAL DONE' }
		phase:           if stage > 0 { stage.str() } else { mode.str() }
		cut_stage:       stage > 0
		inode:           if stage > 0 { '' } else { '0' }
		failures:        ['FAIL END', 'FATAL EXCEPTION', 'KERNEL PANIC']
		failure_newline: true
	}, job.seconds, true)! != 0 {
		return error('mode ' + mode.str() + ' did not reach its expected marker')
	}
}

fn (job JournalRun) inspect() ! {
	path := export_clean(job.work + '/root.vjfs', job.work + '/inspection.ext2')!
	result := capture([os.dir(job.executable) + '/e2fsck', '-f', '-n', path])!
	print(result.stdout)
	os.write_file(job.work + '/e2fsck.log', result.stdout + result.stderr)!
	if result.status != 0 {
		return error('recovered allocation/link/directory invariants failed e2fsck\n' + result.stderr)
	}
	os.rm(path)!
}

fn journal(args []string) !int {
	options := parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--cases', value: true },
		hosttest.Option{ name: '--format' },
		hosttest.Option{ name: '--production' },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-only' },
	],
		'Usage: run [--arch aarch64|amd64] [--cases full,rename,orphan,truncate,churn] [--format] [--production] [--state-dir DIR] [--kernel-dir DIR] [--build-only]')!
	cases := options.value('--cases', 'full,rename,orphan,truncate,churn').split(',')
	if cases.any(it !in ['full', 'rename', 'orphan', 'truncate', 'churn']) {
		return argument('unknown case')
	}
	if options.has('--production') && cases != ['full'] {
		return argument('--production requires --cases=full')
	}
	arch := options.value('--arch', 'aarch64')
	seconds := timeout()!
	executable := tool()!
	work := work_dir(options, 'vinix-journal-')!
	defer { remove_private(work, options) }
	kernel_dir := kernel(work, options.value('--kernel-dir', ''), arch)!
	extra := if options.has('--production') { ['-DVINIX_JOURNAL_PRODUCTION'] } else { []string{} }
	run([...flags(arch), ...extra, root() + '/tests/fs-journal/guest.c', '-o', work + '/init'])!
	seed := work + '/seed'
	for name in ['dev', 'proc', 'tmp', 'run', 'sbin', 'root'] { mkdir(seed + '/' + name)! }
	os.cp(work + '/init', seed + '/sbin/init')!
	os.chmod(seed + '/sbin/init', 0o755)!
	for name, data in {
		'source':  'A'
		'target':  'B'
		'control': 'C'
	} {
		os.write_file(seed + '/root/' + name, data)!
	}
	if os.exists(seed + '/.vinix-image-id') { os.rm(seed + '/.vinix-image-id')! }
	guesthost.archive_tree(seed, work + '/initramfs.tar')!
	seed_identity(seed, work + '/initramfs.tar')!
	job := JournalRun{arch, work, kernel_dir, executable, seconds, options.has('--format')}
	for case_name in cases {
		if options.has('--build-only') {
			job.fresh()!
			println('Prepared journal guest: ' + work)
			return 0
		}
		match case_name {
			'full' {
				job.fresh()!
				job.boot(1, 0)!
				job.boot(2, 0)!
				job.inspect()!
			}
			'rename' {
				for stage in 1 .. 6 {
					job.fresh()!
					job.boot(100 + stage, stage)!
					job.boot(200 + stage, 0)!
					job.inspect()!
				}
			}
			'orphan' {
				job.fresh()!
				job.boot(3, 0)!
				job.boot(4, 0)!
				job.inspect()!
			}
			'truncate' {
				job.fresh()!
				job.boot(5, 2)!
				job.boot(6, 0)!
				job.inspect()!
			}
			else {
				job.fresh()!
				job.boot(8, 0)!
				job.inspect()!
			}
		}
		println('PASS ' + arch + ' ' + case_name)
	}
	return 0
}
