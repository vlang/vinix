// SPDX-License-Identifier: GPL-2.0-or-later
module storagehost

fn stubs() map[string]string {
	return {
		'proc/proc.v':               'module proc\npub fn account_disk_transfer(_ u64, _ bool) {}\npub fn account_disk_io(_ u64, _ u64, _ bool) {}\n'
		'pci/pci.v':                 'module pci\npub struct PCIBar {}\n'
		'stat/stat.v':               'module stat\npub struct Stat {\npub mut:\n size i64\n blksize i64\n blocks i64\n rdev u64\n}\n'
		'event/eventstruct/event.v': 'module eventstruct\npub struct Event {}\n'
		'klock/klock.v':             'module klock\npub struct Lock {}\npub fn (mut lock Lock) acquire() {}\npub fn (mut lock Lock) release() {}\npub fn spin_hint() {}\n'
		'katomic/katomic.v':         'module katomic\npub fn sync() {}\npub fn load[T](value &T) T { return unsafe { *value } }\npub fn store[T](mut value &T, next T) { unsafe { *value = next } }\npub fn inc[T](mut value &T) { unsafe { *value += 1 } }\n'
		'acpisync/acpisync.v':       'module acpisync\npub fn thread_id() u64 { return 1 }\npub fn sleep(_ u64) {}\n'
		'sched/sched.v':             'module sched\npub fn reschedule() {}\n'
		'devcore/devcore.v':         'module devcore\npub struct Device {}\npub fn report_timeout(mut _ Device, _ string) {}\npub fn sleep_ms(_ u64) {}\n'
		'dma/dma.v':                 'module dma\nimport devcore\npub struct Buffer {\npub:\n bus u64\n}\npub fn alloc_buffer(mut _ devcore.Device, _ u64) ?Buffer { return none }\n'
		'lib/lib.v':                 'module lib\npub fn div_roundup[T](a T, b T) T { return (a + b - 1) / b }\n'
		'errno/errno.v':             'module errno\npub const eio = 5\npub const enomem = 12\npub const einval = 22\npub const enodev = 19\npub const erofs = 30\npub const eopnotsupp = 95\npub fn set(_ int) {}\n'
		'memory/memory.v':           '@[has_globals]\nmodule memory\n__global live_pages = u64(0)\npub fn pmm_alloc_nozero_fallible(pages u64) voidptr {\n live_pages += pages\n return unsafe { malloc(int(pages * 4096)) }\n}\npub fn pmm_free(pointer voidptr, pages u64) {\n live_pages -= pages\n unsafe { free(pointer) }\n}\npub fn allocated_pages() u64 { return live_pages }\n'
		'bitmap/bitmap.v':           'module bitmap\npub struct GenericBitmap {\nmut:\n slots []bool\n}\npub fn (mut b GenericBitmap) initialise(count u64) { b.slots = []bool{len: int(count)} }\npub fn (b GenericBitmap) alloc() ?u64 {\n for i, busy in b.slots {\n  if !busy { unsafe { b.slots[i] = true }; return u64(i) }\n }\n return none\n}\npub fn (b GenericBitmap) free_entry(index u64) { unsafe { b.slots[index] = false } }\n'
		'x86/hpet/hpet.v':           '@[has_globals]\nmodule hpet\n__global tick_hook = fn () {}\n__global ticks = u64(0)\npub fn nanoseconds() u64 {\n ticks += 1_000_000_000\n tick_hook()\n return ticks\n}\npub fn set_hook(hook fn ()) { tick_hook = hook; ticks = 0 }\n'
		'aarch64/cpu/cpu.v':         'module cpu\npub fn dmb_ish() {}\n'
		'aarch64/uart/uart.v':       'module uart\npub fn puts(_ &char) {}\n'
		'aarch64/timer/timer.v':     'module timer\nimport x86.hpet as hpet_clock\npub fn get_ns() u64 { return hpet_clock.nanoseconds() }\n'
	}
}
