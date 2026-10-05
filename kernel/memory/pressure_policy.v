module memory

// The reclaim target scales with usable RAM but stays small enough that a
// large workstation does not keep gigabytes unnecessarily empty. This is a
// soft reserve: existing PMM callers can use it, and do not fail at a watermark.
pub struct PressureWatermarks {
pub:
	critical u64
	low      u64
	high     u64
}

pub fn pressure_watermarks(total u64) PressureWatermarks {
	mut low := total / 32
	if low < 16 * 1024 * 1024 { low = 16 * 1024 * 1024 }
	if low > 128 * 1024 * 1024 { low = 128 * 1024 * 1024 }
	// Tiny test/embedded machines still retain a usable fraction of their RAM.
	if low > total / 8 { low = total / 8 }
	return PressureWatermarks{critical: low / 4, low: low, high: low + low / 2}
}

// Pressure rises immediately at the low/critical thresholds; recovery needs
// a larger reserve. This prevents notification/reclaim oscillation at a single
// boundary. 0 = normal, 1 = warning, 2 = critical.
pub fn pressure_next_level(previous int, free u64, marks PressureWatermarks) int {
	if free <= marks.critical { return 2 }
	if previous == 2 && free < marks.critical * 2 { return 2 }
	if free <= marks.low || (previous != 0 && free < marks.high) { return 1 }
	return 0
}
