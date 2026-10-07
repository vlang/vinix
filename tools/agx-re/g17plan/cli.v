module g17plan

import traceanalysis { Value }
import json2
import math.big
import os

fn option_token(text string) bool {
	if text.len < 2 || !text.starts_with('-') { return false }
	if text.starts_with('--') { return true }
	// argparse treats negative decimal integers/floats as values, unless
	// a parser defines a matching negative option (these tools do not).
	digits := text[1..]
	if digits.bytes().all(it.is_digit()) { return false }
	pieces := digits.split('.')
	if pieces.len == 2 && pieces[1].len > 0 && pieces[0].bytes().all(it.is_digit()) && pieces[1].bytes().all(it.is_digit()) {
		return false
	}
	return true
}

fn parse_options(args []string, allowed []string, flags []string, required_options []string) !map[string]string {
	mut output := map[string]string{}
	mut unknown := []string{}
	mut options := allowed.clone()
	options << flags
	options << '--help'
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
				return error_with_code('argument -h/--help: ignored explicit argument', 102)
			}
			output['--help'] = '1'
			return output
		}
		raw_key := token.all_before('=')
		mut key := raw_key
		if key !in options {
			candidates := if key.starts_with('--') {
				options.filter(it.starts_with(key))
			} else {
				[]string{}
			}
			if candidates.len > 1 {
				return error_with_code('ambiguous option: ${key} could match ' + candidates.join(', '), 102)
			}
			if candidates.len == 1 {
				key = candidates[0]
			} else {
				unknown << token
				continue
			}
		}
		if key in flags || key == '--help' {
			if raw_key != token {
				return error_with_code('argument ${key}: ignored explicit argument', 102)
			}
			output[key] = '1'
			if key == '--help' { return output }
			continue
		}
		mut value := ''
		if raw_key != token {
			value = token[raw_key.len + 1..]
		} else {
			if index >= args.len || option_token(args[index]) {
				return error_with_code('argument ${key}: expected one argument', 102)
			}
			value = args[index]
			index++
		}
		if key in ['--command-gpu-address', '--column-count'] {
			address_integer(value)!
		} else if value == '' {
			value = '.'
		}
		output[key] = value
	}
	missing := required_options.filter(it !in output)
	if missing.len > 0 {
		return error_with_code('the following arguments are required: ' + missing.join(', '), 102)
	}
	if unknown.len > 0 {
		return error_with_code('unrecognized arguments: ' + unknown.join(' '), 102)
	}
	return output
}

fn input_abi(path string) !map[string]Value { return decode(os.read_file(path)!) }

fn address_integer(value string) !big.Integer {
	return signed_string_integer(value, 'address') or { return error_with_code('invalid address ${repr(Value(value))}', 102) }
}

fn gpu_address(value string) !u64 {
	parsed := address_integer(value)!
	if parsed <= big.zero_int || parsed > big.integer_from_u64(word_mask) {
		return error('command GPU address must be a nonzero u64')
	}
	return scalar(Value(parsed.str()), 'address')
}

fn generator_command(options map[string]string, base string) ! {
	abi_path := options['--abi'] or { os.join_path(base, 'build/recovered-g17-abi.json') }
	header_path := options['--header-output'] or { os.norm_path(os.join_path(base, '../../kernel/c/agx_fake_g17_encode.h')) }
	source_path := options['--output'] or { os.norm_path(os.join_path(base, '../../kernel/lib/agx_fake_g17_encode.v')) }
	result := generate(input_abi(abi_path)!, os.read_file(os.join_path(base, 'templates/fake_g17_encoder.v.in'))!, os.read_file(os.join_path(base, 'templates/fake_g17_encoder.h.in'))!)!
	if '--check' in options {
		if os.read_file(header_path)! != result.header {
			return error('generated header differs: ${header_path}')
		}
		if os.read_file(source_path)! != result.source {
			return error('generated source differs: ${source_path}')
		}
	} else {
		os.write_file(header_path, result.header)!
		os.write_file(source_path, result.source)!
	}
}

fn plan_command(options map[string]string) ! {
	mut hardware := map[string]u64{}
	if '--column-count' in options {
		hardware['column_count'] = masked_integer(Value(traceanalysis.Number{address_integer(options['--column-count'])!.str()}), 'column_count')!
	}
	abi := fold_accelerator_inputs(input_abi(options['--abi'])!, hardware)!
	plan := compile_plan(abi, os.read_bytes(options['--command'])!, os.read_bytes(options['--descriptor'])!, gpu_address(options['--command-gpu-address'])!)!
	result := encode(Value(plan), true) + '\n'
	if '--output' in options { os.write_file(options['--output'], result)! } else { print(result) }
}

fn encoder_command(options map[string]string) ! {
	mut template := ?[]u8(none)
	if '--template' in options { template = os.read_bytes(options['--template'])! }
	externals := if '--externals' in options {
		traceanalysis.decode(os.read_file(options['--externals'])!)!
	} else {
		Value(json2.null)
	}
	result := encode_3d(input_abi(options['--abi'])!, os.read_bytes(options['--descriptor'])!, gpu_address(options['--command-gpu-address'])!, template, externals)!
	os.write_file_array(options['--command-output'], result.command)!
	os.write_file_array(options['--descriptor-output'], result.descriptor)!
	os.write_file(options['--plan-output'], encode(Value(result.plan), true) + '\n')!
}

pub fn cli(kind string, args []string, base string) int {
	allowed := match kind {
		'generator' { ['--abi', '--header-output', '--output'] }
		'plan' {
			['--abi', '--command', '--descriptor', '--command-gpu-address', '--column-count', '--output']
		}
		else {
			['--abi', '--descriptor', '--command-gpu-address', '--template', '--externals',
				'--command-output', '--descriptor-output', '--plan-output']
		}
	}
	flags := if kind == 'generator' {
		['--check']
	} else if kind == 'encode' {
		['--zero-template']
	} else {
		[]string{}
	}
	required_options := match kind {
		'generator' { []string{} }
		'plan' { ['--abi', '--command', '--descriptor', '--command-gpu-address'] }
		else {
			['--abi', '--descriptor', '--command-gpu-address', '--command-output', '--descriptor-output',
				'--plan-output']
		}
	}
	options := parse_options(args, allowed, flags, required_options) or {
		eprintln('fake-G17 ${kind}: ${err.msg()}')
		return 2
	}
	if '--help' in options {
		println('fake-G17 ${kind}: ' + allowed.join(' ') + ' ' + flags.join(' '))
		return 0
	}
	for key in ['--command-gpu-address', '--column-count'] {
		if key in options {
			address_integer(options[key]) or {
				eprintln('fake-G17 ${kind}: ${err.msg()}')
				return 2
			}
		}
	}
	if kind == 'encode' && (('--template' in options) == ('--zero-template' in options)) {
		eprintln('fake-G17 encode: exactly one of --template and --zero-template is required')
		return 2
	}
	if kind == 'generator' {
		generator_command(options, base) or {
			println('fake-G17 generator: ${err.msg()}')
			return if err.code() == 102 { 2 } else { 1 }
		}
	} else if kind == 'plan' {
		plan_command(options) or {
			eprintln('fake-G17 plan: ${err.msg()}')
			return if err.code() == 102 { 2 } else { 1 }
		}
	} else {
		encoder_command(options) or {
			eprintln('fake-G17 encode: ${err.msg()}')
			return if err.code() == 102 { 2 } else { 1 }
		}
	}
	return 0
}
