// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Intel's digital thermal sensor, read: what the registers mean. Translated
// from Linux's drivers/hwmon/coretemp.c, and for the package zone from
// drivers/thermal/intel/x86_pkg_temp_thermal.c and intel_tcc.c.
//
// The sensor does not report a temperature. It reports how many degrees the
// core is below the temperature at which the processor throttles itself,
// TjMax, and TjMax is a property of the model: recent processors say it in
// IA32_TEMPERATURE_TARGET, and for the older ones coretemp.c carries the
// tables and the guesswork that are repeated here.
//
// Nothing in this file may import the kernel: tests/thermal runs it on the
// machine the kernel is built on.
module thermal

pub const msr_ia32_platform_id = u32(0x17)
pub const msr_ia32_ext_config = u32(0xee)
pub const msr_ia32_therm_status = u32(0x19c)
pub const msr_ia32_temperature_target = u32(0x1a2)
pub const msr_ia32_package_therm_status = u32(0x1b1)

// CPUID.6:EAX: a digital thermal sensor in each core, and one for the package.
pub const cpuid6_dtherm = u32(1) << 0
pub const cpuid6_pts = u32(1) << 6

// IA32_THERM_STATUS and IA32_PACKAGE_THERM_STATUS.
pub struct DtsStatus {
pub mut:
	// Bit 31: the readout is one.
	valid bool
	// Bits 22:16: degrees below TjMax.
	readout u32
	// Bit 0: the processor is throttling itself now; bit 1: it has, since
	// the bit was last cleared.
	prochot     bool
	prochot_log bool
	// Bit 4: at the temperature where it will switch itself off; bit 5: it
	// has been, which is coretemp's tempN_crit_alarm.
	critical     bool
	critical_log bool
}

pub fn dts_decode(status u64) DtsStatus {
	return DtsStatus{
		valid:        status & (u64(1) << 31) != 0
		readout:      u32((status >> 16) & 0x7f)
		prochot:      status & (u64(1) << 0) != 0
		prochot_log:  status & (u64(1) << 1) != 0
		critical:     status & (u64(1) << 4) != 0
		critical_log: status & (u64(1) << 5) != 0
	}
}

// The temperature a core's status register stands for, in millidegrees, as
// coretemp shows it: the valid bit is ignored, because where it is clear the
// readout has been seen to be low or zero and never nonsense.
pub fn coretemp_temperature(status u64, tjmax i64) i64 {
	return tjmax - i64((status >> 16) & 0x7f) * 1000
}

// The temperature thermal management steers by. Here the valid bit counts, as
// it does in intel_tcc_get_temp(): a readout that is not one is a failed
// reading. The sensor cannot report above TjMax, so the critical trip, which
// lies above it, is reached through the status bit that says the processor is
// at its own critical temperature: the reading is then at least `critical`.
pub fn dts_zone_temperature(status u64, tjmax i64, critical i64) ?i64 {
	decoded := dts_decode(status)
	if !decoded.valid {
		return none
	}
	temperature := tjmax - i64(decoded.readout) * 1000
	if decoded.critical && temperature < critical {
		return critical
	}
	return temperature
}

// TjMax as IA32_TEMPERATURE_TARGET gives it, in millidegrees; 0 when the
// register does not say.
pub fn coretemp_target_tjmax(target u64) i64 {
	return i64((target >> 16) & 0xff) * 1000
}

// The temperature the firmware asks the fans to hold, from the still
// undocumented bits 15:8 of the same register: coretemp's tempN_max. Only
// meaningful when TjMax came from the register too.
pub fn coretemp_target_ttarget(target u64) i64 {
	return (i64((target >> 16) & 0xff) - i64((target >> 8) & 0xff)) * 1000
}

// Whether a model has IA32_TEMPERATURE_TARGET at all: cpu_has_tjmax().
pub fn coretemp_has_tjmax(model u32) bool {
	return model > 0xe && model != 0x1c && model != 0x26 && model != 0x27 && model != 0x35
		&& model != 0x36
}

// What adjust_tjmax() looks at.
pub struct TjmaxFacts {
pub mut:
	model    u32
	stepping u32
	// The processor's name, CPUID leaves 0x80000002 to 0x80000004.
	brand string
	// The host bridge at 00:00.0, or zeros.
	bridge_vendor u16
	bridge_device u16
	// IA32_PLATFORM_ID and MSR 0xee, where they could be read.
	platform_ok bool
	platform    u64
	ee_ok       bool
	ee          u64
}

struct TjmaxBridge {
	device u16
	tjmax  i64
}

struct TjmaxName {
	id    string
	tjmax i64
}

struct TjmaxModel {
	model u32
	// A stepping, or any_stepping.
	mask  u32
	tjmax i64
}

const any_stepping = u32(0xff)

