// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

fn negative_path_argument(text string) bool {
	if !text.starts_with('-') || text.len == 1 { return false }
	value := text[1..]
	if value.bytes().all(it.is_digit()) { return true }
	if value.count('.') != 1 { return false }
	before := value.all_before('.')
	after := value.all_after('.')
	return after.len > 0 && before.bytes().all(it.is_digit()) && after.bytes().all(it.is_digit())
}

// Keep argparse's Path semantics: an explicit empty path is the current
// directory, while an omitted option selects a new private temporary directory.
// Unknown arguments are reported after parsing so an eager help action still
// behaves like the original controller. An option cannot consume another flag.
pub fn parse_path_options(args []string, options []string, usage string, scope string) !map[string]string {
	mut paths := map[string]string{}
	mut unknown := []string{}
	mut index := 0
	for index < args.len {
		arg := args[index]
		if arg == '--' {
			// These controllers have no positional arguments. argparse retains
			// the separator as an unrecognized argument even when it is alone.
			unknown << args[index..]
			break
		}
		name := arg.all_before('=')
		has_value := arg.contains('=')
		// CPython 3.9 argparse crashes on this empty short-help argument. Keep
		// its failing exit status while giving the native CLI a clean diagnostic.
		if arg == '-h=' {
			eprintln('argument -h/--help: ignored explicit argument')
			exit(1)
		}
		if arg.starts_with('-h') && !arg[1..].bytes().all(it == `h`) {
			return error('argument -h/--help: ignored explicit argument')
		}
		is_help := (arg.starts_with('-h') && arg[1..].bytes().all(it == `h`))
			|| (name.starts_with('--') && '--help'.starts_with(name))
		matches := options.filter(name.starts_with('--') && it.starts_with(name))
		if matches.len > 1 || (is_help && matches.len > 0) {
			return error('ambiguous option: ${name}')
		}
		if is_help {
			if has_value { return error('argument --help: ignored explicit argument') }
			println(usage + '\n\n' + scope)
			exit(0)
		}
		if matches.len == 1 {
			option := matches[0]
			mut value := ''
			if has_value {
				value = arg.all_after('=')
			} else {
				if index + 1 >= args.len {
					return error('argument ${option}: expected one argument')
				}
				value = args[index + 1]
				if value.starts_with('-') && value != '-' && !negative_path_argument(value) {
					return error('argument ${option}: expected one argument')
				}
				index++
			}
			paths[option] = if value == '' { '.' } else { value }
		} else {
			unknown << arg
		}
		index++
	}
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return paths
}

pub fn parse_keep_dir(args []string, usage string, scope string) !string {
	paths := parse_path_options(args, ['--keep-dir'], usage, scope)!
	return paths['--keep-dir']
}

pub struct Option {
pub:
	name    string
	value   bool
	choices []string
}

pub struct Arguments {
pub:
	options    map[string]string
	positional []string
}

// The standalone fixture commands share argparse's long-option abbreviations,
// eager help, single-value choices and negative positional-path rules.
pub fn parse_arguments(args []string, specifications []Option, positional_count int, usage string, scope string) !Arguments {
	return parse_arguments_choices(args, specifications, positional_count, [][]string{}, usage, scope)
}

// Positional choices are checked when consumed, before a later eager help
// action, just as argparse checks the compatibility module name.
pub fn parse_arguments_choices(args []string, specifications []Option, positional_count int, positional_choices [][]string, usage string, scope string) !Arguments {
	mut options := map[string]string{}
	mut values := []string{}
	mut unknown := []string{}
	mut index := 0
	mut positional := false
	for index < args.len {
		arg := args[index]
		if !positional && arg == '--' {
			if positional_count == 0 {
				unknown << args[index..]
				break
			}
			positional = true
			index++
			continue
		}
		if !positional && arg == '-h=' {
			eprintln('argument -h/--help: ignored explicit argument')
			exit(1)
		}
		if !positional && arg.starts_with('-h') && !arg[1..].bytes().all(it == `h`) {
			return error('argument -h/--help: ignored explicit argument')
		}
		name := arg.all_before('=')
		mut matches := specifications.filter(!positional && name.starts_with('--') && it.name.starts_with(name))
		exact := matches.filter(it.name == name)
		if exact.len == 1 { matches = exact.clone() }
		help := !positional && ((arg.starts_with('-h') && arg[1..].bytes().all(it == `h`))
			|| (name.starts_with('--') && '--help'.starts_with(name)))
		if matches.len > 1 || (help && matches.len > 0 && name != '--help') {
			return error('ambiguous option: ' + name)
		}
		if help {
			if arg.contains('=') { return error('argument --help: ignored explicit argument') }
			println(usage + '\n\n' + scope)
			exit(0)
		}
		if matches.len == 1 {
			specification := matches[0]
			mut value := 'true'
			if specification.value {
				if arg.contains('=') {
					value = arg.all_after('=')
				} else {
					if index + 1 >= args.len {
						return error('argument ' + specification.name + ': expected one argument')
					}
					value = args[index + 1]
					if value.starts_with('-') && value != '-' && !negative_path_argument(value) {
						return error('argument ' + specification.name + ': expected one argument')
					}
					index++
				}
				if specification.choices.len > 0 && value !in specification.choices {
					return error('invalid choice for ' + specification.name + ': ' + value)
				}
			} else if arg.contains('=') {
				return error('argument ' + specification.name + ': ignored explicit argument')
			}
			options[specification.name] = value
		} else if !positional && arg.starts_with('-') && arg != '-' && !negative_path_argument(arg) {
			unknown << arg
		} else if values.len < positional_count {
			if values.len < positional_choices.len && positional_choices[values.len].len > 0
				&& arg !in positional_choices[values.len] {
				return error('invalid positional choice: ' + arg)
			}
			values << arg
		} else {
			unknown << arg
		}
		index++
	}
	if values.len != positional_count { return error('missing required positional argument') }
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return Arguments{options, values}
}
