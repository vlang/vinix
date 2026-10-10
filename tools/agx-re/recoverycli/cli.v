module recoverycli

import hosttest
import os
import traceanalysis as j

fn defaults(mode string) map[string]string {
	if mode == 'recover_g17_abi' {
		return {
			'--driver':    'build/kext/g17c/AGXG17X.macho'
			'--kernel':    'build/kext/g17c/kernel.macho'
			'--firmware':  'build/firmware/g17c/armfw.bin'
			'--iogpu':     'build/kext/g17c/iokit.IOGPUFamily.macho'
			'--iosurface': 'build/kext/g17c/iokit.IOSurface.macho'
			'--rtbuddy':   'build/kext/g17c/AGXFirmwareKextG17XRTBuddy.macho'
		}
	}
	return {
		'--device-tree':   ''
		'--preboot':       '/System/Volumes/Preboot'
		'--pmgr':          'build/kext/g17c/driver.ApplePMGR.macho'
		'--t6050-pmgr':    'build/kext/g17c/driver.AppleT6050PMGR.macho'
		'--pmp':           'build/kext/g17c/driver.ApplePMP.macho'
		'--pmp-firmware':  'build/kext/g17c/driver.ApplePMPFirmware.macho'
		'--rtbuddy':       'build/kext/g17c/driver.RTBuddy.macho'
		'--apple-a7iop':   'build/kext/g17c/driver.AppleA7IOP.macho'
		'--ascwrap-v6':    'build/kext/g17c/driver.AppleA7IOP-ASCWrap-v6.macho'
		'--t8110-dart':    'build/kext/g17c/driver.AppleT8110DART.macho'
		'--iodart-family': 'build/kext/g17c/driver.IODARTFamily.macho'
		'--kernel':        'build/kext/g17c/kernel.macho'
		'--pmp-image':     'build/firmware/t6050pmp.macho'
		'--output':        'build/t6050-power.json'
	}
}

fn usage(mode string) string {
	mut text := 'usage: ${mode} [-h]'
	for option, _ in defaults(mode) {
		text += ' [${option} ${option[2..].replace('-', '_').to_upper()}]'
	}
	return text
}

// Pathlib removes empty/dot components but preserves .. and double-root paths.
fn path_value(path string) string {
	prefix := if path.starts_with('//') && !path.starts_with('///') {
		'//'
	} else if path.starts_with('/') {
		'/'
	} else {
		''
	}
	value := prefix + path.split('/').filter(it != '' && it != '.').join('/')
	return if value == '' { '.' } else { value }
}

pub fn parse_options(mode string, args []string) !map[string]string {
	mut options := defaults(mode)
	specifications := options.keys().map(hosttest.Option{ name: it, value: true })
	parsed := hosttest.parse_arguments(args, specifications, 0, usage(mode),
		'Recover checked Apple GPU contracts from local images using native V.')!
	for key, value in parsed.options { options[key] = path_value(value) }
	return options
}

fn fail(mode string, message string) {
	// Preserve the distinction between validation/OS errors and structural
	// exceptions transported by the native readers, without an interpreter stack.
	if message.starts_with('struct.error:') || message.starts_with('KeyError:')
		|| message.starts_with('IndexError:') || message.starts_with('TypeError:')
		|| message.starts_with('OverflowError:') || message.starts_with('AttributeError:') {
		eprintln('${mode}: ${message}')
		exit(1)
	}
	eprintln(usage(mode))
	eprintln('${mode}: error: ${message}')
	exit(2)
}

pub fn run(mode string, args []string) {
	options := parse_options(mode, args) or {
		fail(mode, err.msg())
		return
	}
	result := if mode == 'recover_g17_abi' {
		recover_g17(options) or {
			fail(mode, err.msg())
			return
		}
	} else {
		recover_t6050(options) or {
			fail(mode, err.msg())
			return
		}
	}
	text := j.encode(result, true) + '\n'
	if mode == 'recover_t6050_power' {
		// All reads and proofs complete before creating a directory or report.
		output := options['--output']
		os.mkdir_all(os.dir(output)) or {
			eprintln('${mode}: ${err}')
			exit(1)
		}
		os.write_file(output, text) or {
			eprintln('${mode}: ${err}')
			exit(1)
		}
	}
	print(text)
}
