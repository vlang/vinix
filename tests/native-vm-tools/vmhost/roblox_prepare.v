// SPDX-License-Identifier: MIT
module vmhost

import cachecli
import cachekey
import gamehost
import hosttest
import os
import perfreport

pub struct RobloxOptions {
pub:
	repo        string
	kernel      string
	translation string
	work        string
	version     string
	version_set bool
	winedebug   string
	arguments   string
	seconds     string
	timeout     string
	memory      string
	cpus        string
	port        string
	strace      bool
	shell       bool
}

pub fn roblox_options(root string, argv []string) !RobloxOptions {
	scalar := ['--repo', '--kernel-dir', '--translation', '--work', '--version', '--winedebug',
		'--arguments', '--seconds', '--timeout', '--mem', '--cpus', '--port']
	mut normalized := []string{}
	mut index := 0
	for index < argv.len {
		if argv[index] in scalar && index + 1 < argv.len && argv[index + 1].starts_with('-') && argv[index + 1].contains(' ') {
			// argparse treats an option-looking value containing a space as a
			// positional value; preserve quoted Windows client arguments.
			normalized << argv[index] + '=' + argv[index + 1]
			index += 2
		} else {
			normalized << argv[index]
			index++
		}
	}
	args := cachecli.arguments(normalized, scalar, [], [
		'--strace',
		'--shell',
	], 0, 0, 'Start Roblox Windows Player on Vinix through Wine and retain its logs and frames.\nUsage: run [--repo PATH --kernel-dir PATH --translation PATH --work PATH --version NAME --winedebug TEXT --arguments TEXT --seconds N --timeout N --mem MB --cpus N --port N --strace --shell]') or { return error_with_code(err.msg(), 2) }
	repo := args.value('--repo', root)
	mut numbers := map[string]string{}
	for name, fallback in {
		'--seconds': '300'
		'--timeout': '1500'
		'--mem':     '12288'
		'--cpus':    '4'
		'--port':    '18791'
	} {
		numbers[name] = perfreport.integer_text(args.value(name, fallback)) or { return error_with_code(err.msg(), 2) }
	}
	return RobloxOptions{
		repo:        repo
		kernel:      args.value('--kernel-dir', repo + '/kernel')
		translation: args.value('--translation', repo + '/build-aarch64-x86-translation/staging')
		work:        cachekey.resolve_path(args.value('--work', root + '/build/roblox-windows'))!
		version:     args.value('--version', '')
		version_set: '--version' in args.options
		winedebug:   args.value('--winedebug', 'fixme-all,err+all')
		arguments:   args.value('--arguments', '')
		seconds:     numbers['--seconds']!
		timeout:     numbers['--timeout']!
		memory:      numbers['--mem']!
		cpus:        numbers['--cpus']!
		port:        numbers['--port']!
		strace:      '--strace' in args.options
		shell:       '--shell' in args.options
	}
}

pub fn roblox_configuration(options RobloxOptions, version string) string {
	mut result := ''
	for pair in [
		['TEST_EXECUTABLE', 'C:\\Roblox\\Versions\\' + version + '\\RobloxPlayerBeta.exe'],
		['TEST_WINEDEBUG', options.winedebug],
		['TEST_UPLOAD', 'http://10.0.2.2:' + options.port],
		['TEST_SECONDS', options.seconds],
		['TEST_GEOMETRY', '1280x720x24'],
		['TEST_ARGUMENTS', options.arguments],
		['TEST_SHELL', if options.shell { '1' } else { '0' }],
		['TEST_STRACE', if options.strace { '1' } else { '0' }],
	] {
		result += pair[0] + '=' + hosttest.shell_quote(pair[1]) + '\n'
	}
	return result
}

pub fn roblox_prepare(root_repo string, options RobloxOptions, client string, version string) !string {
	root := options.work + '/root'
	if !os.exists(root + '/.prepared') {
		gamehost.remove(root)!
		roblox_copy_layer(options.repo + '/build-aarch64-x11/staging', root, [])!
		userland := options.repo + '/build-aarch64-userland/staging'
		for directory in ['lib', 'usr/lib'] {
			for name in os.ls(userland + '/' + directory)! {
				if !name.match_glob('*.so*') { continue }
				source := userland + '/' + directory + '/' + name
				target := root + '/' + directory + '/' + name
				if !os.exists(target) && !os.is_link(target) { gamehost.copy_file(source, target)! }
			}
		}
		gamehost.mkdir(root + '/bin')!
		gamehost.copy_file(userland + '/bin/busybox', root + '/bin/busybox')!
		for name in ['sh', 'cat', 'mkdir', 'chmod', 'sleep', 'uname', 'grep', 'ps', 'tail', 'head',
			'ls', 'wget', 'kill', 'rm', 'ln', 'find', 'sed', 'cut', 'wc', 'tr', 'date', 'cp', 'mv',
			'env'] {
			os.symlink('busybox', root + '/bin/' + name)!
		}
		for directory in ['sbin', 'proc', 'dev', 'sys', 'tmp', 'root', 'run', 'etc'] {
			gamehost.mkdir(root + '/' + directory)!
		}
		os.write_file(root + '/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\n')!
		os.write_file(root + '/etc/group', 'root:x:0:root\n')!
		roblox_copy_layer(options.translation, root, roblox_unused)!
		os.write_file(root + '/.prepared', '')!
	}
	for name in ['run-wine-x86-64', 'run-x86-64', 'run-x86-32'] {
		gamehost.copy_file(root_repo + '/build-support/x86-translation/' + name, root + '/usr/bin/' + name)!
	}
	installed := root + '/root/.wine-x86_64/drive_c/Roblox'
	gamehost.remove(installed)!
	roblox_copy_layer(client, installed + '/Versions/' + version, [])!
	test := root + '/opt/roblox-test'
	gamehost.mkdir(test)!
	os.write_file(test + '/config.sh', roblox_configuration(options, version))!
	gamehost.copy_file(root_repo + '/tests/roblox-windows/guest-init.sh', root + '/sbin/init')!
	os.chmod(root + '/sbin/init', 0o755)!
	return root
}
