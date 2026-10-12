// SPDX-License-Identifier: GPL-2.0-or-later
module cachecli

pub struct Arguments {
pub:
	options    map[string][]string
	positional []string
}

pub fn arguments(argv []string, scalar []string, repeated []string, flags []string, minimum int, maximum int, usage string) !Arguments {
	mut options := map[string][]string{}
	mut positional := []string{}
	mut unknown := []string{}
	mut index := 0
	mut separated := false
	for index < argv.len {
		arg := argv[index]
		if !separated && arg == '--' {
			separated = true
			index++
			continue
		}
		name := arg.all_before('=')
		if !separated && (name == '-h' || name == '--help') {
			if arg.contains('=') { return error('help does not accept a value') }
			println(usage)
			exit(0)
		}
		mut matches := [...scalar, ...repeated, ...flags, '--help'].filter(!separated && name.starts_with('--') && it.starts_with(name))
		exact := matches.filter(it == name)
		if exact.len == 1 { matches = exact.clone() }
		if matches.len > 1 { return error('ambiguous option: ' + name) }
		if matches.len == 1 {
			key := matches[0]
			if key == '--help' {
				if arg.contains('=') { return error('help does not accept a value') }
				println(usage)
				exit(0)
			}
			mut value := 'true'
			if key in flags {
				if arg.contains('=') { return error('option does not accept a value: ' + key) }
			} else if arg.contains('=') {
				value = arg.all_after('=')
			} else {
				if index + 1 >= argv.len { return error('missing value for ' + key) }
				index++
				value = argv[index]
				if value.starts_with('-') && value != '-' && !value[1..].bytes().all(it.is_digit()) {
					return error('missing value for ' + key)
				}
			}
			if key in repeated { options[key] << value } else { options[key] = [value] }
		} else if !separated && arg.starts_with('-') && arg != '-' {
			unknown << arg
		} else {
			positional << arg
		}
		index++
	}
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	if positional.len < minimum || (maximum >= 0 && positional.len > maximum) {
		return error('wrong number of positional arguments')
	}
	return Arguments{options, positional}
}

pub fn (args Arguments) required(key string) !string {
	if key !in args.options { return error('missing required ' + key) }
	return args.options[key][0]
}

pub fn (args Arguments) value(key string, fallback string) string {
	return if key in args.options { args.options[key][0] } else { fallback }
}
