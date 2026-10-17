// SPDX-License-Identifier: GPL-2.0-or-later
module bundlehost

import hosttest
import json2
import os
import tarstream
import verityimage

pub const limine_version = '12.9.3'
pub const limine_sha = 'b28b9c9f614f4252cae79580d6cbbc09f4d764a541ec01d586b5c385e3776c99'

fn valued(names []string) []hosttest.Option {
	return names.map(hosttest.Option{ name: it, value: true })
}

fn usage_root() string {
	return 'Usage: build build --data FILE --output NEW [--pad]\n       build verify IMAGE --data-blocks N --root-hash SHA256\n       build command-line --device /dev/DEVICE --data-blocks N --root-hash SHA256'
}

fn subcommand(args []string, usage string, choices []string) !(string, []string) {
	if args.len == 0 { return argument('missing required operation') }
	if args[0] in ['-h', '--help'] {
		println(usage)
		exit(0)
	}
	if args[0] !in choices { return argument('invalid operation: ' + args[0]) }
	return args[0], args[1..]
}

fn root_command(args []string) ! {
	operation, rest := subcommand(args, usage_root(), ['build', 'verify', 'command-line'])!
	if operation == 'build' {
		mut specs := valued(['--data', '--output'])
		specs << hosttest.Option{ name: '--pad' }
		options := parse(rest, specs, [], 0, usage_root())!
		options.require(['--data', '--output'])!
		println(json2.encode(verityimage.build(options.value('--data', ''), options.value('--output', ''), options.has('--pad'))!,
			prettify: true
		))
	} else {
		mut specs := valued(['--data-blocks', '--root-hash'])
		if operation == 'command-line' { specs << hosttest.Option{ name: '--device', value: true } }
		options := parse(rest, specs, [], if operation == 'verify' { 1 } else { 0 }, usage_root())!
		options.require(['--data-blocks', '--root-hash'])!
		count := options.count('--data-blocks')!
		if operation == 'verify' {
			verityimage.verify(options.positional[0], count, options.value('--root-hash', ''))!
			println('All data and hash blocks verified against the supplied root.')
		} else {
			options.require(['--device'])!
			println(verityimage.command_line(options.value('--device', ''), count, options.value('--root-hash', ''))!)
		}
	}
}

fn boot_command(args []string) ! {
	usage := 'Usage: build build --arch x86_64|aarch64 --loader EFI --kernel ELF --initramfs TAR [--initramfs TAR ...] --output NEW [--key PEM --certificate CRT | --developer-unsigned]\n       build verify BUNDLE --arch ARCH [--certificate CRT | --developer-unsigned]\nOptions: --backend sbsign|osslsigncode --dtb FILE --cmdline TEXT\n         --verity-root IMAGE --verity-device /dev/DEVICE --verity-data-blocks N --verity-root-hash SHA256'
	operation, rest := subcommand(args, usage, ['build', 'verify'])!
	mut specs := [
		hosttest.Option{ name: '--arch', value: true, choices: ['x86_64', 'aarch64'] },
		hosttest.Option{ name: '--backend', value: true, choices: ['sbsign', 'osslsigncode'] },
		hosttest.Option{ name: '--developer-unsigned' },
		hosttest.Option{ name: '--certificate', value: true },
	]
	if operation == 'build' {
		specs << valued(['--loader', '--kernel', '--initramfs', '--dtb', '--output', '--key',
			'--cmdline', '--verity-root', '--verity-device', '--verity-data-blocks',
			'--verity-root-hash'])
	}
	options := parse(rest, specs, ['--initramfs'], if operation == 'verify' { 1 } else { 0 }, usage)!
	options.require(['--arch'])!
	if operation == 'verify' {
		verify(options.positional[0], options.value('--arch', ''), options.value('--certificate', ''), options.value('--backend', 'sbsign'), options.has('--developer-unsigned'))!
		println(if options.has('--developer-unsigned') {
			'Developer bundle checksums verified; boot is UNAUTHENTICATED.'
		} else {
			'Bundle verified.'
		})
	} else {
		options.require(['--loader', '--kernel', '--initramfs', '--output'])!
		build(Build{
			arch:          options.value('--arch', '')
			loader:        options.value('--loader', '')
			kernel:        options.value('--kernel', '')
			initramfs:     options.values['--initramfs']
			dtb:           options.value('--dtb', '')
			output:        options.value('--output', '')
			key:           options.value('--key', '')
			certificate:   options.value('--certificate', '')
			backend:       options.value('--backend', 'sbsign')
			cmdline:       options.value('--cmdline', '')
			developer:     options.has('--developer-unsigned')
			verity_root:   options.value('--verity-root', '')
			verity_device: options.value('--verity-device', '')
			verity_count:  if options.has('--verity-data-blocks') {
				options.count('--verity-data-blocks')!
			} else {
				u64(0)
			}
			verity_hash:   options.value('--verity-root-hash', '')
		})!
	}
}

