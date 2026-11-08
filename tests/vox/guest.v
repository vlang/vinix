// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

fn main() {
	for directory in ['/tmp', '/run/user/0', '/root', '/dev/shm', '/var/log', '/etc', '/proc'] {
		os.mkdir_all(directory) or { panic(err) }
	}
	for directory in ['/tmp', '/dev/shm'] { os.chmod(directory, 0o1777) or { panic(err) } }
	os.setenv('HOME', '/root', true)
	os.setenv('PATH', '/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('TERM', 'linux', true)
	os.setenv('LD_LIBRARY_PATH', '/usr/lib:/lib', true)
	os.setenv('FONTCONFIG_FILE', '/etc/fonts/fonts.conf', true)
	os.setenv('GC_MARKERS', '1', true)
	if os.is_file('/usr/lib/libvox-trace.so') {
		os.setenv('LD_PRELOAD', '/usr/lib/libvox-trace.so', true)
	}
	os.write_file('/root/.vinix-user', 'version=1\nname=56696e6978\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=00112233445566778899aabbccddeeff\nhash=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n') or { panic(err) }
	os.chmod('/root/.vinix-user', 0o600) or { panic(err) }
	println('VOX GUEST: native rendering and spawn tests')
	mut checks := os.new_process('/usr/bin/vox-native-tests')
	checks.run()
	checks.wait()
	println('VOX GUEST: native tests exit=${checks.code}')
	checks.close()
	println('VOX GUEST: original browser headless smoke')
	mut probe := os.new_process('/usr/bin/vox')
	probe.set_args(['--headless-smoke'])
	probe.run()
	probe.wait()
	println('VOX GUEST: self-test exit=${probe.code}')
	probe.close()
	println('VOX GUEST: starting native UI2 desktop')
	mut desktop := os.new_process('/usr/bin/vinix-desktop')
	desktop.set_args(['--open=Vox', '--scale=1'])
	desktop.run()
	mut seen := map[string]int{}
	mut ticks := 0
	for desktop.is_alive() {
		for name in os.ls('/tmp') or { []string{} } {
			if !name.contains('vox') || !name.ends_with('.log') { continue }
			path := '/tmp/' + name
			log := os.read_file(path) or { continue }
			if log.len > seen[path] {
				println(log[seen[path]..])
				seen[path] = log.len
			}
		}
		ticks++
		if ticks % 15 == 0 {
			println('VOX-GUEST-MEMORY ' + (os.read_file('/proc/meminfo') or { '' }).replace('\n', ' '))
			for pid in os.ls('/proc') or { []string{} } {
				if !pid.is_int() { continue }
				command := os.read_file('/proc/' + pid + '/cmdline') or { continue }
				if command.contains('/usr/libexec/vinix-vox/root/usr/bin/vox') {
					println('VOX-PROCESS-MEMORY pid=' + pid + ' ' + (os.read_file('/proc/' + pid + '/status') or { '' }).replace('\n', ' '))
				}
			}
		}
		time.sleep(time.second)
	}
	desktop.wait()
	println('VOX GUEST: desktop exit=${desktop.code}')
	for { time.sleep(time.second) }
}
