// SPDX-License-Identifier: GPL-2.0-only
// Read-only J313 audio evidence collection over the deployment SSH connection.
module main

import crypto.sha256
import json2
import os

const audio_drivers = ['AppleTAS5770LAmp', 'AppleMCA2-T8103', 'AudioDMAController-T8103',
	'AppleS5L8960XNCO', 'AppleS5L8940XI2C', 'AppleEmbeddedAudio', 'AppleARMIISAudio']

fn capture(program string, args []string) !string {
	mut process := os.new_process(program)
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	diagnostics := process.stderr_slurp()
	process.wait()
	status := process.code
	process.close()
	if status != 0 {
		return error('${program} exited ${status}: ${diagnostics}${output}')
	}
	return output
}

fn remote(host string, program string, args []string) !string {
	mut command := ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'ServerAliveInterval=5',
		'-o', 'ServerAliveCountMax=2', host, program]
	// SSH runs a remote shell even when its arguments were supplied separately.
	// Only fixed commands and arguments from this source are passed here.
	command << args
	return capture('/usr/bin/ssh', command)!
}

fn run() ! {
	mut host := os.getenv_opt('VINIX_M1_REMOTE') or { 'sergey@macbook-air-sergej.local' }
	mut output := ''
	mut index := 1
	for index < os.args.len {
		option := os.args[index]
		if option !in ['--host', '--output'] || index + 1 == os.args.len {
			return error('Usage: probe.v [--host user@machine] --output NEW_DIRECTORY')
		}
		index++
		if option == '--host' { host = os.args[index] } else { output = os.args[index] }
		index++
	}
	if host == '' || host.starts_with('-') || output == '' {
		return error('A host and new output directory are required')
	}
	if os.exists(output) { return error('Output directory already exists: ${output}') }
	os.mkdir_all(output)!
	version := remote(host, '/usr/bin/sw_vers', [])!
	model := remote(host, '/usr/sbin/sysctl', ['hw.model', 'kern.uuid'])!
	if !model.contains('hw.model: MacBookAir10,1') {
		return error('Expected the J313 MacBook Air; found ${model}')
	}
	os.write_file(os.join_path(output, 'system.txt'), version + model)!
	for name in ['audio-tas5770L-spkr-l', 'audio-tas5770L-spkr-r', 'mca1', 'nco', 'chosen'] {
		text := remote(host, '/usr/sbin/ioreg', ['-p', 'IODeviceTree', '-r', '-n', name, '-d1',
			'-l', '-w0'])!
		if !text.contains('+-o ') { return error('Missing device tree node ${name}') }
		os.write_file(os.join_path(output, name + '.txt'), text)!
	}
	amp := remote(host, '/usr/sbin/ioreg', ['-r', '-c', 'AppleTAS5770LAmp', '-d1', '-l', '-w0'])!
	os.write_file(os.join_path(output, 'amplifier.txt'), amp)!
	loaded := remote(host, '/usr/bin/kmutil', ['showloaded'])!
	mut selected := []string{}
	for line in loaded.split_into_lines() {
		for driver in audio_drivers {
			if line.contains('com.apple.') && line.contains(driver + ' ') {
				selected << line
				break
			}
		}
	}
	if selected.len != audio_drivers.len {
		return error('Not all expected audio drivers are loaded')
	}
	os.write_file(os.join_path(output, 'loaded.txt'), selected.join('\n') + '\n')!
	chosen := os.read_file(os.join_path(output, 'chosen.txt'))!
	mut objects := ''
	for line in chosen.split_into_lines() {
		if line.contains('"boot-objects-path" = <"') {
			objects = line.all_after('"boot-objects-path" = <"').all_before('">')
		}
	}
	// Validate before this path reaches scp's remote path parser. The active
	// boot directory is UUID/boot/manifest-hash, never the x86 S/L/KernelCollections
	// placeholder also installed on Apple Silicon Macs.
	parts := objects.split('/')
	if parts.len != 4 || parts[0] != '' || parts[1].len != 36 || parts[2] != 'boot'
		|| parts[3].len != 96 || !parts[1].bytes().all(it.is_hex_digit() || it == `-`)
		|| !parts[3].bytes().all(it.is_hex_digit()) {
		return error('Unexpected active boot path: ${objects}')
	}
	path := '/System/Volumes/Preboot' + objects + '/System/Library/Caches/com.apple.kernelcaches/kernelcache'
	destination := os.join_path(output, 'kernelcache')
	capture('/usr/bin/scp', ['-q', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', host + ':' + path,
		destination])!
	data := os.read_bytes(destination)!
	os.write_file(os.join_path(output, 'kernel.json'), json2.encode({
		'source': path
		'sha256': sha256.sum(data).hex()
		'bytes':  data.len.str()
	}) + '\n')!
	println('Saved live J313 audio topology, loaded driver UUIDs and active kernel cache to ${output}')
}

fn main() {
	run() or {
		eprintln('audio-probe: ${err}')
		exit(1)
	}
}
