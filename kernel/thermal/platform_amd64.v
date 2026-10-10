// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the architecture itself brings to thermal management: on x86-64, the
// temperature sensors and energy counters inside the processor. Intel's are
// in coretemp_amd64.v, AMD's in k10temp_amd64.v, and the energy counters of
// both in rapl_amd64.v. Each is started only where CPUID or the model says it
// is there and the first read of it then succeeds, so that a virtual machine
// that passes a CPUID bit through without the register behind it gets no
// zone rather than a broken one.
//
// vinix.thermal_sensors=0 on the command line leaves all three alone.
//
// /sys/class/thermal/x86_probe says what was looked for and what was found,
// for the machine on which nothing shows up. Its first lines read, each time
// the file is read, a register every CPU has and two that none has, through
// msr.read_safe(): the proof that asking after a register that is not there
// costs an answer and not the machine. Two, because QEMU's emulated CPU
// answers 0 for an index it has never heard of where a real one faults; a
// reserved index in the x2APIC's range faults on both. The lines after them
// read the first of those registers on each CPU in turn, which is the proof
// that a read lands on the CPU it was asked of: only the boot CPU has bit 8.
@[has_globals]
module thermal

import devcore
import fs
import katomic
import lib
import x86.cpu
import x86.msr

// IA32_APIC_BASE, which every CPU this kernel runs on has.
const msr_apic_base = u32(0x1b)

// An index no vendor has assigned.
const msr_unassigned = u32(0x12345678)

// 0x800 to 0x8ff are the x2APIC's registers, and 0x804 is none of them: #GP
// in x2APIC mode because it is reserved, and outside it because the whole
// range is.
const msr_x2apic_reserved = u32(0x804)

// CPUs x86_probe reads a register on.
const probe_cpus = 8

__global (
	thermal_x86          X86Identity
	thermal_x86_topology X86Topology
	// The processor's name, CPUID leaves 0x80000002 to 0x80000004.
	thermal_x86_brand        [49]u8
	thermal_x86_brand_length int
	// Every CPU is in one package, so a package's register may be read on
	// whichever CPU the reader happens to be on.
	thermal_x86_one_package bool
	// Why each driver did or did not start, for x86_probe.
	thermal_coretemp_status string
	thermal_k10temp_status  string
	thermal_rapl_status     string
)

// The processor's name: a view of the global, good for the machine's life.
fn x86_brand() string {
	return unsafe { tos(&thermal_x86_brand[0], thermal_x86_brand_length) }
}

fn x86_topology_read() X86Topology {
	// Leaf 0x1f where there is one: it names the levels leaf 0xb leaves out.
	for leaf in [u32(0x1f), u32(0xb)]! {
		mut found := X86Topology{}
		for level := u32(0); level < 8; level++ {
			ok, eax, ebx, ecx, _ := cpu.cpuid(leaf, level)
			if !ok || ebx & 0xffff == 0 {
				break
			}
			shift := eax & 0x1f
			if (ecx >> 8) & 0xff == 1 {
				found.smt_shift = shift
				found.known = true
			}
			// The last level's shift leaves the package's number.
			if shift > found.package_shift {
				found.package_shift = shift
			}
		}
		if found.known {
			return found
		}
	}
	return X86Topology{}
}

fn x86_identify() {
	ok0, _, ebx, ecx, edx := cpu.cpuid(0, 0)
	vendor := if ok0 { x86_vendor_of(ebx, ecx, edx) } else { X86Vendor.other }
	ok1, signature, _, _, _ := cpu.cpuid(1, 0)
	thermal_x86 = x86_identity_of(vendor, if ok1 { signature } else { u32(0) })

	mut length := 0
	for leaf in [u32(0x80000002), u32(0x80000003), u32(0x80000004)]! {
		ok, a, b, c, d := cpu.cpuid(leaf, 0)
		if !ok {
			break
		}
		for register in [a, b, c, d]! {
			for byte in 0 .. 4 {
				thermal_x86_brand[length] = u8(register >> (u32(byte) * 8))
				length++
			}
		}
	}
	thermal_x86_brand[length] = 0
	mut end := 0
	for end < length && thermal_x86_brand[end] != 0 {
		end++
	}
	thermal_x86_brand_length = end

	thermal_x86_topology = x86_topology_read()
	mut one := true
	first := x86_package_of(cpu_locals[0].lapic_id, thermal_x86_topology)
	for i in 1 .. cpu_locals.len {
		if x86_package_of(cpu_locals[i].lapic_id, thermal_x86_topology) != first {
			one = false
		}
	}
	thermal_x86_one_package = one
}

