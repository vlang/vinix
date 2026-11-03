// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const resources = 'android/content/res/Resources.smali'
const loaded = 'android/atl/ATLLoadedApp.smali'
const getter = 'invoke-static {}, Ljava/lang/ClassLoader;->getSystemClassLoader()Ljava/lang/ClassLoader;'

const old_resources = '.method public static getSystem()Landroid/content/res/Resources;
.registers 5
sget-object v0, Landroid/content/res/Resources;->mSystem:Landroid/content/res/Resources;
if-eqz v0, :cond_5
:goto_4
return-object v0
:cond_5
sget-object v1, Landroid/content/res/Resources;->sSync:Ljava/lang/Object;
monitor-enter v1
:try_start_8
sget-object v0, Landroid/content/res/Resources;->mSystem:Landroid/content/res/Resources;
if-nez v0, :cond_25
new-instance v0, Landroid/content/res/Resources;
new-instance v2, Landroid/content/res/AssetManager;
const-class v3, Landroid/content/res/Resources;
invoke-virtual {v3}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v3
invoke-direct {v2, v3}, Landroid/content/res/AssetManager;-><init>(Ljava/lang/ClassLoader;)V
new-instance v3, Landroid/util/DisplayMetrics;
invoke-direct {v3}, Landroid/util/DisplayMetrics;-><init>()V
sget-object v4, Landroid/content/Context;->sys_config:Landroid/content/res/Configuration;
invoke-direct {v0, v2, v3, v4}, Landroid/content/res/Resources;-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
sput-object v0, Landroid/content/res/Resources;->mSystem:Landroid/content/res/Resources;
:cond_25
monitor-exit v1
goto :goto_4
:catchall_27
move-exception v0
monitor-exit v1
:try_end_29
.catchall {:try_start_8 .. :try_end_29} :catchall_27
throw v0
.end method'

