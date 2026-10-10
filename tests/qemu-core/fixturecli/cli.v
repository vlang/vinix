// SPDX-License-Identifier: BSD-2-Clause
module fixturecli

import fixturehost

pub const kinds = ['signal', 'touch', 'restart', 'nanosleep', 'blocked', 'poll', 'epoll', 'int']

pub struct Options {
pub mut:
	output  string
	arch    string
	cc      string = 'clang'
	prepare bool
	native  bool
	guest   bool
	help    bool
}

fn host_arch() string {
	$if arm64 {
		return 'arm64'
	} $else {
		return 'amd64'
	}
}

fn usage(kind string) string {
	if kind == 'generate' { return 'usage: compile-fixtures OUTPUT --arch {arm64,amd64}' }
	return 'usage: test-${kind}fixture OUTPUT [--cc CC] [--arch {arm64,amd64}]\n' +
		'       [--prepare-only | --native-build] [--guest]'
}

fn negative_number(text string) bool {
	if text.len < 2 || text[0] != `-` { return false }
	value := text[1..]
	if value.bytes().all(it.is_digit()) { return true }
	return value.count('.') == 1 && value.all_after('.').len > 0
		&& value.all_before('.').bytes().all(it.is_digit()) && value.all_after('.').bytes().all(it.is_digit())
}

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

// Retain eager help and validate mutually exclusive actions when consumed,
// before file staging. The generator and all eight comparisons share this CLI.
pub fn parse_options(kind string, args []string) !Options {
	mut options := Options{ arch: if kind == 'touch' { host_arch() } else { '' } }
	allowed := if kind == 'generate' {
		['--help', '--arch']
	} else {
		['--help', '--cc', '--arch', '--prepare-only', '--native-build', '--guest']
	}
	mut unknown := []string{}
	mut have_output := false
	mut positional := false
	mut index := 0
	for index < args.len {
		argument := args[index]
		index++
		if !positional && argument == '--' {
			positional = true
			continue
		}
		if !positional && argument.starts_with('-h') {
			if argument[1..].bytes().all(it == `h`) {
				options.help = true
				return options
			}
			return error('argument -h/--help: ignored explicit argument')
		}
		name := argument.all_before('=')
		mut matches := if !positional && name.starts_with('--') {
			allowed.filter(it.starts_with(name))
		} else {
			[]string{}
		}
		if !positional && name in allowed { matches = [name] }
		if matches.len > 1 { return error('ambiguous option: ${name}') }
		if matches.len == 1 {
			option := matches[0]
			if option in ['--help', '--prepare-only', '--native-build', '--guest'] {
				if argument.contains('=') {
					return error('argument ${option}: ignored explicit argument')
				}
				match option {
					'--help' {
						options.help = true
						return options
					}
					'--prepare-only' {
						if options.native {
							return error('argument --prepare-only: not allowed with argument --native-build')
						}
						options.prepare = true
					}
					'--native-build' {
						if options.prepare {
							return error('argument --native-build: not allowed with argument --prepare-only')
						}
						options.native = true
					}
					else { options.guest = true }
				}
				continue
			}
			mut value := argument.all_after('=')
			if !argument.contains('=') {
				if index == args.len || (args[index].starts_with('-') && args[index] != '-' && !negative_number(args[index])) {
					return error('argument ${option}: expected one argument')
				}
				value = args[index]
				index++
			}
			if option == '--arch' {
				if value !in ['arm64', 'amd64'] {
					return error('argument --arch: invalid choice: ${value}')
				}
				options.arch = value
			} else {
				options.cc = value
			}
		} else if !positional && argument.starts_with('-') && argument != '-' && !negative_number(argument) {
			unknown << argument
		} else if !have_output {
			options.output = path_value(argument)
			have_output = true
		} else {
			unknown << argument
		}
	}
	if !have_output { return error('the following arguments are required: output') }
	if kind == 'generate' && options.arch == '' {
		return error('the following arguments are required: --arch')
	}
	if unknown.len > 0 { return error('unrecognized arguments: ${unknown.join(' ')}') }
	if options.native && options.arch == '' { return error('--native-build requires --arch') }
	return options
}

pub fn execute(kind string, options Options) ! {
	if kind == 'generate' {
		fixturehost.generate(options.output, options.arch)!
	} else if options.native {
		fixturehost.prepare(kind, options.output, options.arch, true)!
		if kind in ['signal', 'restart', 'touch'] {
			reference := if kind == 'signal' { 'original-signals' } else { 'original-' + kind }
			fixturehost.native_helper(kind, options.output, options.arch, reference)!
		} else {
			fixturehost.native_build(kind, options.output, options.arch)!
		}
	} else if options.prepare {
		fixturehost.prepare(kind, options.output, if options.arch == '' {
			'arm64'
		} else {
			options.arch
		}, options.guest)!
	} else {
		fixturehost.host(kind, options.output, options.cc, if options.arch == '' {
			host_arch()
		} else {
			options.arch
		})!
	}
}

pub fn run(kind string, args []string) {
	options := parse_options(kind, args) or {
		eprintln(usage(kind))
		eprintln(err.msg())
		exit(2)
	}
	if options.help {
		println(usage(kind))
		println('\nGenerate native V fixtures or compare them with the provenance-checked immutable C oracle.')
		return
	}
	execute(kind, options) or {
		eprintln(err.msg())
		exit(1)
	}
}
