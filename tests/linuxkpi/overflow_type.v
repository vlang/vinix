// SPDX-License-Identifier: GPL-2.0-or-later
// Independent integer oracle and native overflow compiler-fixture controller.
module main

import os
import json2
import math.big
import hosttest

const macros = ['__type_half_max', '__type_max', 'type_max', '__type_min', 'type_min',
	'__overflows_type_constexpr', '__overflows_type', 'overflows_type', 'castable_to_type']
const original_revision = 'd0a65f5953058f4f7542cd588acbb38039491c04'
const original_path = 'kernel/linuxkpi/include/linux/overflow.h'

fn command(argv []string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	if result.code != 0 { return error(result.stdout + result.stderr) }
	return result
}

fn json_field(values map[string]json2.Any, name string) !json2.Any {
	return values[name] or { return error('Missing original compiler-contract field: ' + name) }
}

fn macro_body(text string, name string) !string {
	marker := '#define ' + name + '('
	mut start := 0
	for line in text.split_into_lines() {
		if line.starts_with(marker) {
			mut end := start
			for end < text.len {
				line_end := end + (text[end..].index('\n') or { text.len - end })
				continuation := text[end..line_end].ends_with('\\')
				end = if line_end < text.len { line_end + 1 } else { line_end }
				if !continuation { break }
			}
			return text[start..end]
		}
		start += line.len + 1
	}
	return error('Missing macro ' + name)
}

struct NativeType {
	name string
	minimum big.Integer
	maximum big.Integer
}

fn native_types() []NativeType {
	one := big.integer_from_int(1)
	zero := big.integer_from_int(0)
	mut result := []NativeType{}
	for width in [8, 16, 32, 64] {
		half := one.left_shift(u32(width - 1))
		result << NativeType{name: 's' + width.str(), minimum: zero - half, maximum: half - one}
		result << NativeType{name: 'u' + width.str(), minimum: zero, maximum: one.left_shift(u32(width)) - one}
	}
	return result
}

fn literal(value big.Integer) string {
	if value == big.integer_from_string('-9223372036854775808') or { panic(err) } {
		return '(-9223372036854775807LL - 1LL)'
	}
	return value.str() + (if value > big.integer_from_string('9223372036854775807') or { panic(err) } { 'ULL' } else { 'LL' })
}

