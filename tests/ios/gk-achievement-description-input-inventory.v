// SPDX-License-Identifier: GPL-2.0-or-later
// Selected input hashes; this does not seal compiler and header closures.
module main

import crypto.sha256
import os

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn main() {
	if os.args.len != 4 { panic('usage: gk-achievement-description-input-inventory ROOT OUTPUT REVISION') }
	root := os.real_path(os.args[1])
	out := os.real_path(os.args[2])
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') {
		panic('inventory output must exist outside the repository')
	}
	revision := os.args[3]
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { panic('invalid revision') }
	os.chdir(root) or { panic(err) }
	for path in ['compat/ios/runner/gk_achievement_description.c.v',
		'compat/ios/runner/gk_achievement_description_test.v', 'compat/ios/runner/objc.c.v',
		'compat/ios/runner/objc_associated.c.v', 'compat/ios/runner/game_center.c.v',
		'compat/ios/runner/objc_runtime.c.v', 'compat/ios/runner/objc_storage.c.v',
		'compat/ios/runner/scenes.c.v', 'compat/ios/runner/uikit.v', 'compat/ios/runner/frameworks.c.v',
		'tests/ios/native-checks.v', 'tests/ios/native-init.v',
		'tests/ios/notification-checks.v', 'tests/ios/notification-vm.v',
		'tests/ios/inspect-gk-achievement-description.v',
		'tests/ios/gk-achievement-description-evidence.v', 'tests/ios/gk-achievement-description-input-inventory.v'] {
		result := os.exec(['git', 'show', revision + ':' + path])
		if result.exit_code != 0 { panic(result.output) }
		target := out + '/source/' + path
		os.mkdir_all(os.dir(target)) or { panic(err) }
		os.write_file(target, result.output) or { panic(err) }
	}
	mut paths := [
		'build/ios/fortnite/ns-calendar-checks/toolchain/v',
		'build/ios/fortnite/ns-calendar-checks/toolchain/vlib/os/execute_capture_nix.c',
		'build/ios/fortnite/ns-calendar-checks/toolchain/vlib/builtin/segfault_handler_nix.c',
		'build/ios/fortnite/socket-kernel-arm64/bin/vinix',
		'boot-image/limine-bin/BOOTAA64.EFI',
		'build/ios/fortnite/probe-initramfs.tar.gz',
		'build/ios/cxx/libcxx-ios.a',
		'build/ios/cxx/sysroot/usr/lib/libc++abi.a',
		'build/ios/cxx/sysroot/usr/lib/libunwind.a',
		'build/ios/sqlite/arm64/libsqlite3.a',
		'build/ios/fortnite/video-decode-deps/arm64/libavcodec/libavcodec.a',
		'build/ios/fortnite/video-decode-deps/arm64/libswscale/libswscale.a',
		'build/ios/fortnite/video-decode-deps/arm64/libavutil/libavutil.a',
	]
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a', 'libm.a'] {
		paths << 'build/ios/fortnite/date-encoding-checks/sdk/usr/lib/' + name
	}
	for name in ['crtbegin.o', 'crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] {
		paths << 'build/useralloc-pipe/static-desktop-v5/sysroot/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0/' + name
	}
	gles := 'build/ios/fortnite/staging/usr/lib/vinix/ios-gles'
	for name in os.ls(root + '/' + gles) or { panic(err) } {
		if os.is_file(root + '/' + gles + '/' + name) { paths << gles + '/' + name }
	}
	mut lines := []string{}
	for path in paths {
		lines << (digest(root + '/' + path) or { panic(err) }) + '  ' + path
	}
	for path in ['/opt/homebrew/opt/llvm/bin/clang', '/usr/bin/clang',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/System/iOSSupport/System/Library/Frameworks/GameKit.framework/Versions/A/Headers/GKAchievementDescription.h',
		'/opt/homebrew/bin/qemu-system-aarch64', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'] {
		lines << (digest(path) or { panic(err) }) + '  ' + path
	}
	lines.sort()
	os.write_file(out + '/build-inputs.sha256', lines.join('\n') + '\n') or { panic(err) }
	os.write_file(out + '/source-revision.txt', revision + '\n') or { panic(err) }
	println('selected build inputs: ' + lines.len.str())
}
