module fs

import aarch64.cpu
import lib
import numa

// The Features line of /proc/cpuinfo: what AT_HWCAP tells a program the CPU
// offers it.
fn cpu_feature_names() string {
	return cpu.user_feature_names()
}

fn cpuinfo_text() string {
	features := cpu_feature_names()
	count := numa.cpu_count()
	mut text := lib.new_text(count * (180 + features.len))
	for i := 0; i < count; i++ {
		text.add('processor\t: ')
		text.add_unsigned(u64(i))
		text.add('\nBogoMIPS\t: 100.00\nFeatures\t: ')
		text.add(features)
		text.add('\nCPU implementer\t: 0x61\nCPU architecture: 8\nCPU variant\t: 0x0\nCPU part\t: 0x000\nCPU revision\t: 0\n\n')
	}
	unsafe { features.free() }
	return text.str()
}
