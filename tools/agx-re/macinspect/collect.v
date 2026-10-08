module macinspect

import os
import time
import strings
import traceanalysis as j
import g17decode

pub fn first_node(p Property, source string) !map[string]Property {
	candidate := if p.kind == .array && p.array.len > 0 { p.array[0] } else { p }
	if candidate.kind != .object {
		return error('${source} does not contain an IORegistry dictionary')
	}
	return candidate.fields
}

pub fn load_plist(path string) !Property {
	if !os.exists(path) {
		return error('cannot read plist ${path}: [Errno 2] No such file or directory: ${j.quoted(path)}')
	}
	if os.is_dir(path) {
		return error('cannot read plist ${path}: [Errno 21] Is a directory: ${j.quoted(path)}')
	}
	data := os.read_bytes(path) or { return error('cannot read plist ${path}: ${err}') }
	return parse_plist(data) or { return error('cannot read plist ${path}: ${err}') }
}

fn run_plist(command []string, optional bool) !Property {
	program := os.find_abs_path_of_executable(command[0]) or { return error('${command.join(' ')} failed: [Errno 2] No such file or directory: ${j.quoted(command[0])}') }
	mut process := os.new_process(program)
	process.set_args(command[1..])
	process.set_redirect_stdio()
	defer { process.close() }
	process.run()
	if process.pid <= 0 { return error('${command.join(' ')} failed: cannot start process') }
	mut output := strings.new_builder(4096)
	mut diagnostic := strings.new_builder(256)
	// Drain both pipes while the child runs. Preserve the original unbounded
	// command deadline and literal argv; no shell interprets registry names.
	for {
		output.write_string(process.stdout_read())
		diagnostic.write_string(process.stderr_read())
		if !process.is_alive() { break }
		time.sleep(time.millisecond)
	}
	output.write_string(process.stdout_slurp())
	diagnostic.write_string(process.stderr_slurp())
	if process.code != 0 {
		detail := g17decode.utf8_replace(diagnostic.str().bytes()).trim_space()
		return error('${command.join(' ')} failed: ${if detail != '' {
			detail
		} else {
			'command returned non-zero exit status ${process.code}'
		}}')
	}
	data := output.str().bytes()
	if optional && data.len == 0 { return Property{} }
	return parse_plist(data) or { return error('${command.join(' ')} did not produce a plist') }
}

fn device_command(name string, shallow bool) []string {
	mut command := ['ioreg', '-a', '-p', 'IODeviceTree', '-n', name, '-r']
	if shallow { command << ['-d', '1'] }
	return command
}

fn source(options map[string]string, key string, command []string, optional bool) !Property {
	if path := options[key] { return load_plist(path) }
	return run_plist(command, optional)
}

fn host_version() string {
	p := load_plist('/System/Library/CoreServices/SystemVersion.plist') or { return '' }
	return text(p.fields, 'ProductVersion')
}

