// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const build = 'android/os/Build.smali'
const properties = 'android/os/SystemProperties.smali'
const version = 'android/os/Build$VERSION.smali'
const helper = 'getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;'
const all_anchor = 'sput-object v0, Landroid/os/Build;->SUPPORTED_ABIS:[Ljava/lang/String;'
const arm_anchor = 'const-string v1, "ro.product.cpu.abilist"\nconst-string v2, "arm64-v8a"\ninvoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;'
const build_insert = 'const-string v0, "ro.product.cpu.abilist64"
const-string v1, ","
invoke-static {v0, v1}, Landroid/os/Build;->getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
sput-object v0, Landroid/os/Build;->SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;
const-string v0, "ro.product.cpu.abilist32"
const-string v1, ","
invoke-static {v0, v1}, Landroid/os/Build;->getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
sput-object v0, Landroid/os/Build;->SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;'
const property_insert = 'const-string v1, "ro.product.cpu.abilist64"
const-string v2, "arm64-v8a"
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
const-string v1, "ro.product.cpu.abilist32"
const-string v2, ""
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
const-string v1, "ro.product.cpu.abi2"
const-string v2, ""
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;'
const expected_helper = '.method private static getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
.registers 4
const-string v0, ""
invoke-static {p0, v0}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/String;->isEmpty()Z
move-result v1
if-eqz v1, :split
const/4 v0, 0x0
new-array v0, v0, [Ljava/lang/String;
return-object v0
:split
invoke-virtual {v0, p1}, Ljava/lang/String;->split(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
return-object v0
.end method'
const field64 = '.field public static final SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;'
const field32 = '.field public static final SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;'

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

fn metadata(source string) !string {
	mut rest := source
	for _, body in methods(source)! { rest = rest.replace(body, '') }
	return norm(rest)
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

fn verify(before map[string]string, after map[string]string, raw bool) ! {
	if after.keys().sorted() != before.keys().sorted() || after[version] != before[version] {
		return error('class membership and Build.VERSION must remain unchanged')
	}
	for path in [build, properties] {
		old, changed := methods(before[path])!, methods(after[path])!
		mut names := old.keys()
		if path == build { names << helper }
		if changed.keys().sorted() != names.sorted() {
			return error('only one private Build list helper may be added')
		}
		for name, body in old {
			if name != '<clinit>()V' && (if raw {
				changed[name] != body
			} else {
				norm(changed[name]) != norm(body)
			}) {
				return error('old noninitializer method changed: ' + name)
			}
		}
		initializer := norm(changed['<clinit>()V'])
		insert := if path == build { build_insert } else { property_insert }
		anchor := if path == build { all_anchor } else { arm_anchor }
		if initializer.count(insert) != 1 || initializer.count(anchor + '\n' + insert) != 1
			|| flow(initializer.replace(insert, '')) != flow(old['<clinit>()V']) {
			return error('initializer must retain all old control flow with exact single insertion at ABI anchor')
		}
		if path == build {
			if flow(changed[helper]) != flow(expected_helper) || after[path].count(field64) != 1 || after[path].count(field32) != 1
				|| metadata(after[path].replace(field64, '').replace(field32, ''))! != metadata(before[path])! {
				return error('independent ABI arrays and empty-aware key/separator helper required')
			}
			for field in ['SUPPORTED_ABIS', 'SUPPORTED_64_BIT_ABIS', 'SUPPORTED_32_BIT_ABIS'] {
				if initializer.count('->' + field + ':[Ljava/lang/String;') != 1 {
					return error('ABI array must initialize exactly once')
				}
			}
		} else if metadata(after[path])! != metadata(before[path])! {
			return error('SystemProperties schema changed')
		}
	}
}

fn read(directory string) !map[string]string {
	mut result := map[string]string{}
	for path in os.walk_ext(directory, '.smali') {
		result[path[directory.len + 1..]] = os.read_file(path)!
	}
	return result
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		before := read(work + '/baseline-roundtrip')!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 3
			verify(before, read(work + '/' + directory)!, false)!
		}
		assert read(work + '/patched-roundtrip')! == read(work + '/second-roundtrip')!
		println('BUILD-ABIS-ROUNDTRIP-PASS two-narrow-initializers exact-list-helper retained-VERSION stable-second-DEX')
		return
	}
	before := read(work + '/proof')!
	assert before.keys().sorted() == [build, version, properties].sorted()
	androidtools.framework_build_abis(work + '/proof')!
	after := read(work + '/proof')!
	verify(before, after, true)!
	mut refusals := 0
	for path in [build, properties] {
		mut invalids := [after[path], before[path] + '\n.class public Ljava/lang/Object;\n',
			before[path].replace('.super Ljava/lang/Object;', '.super Landroid/view/View;'),
			before[path].replace('.end method', ''), before[path] + '\n.end method\n',
			before[path] + '\n.method\tpublic unrelated()V\n.end method\n',
			before[path] + '\n' + (methods(before[path])!)['<clinit>()V']]
		if path == build {
			invalids << before[path].replace('.field public static final SUPPORTED_ABIS:', '.field public SUPPORTED_ABIS:')
			invalids << before[path] + '\n' + expected_helper
		} else {
			invalids << before[path].replace('const-string v1, "aarch64"', 'const-string v1, "arm"')
			invalids << before[path].replace('"arm64-v8a"', '"armeabi-v7a"')
		}
		for invalid in invalids {
			for name, source in before { os.write_file(work + '/proof/' + name, source)! }
			os.write_file(work + '/proof/' + path, invalid)!
			expected := read(work + '/proof')!
			mut refused := false
			androidtools.framework_build_abis(work + '/proof') or { refused = true }
			assert refused && read(work + '/proof')! == expected, 'whole two-class preflight must precede writes'
			refusals++
		}
	}
	mut controls := 0
	for change in [
		[build, 'const-string v0, ""', 'const-string v0, "unknown"'],
		[build, '->get(Ljava/lang/String;Ljava/lang/String;)', '->get(Ljava/lang/String;)'],
		[build, 'if-eqz v1, :split', 'if-nez v1, :split'],
		[build, 'new-array v0, v0, [Ljava/lang/String;',
			'sget-object v0, Landroid/os/Build;->SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;'],
		[build, '{v0, p1}, Ljava/lang/String;->split', '{p1, v0}, Ljava/lang/String;->split'],
		[build, 'ro.product.cpu.abilist64', 'ro.product.cpu.abilist'],
		[build, 'ro.product.cpu.abilist32', 'ro.product.cpu.abilist'],
		[build, field64, field64.replace(' final ', ' ')],
		[build, '.method private static getStringList(', '.method public static getStringList('],
		[build, build_insert,
			build_insert.replace('invoke-static {v0, v1}, Landroid/os/Build;->getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;\nmove-result-object v0', 'sget-object v0, Landroid/os/Build;->SUPPORTED_ABIS:[Ljava/lang/String;')],
		[properties, property_insert, property_insert.replace('"arm64-v8a"', '"x86_64"')],
		[properties, property_insert,
			property_insert.replace('const-string v2, ""', 'const-string v2, "armeabi-v7a"')],
		[properties, property_insert,
			property_insert.replace('const-string v1, "ro.product.cpu.abi2"\nconst-string v2, ""', 'const-string v1, "ro.product.cpu.abi2"\nconst-string v2, "unknown"')],
		[properties, 'const-string v1, "aarch64"', 'const-string v1, "x86_64"'],
		[version, 'SDK_INT:I', 'WRONG_SDK_INT:I'],
	] {
		mut broken := after.clone()
		broken[change[0]] = broken[change[0]].replace(change[1], change[2])
		assert broken[change[0]] != after[change[0]]
		mut refused := false
		verify(before, broken, true) or { refused = true }
		assert refused, 'default/null/empty/split/alias/property/identity mutation escaped oracle'
		controls++
	}
	for path in [build, properties] {
		insert := if path == build { build_insert } else { property_insert }
		mut relocated := after.clone()
		initializer := (methods(after[path])!)['<clinit>()V']
		register_line := '    .registers ' + if path == build { '4' } else { '3' }
		relocated[path] = relocated[path].replace(initializer, initializer.replace(insert, '').replace(register_line, register_line + '\n' + insert))
		mut refused := false
		verify(before, relocated, true) or { refused = true }
		assert refused, 'insertion moved outside its ABI branch escaped oracle'
		controls++
	}
	for path, source in after { os.write_file(work + '/proof/' + path, source)! }
	println('BUILD-ABIS-SOURCE-PASS refusals=' + refusals.str() + ' semantic-controls=' + controls.str() + ' independent-empty-aware-arrays aarch64-only-properties retained-VERSION')
}
