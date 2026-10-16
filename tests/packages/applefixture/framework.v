// SPDX-License-Identifier: GPL-2.0-or-later
module applefixture

// This small test assembler emits a real ARM64 Mach-O with chained imports.
// All Foundation, file and Security calls below execute in the loaded image;
// the native package launcher cannot supply their results. No Apple SDK,
// compiler, proprietary program or host framework is needed to build it.
struct FrameworkProbe {
mut:
	bytes []u8 = []u8{len: 0x8000}
	pc int = 0x800
	strings int = 0x4800
	symbols []string
	libraries []int
	failures []int
	check int = 70
}

fn (mut p FrameworkProbe) op(value u32) { put(mut p.bytes, p.pc, value, 4); p.pc += 4 }
fn (mut p FrameworkProbe) imm(reg int, value u32) {
	p.op(0xd2800000 | (value & 65535) << 5 | u32(reg))
	if value >> 16 != 0 { p.op(0xf2a00000 | (value >> 16) << 5 | u32(reg)) }
}
fn (mut p FrameworkProbe) address(reg int, offset int) {
	delta := u32(offset - p.pc) & 0x1fffff
	p.op(0x10000000 | (delta & 3) << 29 | (delta >> 2) << 5 | u32(reg)) // ADR
}
fn (mut p FrameworkProbe) text(reg int, value string) {
	assert p.strings + value.len + 1 <= 0x5000
	p.address(reg, p.strings)
	for i, byte in value { p.bytes[p.strings + i] = byte }
	p.strings += value.len + 1
}
fn (mut p FrameworkProbe) load(reg int, slot int) { p.address(17, slot); p.op(0xf9400220 | u32(reg)) }
fn (mut p FrameworkProbe) save(reg int, slot int) { p.address(17, slot); p.op(0xf9000220 | u32(reg)) }
fn (mut p FrameworkProbe) imported(reg int, library int, symbol string, object bool) {
	mut index := p.symbols.index(symbol)
	if index < 0 { index = p.symbols.len; p.symbols << symbol; p.libraries << library }
	p.load(reg, 0x4000 + index * 8)
	if object { p.op(0xf9400000 | u32(reg) << 5 | u32(reg)) }
}
fn (mut p FrameworkProbe) call(library int, symbol string) { p.imported(16, library, symbol, false); p.op(0xd63f0200) }

