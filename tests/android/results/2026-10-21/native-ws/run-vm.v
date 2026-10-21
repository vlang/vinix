// SPDX-License-Identifier: GPL-2.0-or-later
// Preserved macOS/HVF investigation helper; run from the repository root.
import os

fn main() {
	out := os.getwd() + '/build/android-native-ws'
	mut q := os.new_process(os.getwd() + '/build/qemu-horizontal/bin/qemu-system-aarch64')
	q.set_args(['-qmp', 'unix:' + out + '/vm/qmp.sock,server=on,wait=off', '-machine',
		'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object',
		'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device', '-drive',
		'if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'-drive', 'if=pflash,format=raw,file=' + out + '/vm/efivars.fd', '-drive',
		'format=raw,file=' + out + '/vm/boot.img', '-device', 'virtio-keyboard-device', '-device',
		'virtio-tablet-device', '-netdev', 'user,id=net0', '-device',
		'virtio-net-device,netdev=net0,mac=52:54:00:12:34:56', '-device', 'ramfb', '-display',
		'none', '-monitor', 'none', '-serial', 'file:' + out + '/vm/serial.log'])
	q.run()
	os.write_file(out + '/vm/pid', q.pid.str())!
	q.wait()
	exit(q.code)
}