fn test_source() (string, int) {
	mut lines := [test_prefix]
	mut cases := 0
	one := big.integer_from_int(1)
	types := native_types()
	for source in types {
		lines << '    _Static_assert(type_min(${source.name}) == ${literal(source.minimum)}, "${source.name} minimum");'
		lines << '    _Static_assert(type_max(${source.name}) == ${literal(source.maximum)}, "${source.name} maximum");'
		lines << '    _Static_assert(__same_type(type_min(${source.name}), ${source.name}), "minimum type");'
		lines << '    _Static_assert(__same_type(type_max(${source.name}), ${source.name}), "maximum type");'
		for target in types {
			candidates := [source.minimum, source.minimum + one, source.maximum - one, source.maximum,
				big.integer_from_int(-1), big.integer_from_int(0), one,
				target.minimum - one, target.minimum, target.minimum + one,
				target.maximum - one, target.maximum, target.maximum + one]
			mut selected := []big.Integer{}
			for candidate in candidates {
				if candidate >= source.minimum && candidate <= source.maximum && candidate !in selected { selected << candidate }
			}
			selected.sort(a < b)
			for value in selected {
				expression := '((' + source.name + ')(' + literal(value) + '))'
				overflow := if value < target.minimum || value > target.maximum { 1 } else { 0 }
				same_type := if source.name == target.name { 1 } else { 0 }
				lines << test_case.replace('@source@', source.name).replace('@target@', target.name)
					.replace('@expression@', expression).replace('@overflow@', overflow.str())
					.replace('@1 - overflow@', (1 - overflow).str()).replace('@same_type@', same_type.str())
					.replace('@literal(target_min)@', literal(target.minimum)).replace('@literal(target_max)@', literal(target.maximum))
				cases++
			}
		}
	}
	lines << test_suffix
	return lines.join('\n'), cases
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	header := os.join_path(root, original_path)
	original := os.join_path(linux, 'include/linux/overflow.h')
	production_text := os.read_file(header)!
	original_text := os.read_file(original)!
	metadata_path := os.join_path(root, 'kernel/linuxkpi/abi/overflow.json')
	schema := hosttest.decode_json(os.read_file(metadata_path)!)!.as_map()
	boundary := json_field(schema, 'boundary')!.as_map()
	if json_field(boundary, 'original_revision')!.str() != original_revision || json_field(boundary, 'original_path')!.str() != original_path {
		return error('Original compiler-contract provenance changed')
	}
	immutable := command(['git', '-C', root, 'show', original_revision + ':' + original_path])!.stdout
	blob := command(['git', '-C', root, 'rev-parse', original_revision + ':' + original_path])!.stdout.trim_space()
	if blob != json_field(boundary, 'original_blob')!.str() || hosttest.text_sha(immutable) != json_field(boundary, 'original_sha256')!.str() {
		return error('Original compiler-contract source fingerprint changed')
	}
	mut fingerprints := map[string]string{}
	for item in json_field(boundary, 'native_constant_expression_macros')!.as_array() {
		metadata := item.as_map()
		fingerprints[json_field(metadata, 'name')!.str()] = json_field(metadata, 'sha256')!.str()
	}
	if fingerprints.len != macros.len || macros.any(it !in fingerprints) { return error('Original compiler-contract macro inventory changed') }
	for name in macros {
		pinned := macro_body(original_text, name)!
		if macro_body(immutable, name)! != pinned || hosttest.text_sha(pinned) != fingerprints[name] {
			return error(name + ' differs from the immutable pinned original')
		}
		if production_text.split_into_lines().any(it.starts_with('#define ' + name + '(')) {
			return error(name + ' is still a maintained C implementation')
		}
	}
	for declaration in ['size_t array_size(size_t, size_t);', 'size_t size_add(size_t, size_t);', 'size_t size_mul(size_t, size_t);'] {
		if !production_text.contains(declaration) { return error('Existing V ABI declaration changed: ' + declaration) }
	}
	work := hosttest.work_dir(keep, 'vinix-overflow-type-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or {} } }
	preload := os.join_path(work, 'preload.h')
	os.write_file(preload, '#include "' + os.join_path(root, 'tests/linuxkpi/host_types.h') + '"\n#include <stdio.h>\n#include <stdint.h>\n')!
	source, cases := test_source()
	os.write_file(os.join_path(work, 'test.c'), source)!
	os.write_file(os.join_path(work, 'probe.c'), probe)!
	os.write_file(os.join_path(work, 'file-scope.c'), file_scope)!
	hosttest.generate_abi(metadata_path, os.join_path(root, 'kernel/linuxkpi'), os.join_path(work, 'include/vinix/integer_policy.h'))!
	common := [hosttest.env_default('CC', 'clang'), '-O1', '-g', '-ffreestanding',
		'-fno-builtin', '-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-DVINIX_LINUXKPI_HOST_TEST',
		'-D__KERNEL__', '-D_FORTIFY_SOURCE=0', '-include', preload, '-include', 'linux/kconfig.h',
		'-include', os.join_path(linux, 'include/linux/compiler_types.h'), '-I' + os.join_path(work, 'include'),
		'-I' + os.join_path(root, 'kernel/linuxkpi/include'), '-I' + os.join_path(linux, 'include'),
		'-I' + os.join_path(linux, 'include/uapi'), '-I' + os.join_path(linux, 'arch/x86/include'),
		'-I' + os.join_path(linux, 'arch/x86/include/uapi')]
	mut results := map[string]json2.Any{}
	for implementation in ['production', 'pinned'] {
		include := os.join_path(work, implementation)
		os.mkdir(include)!
		os.write_file(os.join_path(include, 'overflow_under_test.h'), if implementation == 'production' {
			'#include <linux/overflow.h>\n'
		} else { '#include "' + original + '"\n' })!
		for standard in ['gnu99', 'gnu11'] {
			tag := implementation + '-' + standard
			flags := [...common, '-std=' + standard, '-I' + include]
			executable := os.join_path(work, tag + '-test')
			command([...flags, '-fsanitize=address,undefined', '-fno-omit-frame-pointer', os.join_path(work, 'test.c'), '-o', executable])!
			mut env := os.environ()
			env['UBSAN_OPTIONS'] = 'halt_on_error=1'
			env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
			result := hosttest.capture([executable], '', 30, env)!
			os.write_file(os.join_path(work, tag + '-run.log'), result.stdout + result.stderr)!
			if result.code != 0 { return error(result.stdout + result.stderr) }
			println(tag + ': ' + result.stdout.trim_space())
			object := os.join_path(work, tag + '-probe.o')
			command([...flags, '-c', os.join_path(work, 'probe.c'), '-o', object])!
			imports := command(['nm', '-u', object])!.stdout
			os.write_file(os.join_path(work, tag + '-probe-undefined.txt'), imports)!
			if imports.trim_space() != '' { return error('Overflow type helpers import runtime symbols:\n' + imports) }
			invalid := hosttest.capture([...flags, '-fsyntax-only', os.join_path(work, 'file-scope.c')], '', -1, os.environ())!
			os.write_file(os.join_path(work, tag + '-file-scope.log'), invalid.stderr)!
			if invalid.code == 0 || !invalid.stderr.contains('statement expression not allowed at file scope') { return error('Original file-scope restriction changed:\n' + invalid.stderr) }
			results[tag] = {'stdout': json2.Any(result.stdout), 'stderr': result.stderr, 'probe_runtime_imports': imports, 'original_file_scope_limitation': invalid.code}
		}
	}
	mut host := ''
	$if arm64 { host = 'arm64' } $else $if amd64 { host = 'x86_64' } $else { host = os.uname().machine }
	hosttest.write_json(os.join_path(work, 'result.json'), {
		'scope': json2.Any('Generated production and exact pinned headers, GNU99/GNU11 strict host ASan/UBSan independent boundary matrix, ICE and evaluation checks. Compiler-only feature: no allocation, native or GPU support claim.'),
		'host': host, 'header_sha256': hosttest.sha(header)!, 'pinned_header_sha256': hosttest.sha(original)!,
		'test_sha256': hosttest.sha(@FILE)!, 'native_metadata_sha256': hosttest.sha(metadata_path)!,
		'exact_pinned_macros': hosttest.strings(macros), 'boundary_cases': cases, 'results': results
	})!
	println('LinuxKPI overflow types: immutable pinned macro provenance, ' + cases.str() + ' independent boundary cases; single evaluation and ICE contracts passed')
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: overflow_type.v [--keep-dir DIRECTORY]',
		'Check the pinned overflow type macros against independent integer bounds.') or { eprintln(err.msg()); exit(2) }
	run_profile(keep) or { eprintln(err.msg()); exit(1) }
}

