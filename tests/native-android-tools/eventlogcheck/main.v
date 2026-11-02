// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const target = 'android/util/EventLog.smali'
const array_signature = 'writeEvent(I[Ljava/lang/Object;)I'
const utf_signature = 'vinixUtf8Length(Ljava/lang/String;)I'

fn norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || block.count('.end method') != 1 {
			return error('unique complete methods required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn flow(source string) string {
	lines := norm(source).split_into_lines()
	mut labels := map[string]string{}
	mut position := 0
	for line in lines {
		if line.starts_with(':') {
			labels[line] = ':instruction_' + position.str()
		} else {
			position++
		}
	}
	mut result := []string{}
	for line in lines {
		if line in labels { continue }
		last := line.fields().last()
		if (line.starts_with('if-') || line.starts_with('goto')) && last in labels {
			result << line[..line.len - last.len] + labels[last]
		} else {
			result << line
		}
	}
	return result.join('\n')
}

fn verify(source string) ! {
	actual := methods(source)!
	mut expected := {
		'<init>()V': '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method'
	}
	expected[array_signature] = array_program
	expected[utf_signature] = utf_program
	for signature, registers in {
		'writeEvent(II)I':                  3
		'writeEvent(IJ)I':                  4
		'writeEvent(IF)I':                  3
		'writeEvent(ILjava/lang/String;)I': 3
	} {
		expected[signature] = '.method public static ' + signature + '\n.registers ' + registers.str() + '\nconst/16 v0, -0x13\nreturn v0\n.end method'
	}
	if actual.keys().sorted() != expected.keys().sorted() {
		return error('exact five write overloads, constructor and private UTF helper required')
	}
	mut metadata := source
	for name, body in actual {
		if flow(body) != flow(expected[name]) { return error('EventLog method contract: ' + name) }
		metadata = metadata.replace(body, '')
	}
	if norm(metadata) != '.class public Landroid/util/EventLog;\n.super Ljava/lang/Object;' {
		return error('fieldless public EventLog with no native backend required')
	}
}

const array_program = '.method public static varargs writeEvent(I[Ljava/lang/Object;)I
.registers 10
if-eqz p1, :unavailable
const/4 v0, 0x0
const/4 v1, 0x2
array-length v2, p1
const/16 v3, 0xff
const/16 v7, 0xfe0
:next_item
if-ge v0, v2, :unavailable
if-ge v0, v3, :unavailable
aget-object v4, p1, v0
if-eqz v4, :null_item
instance-of v5, v4, Ljava/lang/String;
if-nez v5, :string_item
instance-of v5, v4, Ljava/lang/Integer;
if-nez v5, :fixed_five
instance-of v5, v4, Ljava/lang/Long;
if-nez v5, :fixed_nine
instance-of v5, v4, Ljava/lang/Float;
if-nez v5, :fixed_five
new-instance v4, Ljava/lang/IllegalArgumentException;
const-string v5, "Invalid payload item type"
invoke-direct {v4, v5}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v4
:fixed_five
const/4 v5, 0x5
goto :fixed_item
:fixed_nine
const/16 v5, 0x9
:fixed_item
add-int v6, v1, v5
if-gt v6, v7, :encoding_error
move v1, v6
goto :advance
:null_item
const/4 v5, 0x4
goto :string_length
:string_item
check-cast v4, Ljava/lang/String;
invoke-static {v4}, Landroid/util/EventLog;->vinixUtf8Length(Ljava/lang/String;)I
move-result v5
:string_length
add-int/lit8 v5, v5, 0x5
add-int v6, v1, v5
if-le v6, v7, :string_accepted
add-int/lit8 v5, v1, 0x5
if-ge v5, v7, :encoding_error
:string_accepted
move v1, v6
:advance
add-int/lit8 v0, v0, 0x1
goto :next_item
:encoding_error
const/4 v0, -0x5
return v0
:unavailable
const/16 v0, -0x13
return v0
.end method'

const utf_program = '.method private static vinixUtf8Length(Ljava/lang/String;)I
.registers 9
const/4 v0, 0x0
const/4 v1, 0x0
invoke-virtual {p0}, Ljava/lang/String;->length()I
move-result v2
const/16 v4, 0xfe0
:next_character
if-ge v0, v4, :capped
if-ge v1, v2, :done
invoke-virtual {p0, v1}, Ljava/lang/String;->charAt(I)C
move-result v3
if-eqz v3, :two_bytes
const/16 v5, 0x80
if-lt v3, v5, :one_byte
const/16 v5, 0x800
if-lt v3, v5, :two_bytes
const v5, 0xd800
if-lt v3, v5, :three_bytes
const v5, 0xdc00
if-ge v3, v5, :three_bytes
add-int/lit8 v6, v1, 0x1
if-ge v6, v2, :three_bytes
invoke-virtual {p0, v6}, Ljava/lang/String;->charAt(I)C
move-result v7
const v5, 0xdc00
if-lt v7, v5, :three_bytes
const v5, 0xe000
if-ge v7, v5, :three_bytes
add-int/lit8 v0, v0, 0x4
move v1, v6
goto :advance
:three_bytes
add-int/lit8 v0, v0, 0x3
goto :advance
:one_byte
add-int/lit8 v0, v0, 0x1
goto :advance
:two_bytes
add-int/lit8 v0, v0, 0x2
:advance
add-int/lit8 v1, v1, 0x1
goto :next_character
:capped
move v0, v4
:done
return v0
.end method'

struct Input {
	items      []Item
	null_array bool
	code       int = -19
	throws     bool
}

fn ascii(length int) Item {
	return Item{ kind: 'Ljava/lang/String;', units: []u16{len: length, init: u16(0x61)} }
}

fn suffix(length int, units []u16) Item {
	mut value := []u16{len: length, init: u16(0x61)}
	value << units
	return Item{ kind: 'Ljava/lang/String;', units: value }
}

fn inputs() []Input {
	integer_item := Item{ kind: 'Ljava/lang/Integer;' }
	long_item := Item{ kind: 'Ljava/lang/Long;' }
	float_item := Item{ kind: 'Ljava/lang/Float;' }
	bad := Item{ kind: 'Ljava/lang/Object;' }
	null_item := Item{ kind: 'null' }
	mut cases := [Input{ null_array: true }, Input{},
		Input{ items: [integer_item, long_item, float_item, null_item, ascii(0)] },
		Input{ items: [bad], throws: true },
		Input{ items: [Item{ kind: 'Ljava/lang/Double;' }], throws: true },
		Input{ items: [Item{ kind: '[Ljava/lang/Object;' }], throws: true }]
	for size in [4057, 4058, 6000] {
		cases << Input{ items: [ascii(size)] }
		cases << Input{ items: [ascii(size), bad], throws: true }
		cases << Input{ items: [ascii(size), integer_item, bad], code: -5 }
	}
	for entry in [
		Input{ items: [ascii(4052), integer_item, bad], throws: true },
		Input{ items: [ascii(4053), integer_item, bad], code: -5 },
		Input{ items: [ascii(4048), long_item, bad], throws: true },
		Input{ items: [ascii(4049), long_item, bad], code: -5 },
		Input{ items: [ascii(4052), ascii(0), bad], throws: true },
		Input{ items: [ascii(4053), ascii(0), bad], code: -5 },
		Input{ items: [ascii(4052), ascii(1), bad], code: -5 },
		Input{ items: [ascii(4051), null_item, bad], throws: true },
		Input{ items: [ascii(4052), null_item, bad], code: -5 },
		Input{ items: [ascii(4058), null_item, bad], code: -5 },
	] {
		cases << entry
	}
	for units, prefix in {
		'nul':  4050
		'two':  4050
		'lone': 4049
		'pair': 4048
	} {
		characters := match units {
			'nul' { [u16(0)] }
			'two' { [u16(0x80)] }
			'lone' { [u16(0xd800)] }
			else { [u16(0xd800), u16(0xdc00)] }
		}
		cases << Input{ items: [suffix(prefix, characters), integer_item, bad], throws: true }
		cases << Input{ items: [suffix(prefix + 1, characters), integer_item, bad], code: -5 }
	}
	mut beyond := []Item{len: 255, init: integer_item}
	beyond << bad
	cases << Input{ items: beyond }
	mut processed := beyond.clone()
	processed[254] = bad
	cases << Input{ items: processed, throws: true }
	for kind in ['Ljava/lang/Boolean;', 'Ljava/lang/Byte;', 'Ljava/lang/Short;', 'Ljava/lang/Character;'] {
		cases << Input{ items: [Item{ kind: kind }], throws: true }
	}
	return cases
}

fn behavior(source string) !int {
	surface := methods(source)!
	mut count := 0
	for input_index, input in inputs() {
		argument := if input.null_array {
			Cell{ kind: 'null' }
		} else {
			Cell{ kind: '[Ljava/lang/Object;', items: input.items }
		}
		for tag in [-1, 0, 1397638484] {
			result := evaluate(surface, array_signature, {
				'p0': Cell{ kind: 'number', number: tag }
				'p1': argument
			}, 0)!
			if input.throws {
				if result.thrown != 'Ljava/lang/IllegalArgumentException;' || result.message != 'Invalid payload item type' {
					return error('processed invalid payload did not throw exact exception: case ' + input_index.str())
				}
			} else if result.thrown != '' || result.code != input.code {
				return error('payload/error-priority boundary failed: case ' + input_index.str())
			}
			count++
		}
	}
	for index, input in [
		Item{},
		Item{ units: [u16(0)] },
		Item{ units: [u16(0x7f)] },
		Item{ units: [u16(0x80)] },
		Item{ units: [u16(0x7ff)] },
		Item{ units: [u16(0x800)] },
		Item{ units: [u16(0xd800)] },
		Item{ units: [u16(0xdc00)] },
		Item{ units: [u16(0xd800), u16(0xdc00)] },
		Item{ units: [u16(0xdbff), u16(0xdfff)] },
		ascii(6000),
	] {
		expected := [0, 2, 1, 2, 2, 3, 3, 3, 4, 4, 4064][index]
		result := evaluate(surface, utf_signature, {
			'p0': Cell{ kind: 'Ljava/lang/String;', units: input.units }
		}, 0)!
		if result.thrown != '' || result.code != expected {
			return error('modified UTF8 length or cap failed')
		}
		count++
	}
	for signature in ['writeEvent(II)I', 'writeEvent(IJ)I', 'writeEvent(IF)I',
		'writeEvent(ILjava/lang/String;)I'] {
		result := evaluate(surface, signature, {
			'p0': Cell{ kind: 'number', number: -1 }
			'p1': Cell{ kind: 'null' }
		}, 0)!
		if result.thrown != '' || result.code != -19 {
			return error('scalar unavailable result differs')
		}
		count++
	}
	return count
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 1
			source := os.read_file(work + '/' + directory + '/' + target)!
			verify(source)!
			assert behavior(source)! > 100
		}
		assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!
		println('EVENT-LOG-ROUNDTRIP-PASS five-overloads exact-unavailable-backend modified-UTF8 bounded-payload-execution stable-second-DEX')
		return
	}
	classes := androidtools.framework_event_log_classes()
	assert classes.keys() == ['android/util/EventLog']
	source := classes.values()[0]
	verify(source)!
	case_count := behavior(source)!
	path := work + '/proof/' + target
	for kind in ['file', 'directory', 'symlink'] {
		if kind == 'file' {
			os.write_file(path, 'collision')!
		} else if kind == 'directory' {
			os.mkdir(path)!
		} else {
			os.symlink('absent-event-log', path)!
		}
		mut refused := false
		androidtools.framework_event_log(work + '/proof') or { refused = true }
		assert refused
		if kind == 'directory' {
			assert os.is_dir(path)
			os.rmdir(path)!
		} else if kind == 'symlink' {
			assert os.readlink(path)! == 'absent-event-log'
			os.rm(path)!
		} else {
			assert os.read_file(path)! == 'collision'
			os.rm(path)!
		}
	}
	mut controls := 0
	for change in [
		['.method public static varargs writeEvent(', '.method public static writeEvent('],
		['const/16 v7, 0xfe0', 'const/16 v7, 0x1000'],
		['const/4 v1, 0x2', 'const/4 v1, 0x0'],
		['const/16 v3, 0xff', 'const/16 v3, 0x100'],
		['Ljava/lang/Integer;', 'Ljava/lang/Number;'],
		['const/4 v5, 0x5', 'const/4 v5, 0x4'],
		['const/16 v5, 0x9', 'const/16 v5, 0x8'],
		['const/4 v5, 0x4', 'const/4 v5, 0x6'],
		['if-gt v6, v7, :encoding_error', 'if-ge v6, v7, :encoding_error'],
		['if-ge v5, v7, :encoding_error', 'if-gt v5, v7, :encoding_error'],
		['move v1, v6', 'move v1, v7'],
		['const/4 v0, -0x5', 'const/16 v0, -0x13'],
		['const/16 v0, -0x13', 'const/4 v0, 0x0'],
		['if-eqz v3, :two_bytes', 'if-eqz v3, :one_byte'],
		['add-int/lit8 v0, v0, 0x4', 'add-int/lit8 v0, v0, 0x6'],
		['add-int/lit8 v0, v0, 0x3', 'add-int/lit8 v0, v0, 0x2'],
		['const v5, 0xd800', 'const/16 v5, 0xd800'],
		['Invalid payload item type', 'wrong payload error'],
	] {
		broken := source.replace(change[0], change[1])
		assert broken != source
		mut refused := false
		verify(broken) or { refused = true }
		assert refused, 'event payload, error, shape or UTF mutant escaped exact oracle'
		controls++
	}
	mut refused := false
	verify(source + '\n.field private fakeEvents:Ljava/util/List;\n') or { refused = true }
	assert refused
	mut unknown := methods(source)!
	unknown[utf_signature] = '.method private static ' + utf_signature + '\n.registers 9\nnop\nreturn v0\n.end method'
	mut unsupported := false
	evaluate(unknown, utf_signature, {
		'p0': Cell{ kind: 'Ljava/lang/String;' }
	}, 0) or { unsupported = true }
	assert unsupported, 'instruction evaluator must refuse unknown opcodes'
	androidtools.framework_event_log(work + '/proof')!
	assert os.read_file(path)! == source
	assert os.walk_ext(work + '/proof', '.smali').len == 1
	println('EVENT-LOG-SOURCE-PASS collision-refusals=3 semantic-controls=' + (controls + 1).str() + ' interpreted-inputs=' + case_count.str() + ' no-success-or-event-store')
}