fn loader_command(args []string) ! {
	specs := [
		hosttest.Option{ name: '--arch', value: true, choices: ['x86_64', 'aarch64'] },
		hosttest.Option{ name: '--output', value: true },
		hosttest.Option{ name: '--source-archive', value: true },
	]
	options := parse(args, specs, [], 0, 'Usage: get-loader --arch x86_64|aarch64 --output NEW [--source-archive pinned.tar.gz]')!
	options.require(['--arch', '--output'])!
	output := absolute(options.value('--output', ''))
	if os.exists(output) || os.is_link(output) {
		return error('output already exists; choose a new directory')
	}
	for name in ['clang', 'ld.lld', 'llvm-ar', 'llvm-objcopy', 'make', 'patch'] {
		os.find_abs_path_of_executable(name) or { return error('required command not found: ' + name) }
	}
	work := temporary(os.dir(output), '.vinix-limine-')!
	defer { retire(work) }
	archive := if options.has('--source-archive') {
		absolute(options.value('--source-archive', ''))
	} else {
		work + '/limine.tar.gz'
	}
	if !options.has('--source-archive') {
		run(['curl', '-fL', '--output', archive,
			'https://github.com/limine-bootloader/limine/releases/download/v' + limine_version + '/limine-' + limine_version + '.tar.gz'])!
	}
	if hosttest.file_digest(archive)! != limine_sha {
		return error('Limine source archive SHA-256 mismatch')
	}
	mut reader := tarstream.open(archive)!
	defer { reader.close() }
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name.starts_with('/') || '..' in member.name.split('/') || member.kind in [
			u8(`1`),
			`2`,
		] {
			return error('unsafe source archive entry')
		}
	}
	reader.close()
	run(['tar', 'xzf', archive, '-C', work])!
	source := work + '/limine-' + limine_version
	arch := options.value('--arch', '')
	if arch == 'aarch64' {
		run_in(['patch', '-p1', '--batch', '-i',
			root() + '/build-support/limine/' + limine_version + '-vinix-base-revision-2.patch'], source)!
	}
	run_in(['./configure', '--enable-uefi-' + if arch == 'x86_64' { 'x86-64' } else { arch },
		'--disable-uefi-cd', '--disable-bios', '--disable-bios-cd', '--disable-bios-pxe'], source)!
	run_in(['make', '-j4'], source)!
	filename := if arch == 'x86_64' { 'BOOTX64.EFI' } else { 'BOOTAA64.EFI' }
	staging := work + '/output'
	os.mkdir(staging)!
	os.cp(source + '/bin/' + filename, staging + '/' + filename)!
	hosttest.module_copy_file_preserving_stat(source + '/bin/limine', staging + '/limine')!
	if os.exists(output) || os.is_link(output) {
		return error('output already exists; choose a new directory')
	}
	os.mv(staging, output)!
	println('Built pinned, UNSIGNED Limine ' + limine_version + ': ' + output + '/' + filename)
}

fn dispatch(family string, args []string) ! {
	match family {
		'root' { root_command(args)! }
		'boot' { boot_command(args)! }
		'loader' { loader_command(args)! }
		else { return argument('Unknown verified tool') }
	}
}