const old_loaded = '.method public static loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;
.registers 12
.annotation build Landroid/annotation/NonNull;
.end annotation
.annotation system Ldalvik/annotation/Throws;
value = {
Ljava/io/IOException;
}
.end annotation
const/4 v8, 0x1
const/4 v7, 0x0
new-instance v0, Ldalvik/system/PathClassLoader;
const-class v1, Landroid/atl/ATLLoadedApp;
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
invoke-direct {v0, p2, p1, v1}, Ldalvik/system/PathClassLoader;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V
new-instance v1, Landroid/content/res/AssetManager;
invoke-direct {v1, v0}, Landroid/content/res/AssetManager;-><init>(Ljava/lang/ClassLoader;)V
new-instance v2, Landroid/content/pm/PackageParser;
invoke-direct {v2, p0}, Landroid/content/pm/PackageParser;-><init>(Ljava/lang/String;)V
new-instance v3, Landroid/content/res/Resources;
new-instance v4, Landroid/util/DisplayMetrics;
invoke-direct {v4}, Landroid/util/DisplayMetrics;-><init>()V
sget-object v5, Landroid/content/Context;->sys_config:Landroid/content/res/Configuration;
invoke-direct {v3, v1, v4, v5}, Landroid/content/res/Resources;-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
new-array v4, v8, [Ljava/lang/String;
const/4 v5, 0x1
:try_start_26
invoke-virtual {v1, p0}, Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I
move-result v5
const-string v6, "AndroidManifest.xml"
invoke-virtual {v1, v5, v6}, Landroid/content/res/AssetManager;->openXmlResourceParser(ILjava/lang/String;)Landroid/content/res/XmlResourceParser;
move-result-object v1
const/4 v5, 0x0
invoke-virtual {v2, v3, v1, v5, v4}, Landroid/content/pm/PackageParser;->parsePackage(Landroid/content/res/Resources;Landroid/content/res/XmlResourceParser;I[Ljava/lang/String;)Landroid/content/pm/PackageParser$Package;
:try_end_34
.catch Lorg/xmlpull/v1/XmlPullParserException; {:try_start_26 .. :try_end_34} :catch_43
move-result-object v1
invoke-virtual {v2}, Landroid/content/pm/PackageParser;->getParseError()I
move-result v5
if-eq v5, v8, :cond_4c
new-instance v0, Ljava/io/IOException;
aget-object v1, v4, v7
invoke-direct {v0, v1}, Ljava/io/IOException;-><init>(Ljava/lang/String;)V
throw v0
:catch_43
move-exception v0
new-instance v1, Ljava/io/IOException;
aget-object v2, v4, v7
invoke-direct {v1, v2, v0}, Ljava/io/IOException;-><init>(Ljava/lang/String;Ljava/lang/Throwable;)V
throw v1
:cond_4c
invoke-virtual {v2, v1, v7}, Landroid/content/pm/PackageParser;->collectCertificates(Landroid/content/pm/PackageParser$Package;I)Z
move-result v2
if-nez v2, :cond_5a
new-instance v2, Ljava/io/IOException;
const-string v4, "APK signature verification failed"
invoke-direct {v2, v4}, Ljava/io/IOException;-><init>(Ljava/lang/String;)V
throw v2
:cond_5a
new-instance v2, Landroid/atl/ATLLoadedApp;
invoke-direct {v2, v3, v0, v1}, Landroid/atl/ATLLoadedApp;-><init>(Landroid/content/res/Resources;Ljava/lang/ClassLoader;Landroid/content/pm/PackageParser$Package;)V
return-object v2
.end method'

struct Parts {
	metadata string
	methods map[string]string
}

fn signature(target string) string {
	return if target == resources { 'getSystem()Landroid/content/res/Resources;' } else {
		'loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;'
	}
}

fn parameters(target string) int { return if target == resources { 0 } else { 3 } }
fn register(target string) string { return if target == resources { 'v3' } else { 'v1' } }
fn registers(target string) int { return if target == resources { 5 } else { 12 } }
fn original_method(target string) string { return if target == resources { old_resources } else { old_loaded } }
fn old_class(target string) string { return 'const-class ' + register(target) + ', L' + target.all_before_last('.smali') + ';' }
fn old_call(target string) string { return 'invoke-virtual {' + register(target) + '}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;' }

fn flat(text string) string {
	return text.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn label_char(value u8) bool {
	return (value >= `a` && value <= `z`) || (value >= `A` && value <= `Z`)
		|| (value >= `0` && value <= `9`) || value in [`_`, `$`, `-`]
}

// Labels are compared by their instruction positions, including catch-range
// references inside braces. Quoted strings and field-descriptor colons stay exact.
fn normalized_method(source string, target string) !string {
	lines := flat(source).split_into_lines()
	mut labels := map[string]string{}
	mut instruction := 0
	mut annotation := 0
	for line in lines {
		if line.starts_with(':') {
			if line.len < 2 || line[1..].bytes().any(!label_char(it)) || line in labels {
				return error('unique plain method labels required')
			}
			labels[line] = ':instruction_' + instruction.str()
		} else if line.starts_with('.annotation ') || line.starts_with('.subannotation ') {
			annotation++
		} else if line in ['.end annotation', '.end subannotation'] {
			annotation--
			if annotation < 0 { return error('unbalanced method annotation') }
		} else if annotation == 0 && !line.starts_with('.') { instruction++ }
	}
	if annotation != 0 { return error('unbalanced method annotation') }
	mut result := []string{}
	for original in lines {
		if original.starts_with(':') { continue }
		line := if original.starts_with('.locals ') {
			'.registers ' + (original.all_after(' ').int() + parameters(target)).str()
		} else { original }
		mut rewritten := ''
		mut quoted := false
		mut escaped := false
		mut index := 0
		for index < line.len {
			value := line[index]
			if value == `"` && !escaped { quoted = !quoted }
			if !quoted && value == `:` && (index == 0 || line[index - 1] in [` `, `\t`, `{`, `,`]) {
				mut end := index + 1
				for end < line.len && label_char(line[end]) { end++ }
				name := line[index..end]
				replacement := labels[name] or { return error('undefined method branch or catch-range label: ' + name) }
				rewritten += replacement
				index = end
				escaped = false
				continue
			}
			rewritten += value.ascii_str()
			escaped = value == `\\` && !escaped
			index++
		}
		result << rewritten
	}
	return result.join('\n')
}

fn parts(source string) !Parts {
	mut methods := map[string]string{}
	mut metadata := source
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').trim_space().all_after_last(' ')
		if name in methods || !name.contains('(') || block.count('.end method') != 1 {
			return error('unique complete class methods required')
		}
		body := '.method ' + block.all_before('.end method') + '.end method'
		methods[name] = body
		metadata = metadata.replace(body, '')
	}
	return Parts{metadata, methods}
}

fn expected_method(target string) string {
	old := original_method(target)
	return old.replace(old_class(target) + '\n' + old_call(target), getter)
}

// Raw oracle compares every original byte except the prescribed class/call
// lines; the complete explicit method oracle above supplies independent behavior.
fn expected_raw(source string, target string) !string {
	body := parts(source)!.methods[signature(target)]!
	mut removed, replaced := 0, 0
	mut result := []string{}
	for line in body.split('\n') {
		clean := line.all_before('#').trim_space()
		ending := if line.ends_with('\r') { '\r' } else { '' }
		if clean == old_class(target) {
			result << ending
			removed++
		} else if clean == old_call(target) {
			indent := line[..line.len - line.trim_left(' \t').len]
			result << indent + getter + ending
			replaced++
		} else { result << line }
	}
	if removed != 1 || replaced != 1 { return error('one exact raw loader site required') }
	return source.replace(body, result.join('\n'))
}

fn verify(before string, after string, target string, raw bool) ! {
	old, new := parts(before)!, parts(after)!
	count := if target == resources { 81 } else { 23 }
	if old.methods.len != count || old.methods.keys().sorted() != new.methods.keys().sorted()
		|| flat(old.metadata) != flat(new.metadata) { return error('complete existing class membership/metadata must remain unchanged') }
	name := signature(target)
	previous := old.methods[name] or { return error('original required loader method missing') }
	changed := new.methods[name] or { return error('required loader method missing') }
	if normalized_method(previous, target)! != normalized_method(original_method(target), target)!
		|| normalized_method(changed, target)! != normalized_method(expected_method(target), target)! {
		return error('complete original target body permits only one system-loader replacement')
	}
	for member, body in old.methods {
		if member != name && body != new.methods[member]! { return error('unrelated original method changed: ' + member) }
	}
	if raw && after != expected_raw(before, target)! { return error('raw source changed beyond the two prescribed lines') }
}

fn apply(target string, source string) !string {
	return if target == resources { androidtools.framework_boot_resources_source(source)! } else {
		androidtools.framework_boot_loaded_source(source)!
	}
}

fn write_pair(work string, pair map[string]string) ! {
	for target, source in pair { os.write_file(work + '/proof/' + target, source)! }
}

fn refuse_pair(work string, before map[string]string, target string, invalid string) ! {
	if invalid == before[target]! { return error('ineffective prewrite control') }
	mut snapshot := before.clone()
	snapshot[target] = invalid
	write_pair(work, snapshot)!
	mut refused := false
	androidtools.framework_boot_classpath(work + '/proof') or { refused = true }
	if !refused { return error('malformed input accepted by atomic wrapper') }
	for path, source in snapshot {
		if os.read_file(work + '/proof/' + path)! != source { return error('refusal must precede writes to both classes') }
	}
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		for directory in ['baseline-roundtrip', 'patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 2
		}
		for target in [resources, loaded] {
			before := os.read_file(work + '/baseline-roundtrip/' + target)!
			for directory in ['patched-roundtrip', 'second-roundtrip'] {
				verify(before, os.read_file(work + '/' + directory + '/' + target)!, target, false)!
			}
			assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!
		}
		println('FRAMEWORK-BOOT-SDK-ROUNDTRIP-PASS exactly2-existing-methods full-instruction-register-branch-catch-annotation-preservation stable-second-DEX')
		return
	}
	mut before := map[string]string{}
	mut after := map[string]string{}
	mut refusals, mutations, positives := 0, 0, 0
	for target in [resources, loaded] {
		original := os.read_file(work + '/baseline/' + target)!
		before[target] = original
		after[target] = apply(target, original)!
		verify(original, after[target]!, target, true)!
		body := parts(original)!.methods[signature(target)]!
		locals_body := body.replace('.registers ' + registers(target).str(), '.locals ' + (registers(target) - parameters(target)).str())
		for variant in [original.replace(body, locals_body), original.trim_right('\n'), original.replace('\n', '\r\n'),
			original.replace(body, body.replace('    ' + old_class(target), '\t' + old_class(target)).replace('    ' + old_call(target), '\t' + old_call(target)))] {
			assert variant != original
			verify(variant, apply(target, variant)!, target, true)!
			positives++
		}
	}
	for target in [resources, loaded] {
		original := before[target]!
		body := parts(original)!.methods[signature(target)]!
		declaration := if target == resources { '.class public Landroid/content/res/Resources;' } else { '.class public final Landroid/atl/ATLLoadedApp;' }
		invalids := [after[target]!, original.replace(declaration, declaration.replace('public', 'private')),
			original + '\n' + declaration + '\n', original.replace('.super Ljava/lang/Object;', '.super Landroid/content/Context;'),
			original + '\n.implements Ljava/lang/Runnable;\n', original + '\n.end method\n',
			original + '\n' + body + '\n', original.replace(body, ''),
			original.replace(body, body.replace('.method public static ', '.method private static ')),
			original.replace(body, body.replace('.method public static ', '.method public static native ')),
			original.replace(body, body.replace('.method public static ', '.method\tpublic static ')),
			original.replace(body, body.replace('.end method', '')),
			original.replace(body, body.replace('.registers ' + registers(target).str(), '.registers ' + (registers(target) + 1).str())),
			original.replace(body, body.replace('.registers ' + registers(target).str(), '.locals ' + (registers(target) - parameters(target) + 1).str())),
			original.replace(body, body.replace(old_class(target), old_class(target).replace(register(target), 'v0'))),
			original.replace(body, body.replace(old_call(target), old_call(target).replace(register(target), 'v0'))),
			original.replace(body, body.replace('move-result-object ' + register(target), 'move-result-object v8')),
			original.replace(body, body.replace(old_class(target), old_class(target) + '\nnop')),
			original.replace(body, body.replace(old_class(target), old_class(target) + '\n' + old_call(target) + '\nmove-result-object ' + register(target) + '\n' + old_class(target))),
			original.replace(body, body.replace('.end method', getter + '\nmove-result-object ' + register(target) + '\n.end method'))]
		for invalid in invalids { refuse_pair(work, before, target, invalid)!; refusals++ }
		changed := after[target]!
		new_body := parts(changed)!.methods[signature(target)]!
		mut broken := [changed.replace(new_body, new_body.replace(getter, getter.replace('getSystemClassLoader', 'getPlatformClassLoader'))),
			changed.replace(new_body, new_body.replace(getter, 'const/4 ' + register(target) + ', 0x0')),
			changed.replace(new_body, new_body.replace('move-result-object ' + register(target), 'move-result-object v8')),
			changed.replace(new_body, new_body.replace('.registers ' + registers(target).str(), '.registers ' + (registers(target) + 1).str())),
			changed.replace(new_body, new_body.replace('.method public static ', '.method public ')),
			changed + '\n.field private static injected:Ljava/lang/ClassLoader;\n',
			changed + '\n.method public static injected()V\n.registers 0\nreturn-void\n.end method\n',
			changed.replace(new_body, new_body.replace('->sys_config:', '->injected_config:'))]
		if target == resources {
			broken << changed.replace(new_body, new_body.replace('monitor-exit v1', 'monitor-enter v1'))
			broken << changed.replace(new_body, new_body.replace('.catchall ', '.catch Ljava/lang/Exception; '))
			broken << changed.replace(new_body, new_body.replace('if-eqz v0, :cond_5', 'if-eqz v0, :cond_25'))
			broken << changed.replace(new_body, new_body.replace(':try_end_29} :catchall_27', ':cond_25} :catchall_27'))
			broken << changed.replace('.method public native getFont(I)Landroid/graphics/Typeface;', '.method private native getFont(I)Landroid/graphics/Typeface;')
		} else {
			broken << changed.replace(new_body, new_body.replace('Landroid/annotation/NonNull;', 'Landroid/annotation/Nullable;'))
			broken << changed.replace(new_body, new_body.replace('collectCertificates', 'skipCertificates'))
			broken << changed.replace(new_body, new_body.replace(':try_start_26 .. :try_end_34', ':try_start_26 .. :cond_4c'))
			broken << changed.replace('.method public native vinixEnsureApplicationStarted()V', '.method private native vinixEnsureApplicationStarted()V')
		}
		for invalid in broken {
			assert invalid != changed, 'ineffective preservation mutation'
			mut refused := false
			verify(original, invalid, target, true) or { refused = true }
			assert refused, 'preservation oracle accepted changed instruction/member/metadata'
			mut canonical_refused := false
			verify(original, invalid, target, false) or { canonical_refused = true }
			assert canonical_refused, 'canonical preservation oracle accepted changed instruction/member/metadata'
			mutations++
		}
	}
	write_pair(work, before)!
	os.rm(work + '/proof/' + loaded)!
	mut missing_refused := false
	androidtools.framework_boot_classpath(work + '/proof') or { missing_refused = true }
	assert missing_refused && os.read_file(work + '/proof/' + resources)! == before[resources]! && !os.exists(work + '/proof/' + loaded)
	refusals++
	write_pair(work, before)!
	androidtools.framework_boot_classpath(work + '/proof')!
	for target in [resources, loaded] { assert os.read_file(work + '/proof/' + target)! == after[target]! }
	println('FRAMEWORK-BOOT-SDK-SOURCE-PASS atomic-prewrite-refusals=' + refusals.str() + ' preservation-controls=' + mutations.str()
		+ ' format-positives=' + positives.str() + ' full-two-method-oracle all-fields-and-other-methods-unchanged registers-branches-catches-annotations-preserved')
}
