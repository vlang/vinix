// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import iosui
import os
import strconv

fn integer(text string) !int {
	return int(strconv.common_parse_int(text, 10, 32, true, true) or { return error_with_code('invalid integer: ' + text, 2) })
}

fn run() ! {
	if os.args.len < 2 { return error_with_code('expected uikit|game2048|desktop', 2) }
	root := os.real_path(os.dir(@FILE) + '/../..')
	mode := os.args[1]
	if mode == 'uikit' {
		args := cachecli.arguments(os.args[2..], ['--runner', '--binary'], [], [], 0, 0, 'Exercise the unmodified iOS Mach-O through the desktop protocol.\nUsage: uikit [--runner FILE] [--binary FILE]') or { return error_with_code(err.msg(), 2) }
		iosui.uikit(args.value('--runner', root + '/build/ios/run-ios-host'), args.value('--binary', root + '/build/ios/objc/Calculator.app/Calculator'))!
	} else if mode == 'game2048' {
		args := cachecli.arguments(os.args[2..], ['--runner', '--binary', '--cycles'], [], [], 0, 0, 'Run upstream iOS-2048 and check native game/UI behavior.\nUsage: game2048 [--runner FILE --binary FILE --cycles 32]') or { return error_with_code(err.msg(), 2) }
		iosui.game2048(args.value('--runner', root + '/build/ios/run-ios-host'), args.value('--binary', root + '/build/ios/2048/NumberTileGame.app/NumberTileGame'), integer(args.value('--cycles', '32'))!)!
	} else if mode == 'desktop' {
		args := cachecli.arguments(os.args[2..], ['--desktop', '--timeout', '--app'], [], [], 0, 0, 'Boot a minimal Vinix desktop, click the iOS binary, save its screen.\nUsage: desktop [--desktop FILE --timeout 120 --app calculator|2048]') or { return error_with_code(err.msg(), 2) }
		iosui.desktop(root, args.value('--desktop', root + '/build/vinix-desktop'), integer(args.value('--timeout', '120'))!, args.value('--app', 'calculator'))!
	} else {
		return error_with_code('unknown iOS UI mode', 2)
	}
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
}
