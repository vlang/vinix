// SPDX-License-Identifier: GPL-2.0-or-later
module ansreads

const usage = 'Usage: verify-reads record SOURCE MANIFEST --range OFFSET:LENGTH [--range ...] --label LABEL
       verify-reads check SOURCE MANIFEST [--passes 1..10]'
const description = 'Compare read-only ranges with a user-trusted reference; never write a device.
Record on a trusted OS with the partition unmounted. PASS establishes matching
bytes, not independently verified hardware identity or power-loss persistence.'

struct Arguments {
	command  string
	source   string
	manifest string
	ranges   []Range
	label    string
	passes   int = 2
	help     bool
}

fn arguments(args []string) !Arguments {
	if args.len == 0 { return error('record or check is required') }
	if args[0] in ['-h', '--help'] { return Arguments{ help: true } }
	command := args[0]
	if command !in ['record', 'check'] { return error('expected record or check') }
	options := if command == 'record' { ['--range', '--label'] } else { ['--passes'] }
	mut paths := []string{}
	mut ranges := []Range{}
	mut label := ''
	mut has_label := false
	mut passes := 2
	mut position := 1
	mut literal := false
	mut unknown := []string{}
	for position < args.len {
		arg := args[position]
		position++
		if !literal && arg == '--' {
			literal = true
			continue
		}
		if !literal && arg.starts_with('-') && arg != '-' {
			name := arg.all_before('=')
			matches := options.filter(name.starts_with('--') && it.starts_with(name))
			help := name == '-h' || (name.starts_with('--') && '--help'.starts_with(name))
			if matches.len > 1 || (help && matches.len > 0) {
				return error('ambiguous option: ' + name)
			}
			if help {
				if arg.contains('=') { return error('help does not take an argument') }
				return Arguments{ help: true }
			}
			if matches.len == 0 {
				unknown << arg
				continue
			}
			option := matches[0]
			mut value := ''
			if arg.contains('=') {
				value = arg.all_after('=')
			} else {
				if position >= args.len { return error(option + ' requires an argument') }
				value = args[position]
				if value.starts_with('-') && value != '-' && !value[1..].bytes().all(it.is_digit()) {
					return error(option + ' requires an argument')
				}
				position++
			}
			match option {
				'--range' { ranges << parse_range(value)! }
				'--label' {
					label = value
					has_label = true
				}
				'--passes' {
					number := bounded_integer(value, 10) or {
						if err.msg() == 'integer exceeds signed 64-bit bounds' {
							i64(11)
						} else {
							return err
						}
					}
					// Preserve operational rejection for syntactically valid large
					// integers, without narrowing them into a valid pass count.
					passes = if number < 1 || number > 10 { 11 } else { int(number) }
				}
				else {}
			}
		} else {
			paths << arg
		}
	}
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	if paths.len != 2 { return error('SOURCE and MANIFEST are required') }
	if command == 'record' && (ranges.len == 0 || !has_label) {
		return error('record requires --range and --label')
	}
	return Arguments{command, paths[0], paths[1], ranges, label, passes, false}
}

fn execute(args Arguments) ! {
	if args.command == 'record' {
		value := record(args.source, args.ranges, args.label)!
		save_new_manifest(args.manifest, value)!
		println('Reference saved; no writes were made to the source.')
	} else {
		value := check(args.source, load_manifest(args.manifest)!, args.passes)!
		print(value.json_text())
	}
}

pub fn run(args []string) int {
	parsed := arguments(args) or {
		eprintln(usage + '\nerror: ' + err.msg())
		return 2
	}
	if parsed.help {
		println(usage + '\n\n' + description)
		return 0
	}
	execute(parsed) or {
		eprintln('FAIL: ' + err.msg())
		return 1
	}
	return 0
}
