@[has_globals]
module linuxkpi
import policytransport
pub type Local = policytransport.Local
__global cpu_locals []&Local

@[export: 'policy_configure']
pub fn fixture_configure(count i64, direct u32, shstk bool, la57 bool) {
	boot_directstore_bits = 0; boot_directstore_count = 0; boot_directstore_ready = 0
	boot_infrastructure_bits = 0; boot_infrastructure_count = 0; boot_infrastructure_ready = 0
	policytransport.configure(unsafe { &cpu_locals }, count, direct, shstk, la57)
	policytransport.register_slots(&boot_directstore_bits, &boot_directstore_count, &boot_directstore_ready,
		&boot_infrastructure_bits, &boot_infrastructure_count, &boot_infrastructure_ready)
}
@[export: 'policy_initialize']
pub fn fixture_initialize(kind u32) {
	if kind == 0 { initialise_cpu_features() } else { initialise_cpu_infrastructure_features() }
}
@[export: 'policy_state']
pub fn fixture_state(field int) u32 {
	return match field {
		0 { boot_directstore_bits } 1 { boot_directstore_count } 2 { boot_directstore_ready }
		3 { boot_infrastructure_bits } 4 { boot_infrastructure_count } else { boot_infrastructure_ready }
	}
}
@[export: 'policy_seed_ready']
pub fn fixture_seed_ready(value u32) {
	boot_directstore_ready = value
	boot_infrastructure_ready = value
}