const probe = '
#include "overflow_under_test.h"
bool narrow_signed(s64 value) { return overflows_type(value, s8); }
bool narrow_unsigned(u64 value) { return overflows_type(value, u32); }
bool negative_unsigned(s64 value) { return overflows_type(value, u64); }
bool unsigned_signed(u64 value) { return overflows_type(value, s64); }
'

const file_scope = '
#include "overflow_under_test.h"
enum { unsupported_file_scope = overflows_type((s64)127, s8) };
'

const test_prefix = '
#include "overflow_under_test.h"
static unsigned assertions, source_calls, target_calls;
static s64 supplied;
static u8 destination;

#define CHECK(condition) do { \\
    assertions++; \\
    if (!(condition)) { \\
        fprintf(stderr, "overflow type assertion failed at line %d: %s\\n", \\
                __LINE__, #condition); \\
        abort(); \\
    } \\
} while (0)

static s64 next_source(void) { source_calls++; return supplied; }
static u8 *next_target(void) { target_calls++; return &destination; }

_Static_assert(type_min(s64) == (-9223372036854775807LL - 1LL), "signed minimum ICE");
_Static_assert(type_max(u64) == 18446744073709551615ULL, "unsigned maximum ICE");
_Static_assert(castable_to_type((s64)127, s8), "file-scope castable constant ICE");
_Static_assert(!castable_to_type((s64)128, s8), "file-scope castable overflow ICE");

int main(void) {
    CHECK(type_min(_Bool) == 0 && type_max(_Bool) == 1);
'

const test_suffix = '
    supplied = 256;
    CHECK(overflows_type(next_source(), *next_target()));
    CHECK(source_calls == 1 && target_calls == 0);
    source_calls = target_calls = 0;
    CHECK(!castable_to_type(next_source(), *next_target()));
    CHECK(source_calls == 0 && target_calls == 0);
    s64 changing = -1;
    CHECK(overflows_type(changing++, destination++));
    CHECK(changing == 0 && destination == 0);
    changing = 255;
    CHECK(!overflows_type(changing++, destination++));
    CHECK(changing == 256 && destination == 0);
    changing = 123;
    CHECK(!castable_to_type(changing++, destination++));
    CHECK(changing == 123 && destination == 0);
    CHECK(type_min(*next_target()) == 0 && type_max(*next_target()) == 255);
    CHECK(target_calls == 0);
    printf("LinuxKPI overflow types: %u assertions passed\\n", assertions);
    return 0;
}
'

const test_case = '    {
        volatile @source@ changing = @expression@;
        @target@ target = 0;
        _Static_assert(__is_constexpr(overflows_type(@expression@, @target@)), "overflow remains ICE");
        _Static_assert(overflows_type(@expression@, @target@) == @overflow@, "constant boundary");
        _Static_assert(castable_to_type(@expression@, @target@) == @1 - overflow@, "constant castability");
        _Static_assert(__is_constexpr(castable_to_type(@expression@, @target@)), "castability remains ICE");
        CHECK(overflows_type(changing, @target@) == @overflow@);
        CHECK(overflows_type(changing, target) == @overflow@);
        CHECK(__overflows_type(changing, @target@) == @overflow@);
        CHECK(__overflows_type_constexpr(@expression@, target) == @overflow@);
        CHECK(castable_to_type(changing, @target@) == @same_type@);
        CHECK(castable_to_type(changing, target) == @same_type@);
        CHECK(target == 0);
        CHECK(type_min(target) == @literal(target_min)@);
        CHECK(type_max(target) == @literal(target_max)@);
    }'