// Every failed assertion returns a distinct status in 70..254. Branches share
// the ABI epilogue, so errors propagate through run-ios and the package CLI.
fn (mut p FrameworkProbe) require(condition u32) {
	assert p.check < 255
	p.op(0x54000060 | condition) // b.<condition> +12
	p.op(0x52800000 | u32(p.check) << 5)
	p.failures << p.pc
	p.op(0x14000000)
	p.check++
}
fn (mut p FrameworkProbe) equal(value u32) {
	p.imm(15, value); p.op(0xeb0f001f); p.require(0) // cmp x0,x15; b.eq
}
fn (mut p FrameworkProbe) nonzero() { p.op(0xf100001f); p.require(1) }
fn (mut p FrameworkProbe) jump() int { offset := p.pc; p.op(0x14000000); return offset }
fn (mut p FrameworkProbe) branch(at int, destination int) { put(mut p.bytes, at, 0x14000000 | (u32((destination - at) / 4) & 0x3ffffff), 4) }
fn (mut p FrameworkProbe) dictionary(slot int) {
	p.imm(0, 0); p.imm(1, 0)
	p.imported(2, 3, '_kCFTypeDictionaryKeyCallBacks', false)
	p.imported(3, 3, '_kCFTypeDictionaryValueCallBacks', false)
	p.call(3, '_CFDictionaryCreateMutable'); p.nonzero(); p.save(0, slot)
}
fn (mut p FrameworkProbe) set_constant(slot int, key string, value string) {
	p.load(0, slot); p.imported(1, 4, key, true); p.imported(2, 4, value, true)
	p.call(3, '_CFDictionarySetValue')
}
fn (mut p FrameworkProbe) set_string(slot int, key string, value string) {
	p.imm(0, 0); p.text(1, value); p.imm(2, 0x08000100)
	p.call(3, '_CFStringCreateWithCString'); p.nonzero(); p.save(0, 0x5040)
	p.load(0, slot); p.imported(1, 4, key, true); p.load(2, 0x5040)
	p.call(3, '_CFDictionarySetValue'); p.load(0, 0x5040); p.call(3, '_CFRelease')
}
fn (mut p FrameworkProbe) set_data(slot int) {
	p.imm(0, 0); p.address(1, 0x5080); p.imm(2, 1)
	p.call(3, '_CFDataCreate'); p.nonzero(); p.save(0, 0x5040)
	p.load(0, slot); p.imported(1, 4, '_kSecValueData', true); p.load(2, 0x5040)
	p.call(3, '_CFDictionarySetValue'); p.load(0, 0x5040); p.call(3, '_CFRelease')
}
fn (mut p FrameworkProbe) query(slot int, account string) {
	p.dictionary(slot)
	p.set_constant(slot, '_kSecClass', '_kSecClassGenericPassword')
	p.set_string(slot, '_kSecAttrService', 'vinix-package-framework')
	p.set_string(slot, '_kSecAttrAccount', account)
}
fn (mut p FrameworkProbe) result_counter() {
	p.load(0, 0x5020); p.nonzero(); p.call(3, '_CFDataGetLength'); p.equal(1)
	p.load(0, 0x5020); p.call(3, '_CFDataGetBytePtr'); p.nonzero()
	p.op(0x39400000) // ldrb w0,[x0]
	p.save(0, 0x5030)
	p.op(0xf100041f); p.require(2) // counter >= 1
	p.op(0xf100241f); p.require(9) // counter <= 9
	p.load(0, 0x5020); p.call(3, '_CFRelease'); p.imm(0, 0); p.save(0, 0x5020)
}
fn (mut p FrameworkProbe) cstring() {
	p.address(1, 0x5800); p.imm(2, 1024); p.imm(3, 0x08000100)
	p.call(3, '_CFStringGetCString'); p.nonzero()
}
fn (mut p FrameworkProbe) compare_environment(name string, suffix string) {
	p.text(0, name); p.call(1, '_getenv'); p.nonzero()
	p.save(0, 0x5040); p.address(0, 0x5c00); p.load(1, 0x5040); p.call(1, '_strcpy')
	if suffix != '' { p.address(0, 0x5c00); p.text(1, suffix); p.call(1, '_strcat') }
	p.address(0, 0x5800); p.address(1, 0x5c00); p.call(1, '_strcmp'); p.equal(0)
}
fn (mut p FrameworkProbe) write_file(suffix string) {
	p.address(0, 0x5800); p.text(1, suffix); p.call(1, '_strcat')
	p.address(0, 0x5800); p.text(1, 'w'); p.call(1, '_fopen'); p.nonzero(); p.save(0, 0x5048)
	p.text(0, 'Mach-O Foundation wrote this\n'); p.imm(1, 1); p.imm(2, 29); p.load(3, 0x5048)
	p.call(1, '_fwrite'); p.equal(29); p.load(0, 0x5048); p.call(1, '_fclose'); p.equal(0)
}

