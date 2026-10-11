// SPDX-License-Identifier: GPL-2.0-or-later
// Install a static native guest fetcher; the host bootstrap is never packaged.
import bundlehost as bh
import hosttest
import os
import policyhost

fn checked(args []string) ! {
	options := bh.parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--staging', value: true },
		hosttest.Option{ name: '--cc', value: true },
	], [], 0, 'Usage: stage --arch aarch64|x86_64 --staging EXISTING [--cc MUSL_COMPILER]')!
	options.require(['--arch', '--staging'])!
	arch := options.value('--arch', '')
	staging := os.real_path(options.value('--staging', ''))
	if staging == '/' || !os.is_dir(staging) {
		return bh.ArgumentError{ message: 'Select an existing target directory' }
	}
	cc := options.value('--cc', os.getenv_opt('VINIX_MUSL_CC_' + arch.to_upper()) or { arch + '-linux-musl-gcc' })
	machine := bh.capture([cc, '-dumpmachine'])!.trim_space()
	if !machine.starts_with(arch + '-') || !machine.contains('linux') || !machine.contains('musl') {
		return error('Expected target Linux musl compiler, got ' + machine)
	}
	work := bh.temporary(os.temp_dir(), 'vinix-minecraft-stage-')!
	defer { bh.retire(work) }
	v := bh.capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
		bh.root()])!
	tools := ['fetch-minecraft', 'minecraft-login']
	for tool in tools {
		source := work + '/' + tool + '.c'
		bh.run([v, '-nocache', '-enable-globals', '-os', 'linux', '-arch',
			if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-d', 'glibc', '-d',
			'no_backtrace', '-path', bh.root() + '/build-support/minecraft|@vlib', '-o', source,
			bh.root() + '/build-support/minecraft/' + tool + '.v'])!
		binary := work + '/' + tool
		bh.run([cc, '-static', '-O2', '-w', '-D_GNU_SOURCE', source, '-pthread', '-lm', '-o', binary])!
		mut stream := os.open(binary)!
		header := stream.read_bytes(64)
		stream.close()
		if header.len != 64 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || int(header[18]) | (int(header[19]) << 8) != if arch == 'aarch64' {
			183
		} else {
			62
		} {
			return error('Native Minecraft ' + tool + ' ELF architecture mismatch')
		}
	}
	directory := staging + '/usr/libexec/vinix-minecraft'
	bh.mkdirs(directory)!
	publish := bh.temporary(directory, '.minecraft-stage-')!
	defer { bh.retire(publish) }
	for tool in tools {
		os.cp(work + '/' + tool, publish + '/' + tool)!
		os.chmod(publish + '/' + tool, 0o755)!
	}
	for tool in tools {
		policyhost.command_checkpoint()!
		os.mv(publish + '/' + tool, directory + '/' + tool)!
	}
	// Cached layers may contain the old interpreter entry point.
	os.rm(directory + '/fetch-minecraft.py') or {}
	println('Staged native Minecraft fetcher and sign-in (' + arch + ').')
}

fn main() {
	guard := policyhost.own_commands()
	defer { guard.close() }
	checked(os.args[1..]) or {
		eprintln(err)
		exit(if policyhost.command_interrupted() {
			130
		} else if err is bh.ArgumentError {
			2
		} else {
			1
		})
	}
}
