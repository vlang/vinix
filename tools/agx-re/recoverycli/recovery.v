module recoverycli

import appleadt
import encoding.hex
import g17expr
import imageextract
import os
import t6050power as power
import traceanalysis as j

fn read_file(path string) ![]u8 {
	if !os.exists(path) { return error('[Errno 2] No such file or directory: ${j.quoted(path)}') }
	if os.is_dir(path) { return error('[Errno 21] Is a directory: ${j.quoted(path)}') }
	return os.read_bytes(path)
}

// The six reads precede every proof, retaining missing-input error priority.
pub fn recover_g17(options map[string]string) !j.Value {
	driver := read_file(options['--driver'])!
	kernel := read_file(options['--kernel'])!
	firmware := read_file(options['--firmware'])!
	iogpu := read_file(options['--iogpu'])!
	iosurface := read_file(options['--iosurface'])!
	rtbuddy := read_file(options['--rtbuddy'])!
	return g17expr.query(driver, 'recover_g17_report', {
		'kernel':    j.Value(hex.encode(kernel))
		'firmware':  j.Value(hex.encode(firmware))
		'iogpu':     j.Value(hex.encode(iogpu))
		'iosurface': j.Value(hex.encode(iosurface))
		'rtbuddy':   j.Value(hex.encode(rtbuddy))
	})!
}

// Enumerate only the two wildcard directories from the original fixed-depth
// Preboot glob. Sorting keeps ambiguous-source diagnostics deterministic.
pub fn find_device_tree(preboot string) !string {
	mut candidates := []string{}
	for volume in os.ls(preboot) or { []string{} } {
		boot := os.join_path(preboot, volume, 'boot')
		for image in os.ls(boot) or { []string{} } {
			path := os.join_path(boot, image, 'usr/standalone/firmware/devicetree.img4')
			info := os.stat(path) or { continue }
			if info.get_filetype() == .regular { candidates << path }
		}
	}
	candidates.sort()
	if candidates.len != 1 {
		rendered := if candidates.len == 0 { 'none' } else { candidates.join(', ') }
		return error('expected one boot DeviceTree, found: ${rendered}')
	}
	return candidates[0]
}

pub fn device_tree(data []u8) !appleadt.Node {
	im4p := imageextract.unwrap_im4p(data)!
	kind := data[im4p.image_type.start..im4p.image_type.end]
	if kind.bytestr() != 'dtre' {
		return error('not a DeviceTree IM4P (type=${imageextract.bytes_repr(kind)})')
	}
	payload := data[im4p.payload.start..im4p.payload.end]
	return appleadt.parse(appleadt.decompress(payload, 0)!)!
}

fn controller(options map[string]string, name string) !power.ControllerImage {
	return power.ControllerImage{ image: read_file(options[name])! }
}

pub fn recover_t6050(options map[string]string) !j.Value {
	source := if options['--device-tree'] != '' {
		options['--device-tree']
	} else {
		find_device_tree(options['--preboot'])!
	}
	root := device_tree(read_file(source)!)!
	mut manifest := power.recover_power_topology(root)!
	pmgr := controller(options, '--pmgr')!
	pmgr_symbols := pmgr.symbols()!
	manifest['apple_pmgr'] = j.Value(power.recover_pmgr_controller(pmgr)!)
	manifest['apple_t6050_pmgr'] = j.Value(power.recover_t6050_pmgr_controller(controller(options, '--t6050-pmgr')!, pmgr_symbols)!)
	pmp := controller(options, '--pmp')!
	rtbuddy := controller(options, '--rtbuddy')!
	manifest['apple_pmp'] = j.Value(power.recover_pmp_controller(pmp, rtbuddy)!)
	pmp_firmware := controller(options, '--pmp-firmware')!
	// Re-open the paired image at the same stage as the original command.
	firmware_rtbuddy := controller(options, '--rtbuddy')!
	manifest['apple_pmp_firmware'] = j.Value(power.recover_pmp_firmware_controller(pmp_firmware, firmware_rtbuddy)!)
	format := j.value(j.value(manifest, 'apple_pmp_firmware').as_map(), 'patchbay_format')
	manifest['t6050pmp_patchbay'] = j.Value(power.recover_pmp_patchbay(read_file(options['--pmp-image'])!, format)!)
	manifest['apple_a7iop'] = j.Value(power.recover_a7iop_controller(controller(options, '--apple-a7iop')!)!)
	manifest['apple_ascwrap_v6'] = j.Value(power.recover_ascwrap_controller(controller(options, '--ascwrap-v6')!)!)
	manifest['apple_t8110_dart'] = j.Value(power.recover_t8110_dart_controller(controller(options, '--t8110-dart')!)!)
	manifest['iodart_family'] = j.Value(power.recover_iodart_controller(controller(options, '--iodart-family')!)!)
	manifest['t8110_kernel'] = j.Value(power.recover_kernel_controller(controller(options, '--kernel')!)!)
	return j.Value(manifest)
}
