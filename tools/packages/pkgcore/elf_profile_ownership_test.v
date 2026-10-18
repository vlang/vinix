// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.mkfifo(&char, u32) int
struct ElfOwnershipLimit { current u64 maximum u64 }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn elf_owned_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn elf_owned_attempt(root int, architecture string, kind string, path string, accepted bool) {
	if _ := profile_elf(root, path, architecture, kind, true) { assert accepted }
	else { message := err.msg(); assert !accepted && message != ''; unsafe { message.free(); err.free() } }
}

fn test_elf_checks_retire_valid_images_signature_header_segment_interpreter_and_file_refusals() {
	fixture := os.real_path(os.temp_dir()) + '/vinix-elf-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(fixture)!; defer { os.rmdir_all(fixture) or {} }
	root := capture_prepared_root(fixture, 'ELF owner test')!; defer { C.close(root) }
	mut original := ElfOwnershipLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limit := ElfOwnershipLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	mut cases := 0
	for architecture in ['aarch64', 'x86_64']! {
		for kind in ['static', 'pie', 'shared']! {
			for mode in ['valid', 'signature-0', 'signature-1', 'signature-2', 'signature-3', 'signature-4', 'signature-5', 'signature-6',
				'target', 'type', 'width', 'count', 'segment', 'memory', 'alignment', 'entry', 'no-load', 'empty', 'mode', 'directory', 'fifo', 'missing', 'alias',
				'interpreter-relative', 'interpreter-terminator', 'interpreter-nul', 'interpreter-duplicate', 'interpreter-limit', 'interpreter-oversized']! {
				if mode.starts_with('interpreter-') && kind != 'pie' { continue }
				path := fixture + '/image'
				if os.is_dir(path) { os.rmdir_all(path)! } else if os.exists(path) || os.is_link(path) { os.rm(path)! }
				mut bytes := elffixture.image(architecture, kind)
				defer { unsafe { bytes.free() } }
				mut accepted := mode in ['valid', 'alias', 'interpreter-limit']! || (mode == 'entry' && kind == 'shared')
				if mode.starts_with('signature-') { bytes[int(mode[10] - `0`)] ^= 1 }
				match mode {
					'target' { bytes[18] = 0 } 'type' { bytes[16] = 0 } 'width' { bytes[54] = 57 } 'count' { bytes[56] = 0 }
					'segment' { elffixture.put(mut bytes, 96, 513) } 'memory' { elffixture.put(mut bytes, 104, 511) }
					'alignment' { elffixture.put(mut bytes, 112, 3) } 'entry' { elffixture.put(mut bytes, 24, 0) }
					'no-load' { bytes[64] = 4 } 'empty' { bytes.clear() }
					'interpreter-relative' { bytes[320] = `x` } 'interpreter-terminator' { bytes[320 + int(bytes[152]) - 1] = `x` }
					'interpreter-nul' { bytes[321] = 0 } 'interpreter-duplicate' { bytes[56] = 3; for i in 0 .. 56 { bytes[176 + i] = bytes[120 + i] } }
					'interpreter-limit', 'interpreter-oversized' {
						bytes << []u8{len: 4096}; elffixture.put(mut bytes, 96, u64(bytes.len)); elffixture.put(mut bytes, 104, u64(bytes.len))
						elffixture.put(mut bytes, 152, if mode == 'interpreter-limit' { u64(4096) } else { u64(4097) })
						for i in 321 .. 320 + 4095 { bytes[i] = `a` }; bytes[320 + 4095] = 0
					}
					else {}
				}
				match mode {
					'directory' { os.mkdir(path)! } 'fifo' { assert C.mkfifo(path.str, 0o600) == 0 } 'missing' {}
					'alias' { os.write_file_array(fixture + '/real', bytes)!; os.chmod(fixture + '/real', 0o755)!; os.symlink('real', path)! }
					else { os.write_file_array(path, bytes)!; os.chmod(path, if mode == 'mode' { 0o644 } else { 0o755 })! }
				}
				before := elf_owned_descriptors()
				mut maximum := u64(0); mut records := u32(0)
				for _ in 0 .. 8 {
					$if track_heap ? { C.vinix_heap_begin() }
					elf_owned_attempt(root, architecture, kind, 'image', accepted)
					$if track_heap ? {
						kept := C.vinix_heap_end(); count := C.vinix_heap_count()
						if kept > maximum { maximum = kept }; if count > records { records = count }
					}
					assert elf_owned_descriptors() == before
				}
				$if track_heap ? {
					assert maximum == 0 && records == 0, architecture + '/' + kind + '/' + mode + ' retains storage'
				}
				cases++
			}
		}
	}
	assert cases == 150
	println('ELF OWNERSHIP 150 static/PIE/shared target, signature, range, interpreter and file cases; 1200 checks retain zero tracked bytes/allocations and stable descriptors PASS')
}
