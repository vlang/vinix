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
	if os.args.len != 4 { panic('usage: image-initializers-input-inventory ROOT OUTPUT REVISION') }
	root := os.real_path(os.args[1])
	out := os.real_path(os.args[2])
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') {
		panic('inventory output must exist outside the repository')
	}
	revision := os.args[3]
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { panic('invalid revision') }
	os.chdir(root) or { panic(err) }
	listing := os.exec(['git', 'ls-tree', '-r', '--name-only', revision, '--', 'compat/ios', 'tests/ios/native-checks.v', 'tests/ios/native-init.v', 'tests/ios/notification-checks.v', 'tests/ios/notification-vm.v', 'tests/ios/image-initializers-evidence.v', 'tests/ios/image-initializers-input-inventory.v', 'tests/ios/string-character-search-evidence.v', 'tests/ios/scene-notifications-evidence.v', 'tests/ios/foundation-file-memory-evidence.v', 'tests/ios/foundation-http-evidence.v', 'tests/ios/probe-memory-evidence.v', 'tests/ios/probe-fault-evidence.v', 'tests/ios/probefault', 'tests/ios/probebudget', 'tests/ios/tlsbuild', 'tests/ios/startup-host.v', 'tests/ios/inspect-string-character-search.v', 'tests/ios/inspect-scene-notifications.v', 'tests/ios/inspect-probe-fault.v'])
	if listing.exit_code != 0 { panic(listing.output) }
	mut paths_in_revision := listing.output.trim_space().split_into_lines()
	for checker in ['tests/ios/probe-vm-evidence.v', 'tests/ios/probe-vm-tags-evidence.v', 'tests/ios/block-byref-evidence.v', 'tests/ios/dictionary-snapshot-evidence.v', 'tests/ios/inspect-dictionary-snapshot-fault.v', 'tests/ios/inline-pthread-self-run.v', 'tests/ios/inline-pthread-self-evidence.v'] {
		listing_checker := os.exec(['git', 'ls-tree', '-r', '--name-only', revision, '--', checker])
		if listing_checker.exit_code != 0 { panic(listing_checker.output) }
		if listing_checker.output.trim_space() == checker { paths_in_revision << checker }
	}
	paths_in_revision.sort()
	os.write_file(out + '/source-files.txt', paths_in_revision.join('\n') + '\n') or { panic(err) }
	for path in paths_in_revision {
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
	tls := 'build/ios/fortnite/ns-calendar-checks/toolchain/thirdparty/mbedtls'
	for extension in ['.c', '.h'] {
		for path in os.walk_ext(root + '/' + tls, extension) { paths << path[root.len + 1..] }
	}
	mut lines := []string{}
	for path in paths {
		lines << (digest(root + '/' + path) or { panic(err) }) + '  ' + path
	}
	for path in ['/opt/homebrew/opt/llvm/bin/clang', '/opt/homebrew/opt/llvm/bin/llvm-ar', '/opt/homebrew/opt/llvm/bin/llvm-objdump', '/usr/bin/clang', '/usr/bin/ar', '/usr/bin/openssl', '/etc/ssl/cert.pem',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSObject.h',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/usr/include/objc/runtime.h',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/System/iOSSupport/System/Library/Frameworks/UIKit.framework/Versions/A/Headers/UIScene.h',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/System/iOSSupport/System/Library/Frameworks/UIKit.framework/Versions/A/UIKit.tbd',
		'/opt/homebrew/bin/qemu-system-aarch64', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'] {
		lines << (digest(path) or { panic(err) }) + '  ' + path
	}
	resource := os.exec(['/opt/homebrew/opt/llvm/bin/clang', '-print-resource-dir'])
	if resource.exit_code != 0 { panic(resource.output) }
	for path in os.walk_ext(resource.output.trim_space() + '/include', '.h') {
		lines << (digest(path) or { panic(err) }) + '  ' + path
	}
	lines.sort()
	os.write_file(out + '/build-inputs.sha256', lines.join('\n') + '\n') or { panic(err) }
	os.write_file(out + '/source-revision.txt', revision + '\n') or { panic(err) }
	println('selected build inputs: ' + lines.len.str())
}