// tjmax_pci_table, tjmax_table and tjmax_model_table of coretemp.c.
const tjmax_bridges = [
	TjmaxBridge{0x0708, 110000}, // CE41x0 (Sodaville)
	TjmaxBridge{0x0c72, 102000}, // Atom S1240 (Centerton)
	TjmaxBridge{0x0c73, 95000}, // Atom S1220 (Centerton)
	TjmaxBridge{0x0c75, 95000}, // Atom S1260 (Centerton)
]!

const tjmax_names = [
	TjmaxName{'CPU  230', 100000}, // Model 0x1c, stepping 2
	TjmaxName{'CPU  330', 125000}, // Model 0x1c, stepping 2
]!

const tjmax_models = [
	TjmaxModel{0x1c, 10, 100000}, // D4xx, K4xx, N4xx, D5xx, K5xx, N5xx
	TjmaxModel{0x1c, any_stepping, 90000}, // Z5xx, N2xx, possibly others
	TjmaxModel{0x26, any_stepping, 90000}, // Atom Tunnel Creek (Exx), Lincroft (Z6xx)
	TjmaxModel{0x27, any_stepping, 90000}, // Atom Medfield (Z2460)
	TjmaxModel{0x35, any_stepping, 90000}, // Atom Clover Trail/Cloverview (Z27x0)
	TjmaxModel{0x36, any_stepping, 100000}, // Atom Cedar Trail/Cedarview (N2xxx, D2xxx)
]!

// TjMax for a processor that does not say: adjust_tjmax(), in millidegrees.
// The tables first -- host bridge, then name, then model and stepping -- and
// after them the guess by whether this is a mobile part, which is what the
// two registers in `facts` are for.
pub fn coretemp_adjust_tjmax(facts TjmaxFacts) i64 {
	// 100 C is the default for mobile and other processors alike.
	mut tjmax := i64(100000)
	mut tjmax_ee := i64(85000)
	mut use_ee := true

	if facts.bridge_vendor == 0x8086 {
		for entry in tjmax_bridges {
			if facts.bridge_device == entry.device {
				return entry.tjmax
			}
		}
	}
	for entry in tjmax_names {
		if facts.brand.contains(entry.id) {
			return entry.tjmax
		}
	}
	for entry in tjmax_models {
		if facts.model == entry.model && (entry.mask == any_stepping
			|| facts.stepping == entry.mask) {
			return entry.tjmax
		}
	}

	// Early chips have no register for TjMax.
	if facts.model == 0xf && facts.stepping < 4 {
		use_ee = false
	}
	if facts.model > 0xe && use_ee {
		// For Core 2, bit 28 of IA32_PLATFORM_ID is set on a mobile part.
		low := u32(facts.platform)
		high := u32(facts.platform >> 32)
		if !facts.platform_ok {
			// Assume a desktop part.
			use_ee = false
		} else if facts.model < 0x17 && low & 0x10000000 == 0 {
			// The bit is trusted up to Penryn.
			use_ee = false
		} else {
			// Platform ID, bits 52:50. A mobile Penryn seems to be 7 or 5.
			platform_id := (high >> 18) & 0x7
			if facts.model == 0x17 && (platform_id == 5 || platform_id == 7) {
				tjmax_ee = 90000
				tjmax = 105000
			}
		}
	}
	if use_ee {
		// Bit 30 of MSR 0xee chooses the lower of the two.
		if facts.ee_ok && u32(facts.ee) & 0x40000000 != 0 {
			tjmax = tjmax_ee
		}
	}
	return tjmax
}

pub struct Tjmax {
pub mut:
	millicelsius i64
	// IA32_TEMPERATURE_TARGET said so, rather than a table or a guess.
	from_register bool
}

// get_tjmax(): the register if it could be read and says something, else
// what was forced on the command line, else the tables and the guess.
// `forced` is in millidegrees, 0 for none.
pub fn coretemp_tjmax(target_ok bool, target u64, forced i64, facts TjmaxFacts) Tjmax {
	if target_ok {
		value := coretemp_target_tjmax(target)
		if value != 0 {
			return Tjmax{
				millicelsius:  value
				from_register: true
			}
		}
	}
	if forced != 0 {
		return Tjmax{
			millicelsius: forced
		}
	}
	return Tjmax{
		millicelsius: coretemp_adjust_tjmax(facts)
	}
}

// The package zone's passive trip: where the firmware asks the fans to hold
// the temperature, if it says and that is below TjMax, and otherwise ten
// degrees below TjMax.
pub fn coretemp_passive_trip(tjmax Tjmax, target u64) i64 {
	if tjmax.from_register {
		ttarget := coretemp_target_ttarget(target)
		if ttarget > 0 && ttarget < tjmax.millicelsius {
			return ttarget
		}
	}
	return tjmax.millicelsius - 10000
}

// Its critical trip. Nothing the processor has says otherwise, and the
// sensor cannot read this high: see dts_zone_temperature().
pub fn coretemp_critical_trip(tjmax Tjmax) i64 {
	return tjmax.millicelsius + 5000
}