// The persistent credential is a one-byte launch counter. A second credential
// exercises duplicate insertion, deletion and an unsupported access group.
// The guest checks counter progression across users, upgrade, rollback and
// cached reinstall; a fresh empty keychain cannot masquerade as persistence.
pub fn framework_image(status u8) []u8 {
	mut p := FrameworkProbe{}
	p.op(0xa9bf7bfd) // stp x29,x30,[sp,#-16]!
	p.call(5, '_objc_autoreleasePoolPush'); p.save(0, 0x5000)
	p.call(2, '_NSHomeDirectory'); p.cstring(); p.compare_environment('HOME', '')
	p.call(2, '_NSTemporaryDirectory'); p.cstring(); p.compare_environment('TMPDIR', '/')
	p.write_file('framework.tmp')
	p.imm(0, 9); p.imm(1, 1); p.imm(2, 1); p.call(2, '_NSSearchPathForDirectoriesInDomains')
	p.nonzero(); p.save(0, 0x5008); p.call(3, '_CFArrayGetCount'); p.equal(1)
	p.load(0, 0x5008); p.imm(1, 0); p.call(3, '_CFArrayGetValueAtIndex')
	p.cstring(); p.compare_environment('VINIX_IOS_DOCUMENTS', ''); p.write_file('/framework.txt')
	p.query(0x5010, 'persist')
	p.query(0x5060, 'persist') // mutation queries carry no return-data flag
	p.load(0, 0x5010); p.imported(1, 4, '_kSecReturnData', true); p.imported(2, 3, '_kCFBooleanTrue', true)
	p.call(3, '_CFDictionarySetValue')
	p.load(0, 0x5010); p.address(1, 0x5020); p.call(4, '_SecItemCopyMatching')
	p.op(0x7100001f) // cmp w0,#0
	fresh := p.pc; p.op(0x54000001) // b.ne, patched below
	p.result_counter(); p.imm(0, 0); p.save(0, 0x5038)
	join := p.jump()
	put(mut p.bytes, fresh, 0x54000001 | u32((p.pc - fresh) / 4) << 5, 4)
	// Compare the signed 32-bit OSStatus, not its unspecified upper bits.
	p.imm(15, u32(0xffff9d2c)); p.op(0x6b0f001f); p.require(0) // errSecItemNotFound = -25300
	p.load(0, 0x5020); p.equal(0); p.imm(0, 0); p.save(0, 0x5030)
	p.imm(0, 1); p.save(0, 0x5038)
	p.branch(join, p.pc)
	p.load(0, 0x5030); p.op(0x91000400); p.address(17, 0x5080); p.op(0x39000220) // counter++ ; strb
	p.dictionary(0x5018); p.set_data(0x5018)
	p.load(0, 0x5038); p.op(0xf100001f)
	update := p.pc; p.op(0x54000000) // b.eq, patched below
	p.set_constant(0x5018, '_kSecClass', '_kSecClassGenericPassword')
	p.set_string(0x5018, '_kSecAttrService', 'vinix-package-framework')
	p.set_string(0x5018, '_kSecAttrAccount', 'persist')
	p.set_constant(0x5018, '_kSecAttrAccessible', '_kSecAttrAccessibleAfterFirstUnlock')
	p.load(0, 0x5018); p.imm(1, 0); p.call(4, '_SecItemAdd'); p.equal(0)
	updated := p.jump()
	put(mut p.bytes, update, 0x54000000 | u32((p.pc - update) / 4) << 5, 4)
	p.load(0, 0x5060); p.load(1, 0x5018); p.call(4, '_SecItemUpdate'); p.equal(0)
	p.branch(updated, p.pc)
	p.load(0, 0x5010); p.address(1, 0x5020); p.call(4, '_SecItemCopyMatching'); p.equal(0)
	p.result_counter()
	p.load(0, 0x5030); p.address(17, 0x5080); p.op(0x39400221); p.op(0xeb01001f); p.require(0)
	p.query(0x5050, 'scratch'); p.set_data(0x5050)
	p.set_constant(0x5050, '_kSecAttrAccessible', '_kSecAttrAccessibleAfterFirstUnlock')
	p.load(0, 0x5050); p.imm(1, 0); p.call(4, '_SecItemAdd'); p.equal(0)
	p.load(0, 0x5050); p.imm(1, 0); p.call(4, '_SecItemAdd')
	p.imm(15, 0xffff9d2d); p.op(0x6b0f001f); p.require(0) // errSecDuplicateItem = -25299
	p.query(0x5058, 'scratch')
	p.load(0, 0x5058); p.call(4, '_SecItemDelete'); p.equal(0)
	p.load(0, 0x5058); p.address(1, 0x5020); p.call(4, '_SecItemCopyMatching')
	p.imm(15, 0xffff9d2c); p.op(0x6b0f001f); p.require(0); p.load(0, 0x5020); p.equal(0)
	p.set_string(0x5058, '_kSecAttrAccessGroup', 'ungranted.group')
	p.load(0, 0x5058); p.address(1, 0x5020); p.call(4, '_SecItemCopyMatching')
	p.imm(15, 0xffff7b1e); p.op(0x6b0f001f); p.require(0) // errSecMissingEntitlement = -34018
	p.load(0, 0x5020); p.equal(0)
	p.imm(0, u32(status))
	cleanup := p.pc
	p.save(0, 0x5070)
	for slot in [0x5010, 0x5018, 0x5050, 0x5058, 0x5060, 0x5020] { p.load(0, slot); p.call(3, '_CFRelease') }
	p.load(0, 0x5000); p.call(5, '_objc_autoreleasePoolPop')
	p.load(0, 0x5070); p.imm(15, u32(status)); p.op(0xeb0f001f)
	failed := p.pc; p.op(0x54000001) // b.ne to the epilogue; no success marker
	p.text(0, 'PACKAGE APPLE FRAMEWORK counter=0 paths files keychain PASS')
	p.load(1, 0x5030); p.op(0x9100c021); p.op(0x39008001) // add x1,#'0'; strb w1,[x0,#32]
	p.call(1, '_puts')
	end := p.pc
	put(mut p.bytes, failed, 0x54000001 | u32((end - failed) / 4) << 5, 4)
	p.load(0, 0x5070)
	p.op(0xa8c17bfd); p.op(0xd65f03c0)
	for at in p.failures { p.branch(at, cleanup) }
	assert p.pc < 0x4000 && p.symbols.len < 128
	framework_header(mut p)
	return p.bytes
}

