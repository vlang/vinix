module imageextract

import crypto.sha256
import encoding.hex
import os
import traceanalysis as j

struct Options {
mut:
	source        string
	preboot       string = '/System/Volumes/Preboot'
	output        string
	variant       string = 'g17c'
	platform_name string
	entries       []string
	list          bool
}

fn usage(mode string) string {
	return match mode {
		'extract_firmware' {
			'usage: extract_firmware [-h] [--source-dir SOURCE_DIR] [--preboot PREBOOT]\n                        [--output OUTPUT] [--variant VARIANT]'
		}
		'extract_pmp_firmware' {
			'usage: extract_pmp_firmware [-h] [--firmware FIRMWARE] [--preboot PREBOOT]\n                            [--output OUTPUT]'
		}
		else {
			'usage: extract_fileset [-h] [--kernel KERNEL] [--platform PLATFORM]\n                       [--preboot PREBOOT] [--output OUTPUT] [--entry ENTRIES]\n                       [--list]'
		}
	}
}

fn fail(mode string, message string) {
	eprintln(usage(mode))
	eprintln('${mode}: error: ${message}')
	exit(2)
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
	for index in 1 .. text.len {
		if text[index] == `.` && dot == -1 {
			dot = index
		} else if text[index] < `0` || text[index] > `9` {
			return false
		}
	}
	return dot == -1 || dot < text.len - 1
}

