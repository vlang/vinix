// SPDX-License-Identifier: ISC
// Read-only capture of the files selected by the live macOS Wi-Fi driver.
module main

import x.json2
import os
import wifihost

fn command(program string, args []string) !string {
	mut p := os.new_process(program)
	p.set_args(args)
	p.set_redirect_stdio()
	p.run()
	out := p.stdout_slurp()
	diagnostics := p.stderr_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 0 { return error('${program} failed (${code}): ${diagnostics}') }
	return out
}

fn remote(host string, command_text string) !string {
	return command('ssh', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', host, command_text])!
}

fn run() ! {
	if os.args.len != 3 { return error('Usage: capture.v USER@HOST NEW_OUTPUT_DIRECTORY') }
	host := os.args[1]
	if host.starts_with('-') || host.contains_any(' \t\r\n/:') {
		return error('Invalid SSH destination')
	}
	output := os.abs_path(os.args[2])
	if os.exists(output) { return error('Output already exists') }
	model := remote(host, '/usr/sbin/sysctl -n hw.model')!
	core := remote(host, '/usr/sbin/ioreg -l -w0 -r -c AppleBCMWLANCore')!
	tree := remote(host, '/usr/sbin/ioreg -p IODeviceTree -l -w0 -r -n wlan')!
	identity := wifihost.macos_wifi(model, core, tree)!
	temporary := os.join_path(os.temp_dir(), 'vinix-wifi-capture-${os.getpid()}')
	os.mkdir(temporary)!
	defer { os.rmdir_all(temporary) or {} }
	for i, file in identity.files {
		command('scp', ['-q', '-o', 'BatchMode=yes', host + ':/usr/share/firmware/wifi/' + file,
			'${temporary}/${i}'])!
	}
	wifihost.package_macos(wifihost.PackageOptions{ firmware: temporary + '/0', nvram: temporary + '/1', clm: temporary + '/2', txcap: temporary + '/3', output: output }, identity)!
	// Keep only the selected identity, avoiding SSIDs and other IORegistry data.
	os.write_file(output + '/macos-selection.json', json2.encode(identity, prettify: true) + '\n')!
	println('Captured ${identity.board} ${identity.module_name}/${identity.module_revision} ${identity.antenna}: ${output}')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
