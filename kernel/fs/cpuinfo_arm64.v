module fs

import aarch64.cpu

// The Features line of /proc/cpuinfo: what AT_HWCAP tells a program the CPU
// offers it.
fn cpu_feature_names() string {
	return cpu.user_feature_names()
}
