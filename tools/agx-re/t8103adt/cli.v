module t8103adt

import os
import traceanalysis as j

pub struct Options {
pub mut:
	preboot     string = '/System/Volumes/Preboot'
	board       string = default_board
	device_tree string
	live_sgx    string
	agx_g13g    string = 'build/kext/g13g/AGXG13G.macho'
	help        bool
}

fn usage() string {
	return 'usage: recover_t8103_adt [-h] [--preboot PREBOOT]\n                        [--board {j274ap,j293ap,j313ap,j456ap,j457ap}]\n                        [--device-tree DEVICE_TREE] [--live-sgx LIVE_SGX]\n                        [--agx-g13g AGX_G13G]'
}

// Retain argparse's exit status for its empty short-help argument without
// reproducing an interpreter traceback.
const empty_short_help_error = 1314

fn fail(message string, code int) {
	if message.starts_with('IndexError: ') || message.starts_with('AttributeError: ') {
		eprintln(message)
		exit(1)
	}
	eprintln(usage())
	eprintln('recover_t8103_adt: error: ${message}')
	exit(if code == empty_short_help_error { 1 } else { 2 })
}

// Pathlib removes redundant separators and dot segments without resolving .. .
fn path_value(path string) string {
	prefix := if path.starts_with('//') && !path.starts_with('///') {
		'//'
	} else if path.starts_with('/') {
		'/'
	} else {
		''
	}
	components := path.split('/').filter(it != '' && it != '.')
	value := prefix + components.join('/')
	return if value == '' { '.' } else { value }
}

struct Argument {
	raw      string
	option   string
	explicit bool
	value    string
	optional bool
}

fn negative_number(text string) bool {
	if text.len < 2 || text[0] != `-` { return false }
	mut dot := -1
	for i in 1 .. text.len {
		if text[i] == `.` && dot == -1 {
			dot = i
		} else if text[i] < `0` || text[i] > `9` {
			return false
		}
	}
	return dot == -1 || dot < text.len - 1
}

fn classify(args []string) ![]Argument {
	allowed := ['--help', '--preboot', '--board', '--device-tree', '--live-sgx', '--agx-g13g']!
	mut tokens := []Argument{}
	mut positional := false
	for raw in args {
		if positional {
			tokens << Argument{ raw: raw }
			continue
		}
		if raw == '--' {
			positional = true
			tokens << Argument{ raw: raw }
			continue
		}
		if raw == '-h' || (raw.starts_with('-h') && raw.len > 2) {
			suffix := raw[2..].trim_string_left('=')
			all_help := suffix.len != 0 && suffix.bytes().all(it == `h`) && !raw.contains('=')
			tokens << Argument{ raw: raw, option: '-h/--help', optional: true, explicit: raw.len > 2 && !all_help, value: suffix }
			continue
		}
		if raw.starts_with('--') {
			option := raw.all_before('=')
			mut matches := []string{}
			if option in allowed {
				matches << option
			} else {
				for known in allowed { if known.starts_with(option) { matches << known } }
			}
			if matches.len > 1 {
				return error('ambiguous option: ${raw} could match ${matches.join(', ')}')
			}
			if matches.len == 1 {
				tokens << Argument{
					raw:      raw
					option:   if matches[0] == '--help' {
						'-h/--help'
					} else {
						matches[0]
					}
					optional: true
					explicit: raw.contains('=')
					value:    raw.all_after('=')
				}
				continue
			}
		}
		tokens << Argument{ raw: raw, optional: raw.len > 1 && raw.starts_with('-') && !negative_number(raw) }
	}
	return tokens
}

pub fn parse_options(args []string) !Options {
	tokens := classify(args)!
	mut result := Options{}
	mut extras := []string{}
	mut index := 0
	for index < tokens.len {
		token := tokens[index]
		index++
		if token.option == '' {
			extras << token.raw
			continue
		}
		if token.option == '-h/--help' {
			if token.explicit {
				message := 'argument -h/--help: ignored explicit argument ${j.quoted(token.value)}'
				if token.raw == '-h=' { return error_with_code(message, empty_short_help_error) }
				return error(message)
			}
			result.help = true
			return result
		}
		mut value := token.value
		if !token.explicit {
			if index == tokens.len || tokens[index].optional || tokens[index].raw == '--' {
				return error('argument ${token.option}: expected one argument')
			}
			value = tokens[index].raw
			index++
		}
		match token.option {
			'--board' {
				if value !in base_m1_boards {
					return error('argument --board: invalid choice: ${j.quoted(value)} (choose from ${base_m1_boards.map(j.quoted(it)).join(', ')})')
				}
				result.board = value
			}
			'--preboot' { result.preboot = path_value(value) }
			'--device-tree' { result.device_tree = path_value(value) }
			'--live-sgx' { result.live_sgx = path_value(value) }
			'--agx-g13g' { result.agx_g13g = path_value(value) }
			else {}
		}
	}
	if extras.len != 0 { return error('unrecognized arguments: ${extras.join(' ')}') }
	return result
}

pub fn cli(args []string) !string {
	options := parse_options(args)!
	if options.help {
		return usage() + '\n\nRecover the base-M1 native boot-data contract from a staged DeviceTree\nor live sgx plist and the AGXG13G driver.\n\noptions:\n  -h, --help            show this help message and exit\n  --preboot PREBOOT     local Preboot directory\n  --board BOARD         base-M1 board to inspect\n  --device-tree PATH    override the staged DeviceTree\n  --live-sgx PATH       IORegistry sgx capture from a running M1\n  --agx-g13g PATH       AGXG13G Mach-O driver\n'
	}
	mut source := options.live_sgx
	live := source != ''
	mut inventory := map[string]j.Value{}
	mut states := ?[]u8(none)
	if live {
		inventory = live_sgx_inventory(source)!
		captured := read_perf_states(source)!
		if captured.present { states = captured.data }
	} else {
		source = if options.device_tree != '' {
			options.device_tree
		} else {
			find_platform_device_tree(options.preboot, options.board)!
		}
		inventory = sgx_inventory(load_device_tree(source)!)!
	}
	mut driver := ?[]u8(none)
	if os.is_file(options.agx_g13g) { driver = read_file(options.agx_g13g)! }
	return j.encode(j.Value(recover(inventory, source, live, driver, states)!), true) + '\n'
}

pub fn run(args []string) {
	result := cli(args) or {
		fail(err.msg(), err.code())
		return
	}
	print(result)
}
