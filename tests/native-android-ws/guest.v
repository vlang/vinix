// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated native-WS application investigation. APK functionality is checked
// through real desktop input and retained framebuffer captures.
module main

import os
import time

fn main() {
	os.setenv('HOME', '/root', true)
	os.setenv('PATH', '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('LD_LIBRARY_PATH', '/usr/lib', true)
	// The desktop intentionally passes a small environment to app processes;
	// production runs do not enable content tracing.
	os.write_file('/root/.vinix-user', 'version=1\nname=564d\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=00000000000000000000000000000000\nhash=0000000000000000000000000000000000000000000000000000000000000000\n') or { panic(err) }
	os.chmod('/root/.vinix-user', 0o600) or { panic(err) }
	direct := (os.read_file('/opt/android-test/native-mode') or { '' }).trim_space() == 'direct'
	executable := if direct { '/usr/bin/run-android-calculator' } else { '/usr/bin/vinix-desktop' }
	if direct { os.setenv('VINIX_SURFACE_PATH', '/tmp/android-native.surface', true) }
	mut process := os.new_process(executable)
	if !direct { process.set_args(['--open=Android Calculator']) }
	process.run()
	println('ANDROID-WS-GUEST pid=${process.pid} mode=${if direct { 'direct' } else { 'desktop' }}')
	for tick in 0 .. 900 {
		if tick % 10 == 0 {
			for entry in os.ls('/proc') or { []string{} } {
				if entry.int() <= 0 { continue }
				command := os.read_file('/proc/' + entry + '/cmdline') or { '' }
				maps := os.read_file('/proc/' + entry + '/maps') or { '' }
				if maps.contains('libvinix-android-native.so') {
					if maps.contains('libgtk') || maps.contains('libgdk') || maps.contains('libX11') {
						println('ANDROID-WS-DEPENDENCY-FAIL pid=${entry}\n${maps}')
						exit(1)
					}
					println('ANDROID-WS-MAPS pid=${entry} gtk=absent gdk=absent x11=absent')
				}
				if command.contains('Xvnc') || command.contains('Xvfb') || command.contains('vinix-wine-host') {
					println('ANDROID-WS-PROCESS-FAIL ' + command)
					exit(1)
				}
			}
		}
		if !process.is_alive() {
			process.wait()
			eprintln('ANDROID-WS-HOST-EXIT code=${process.code}')
			exit(process.code)
		}
		time.sleep(time.second)
	}
	println('ANDROID-WS-OBSERVED functionality=manual')
	for { time.sleep(time.second) }
}
