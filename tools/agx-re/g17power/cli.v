module g17power

import os

fn argument_is_option(text string) bool {
	if text.len < 2 || !text.starts_with('-') { return false }
	if text.starts_with('--') { return true }
	digits := text[1..]
	if digits.bytes().all(it.is_digit()) { return false }
	parts := digits.split('.')
	return !(parts.len == 2 && parts[1].len > 0 && parts[0].bytes().all(it.is_digit()) && parts[1].bytes().all(it.is_digit()))
}

fn parse_options(args []string) !map[string]string {
	options := ['--driver', '--device-tree', '--output', '--check', '--help']
	mut result := map[string]string{}
	mut unknown := []string{}
	mut index := 0
	for index < args.len {
		token := args[index]
		index++
		if token == '--' {
			unknown << token
			unknown << args[index..]
			break
		}
		if token.starts_with('-h') && !token.starts_with('--') {
			if !token[1..].bytes().all(it == `h`) {
				return error('argument -h/--help: ignored explicit argument')
			}
			result['--help'] = '1'
			return result
		}
		raw := token.all_before('=')
		mut key := raw
		if key !in options {
			choices := if key.starts_with('--') {
				options.filter(it.starts_with(key))
			} else {
				[]string{}
			}
			if choices.len > 1 {
				return error('ambiguous option: ${key} could match ' + choices.join(', '))
			}
			if choices.len == 0 {
				unknown << token
				continue
			}
			key = choices[0]
		}
		if key in ['--help', '--check'] {
			if token != raw { return error('argument ${key}: ignored explicit argument') }
			result[key] = '1'
			if key == '--help' { return result }
			continue
		}
		mut value := ''
		if token != raw {
			value = token[raw.len + 1..]
		} else {
			if index >= args.len || argument_is_option(args[index]) {
				return error('argument ${key}: expected one argument')
			}
			value = args[index]
			index++
		}
		result[key] = if value == '' { '.' } else { value }
	}
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return result
}

fn command(options map[string]string, base string) ! {
	driver := options['--driver'] or { os.join_path(base, 'build/kext/g17c/AGXG17X.macho') }
	tree := options['--device-tree'] or { os.join_path(base, 'build/live_macos.json') }
	output := options['--output'] or { os.norm_path(os.join_path(base, '../../kernel/gpu/agx/fw/g17_power_tables.v')) }
	record := recover_variant_records(os.read_bytes(driver)!)!
	source := generated_source(record.uuid, device_voltages(tree)!, record.vdd, record.afr)!
	if '--check' in options {
		if !os.exists(output) || os.read_file(output)! != source {
			return error('stale generated G17 power model: ${output}')
		}
	} else {
		os.write_file(output, source)!
	}
}

pub fn cli(args []string, base string) int {
	options := parse_options(args) or {
		eprintln('G17 power model: ${err.msg()}')
		return 2
	}
	if '--help' in options {
		println('Generate G17C Q24.40 leakage tables: --driver PATH --device-tree PATH --output PATH [--check]')
		return 0
	}
	command(options, base) or {
		eprintln(err.msg())
		return 1
	}
	return 0
}
