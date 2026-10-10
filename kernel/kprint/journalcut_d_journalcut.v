module kprint

// Qualification output must reach serial even in a production-style kernel.
// Stages are single digits; formatting and allocation are unnecessary.
pub fn journal_cut(stage int) {
	for byte in 'JOURNAL CUT stage=' { policy_serial(byte, true) }
	policy_serial(u8(stage) + `0`, true)
	policy_serial(`\n`, true)
}

pub fn journal_sites(buffer voidptr, length u64) {
	mut start := true
	for i := u64(0); i < length; i++ {
		if start { for byte in 'JOURNAL SITE ' { policy_serial(byte, true) } }
		byte := unsafe { (&u8(buffer))[i] }
		policy_serial(byte, true)
		start = byte == `\n`
	}
}
