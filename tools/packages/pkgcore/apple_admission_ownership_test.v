// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.applefixture

$if track_heap ? {
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
}

fn admission_binary_info() []u8 {
	mut bytes := 'bplist00'.bytes(); mut offsets := [u8(8)]
	bytes << [u8(0xd3), 1, 2, 3, 4, 5, 6]
	for text in ['CFBundleIdentifier', 'CFBundleExecutable', 'CFBundlePackageType', 'org.example.apple', 'Example', 'APPL']! {
		offsets << u8(bytes.len)
		if text.len < 15 { bytes << u8(0x50 | text.len) } else { bytes << [u8(0x5f), 0x10, u8(text.len)] }
		bytes << text.bytes()
	}
	table := bytes.len; bytes << offsets; bytes << []u8{len: 32}
	trailer := bytes.len - 32; bytes[trailer + 6] = 1; bytes[trailer + 7] = 1
	bytes[trailer + 15] = 7; bytes[trailer + 31] = u8(table)
	return bytes
}

fn admission_attempt(root int, p Package, image bool, valid bool) {
	if _ := admission_check(root, p, image) { assert valid }
	else { message := err.msg(); unsafe { message.free(); err.free() }; assert !valid }
}

fn admission_check(root int, p Package, image bool) ! {
	if image { profile_apple_image(root, 'input')! }
	else { apple_profile_plist(root, 'input', p)! }
}

fn test_apple_admission_retires_macho_and_xml_binary_plist_success_and_refusal_storage() {
	work := os.real_path(os.temp_dir()) + '/vinix-apple-admission-' + time.now().unix_micro().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	root := capture_prepared_root(work, 'Apple admission ownership')!; defer { C.close(root) }
	p := Package{ id: 'org.example.apple', arguments: ['@APP@/Example.app/Example'] }
	good := '<plist><dict><key>CFBundleIdentifier</key><string>org.example.apple</string><key>CFBundleExecutable</key><string>Example</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>'
	for selection in 0 .. 15 {
		mut bytes := match selection {
			0 { good.bytes() }
			1 { admission_binary_info() }
			2 { good.replace('org.example.apple', 'org.example.&#x61;pple').bytes() }
			3 { good.replace('org.example.apple', 'other.app').bytes() }
			4 { good.replace('</dict>', '<key>extra</key><array><string>a&amp;b</string><integer> 1 </integer><data>YQ==</data><dict/></array></dict>').bytes() }
			5 { good.replace('</dict>', '<key>CFBundleIdentifier</key><string>duplicate</string></dict>').bytes() }
			6 { '<plist><dict><key>first</key><string>owned</string><key>broken</key>'.bytes() }
			7 { '<plist><dict><key>unknown</key><string>&unknown;</string></dict></plist>'.bytes() }
			8 { '<plist><dict/></plist>trailing'.bytes() }
			9 { admission_binary_info() }
			10, 11, 12, 13, 14 { applefixture.image(23) }
			else { panic('selection') }
		}
		if selection == 9 { bytes[15] = 0xff } // malformed string object after dictionary allocation
		if selection == 11 { bytes[0] = 0 }
		if selection == 12 { bytes[136] = 1 } // wrong platform
		if selection == 13 { bytes[152] = 0x28; bytes[155] = 0x80; bytes[16] = 4; bytes[20] = 144; bytes[156] = 24 } // duplicate LC_MAIN
		if selection == 14 { bytes[152] = 0x0c; bytes[16] = 4; bytes[20] = 128; bytes[156] = 8 } // optional unknown command
		os.write_file_array(work + '/input', bytes)!
		valid := selection in [0, 1, 2, 4, 10, 14]!
		admission_attempt(root, p, selection >= 10, valid)
		mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 128 {
			$if track_heap ? { C.vinix_heap_begin() }
			admission_attempt(root, p, selection >= 10, valid)
			$if track_heap ? {
				kept := C.vinix_heap_end(); count := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if count > records { records = count }
			}
		}
		$if track_heap ? {
			println('APPLE ADMISSION selection=' + selection.str() + ' retained=' + maximum.str() + ' allocations=' + records.str())
			assert maximum == 0 && records == 0
		}
	}
	println('APPLE ADMISSION 1920 Mach-O and XML/binary plist cycles retire successful and refused admission storage PASS')
}
