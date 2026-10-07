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
			unknown << args[index + 1..]
			break
		}
		name := arg.all_before('=')
		has_value := arg.contains('=')
		if arg.starts_with('-h') && !arg[1..].bytes().all(it == `h`) {
			return error('argument -h/--help: ignored explicit argument')
		}
		is_help := (arg.starts_with('-h') && arg[1..].bytes().all(it == `h`)) ||
			(name.starts_with('--') && '--help'.starts_with(name))
		matches := options.filter(name.starts_with('--') && it.starts_with(name))
		if matches.len > 1 || (is_help && matches.len > 0) { return error('ambiguous option: ${name}') }
		if is_help {
			if has_value { return error('argument --help: ignored explicit argument') }
			println(usage + '\n\n' + scope)
			exit(0)
		}
		if matches.len == 1 {
			option := matches[0]
			mut value := ''
			if has_value { value = arg.all_after('=') }
			else {
				if index + 1 >= args.len { return error('argument ${option}: expected one argument') }
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
