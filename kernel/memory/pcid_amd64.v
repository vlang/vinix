// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module memory

import katomic
import klock
import x86.cpu
import dev.serial

const pcid_enable_bit = u64(1) << 17
const cr3_no_flush = u64(1) << 63
const full_tlb_request = ~u64(0)

struct PCIDDescriptor {
	pcid u64
	address u64
}

__global (
	pcid_available = true
	pcid_lock klock.Lock
	pcid_used [64]u64
)

// Called with a plain kernel CR3 before this CPU is published online. All
// CPUs can veto retention before user maps exist. PCID without INVPCID uses
// the ordinary flush-on-switch path too.
pub fn enable_pcid() {
	valid1, _, _, ecx, _ := cpu.cpuid(1, 0)
	valid7, _, ebx, _, _ := cpu.cpuid(7, 0)
	$if no_pcid ? {
		katomic.store(mut &pcid_available, false)
		cpu.write_cr4(cpu.read_cr4() & ~pcid_enable_bit)
		return
	}
	if !valid1 || !valid7 || ecx & (u32(1) << 17) == 0 || ebx & (u32(1) << 10) == 0 {
		katomic.store(mut &pcid_available, false)
		cpu.write_cr4(cpu.read_cr4() & ~pcid_enable_bit)
		return
	}
	if cpu.read_cr3() & 0xfff != 0 { panic('PCID setup requires a plain kernel root') }
	cpu.write_cr4(cpu.read_cr4() | pcid_enable_bit)
	invpcid(2, 0)
}

fn invpcid(kind u64, pcid u16) {
	// A borrowed stack descriptor: V must not box an address-escaping local.
	mut descriptor := PCIDDescriptor{pcid: pcid}
	ptr := unsafe { &descriptor }
	asm volatile amd64 {
		invpcid kind, [ptr]
		; ; r (ptr)
		    r (kind)
		; memory
	}
}

fn take_pcid() u16 {
	if !katomic.load(&pcid_available) { return 0 }
	pcid_lock.acquire()
	defer { pcid_lock.release() }
	for tag := u16(1); tag < 4096; tag++ {
		bit := u64(1) << (tag % 64)
		if pcid_used[tag / 64] & bit == 0 {
			pcid_used[tag / 64] |= bit
			return tag
		}
	}
	return 0
}

pub fn (pagemap &Pagemap) tagged_root() u64 {
	return u64(pagemap.top_level) | u64(pagemap.tlb_tag)
}

pub fn switch_cr3(root u64) {
	retained := root & 0xfff != 0 && katomic.load(&pcid_available)
	cpu.write_cr3(root | if retained { cr3_no_flush } else { u64(0) })
}

// Every CPU can retain a tagged map even after switching away. Context
// invalidation also drops its paging-structure cache before table reclamation.
pub fn invalidate_local_tlb(root u64, address u64, everywhere bool) {
	if cpu.read_cr4() & pcid_enable_bit != 0 {
		if everywhere {
			invpcid(2, 0) // Includes kernel translations under every context.
		} else if root & 0xfff != 0 || address == full_tlb_request {
			invpcid(1, u16(root & 0xfff))
		} else if cpu.read_cr3() == root {
			cpu.invlpg(address)
		}
	} else if everywhere || cpu.read_cr3() == root {
		if address == full_tlb_request { cpu.write_cr3(cpu.read_cr3()) }
		else { cpu.invlpg(address) }
	}
}

pub fn (pagemap &Pagemap) prepare_tlb_teardown() {
	if pagemap.tlb_tag == 0 { return }
	pagemap.invalidate_context()
}

fn (pagemap &Pagemap) invalidate_context() {
	root := pagemap.tagged_root()
	invalidate_local_tlb(root, full_tlb_request, false)
	full_fence()
	if tlb_shootdown != unsafe { nil } { tlb_shootdown(root, full_tlb_request, false) }
}

pub fn (mut pagemap Pagemap) release_tlb_tag() {
	tag := pagemap.tlb_tag
	if tag == 0 { return }
	// Keep ownership until every online CPU acknowledged the stale context.
	pagemap.invalidate_context()
	pcid_lock.acquire()
	pcid_used[tag / 64] &= ~(u64(1) << (tag % 64))
	pcid_lock.release()
	pagemap.tlb_tag = 0
}

pub fn flush_tlb_everywhere() {
	invalidate_local_tlb(0, full_tlb_request, true)
	full_fence()
	if tlb_shootdown != unsafe { nil } { tlb_shootdown(0, full_tlb_request, true) }
}

fn pcid_selftest() {
	if !katomic.load(&pcid_available) {
		tlb_test_report('TLB: PCID unavailable; conservative switching PASS')
		return
	}
	for tag := u16(1); tag < 4096; tag++ {
		if take_pcid() != tag { panic('TLB self-test: PCID ownership') }
	}
	if take_pcid() != 0 || pcid_used[0] & 1 != 0 { panic('TLB self-test: PCID exhaustion') }
	// The mut receiver would promote a local Pagemap onto the heap. This
	// probe is borrowed only for synchronous invalidations during the test.
	mut probe := unsafe { &Pagemap(C.__builtin_alloca(sizeof(Pagemap))) }
	unsafe { *probe = Pagemap{tlb_tag: 127} }
	probe.release_tlb_tag()
	if take_pcid() != 127 || take_pcid() != 0 { panic('TLB self-test: PCID reuse') }
	for tag := u16(1); tag < 4096; tag++ {
		probe.tlb_tag = tag
		probe.release_tlb_tag()
	}
	for _ in 0 .. 2000 {
		probe.tlb_tag = take_pcid()
		if probe.tlb_tag != 1 { panic('TLB self-test: repeated PCID reuse') }
		probe.release_tlb_tag()
	}
	tlb_test_report('TLB: PCID pool exhaustion and reuse PASS')
}

fn tlb_test_report(line string) {
	println(line)
	// Production x86 kprint omits COM1; qualification still needs a verdict.
	$if prod {
		for i in 0 .. line.len { serial.out(line[i]) }
		serial.out(`\n`)
	}
}
