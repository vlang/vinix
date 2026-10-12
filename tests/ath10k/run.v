// SPDX-License-Identifier: ISC
module main

import os

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	work := os.join_path(os.temp_dir(), 'vinix-ath10k-${os.getpid()}')
	os.mkdir_all(work) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	for name in ['firmware.v', 'transport.v', 'boot.v', 'htc.v', 'wmi.v', 'wmi_tags.v', 'htt.v',
		'wpa_crypto.v', 'wpa.v', 'station_commands.v', 'station.v', 'abi.v'] {
		os.cp(root + '/kernel/dev/ath10k/' + name, work + '/' + name) or { panic(err) }
	}
	for name in ['fixture.v', 'allocation_darwin.c.v', 'allocation_test.v', 'firmware_test.v',
		'crypto_test.v', 'protocol_test.v', 'wpa_test.v', 'abi_test.v'] {
		os.cp(root + '/tests/ath10k/' + name, work + '/' + name) or { panic(err) }
	}
	// Exercise the actual desktop consumer against the driver's wire output.
	client := os.read_file(root + '/desktop/wifi_client.v') or { panic(err) }
	os.write_file(work + '/desktop_wifi.v', client.all_before('fn wifi_ioctl_with').replace('module main', 'module ath10k')) or { panic(err) }
	device := os.read_file(root + '/desktop/device_io.v') or { panic(err) }
	os.write_file(work + '/device_io.v', device.replace('module main', 'module ath10k')) or { panic(err) }
	os.write_file(work + '/v.mod', "Module { name: 'ath10k_fixture' }") or { panic(err) }
	mut p := os.new_process(os.getenv_opt('V') or { @VEXE })
	p.set_args(['-nocache', '-gc', 'none', '-manualfree', '-cc', 'clang', 'test', work])
	p.run()
	p.wait()
	code := p.code
	p.close()
	exit(code)
}
