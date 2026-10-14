// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

fn elf_profile_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-elf-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn elf_profile_check(work string, architecture string, kind string, bytes []u8, accepted bool) ! {
	os.write_file_array(work + '/image', bytes)!
	os.chmod(work + '/image', 0o755)!
	root := C.open(work.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	assert root >= 0
	defer { C.close(root) }
	mut diagnostic := ''
	profile_elf(root, 'image', architecture, kind, true) or { diagnostic = err.msg() }
	assert (diagnostic == '') == accepted, '${architecture}/${kind}: ${diagnostic}'
	if !accepted { assert diagnostic.contains('ELF profile') }
}

fn test_elf_profiles_accept_both_targets_with_file_backed_code_and_legal_zero_fill() {
	work := elf_profile_work()!
	defer { os.rmdir_all(work) or {} }
	for architecture in ['aarch64', 'x86_64'] {
		for kind in ['static', 'pie', 'shared'] {
			original := elffixture.image(architecture, kind)
			elf_profile_check(work, architecture, kind, original, true)!
			for alignment in [u64(0), 1, 4096] {
				mut bytes := original.clone()
				elffixture.put(mut bytes, 112, alignment)
				elf_profile_check(work, architecture, kind, bytes, true)!
			}
			// An additional memory-only PT_LOAD is legal; shared objects may
			// have e_entry=0. Neither permits a CLI entry in zero-fill memory.
			mut bytes := original.clone()
			second := 64 + int(bytes[56]) * 56
			bytes[56] += 1; bytes[second] = 1; bytes[second + 4] = 6
			elffixture.put(mut bytes, second + 8, 512)
			elffixture.put(mut bytes, second + 16, 0x200200)
			elffixture.put(mut bytes, second + 40, 4096)
			elffixture.put(mut bytes, second + 48, 4096)
			elf_profile_check(work, architecture, kind, bytes, true)!
		}
	}
}

fn test_elf_profiles_refuse_invalid_header_ranges_load_segments_and_entry_points() {
	work := elf_profile_work()!
	defer { os.rmdir_all(work) or {} }
	for architecture in ['aarch64', 'x86_64'] {
		for kind in ['static', 'pie', 'shared'] {
			original := elffixture.image(architecture, kind)
			for field in ['header-size', 'header-width', 'header-before-elf', 'header-outside-file', 'header-overflow',
				'no-headers', 'many-headers', 'no-load', 'truncated-load', 'load-offset-overflow', 'load-size-overflow',
				'memory-too-small', 'memory-address-overflow', 'alignment-not-power-two', 'alignment-mismatch'] {
				mut bytes := original.clone()
				match field {
					'header-size' { bytes[52] = 0 }
					'header-width' { bytes[54] = 57 }
					'header-before-elf' { elffixture.put(mut bytes, 32, 8) }
					'header-outside-file' { elffixture.put(mut bytes, 32, 512) }
					'header-overflow' { elffixture.put(mut bytes, 32, ~u64(0)) }
					'no-headers' { bytes[56] = 0 }
					'many-headers' { bytes[56] = 1; bytes[57] = 4 }
					'no-load' { bytes[64] = 4 }
					'truncated-load' { elffixture.put(mut bytes, 96, 513) }
					'load-offset-overflow' { elffixture.put(mut bytes, 72, ~u64(0)) }
					'load-size-overflow' { elffixture.put(mut bytes, 96, ~u64(0)) }
					'memory-too-small' { elffixture.put(mut bytes, 104, 511) }
					'memory-address-overflow' { elffixture.put(mut bytes, 80, ~u64(0) - 10) }
					'alignment-not-power-two' { elffixture.put(mut bytes, 112, 3) }
					'alignment-mismatch' { elffixture.put(mut bytes, 80, 0x100001) }
					else { assert false }
				}
				elf_profile_check(work, architecture, kind, bytes, false)!
			}
			if kind == 'shared' { continue }
			for entry in [u64(0), 0x100200, 0x100300, 0x200000, ~u64(0)] {
				mut bytes := original.clone()
				elffixture.put(mut bytes, 24, entry)
				elf_profile_check(work, architecture, kind, bytes, false)!
			}
			mut bytes := original.clone()
			bytes[68] = 4
			elf_profile_check(work, architecture, kind, bytes, false)!
		}
	}
}

fn test_elf_profiles_require_one_bounded_absolute_terminated_interpreter_only_for_pie() {
	work := elf_profile_work()!
	defer { os.rmdir_all(work) or {} }
	for architecture in ['aarch64', 'x86_64'] {
		for field in ['missing', 'empty', 'short', 'oversized', 'truncated', 'relative', 'unterminated', 'embedded-nul', 'duplicate'] {
			mut bytes := elffixture.image(architecture, 'pie')
			match field {
				'missing' { bytes[120] = 0 }
				'empty' { elffixture.put(mut bytes, 152, 0) }
				'short' { elffixture.put(mut bytes, 152, 1) }
				'oversized' { elffixture.put(mut bytes, 152, 4097) }
				'truncated' { elffixture.put(mut bytes, 128, 511) }
				'relative' { bytes[320] = `l` }
				'unterminated' { bytes[320 + int(bytes[152]) - 1] = `x` }
				'embedded-nul' { bytes[321] = 0 }
				'duplicate' { bytes[56] = 3; for i in 0 .. 56 { bytes[176 + i] = bytes[120 + i] } }
				else { assert false }
			}
			elf_profile_check(work, architecture, 'pie', bytes, false)!
		}
		for kind in ['static', 'shared'] {
			mut bytes := elffixture.image(architecture, 'pie')
			bytes[16] = if kind == 'static' { u8(2) } else { u8(3) }
			elf_profile_check(work, architecture, kind, bytes, false)!
		}
		// The inclusive interpreter bound is admitted without unbounded reads.
		mut bytes := elffixture.image(architecture, 'pie')
		bytes << []u8{len: 4096}
		elffixture.put(mut bytes, 96, u64(bytes.len)); elffixture.put(mut bytes, 104, u64(bytes.len))
		elffixture.put(mut bytes, 152, 4096)
		for i in 321 .. 320 + 4095 { bytes[i] = `a` }
		bytes[320 + 4095] = 0
		elf_profile_check(work, architecture, 'pie', bytes, true)!
		elffixture.put(mut bytes, 152, 4097)
		elf_profile_check(work, architecture, 'pie', bytes, false)!
	}
	elf_profile_check(work, 'riscv64', 'static', elffixture.image('x86_64', 'static'), false)!
	elf_profile_check(work, 'x86_64', 'unknown', elffixture.image('x86_64', 'shared'), false)!
}
