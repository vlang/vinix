module samplefixture
import x86.cpu.local as cpulocal

@[export: 'policy_sample']
pub fn fixture_sample(local voidptr, directstore_available bool, directstore_ecx u32) {
	mut cpu_local := unsafe { &cpulocal.Local(local) }
	sample(mut cpu_local, directstore_available, directstore_ecx)
}
