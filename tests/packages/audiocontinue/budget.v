// SPDX-License-Identifier: GPL-2.0-or-later
module audiocontinue

import json2

// These are explicit planning assumptions, not measurements or upper bounds
// established by this pure arithmetic check. current_* must include every
// retained root and repeated hardlink pathname before this proposed phase.
pub struct Projection2 {
pub:
	current_allocated u64
	current_apparent u64
	preparation_reserve u64
	scenario_count int
	boot_image_bytes u64
	firmware_vars_bytes u64
	rootfs_archive_bytes_per_scenario u64
	wave_bytes_per_scenario u64
	logs_bytes_per_scenario u64
	receipt_reserve u64
	cap u64
}

fn budget2_add(a u64, b u64) !u64 {
	if b > ~u64(0) - a { return error('audio v2 budget addition overflow') }
	return a + b
}

fn budget2_mul(a u64, b u64) !u64 {
	if b != 0 && a > ~u64(0) / b { return error('audio v2 budget multiplication overflow') }
	return a * b
}

// The 16MiB global floor alone is insufficient for this donor: the legacy
// map is approximately15MiB. Preserve all known after inventories twice over,
// a maximum32MiB preparation JSON, and8MiB of final/refusal bookkeeping.
// Unexpected input growth can still force an explicit incomplete-inventory
// refusal; it can never produce an accepted preparation.
pub fn proof_reserve2(legacy LegacyPlan2, donor Donor2, source Source2) !u64 {
	legacy_bytes := u64(json2.encode(legacy.inputs).len) + 1
	donor_bytes := u64(json2.encode(donor).len) + 1
	source_bytes := u64(json2.encode(source).len) + 1
	// Source2 contains more metadata than the copied subset's OwnedEntry2.
	known := budget2_add(budget2_add(legacy_bytes, donor_bytes)!, budget2_mul(source_bytes, 2)!)!
	value := budget2_add(budget2_mul(known, 2)!, (u64(40) << 20) + 65536)!
	return (budget2_add(value, 4095)! / 4096) * 4096
}

// payload includes the kernel, loader, configuration and estimated USTAR
// archive, with caller-side per-file FAT limits and archive rounding already
// checked. A 64MiB image is only the minimum; a larger payload doubles the
// image budget. This calculation does not guarantee the estimated payload size.
pub fn boot_image_budget2(payload u64) !u64 {
	maximum := u64(16) << 30
	required := budget2_add(budget2_add(payload, payload / 8)!, u64(8) << 20)!
	if required > maximum { return error('audio v2 FAT image requirement exceeds16GiB') }
	mut image := u64(64) << 20
	for image < required {
		if image > maximum / 2 { return error('audio v2 FAT image doubling exceeds16GiB') }
		image = budget2_mul(image, 2)!
	}
	return image
}

// Return the full proposed new growth only when it fits both fixed inclusive
// 2GiB caps. run adds all three retained guest media/output sets; no write or
// launch occurs here. The 200MiB preparation floor is a conservative planning
// assumption, not a measured guarantee. It covers all eight fresh C/i/s/o/ELF
// outputs, host generator/adapter and compiler temporaries, publisher/extras,
// source/controller copies, complete before/after donor and original-tool maps
// and logs. Reusing immutable captures avoids recapture, not these new outputs.
pub fn assess_budget2(b Projection2, run bool) !u64 {
	if b.cap != u64(2048) << 20 { return error('audio v2 budget requires the unchanged 2GiB cap') }
	if b.current_allocated > b.cap || b.current_apparent > b.cap {
		return error('retained audio v2 namespace already exceeds its cap')
	}
	if b.receipt_reserve < u64(16) << 20 { return error('audio v2 budget requires at least16MiB receipt reserve') }
	if b.preparation_reserve < u64(200) << 20 {
		return error('audio v2 preparation requires at least200MiB planning reserve, separately from receipts')
	}
	if b.scenario_count < 0 || b.scenario_count > 3 { return error('invalid fixed audio v2 scenario count') }
	mut growth := budget2_add(b.preparation_reserve, b.receipt_reserve)!
	if run {
		if b.scenario_count != 3 { return error('audio v2 run must retain all three scenarios') }
		if b.boot_image_bytes < u64(64) << 20 || b.firmware_vars_bytes < u64(64) << 20 {
			return error('audio v2 run requires at least64MiB boot and64MiB firmware state per scenario')
		}
		// This combined fresh rootfs-copy/USTAR allowance is another conservative
		// planning floor, not a measured guarantee about generated archive size.
		if b.rootfs_archive_bytes_per_scenario < u64(64) << 20 {
			return error('audio v2 run requires at least64MiB rootfs-copy/archive planning reserve per scenario')
		}
		if b.wave_bytes_per_scenario < u64(48000) * 2 * 2 * 240 + 4096
			|| b.logs_bytes_per_scenario < u64(16) << 20 {
			return error('audio v2 run requires full240-second stereo PCM plus a WAV header page and at least16MiB logs per scenario')
		}
		media := budget2_add(b.boot_image_bytes, b.firmware_vars_bytes)!
		outputs := budget2_add(b.wave_bytes_per_scenario, b.logs_bytes_per_scenario)!
		per_scenario := budget2_add(budget2_add(media, b.rootfs_archive_bytes_per_scenario)!, outputs)!
		growth = budget2_add(growth, budget2_mul(per_scenario, u64(b.scenario_count))!)!
	}
	if budget2_add(b.current_allocated, growth)! > b.cap
		|| budget2_add(b.current_apparent, growth)! > b.cap {
		return error('complete proposed audio v2 growth ' + growth.str()
			+ ' bytes exceeds retained cap headroom: allocated ' + (b.cap - b.current_allocated).str()
			+ ', apparent ' + (b.cap - b.current_apparent).str())
	}
	return growth
}