pub fn collect(options map[string]string) !map[string]j.Value {
	arm := source(options, '--arm-io-plist', device_command('arm-io', false), false)!
	sgx := source(options, '--sgx-plist', device_command('sgx', false), false)!
	asc := source(options, '--asc-plist', device_command('gfx-asc', false), false)!
	asc1 := if '--asc1-plist' in options {
		load_plist(options['--asc1-plist'])!
	} else if '--asc-plist' in options {
		Property{}
	} else {
		run_plist(device_command('gfx1-asc', false), false)!
	}
	pmp0 := source(options, '--pmp0-plist', device_command('pmp0', false), false)!
	pmp1 := if '--pmp1-plist' in options {
		load_plist(options['--pmp1-plist'])!
	} else if '--pmp0-plist' in options {
		Property{}
	} else {
		run_plist(device_command('pmp1', false), true)!
	}
	chosen := source(options, '--chosen-plist', device_command('chosen', true), false)!
	pmgr := source(options, '--pmgr-plist', device_command('pmgr', true), false)!
	nub0 := if '--pmp0-nub-plist' in options {
		load_plist(options['--pmp0-nub-plist'])!
	} else if '--pmp0-plist' in options {
		pmp0
	} else {
		run_plist(device_command('iop-pmp0-nub', true), false)!
	}
	nub1 := if '--pmp1-nub-plist' in options {
		load_plist(options['--pmp1-nub-plist'])!
	} else if '--pmp1-plist' in options || pmp1.kind == .null {
		Property{}
	} else {
		run_plist(device_command('iop-pmp1-nub', true), true)!
	}
	endpoint0 := if '--pmp0-endpoint-plist' in options {
		load_plist(options['--pmp0-endpoint-plist'])!
	} else if '--pmp0-plist' in options {
		Property{}
	} else {
		run_plist(['ioreg', '-a', '-r', '-n', 'PMP0Endpoint1'], false)!
	}
	endpoint1 := if '--pmp1-endpoint-plist' in options {
		load_plist(options['--pmp1-endpoint-plist'])!
	} else if '--pmp1-plist' in options || pmp1.kind == .null {
		Property{}
	} else {
		run_plist(['ioreg', '-a', '-r', '-n', 'PMP1Endpoint1'], false)!
	}
	accelerator := source(options, '--accelerator-plist', ['ioreg', '-a', '-r', '-c',
		'AGXAcceleratorG17X'], false)!
	driver_path := options['--driver-info'] or { '/System/Library/Extensions/AGXG17X.kext/Contents/Info.plist' }
	primary := parse_asc(first_node(asc, 'gfx-asc plist')!)!
	mut asc_roles := [j.Value(primary)]
	if asc1.kind != .null { asc_roles << j.Value(parse_asc(first_node(asc1, 'gfx1-asc plist')!)!) }
	mut pmp_roles := [j.Value(parse_pmp(first_node(pmp0, 'pmp0 plist')!)!)]
	mut nubs := [j.Value(parse_pmp_nub(first_node(nub0, 'pmp0 nub plist')!, 'PMP0')!)]
	if pmp1.kind != .null { pmp_roles << j.Value(parse_pmp(first_node(pmp1, 'pmp1 plist')!)!) }
	if nub1.kind != .null {
		nubs << j.Value(parse_pmp_nub(first_node(nub1, 'pmp1 nub plist')!, 'PMP1')!)
	}
	mut endpoints := []j.Value{}
	if endpoint0.kind != .null {
		endpoints << j.Value(parse_pmp_endpoint_service(first_node(endpoint0, 'PMP0 endpoint plist')!)!)
	}
	if endpoint1.kind != .null {
		endpoints << j.Value(parse_pmp_endpoint_service(first_node(endpoint1, 'PMP1 endpoint plist')!)!)
	}
	architecture := $if arm64 { 'arm64' } $else $if amd64 { 'x86_64' } $else { os.uname().machine }
	mut manifest := map[string]j.Value{
		'schema':                number(6)
		'host':                  j.Value(map[string]j.Value{
			'architecture':  j.Value(architecture)
			'macos_version': j.Value(host_version())
		})
		'platform':              j.Value(parse_arm_io(first_node(arm, 'arm-io plist')!)!)
		'device_tree':           j.Value(parse_sgx(first_node(sgx, 'sgx plist')!)!)
		'asc':                   j.Value(primary)
		'asc_roles':             j.Value(asc_roles)
		'pmp_roles':             j.Value(pmp_roles)
		'pmp_nubs':              j.Value(nubs)
		'pmp_patchbay_inputs':   j.Value(parse_pmp_patchbay_inputs({
			'chosen':   Property{ kind: .object, fields: first_node(chosen, 'chosen plist')! }
			'pmgr':     Property{ kind: .object, fields: first_node(pmgr, 'pmgr plist')! }
			'provider': Property{ kind: .object, fields: first_node(nub0, 'pmp0 nub plist')! }
		})!)
		'pmp_endpoint_services': j.Value(endpoints)
		'accelerator':           j.Value(parse_accelerator(first_node(accelerator, 'accelerator plist')!)!)
		'driver':                j.Value(parse_driver_info(load_plist(driver_path)!.fields))
	}
	manifest['warnings'] = j.Value(validate_manifest(manifest)!.map(j.Value(it)))
	return manifest
}