fn framework_header(mut p FrameworkProbe) {
	put(mut p.bytes, 0, 0xfeedfacf, 4); put(mut p.bytes, 4, 0x100000c, 4)
	put(mut p.bytes, 12, 2, 4); put(mut p.bytes, 16, 11, 4); put(mut p.bytes, 24, 0x200000, 4)
	mut cursor := 32
	for i, name in ['__PAGEZERO', '__TEXT', '__DATA'] {
		put(mut p.bytes, cursor, 0x19, 4); put(mut p.bytes, cursor + 4, 72, 4)
		for j, byte in name { p.bytes[cursor + 8 + j] = byte }
		put(mut p.bytes, cursor + 32, if i == 0 { u64(0x100000000) } else { u64(0x4000) }, 8)
		if i > 0 {
			put(mut p.bytes, cursor + 24, 0x100000000 + u64(i - 1) * 0x4000, 8)
			put(mut p.bytes, cursor + 40, u64(i - 1) * 0x4000, 8); put(mut p.bytes, cursor + 48, 0x4000, 8)
			put(mut p.bytes, cursor + 56, if i == 1 { u64(5) } else { u64(3) }, 4)
			put(mut p.bytes, cursor + 60, if i == 1 { u64(5) } else { u64(3) }, 4)
		}
		cursor += 72
	}
	put(mut p.bytes, cursor, 0x80000028, 4); put(mut p.bytes, cursor + 4, 24, 4); put(mut p.bytes, cursor + 8, 0x800, 8); cursor += 24
	put(mut p.bytes, cursor, 0x32, 4); put(mut p.bytes, cursor + 4, 24, 4); put(mut p.bytes, cursor + 8, 2, 4)
	put(mut p.bytes, cursor + 12, 0xf0000, 4); cursor += 24
	for library in ['/usr/lib/libSystem.B.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation',
		'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '/System/Library/Frameworks/Security.framework/Security', '/usr/lib/libobjc.A.dylib'] {
		size := (24 + library.len + 1 + 7) & ~7
		put(mut p.bytes, cursor, 0xc, 4); put(mut p.bytes, cursor + 4, u64(size), 4); put(mut p.bytes, cursor + 8, 24, 4)
		for j, byte in library { p.bytes[cursor + 24 + j] = byte }; cursor += size
	}
	put(mut p.bytes, cursor, 0x80000034, 4); put(mut p.bytes, cursor + 4, 16, 4); put(mut p.bytes, cursor + 8, 0x7000, 4)
	put(mut p.bytes, 20, u64(cursor + 16 - 32), 4); assert cursor + 16 <= 0x800
	put(mut p.bytes, 0x7004, 28, 4); put(mut p.bytes, 0x7008, 68, 4)
	names := 68 + p.symbols.len * 4
	put(mut p.bytes, 0x700c, u64(names), 4); put(mut p.bytes, 0x7010, u64(p.symbols.len), 4); put(mut p.bytes, 0x7014, 1, 4)
	put(mut p.bytes, 0x701c, 3, 4); put(mut p.bytes, 0x7028, 16, 4)
	put(mut p.bytes, 0x702c, 24, 4); put(mut p.bytes, 0x7030, 0x4000, 2); put(mut p.bytes, 0x7032, 6, 2)
	put(mut p.bytes, 0x7034, 0x4000, 8); put(mut p.bytes, 0x7040, 1, 2)
	mut offset := 0
	for i, symbol in p.symbols {
		put(mut p.bytes, 0x4000 + i * 8, (u64(1) << 63) | u64(i) | if i + 1 < p.symbols.len { u64(2) << 51 } else { u64(0) }, 8)
		put(mut p.bytes, 0x7044 + i * 4, u64(p.libraries[i]) | u64(offset) << 9, 4)
		for j, byte in symbol { p.bytes[0x7000 + names + offset + j] = byte }; offset += symbol.len + 1
	}
	put(mut p.bytes, cursor + 12, u64(names + offset), 4)
}
