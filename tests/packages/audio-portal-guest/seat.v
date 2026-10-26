// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn seat() ! {
	pid := launch('tone', 'seat', 'seat', 0)!
	value := ready('seat')!
	alex_seat := text('/proc/sys/kernel/seat_session').trim_space()
	require(alex_seat.u64() > 0 && text('/run/vinix/session/active').trim_space() == '1000', 'Alex is not the real active seat')!
	sam := child_start(['/usr/sbin/vinix-session', 'run', '--seat', 'sam', '/sbin/init', 'samhold'], '', '')!
	wait_file('/home/sam/seat.ready')!
	sam_seat := text('/proc/sys/kernel/seat_session').trim_space()
	require(sam_seat.u64() > 0 && sam_seat != alex_seat && text('/run/vinix/session/active').trim_space() == '1001', 'Sam did not take the real seat')!
	os.write_file(data + '/seat.inactive', 'go\n')!
	require(wait_file(data + '/seat.inactive-refused')! == 'PASS\n', 'held inactive client not refused')!
	C.usleep(1_500_000)
	os.write_file('/home/sam/seat.go', 'go\n')!
	require(wait(sam)! == 0, 'Sam session failed')!
	require(text('/proc/sys/kernel/seat_session').trim_space() == '0', 'Sam did not release the kernel seat')!
	os.write_file('/proc/sys/kernel/seat_session', alex_seat + '\n')!
	os.write_file('/run/vinix/session/active', '1000\n')!
	require(text('/proc/sys/kernel/seat_session').trim_space() == alex_seat, 'Alex seat restore failed')!
	os.write_file(data + '/seat.active', 'go\n')!
	finish(pid, 'seat', 'tone')!
	gone(value)!
	C.usleep(1_500_000)
	println('AUDIO SEAT real-other-login inactive-write-refused active-relaunch PASS')
}