// A register of the boot CPU's package: the package's temperature, its
// energy counters. Read where the caller is when that is the same package.
fn read_package_msr(index u32) ?u64 {
	if thermal_x86_one_package {
		value := msr.read_safe(index) or { return none }
		return value
	}
	value := read_msr_on(0, index) or { return none }
	return value
}

fn platform_start() {
	x86_identify()
	cross_cpu_start()
	if devcore.boot_flag('vinix.thermal_sensors=', true) {
		coretemp_start()
		k10temp_start()
		rapl_start()
	} else {
		thermal_coretemp_status = 'switched off on the command line'
		thermal_k10temp_status = 'switched off on the command line'
		thermal_rapl_status = 'switched off on the command line'
	}
	fs.sysfs_attribute('class/thermal/x86_probe', 0o444, show_x86_probe, unsafe { nil },
		unsafe { nil })
}

// Whether the polling thread has anything of the platform's to look after:
// the energy counters, which wrap unless they are read.
fn platform_polls() bool {
	return thermal_rapl_count != 0
}

fn platform_poll() {
	rapl_poll()
}

fn add_hex(mut text lib.Text, value u64, width int) {
	text.add('0x')
	text.add_radix(value, 16, width)
}

fn show_msr(mut text lib.Text, index u32) {
	text.add('rdmsr ')
	add_hex(mut text, u64(index), 8)
	text.add(': ')
	if value := msr.read_safe(index) {
		add_hex(mut text, value, 16)
	} else {
		text.add('fault')
	}
	text.add_byte(`\n`)
}

fn show_msr_on(mut text lib.Text, cpu_number u64, index u32) {
	text.add('rdmsr ')
	add_hex(mut text, u64(index), 8)
	text.add(' on cpu ')
	text.add_unsigned(cpu_number)
	text.add(': ')
	mut value := u64(0)
	outcome := cross_read(cpu_number, index, unsafe { &value })
	if outcome == .found {
		add_hex(mut text, value, 16)
	} else if outcome == .absent {
		text.add('fault')
	} else {
		text.add('no answer in time')
	}
	text.add_byte(`\n`)
}

fn show_status(mut text lib.Text, name string, status string) {
	text.add(name)
	text.add(': ')
	text.add(status)
	text.add_byte(`\n`)
}

fn show_x86_probe(_ voidptr, mut text lib.Text) {
	show_msr(mut text, msr_apic_base)
	show_msr(mut text, msr_unassigned)
	show_msr(mut text, msr_x2apic_reserved)
	$if thermal_selftest ? {
		// A write to a register that is not there: only where it is asked for.
		text.add('wrmsr ')
		add_hex(mut text, u64(msr_x2apic_reserved), 8)
		text.add(if msr.write_safe(msr_x2apic_reserved, 0) { ': written\n' } else { ': fault\n' })
	}
	count := if cpu_locals.len < probe_cpus { cpu_locals.len } else { probe_cpus }
	for i in 0 .. count {
		show_msr_on(mut text, u64(i), msr_apic_base)
	}
	if count > 1 {
		show_msr_on(mut text, u64(count - 1), msr_x2apic_reserved)
	}
	text.add('cross-cpu reads given up: ')
	text.add_unsigned(katomic.load(&thermal_cross_timeouts))
	text.add_byte(`\n`)

	text.add('cpu: ')
	text.add(match thermal_x86.vendor {
		.intel { 'intel' }
		.amd { 'amd' }
		.hygon { 'hygon' }
		.other { 'other' }
	})
	text.add(' family ')
	add_hex(mut text, u64(thermal_x86.family), 0)
	text.add(' model ')
	add_hex(mut text, u64(thermal_x86.model), 0)
	text.add(' stepping ')
	add_hex(mut text, u64(thermal_x86.stepping), 0)
	text.add(if thermal_x86_one_package { ', one package' } else { ', several packages' })
	text.add(', "')
	text.add(x86_brand())
	text.add('"\n')
	_, thermal_leaf, _, _, _ := cpu.cpuid(6, 0)
	text.add('cpuid 6 eax: ')
	add_hex(mut text, u64(thermal_leaf), 8)
	text.add_byte(`\n`)
	show_status(mut text, 'coretemp', thermal_coretemp_status)
	show_status(mut text, 'k10temp', thermal_k10temp_status)
	show_status(mut text, 'rapl', thermal_rapl_status)
	if power := package_power_mw() {
		text.add('rapl: package power ')
		text.add_unsigned(power)
		text.add(' mW\n')
	}
}