fn classify(mode string, args []string, allowed []string) []Argument {
	mut tokens := []Argument{}
	mut positional := false
	for raw in args[1..] {
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
				fail(mode, 'ambiguous option: ${raw} could match ${matches.join(', ')}')
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

fn parse_options(mode string, args []string) Options {
	mut options := Options{
		output: match mode {
			'extract_firmware' { 'build/firmware/g17c' }
			'extract_pmp_firmware' { 'build/firmware/t6050pmp' }
			else { 'build/kext/g17c' }
		}
	}
	allowed := match mode {
		'extract_firmware' { ['--help', '--source-dir', '--preboot', '--output', '--variant'] }
		'extract_pmp_firmware' { ['--help', '--firmware', '--preboot', '--output'] }
		else { ['--help', '--kernel', '--platform', '--preboot', '--output', '--entry', '--list'] }
	}
	tokens := classify(mode, args, allowed)
	mut extras := []string{}
	mut index := 0
	for index < tokens.len {
		token := tokens[index]
		index++
		if token.option == '' {
			extras << token.raw
			continue
		}
		if token.option in ['-h/--help', '--list'] {
			if token.explicit {
				fail(mode, 'argument ${token.option}: ignored explicit argument ${j.quoted(token.value)}')
			}
			if token.option == '-h/--help' {
				println(usage(mode))
				println('\nExtract local Apple images using the native V image parser.\n\n--preboot PREBOOT  Local Preboot directory.\n--output OUTPUT    Directory for extracted images and manifest.json.')
				exit(0)
			}
			options.list = true
			continue
		}
		mut value := token.value
		if !token.explicit {
			if index == tokens.len || tokens[index].optional || tokens[index].raw == '--' {
				fail(mode, 'argument ${token.option}: expected one argument')
			}
			value = tokens[index].raw
			index++
		}
		match token.option {
			'--source-dir', '--firmware', '--kernel' { options.source = path_value(value) }
			'--preboot' { options.preboot = path_value(value) }
			'--output' { options.output = path_value(value) }
			'--variant' { options.variant = value }
			'--platform' { options.platform_name = value }
			'--entry' { options.entries << value }
			else {}
		}
	}
	if extras.len != 0 { fail(mode, 'unrecognized arguments: ${extras.join(' ')}') }
	return options
}

fn read_file(path string) ![]u8 {
	if !os.exists(path) { return error('[Errno 2] No such file or directory: ${j.quoted(path)}') }
	if os.is_dir(path) { return error('[Errno 21] Is a directory: ${j.quoted(path)}') }
	return os.read_bytes(path)
}

fn save(path string, bytes []u8) ! {
	mut file := os.create(path)!
	defer { file.close() }
	file.write(bytes)!
}

fn digest(data []u8) string { return hex.encode(sha256.sum(data)) }

struct Output {
	identifier string
	filename   string
	data       []u8
	metadata   map[string]j.Value
}

fn execute(mode string, options Options) !map[string]j.Value {
	mut source := options.source
	if source == '' {
		source = find_source(options.preboot, match mode {
			'extract_firmware' { 'firmware' }
			'extract_pmp_firmware' { 'pmp' }
			else {
				if options.platform_name == '' { 'kernel' } else { 'platform' }
			}
		}, options.platform_name)!
	}
	mut outputs := []Output{}
	mut manifest := map[string]j.Value{}
	if mode == 'extract_firmware' {
		for position, input_name in ['armfw_g17x.im4p', 'armfw1_g17x.im4p'] {
			path := path_value(os.join_path(source, input_name))
			// Report filesystem errors with the original CLI's path spelling.
			read_file(path)!
			tag, image := select_variant(path, options.variant)!
			outputs << Output{input_name, if position == 0 { 'armfw.bin' } else { 'armfw1.bin' }, image, {
				'entry': j.Value(tag)
			}}
		}
		manifest = {
			'schema':  j.Value(1)
			'variant': j.Value(options.variant)
			'source':  j.Value(source)
		}
	} else if mode == 'extract_pmp_firmware' {
		blob := read_file(source)!
		span := pmp_payload(blob)!
		image := blob[span.start..span.end]
		mut metadata := macho_metadata(image)!
		for key, value in pmp_command_summary(image)! { metadata[key] = value }
		outputs << Output{'', 'pmp.macho', image, metadata}
		manifest = {
			'schema':   j.Value(1)
			'firmware': j.Value('t6050pmp')
			'source':   j.Value(source)
		}
	} else {
		blob := read_file(source)!
		span := kernel_im4p_payload(blob)!
		collection := decompress_kernel(blob[span.start..span.end], 0)!
		available := fileset_entries(collection)!
		if options.list {
			mut names := available.keys()
			names.sort()
			mut values := []j.Value{}
			for name in names { values << j.Value(name) }
			return {
				'source':  j.Value(source)
				'entries': j.Value(values)
			}
		}
		identifiers := if options.entries.len != 0 { options.entries } else { default_entries }
		for identifier in identifiers {
			entry := available[identifier] or { return error('kernel collection has no fileset entry ${identifier}') }
			image := extract_entry(collection, int(entry.file_offset))!
			outputs << Output{identifier, identifier.trim_string_left('com.apple.') + '.macho', image, map[string]j.Value{}}
		}
		manifest = {
			'schema':           j.Value(1)
			'source':           j.Value(source)
			'collection_bytes': j.Value(collection.len)
		}
	}
	os.mkdir_all(options.output)!
	mut records := []j.Value{}
	for output in outputs {
		save(os.join_path(options.output, output.filename), output.data)!
		mut metadata := output.metadata
		mut record := map[string]j.Value{
			'file':   j.Value(output.filename)
			'bytes':  j.Value(output.data.len)
			'sha256': j.Value(digest(output.data))
		}
		if mode == 'extract_firmware' {
			record['container'] = j.Value(output.identifier)
			record['entry'] = j.value(metadata, 'entry')
			metadata = macho_metadata(output.data)!
		} else if mode == 'extract_fileset' {
			record['identifier'] = j.Value(output.identifier)
			metadata = macho_identity(output.data)!
		}
		record['macho'] = j.Value(metadata)
		records << j.Value(record)
	}
	if mode == 'extract_pmp_firmware' {
		manifest['image'] = records[0]
	} else {
		manifest[if mode == 'extract_firmware' { 'images' } else { 'entries' }] = j.Value(records)
	}
	os.write_file(os.join_path(options.output, 'manifest.json'), j.encode(j.Value(manifest), true) + '\n')!
	return manifest
}

pub fn run(mode string, args []string) {
	options := parse_options(mode, args)
	manifest := execute(mode, options) or {
		fail(mode, err.msg())
		map[string]j.Value{}
	}
	println(j.encode(j.Value(manifest), true))
}
