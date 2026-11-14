@[has_globals]
module timer

__global fake_ns = u64(0)

pub fn get_ns() u64 {
	fake_ns += 1_000_000
	return fake_ns
}
