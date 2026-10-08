module macinspect

import traceanalysis as j

pub const plist_options = ['--arm-io-plist', '--sgx-plist', '--asc-plist', '--asc1-plist',
	'--pmp0-plist', '--pmp1-plist', '--chosen-plist', '--pmgr-plist', '--pmp0-nub-plist',
	'--pmp1-nub-plist', '--pmp0-endpoint-plist', '--pmp1-endpoint-plist', '--accelerator-plist',
	'--driver-info']

fn option_token(s string) bool {
	if s.len < 2 || s[0] != `-` { return false }
	if s.starts_with('--') { return true }
	if s[1..].bytes().all(it.is_digit()) { return false }
	parts := s[1..].split('.')
	return !(parts.len == 2 && parts[1].len > 0 && parts[0].bytes().all(it.is_digit()) && parts[1].bytes().all(it.is_digit()))
}

fn path_value(s string) string {
	parts := s.split('/').filter(it != '' && it != '.')
	prefix := if s.starts_with('//') && !s.starts_with('///') {
		'//'
	} else if s.starts_with('/') {
		'/'
	} else {
		''
	}
	return if parts.len == 0 {
		if prefix == '' { '.' } else { prefix }
	} else {
		prefix + parts.join('/')
	}
}

pub fn parse_options(args []string) !map[string]string {
	mut options := map[string]string{}
	mut unknown := []string{}
	mut allowed := plist_options.clone()
	allowed << ['--compact', '--help']
	// argparse classifies every option (including ambiguous abbreviations)
	// before applying actions, so an earlier help still detects ambiguity.
	for arg in args {
		key := arg.all_before('=')
		if key.starts_with('--') && key != '--' && key !in allowed {
			candidates := allowed.filter(it.starts_with(key))
			if candidates.len > 1 {
				return error_with_code('ambiguous option: ${key} could match ${candidates.join(', ')}', 102)
			}
		}
		if arg == '--' { break }
	}
	mut i := 0
	for i < args.len {
		arg := args[i]
		i++
		if arg == '--' {
			unknown << arg
			unknown << args[i..]
			break
		}
		if arg.starts_with('-h') && !arg.starts_with('--') {
			if !arg[1..].bytes().all(it == `h`) {
				return error_with_code('argument -h/--help: ignored explicit argument', 102)
			}
			return {
				'--help': '1'
			}
		}
		raw := arg.all_before('=')
		mut key := raw
		if key !in allowed {
			candidates := if key.starts_with('--') {
				allowed.filter(it.starts_with(key))
			} else {
				[]string{}
			}
			if candidates.len == 1 {
				key = candidates[0]
			} else {
				unknown << arg
				continue
			}
		}
		if key in ['--compact', '--help'] {
			if arg != raw {
				return error_with_code('argument ${key}: ignored explicit argument', 102)
			}
			options[key] = '1'
			if key == '--help' { return options }
			continue
		}
		mut path := ''
		if arg != raw {
			path = arg[raw.len + 1..]
		} else {
			if i >= args.len || option_token(args[i]) {
				return error_with_code('argument ${key}: expected one argument', 102)
			}
			path = args[i]
			i++
		}
		options[key] = path_value(path)
	}
	if unknown.len != 0 {
		return error_with_code('unrecognized arguments: ${unknown.join(' ')}', 102)
	}
	return options
}

pub fn cli(args []string) !string {
	options := parse_options(args)!
	if '--help' in options {
		return 'usage: inspect_macos [--arm-io-plist PATH] [--sgx-plist PATH] [--asc-plist PATH]\n                     [--pmp0-plist PATH] [--accelerator-plist PATH]\n                     [other plist options] [--compact]\n\nCollect selected AGX topology, memory ranges, firmware and driver identity.\nSerial numbers and registry IDs are excluded.\n\n' + plist_options.join('\n') + '\n--compact\n-h, --help'
	}
	return encode_manifest(j.Value(collect(options)!), '--compact' in options)
}
