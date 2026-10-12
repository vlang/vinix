// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import cachecli
import gamehost
import hosttest
import json2
import runtime
import strconv
import vulkanbuild

pub fn driver_cli(root string, argv []string, venus bool) !int {
	args := cachecli.arguments(argv, ['--base-root', '--work', '--jobs'], [], ['--refresh'], 0, 0, 'Cross-build the private amd64 Mesa driver.\nUsage: driver --base-root DIR [--work DIR --jobs N --refresh]') or { return error_with_code(err.msg(), 2) }
	base := args.required('--base-root') or { return error_with_code(err.msg(), 2) }
	jobs := strconv.atoi(args.value('--jobs', runtime.nr_cpus().str())) or { return error_with_code(err.msg(), 2) }
	work := args.value('--work', root + '/build/dota2-runtime/' + if venus {
		'venus'
	} else {
		'mesa'
	})
	for output in build_driver(gamehost.Tools{ root: root }, venus, base, work, jobs, '--refresh' in args.options)! {
		println(output)
	}
	return 0
}

pub fn vulkan_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--steam-build', '--build', '--root', '--guest-root', '--mirror',
		'--release'], [], ['--refresh', '--keep-steam-libc', '--debian-lavapipe', '--no-venus'], 0, 0, 'Stage the private x86-64 Vulkan runtime.\nUsage: vulkan-stage [--steam-build DIR --build DIR --root DIR --guest-root PATH --refresh --mirror URL --release bookworm --keep-steam-libc --debian-lavapipe --no-venus]') or { return error_with_code(err.msg(), 2) }
	mut options := map[string]json2.Any{}
	for name, fallback in {
		'--steam-build': root + '/build-aarch64-steam'
		'--build':       root + '/build/dota2-vulkan'
	} {
		options[name[2..].replace('-', '_')] = tagged_path(hosttest.module_resolve(args.value(name, fallback))!)
	}
	options['root'] = if '--root' in args.options {
		tagged_path(args.value('--root', ''))
	} else {
		json2.Any(json2.Null{})
	}
	for name, fallback in {
		'--guest-root': '/usr/libexec/vinix-dota2/root'
		'--mirror':     'https://deb.debian.org/debian'
		'--release':    'bookworm'
	} {
		options[name[2..].replace('-', '_')] = json2.Any(args.value(name, fallback))
	}
	for name in ['--refresh', '--keep-steam-libc', '--debian-lavapipe', '--no-venus'] {
		options[name[2..].replace('-', '_')] = json2.Any(name in args.options)
	}
	mut context := VulkanContext{ tools: gamehost.Tools{ root: root } }
	defer { context.close() }
	context.call('main', {
		'options': json2.Any(options)
	}) or {
		if err is vulkanbuild.StageError && err.kind == 'ArgumentError' {
			return error_with_code(err.msg(), 2)
		}
		return err
	}
	return 0
}

pub fn doom_build_cli(root string, argv []string) !int {
	cachecli.arguments(argv, [], [], [], 0, 0, 'Build ARM64/musl dhewm3 and its verified demo.\nUsage: dhewm-build') or { return error_with_code(err.msg(), 2) }
	build := hosttest.module_resolve(gamehost.env('VINIX_DHEWM3_BUILD_DIR', root + '/build-aarch64-dhewm3'))!
	x11 := hosttest.module_resolve(gamehost.env('VINIX_X11_BUILD_DIR', root + '/build-aarch64-x11'))!
	build_dhewm(gamehost.Tools{ root: root }, build, x11)!
	return 0
}
