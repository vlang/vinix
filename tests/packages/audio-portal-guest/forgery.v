// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.audiopcm
import tools.packages.pkgcore
import tools.packages.pkglaunch

fn isolated_forgery() ! {
	require(C.getuid() == 1000 && C.geteuid() == 1000 && C.getgroups(0, unsafe { nil }) == 0,
		'forgery control did not enter an isolated ordinary account')!
	mut admission := (pkgcore.Service{}).audio_admission('tone')!
	defer { admission.close() }
	require(admission.allowed, 'forgery control has no real signed audio admission')!
	mut portal := audiopcm.start('tone', admission.generation, admission.manifest)!
	defer { portal.close() }
	portal.capability.export_environment()
	mut refused := false
	result := pkglaunch.run(['run-args', 'tone', '--', 'tone', 'forgery', '440']) or {
		refused = true
		-1
	}
	require(refused || result != 0, 'group0 sameUID account action admitted an inactive forged endpoint')!
	require(!os.exists(data + '/forgery.done'), 'forged account action ran the native app')!
}

fn qualify_forgery() ! {
	active := child_start(['/usr/sbin/vinix-session', 'run', '--seat', 'alex', '/sbin/init', 'alexhold'], '', '')!
	wait_file('/home/alex/seat.ready')!
	require(text('/proc/sys/kernel/seat_session').trim_space().u64() > 0, 'forgery control has no active real seat')!
	command(['/usr/sbin/vinix-session', 'run', '--isolated', 'alex', '/sbin/init', 'isolated-forgery'], '')!
	os.write_file('/home/alex/seat.go', 'go\n')!
	require(wait(active)! == 0, 'forgery control active login failed')!
	entries := os.ls('/run/user/1000')!
	require(!entries.any(it.starts_with('vinix-audio-')), 'forged portal endpoint survived close')!
	println('AUDIO CONTROL group0-forged-account-action refused PASS')
}
