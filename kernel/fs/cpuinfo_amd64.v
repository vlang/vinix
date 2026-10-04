module fs

import lib
import numa
import x86.cpu
import x86.hpet as hpet_clock

__global (
	// The TSC's rate in MHz, for a CPU that does not report its frequency;
	// measured once, when /proc/cpuinfo is first read.
	cpuinfo_measured_mhz = u64(0)
)

// The TSC's rate against the kernel's nanosecond clock, over 10 ms.
fn measured_mhz() u64 {
	if cpuinfo_measured_mhz != 0 {
		return cpuinfo_measured_mhz
	}
	start_ns := hpet_clock.nanoseconds()
	start_tsc := cpu.rdtsc()
	for hpet_clock.nanoseconds() - start_ns < 10000000 {}
	elapsed := hpet_clock.nanoseconds() - start_ns
	cycles := cpu.rdtsc() - start_tsc
	cpuinfo_measured_mhz = cycles * 1000 / elapsed
	return cpuinfo_measured_mhz
}

// /proc/cpuinfo as Linux lays it out on x86-64, one block per CPU.
fn cpuinfo_text() string {
	identity := cpu.identity()
	flags := cpu.user_feature_names()
	mhz := if identity.base_mhz != 0 { u64(identity.base_mhz) } else { measured_mhz() }
	count := numa.cpu_count()
	mut text := lib.new_text(count * (640 + flags.len))
	for i := 0; i < count; i++ {
		apic_id := if i < cpu_locals.len { u64(cpu_locals[i].lapic_id) } else { u64(i) }
		text.add('processor\t: ')
		text.add_unsigned(u64(i))
		text.add('\nvendor_id\t: ')
		text.add(identity.vendor)
		text.add('\ncpu family\t: ')
		text.add_unsigned(identity.family)
		text.add('\nmodel\t\t: ')
		text.add_unsigned(identity.model)
		text.add('\nmodel name\t: ')
		text.add(identity.model_name)
		text.add('\nstepping\t: ')
		text.add_unsigned(identity.stepping)
		text.add('\ncpu MHz\t\t: ')
		text.add_unsigned(mhz)
		text.add('.000\nphysical id\t: 0\nsiblings\t: ')
		text.add_unsigned(u64(count))
		text.add('\ncore id\t\t: ')
		text.add_unsigned(u64(i))
		text.add('\ncpu cores\t: ')
		text.add_unsigned(u64(count))
		text.add('\napicid\t\t: ')
		text.add_unsigned(apic_id)
		text.add('\ninitial apicid\t: ')
		text.add_unsigned(apic_id)
		text.add('\nfpu\t\t: yes\nfpu_exception\t: yes\ncpuid level\t: ')
		text.add_unsigned(identity.cpuid_level)
		text.add('\nwp\t\t: yes\nflags\t\t: ')
		text.add(flags)
		text.add('\nbugs\t\t:\nbogomips\t: ')
		text.add_unsigned(mhz * 2)
		text.add('.00\nclflush size\t: ')
		text.add_unsigned(identity.clflush_size)
		text.add('\ncache_alignment\t: ')
		text.add_unsigned(identity.clflush_size)
		text.add('\naddress sizes\t: ')
		text.add_unsigned(identity.phys_bits)
		text.add(' bits physical, ')
		text.add_unsigned(identity.virt_bits)
		text.add(' bits virtual\npower management:\n\n')
	}
	unsafe {
		flags.free()
		identity.vendor.free()
		identity.model_name.free()
	}
	return text.str()
}
