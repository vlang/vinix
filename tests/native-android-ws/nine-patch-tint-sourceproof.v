// SPDX-License-Identifier: GPL-2.0-or-later
// Authenticate Maps' switch tint calls, the exact312 provider and AOSP contract.
module main

import crypto.sha256
import json2
import net.http
import os

const maps_pin = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
const framework = '/Users/alex/.local/state/vinix/android/paint-text-widths312-framework-build-2026-10-25'
const framework_seal = 'c4ea45675a661c38278173945c896bc69b4ce7812d054a44e680ef8ca1e23287'
const native = '/Users/alex/.local/state/vinix/android/paint-text-widths312-native-build-2026-10-25'
const native_seal = '66d1b23301a43bf29c3dbc45b1298a7e15e397c1e5addfb7648c435b560bc417'
const aosp_revision = '1cdfff555f4a21f71ccc978290e2e212e2f8b168'
const switch_owner = 'Landroid/support/v7/widget/SwitchCompat;'
const drawable = 'Landroid/graphics/drawable/Drawable;'
const source = 'tests/native-android-ws/nine-patch-tint-sourceproof.v'

fn hash(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := f.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn checked(out string, name string, argv []string) !string {
	r := os.exec(argv)
	write_json(out + '/' + name + '-receipt.json', {
		'argv':      json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
		'output':    json2.Any(r.output)
	})!
	assert r.exit_code == 0, r.output
	return r.output
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular entry: ' + key) }
		}
	}
}

fn reference(root string, seal string, name string, out string) !map[string]string {
	assert hash(root + '/sha256.json')! == seal, root
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	os.cp(root + '/sha256.json', out + '/qualified-' + name + '-sha256.json')!
	return pins
}

fn retain(root string, pins map[string]string, relative string, target string) ! {
	assert hash(root + '/' + relative)! == pins[relative]!, relative
	os.mkdir_all(os.dir(target))!
	os.cp(root + '/' + relative, target)!
	assert hash(target)! == pins[relative]!, relative
}

fn method(text string, declaration string) string {
	assert text.count(declaration + '\n') == 1, declaration
	start := text.index(declaration + '\n') or { panic(declaration) }
	end := text[start..].index('.end method') or { panic(declaration) }
	return text[start..start + end + '.end method'.len]
}

fn no_op(text string, declaration string, instruction string) {
	body := method(text, declaration).split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('.method ') && !it.starts_with('.registers ') && it != '.end method')
	assert body == instruction.split_into_lines(), declaration + '\n' + body.str()
}

fn main() {
	$if prod {
		panic('requires assertions; compile without -prod')
	}
	assert os.args.len == 2, 'OUTPUT (fresh external directory)'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), out
	apk := os.abs_path('build/android-maps/GoogleMaps.apk')
	mut input_pins := map[string]string{}
	mut input_paths := [os.abs_path(source), os.executable(), apk, framework + '/sha256.json',
		framework + '/framework/api-impl.jar', native + '/sha256.json']
	for name in ['Drawable', 'NinePatchDrawable'] {
		input_paths << framework + '/disassembled-312/android/graphics/drawable/' + name + '.smali'
	}
	for relative in ['native/bindings.txt', 'native/atlframework/ws_generated.v',
		'native/atlframework/bitmaps.v'] {
		input_paths << native + '/' + relative
	}
	for path in input_paths { input_pins[path] = hash(path)! }
	os.mkdir_all(out + '/entries')!
	write_json(out + '/input-pins-before.json', input_pins)!
	write_json(out + '/author-invocation.json', os.args)!
	os.cp(source, out + '/author.v')!
	os.cp(os.executable(), out + '/author')!
	assert hash(apk)! == maps_pin
	java := '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
	unzip := '/usr/bin/unzip'
	tools_root := os.abs_path('build/android-framework/tools')
	mut jars := os.ls(tools_root)!.filter(it.ends_with('.jar'))
	jars.sort()
	assert jars.len > 0
	mut tools := map[string]string{}
	for path in [java, unzip] { tools[path] = hash(path)! }
	for jar in jars { tools[tools_root + '/' + jar] = hash(tools_root + '/' + jar)! }
	write_json(out + '/tools-before.json', tools)!
	checked(out, 'maps-dex-extract', [unzip, '-q', '-j', apk, 'classes*.dex', '-d', out + '/entries'])!
	mut dex_pins := map[string]string{}
	mut found := []string{}
	for name in os.ls(out + '/entries')! {
		assert name.starts_with('classes') && name.ends_with('.dex'), name
		dex_pins[name] = hash(out + '/entries/' + name)!
		classes := checked(out, 'maps-list-' + name, [java, '-cp', tools_root + '/*',
			'org.jf.baksmali.Main', 'list', 'classes', out + '/entries/' + name])!
		if classes.split_into_lines().contains(switch_owner) { found << name }
	}
	assert dex_pins.len == 10 && found.len == 1, found.str()
	checked(out, 'maps-switch-disassemble', [java, '-cp', tools_root + '/*', 'org.jf.baksmali.Main',
		'disassemble', '--classes', switch_owner, '-o', out + '/maps-smali',
		out + '/entries/' + found[0]])!
	switch_text := os.read_file(out + '/maps-smali/android/support/v7/widget/SwitchCompat.smali')!
	for name in ['o', 'p'] {
		body := method(switch_text, '.method private final ' + name + '()V')
		for call in ['setTintList(Landroid/content/res/ColorStateList;)V',
			'setTintMode(Landroid/graphics/PorterDuff$Mode;)V', 'isStateful()Z', 'setState([I)Z'] {
			assert body.count(drawable + '->' + call) == 1, name + ':' + call
		}
		stateful_at := body.index('->isStateful()Z') or { panic(name) }
		set_state_at := body.index('->setState([I)Z') or { panic(name) }
		assert stateful_at < set_state_at
	}
	changed := method(switch_text, '.method protected final drawableStateChanged()V')
	assert changed.count(drawable + '->isStateful()Z') == 2
	assert changed.count(drawable + '->setState([I)Z') == 2
	framework_pins := reference(framework, framework_seal, 'framework312', out)!
	retain(framework, framework_pins, 'framework/api-impl.jar', out + '/provider312/api-impl.jar')!
	assert hash(out + '/provider312/api-impl.jar')! == '33d231c02740bbb79bdc663f1ac79e142452aadb85348bee5a5165b0a03d674f'
	checked(out, 'framework-dex-extract', [unzip, '-q', '-j', out + '/provider312/api-impl.jar',
		'classes.dex', '-d', out + '/provider312'])!
	checked(out, 'framework-disassemble', [java, '-cp', tools_root + '/*', 'org.jf.baksmali.Main',
		'disassemble', '--classes', drawable + ',Landroid/graphics/drawable/NinePatchDrawable;',
		'-o', out + '/provider312/smali', out + '/provider312/classes.dex'])!
	for name in ['Drawable', 'NinePatchDrawable'] {
		relative := 'disassembled-312/android/graphics/drawable/' + name + '.smali'
		assert hash(framework + '/' + relative)! == framework_pins[relative]!
		assert hash(out + '/provider312/smali/android/graphics/drawable/' + name + '.smali')! == framework_pins[relative]!
	}
	nine := os.read_file(out + '/provider312/smali/android/graphics/drawable/NinePatchDrawable.smali')!
	base := os.read_file(out + '/provider312/smali/android/graphics/drawable/Drawable.smali')!
	for signature in ['setTintList(', 'setTintMode(', 'setColorFilter(', 'isStateful(', 'onStateChange(',
		'draw('] {
		assert !nine.split_into_lines().any(it.starts_with('.method ') && it.contains(' ' + signature)), signature
	}
	assert method(nine, '.method public setTint(I)V').contains('->nativeSetTint(JI)V')
	for declaration in ['setTintList(Landroid/content/res/ColorStateList;)V',
		'setTintMode(Landroid/graphics/PorterDuff$Mode;)V',
		'setColorFilter(Landroid/graphics/ColorFilter;)V'] {
		no_op(base, '.method public ' + declaration, 'return-void')
	}
	no_op(base, '.method public isStateful()Z', 'const/4 v0, 0x0\nreturn v0')
	assert method(base, '.method public draw(Landroid/graphics/Canvas;)V').contains('->native_draw(JJII)V')
	native_pins := reference(native, native_seal, 'native312', out)!
	for relative in ['native/bindings.txt', 'native/atlframework/ws_generated.v',
		'native/atlframework/bitmaps.v'] {
		retain(native, native_pins, relative, out + '/provider312/' + relative)!
	}
	bindings := os.read_file(out + '/provider312/native/bindings.txt')!
	generated := os.read_file(out + '/provider312/native/atlframework/ws_generated.v')!
	assert bindings.count('android/graphics/drawable/Drawable|native_draw|ws_draw_bitmap(p0,0,0,p2,p3)') == 1
	assert !bindings.contains('NinePatchDrawable|nativeSetTint')
	assert !generated.contains('Java_android_graphics_drawable_NinePatchDrawable_nativeSetTint')
	assert generated.contains("@[export: 'Java_android_graphics_drawable_Drawable_native_1draw__JJII']")
	assert generated.contains('ws_draw_bitmap(p0,0,0,p2,p3)')
	url := 'https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/' + aosp_revision + '/graphics/java/android/graphics/drawable/NinePatchDrawable.java'
	response := http.get(url)!
	assert response.status_code == 200
	os.write_file(out + '/AOSP-NinePatchDrawable.java', response.body)!
	contract := response.body.fields().join(' ')
	for signature in ['public void draw(Canvas canvas)',
		'public void setColorFilter(@Nullable ColorFilter colorFilter)',
		'public void setTintList(@Nullable ColorStateList tint)', 'public int getAlpha()',
		'public Paint getPaint()', 'protected boolean onStateChange(int[] stateSet)',
		'public boolean isStateful()'] {
		assert contract.contains(signature), signature
	}
	assert contract.contains('mPaint.setColorFilter(null)') && contract.contains('getPaint().getColorFilter() == null')
	write_json(out + '/inputs.json', {
		'apk':                          apk
		'apk_sha256':                   maps_pin
		'maps_switch_dex':              found[0]
		'framework312_root':            framework
		'framework312_manifest_sha256': framework_seal
		'native312_root':               native
		'native312_manifest_sha256':    native_seal
		'aosp_url':                     url
		'aosp_revision':                aosp_revision
		'aosp_source_sha256':           hash(out + '/AOSP-NinePatchDrawable.java')!
		'scope':                        'Static API and exact provider proof. Actual checked-state tint in Maps requires a separate runtime replay.'
	})!
	write_json(out + '/maps-dex-pins.json', dex_pins)!
	assert hash(apk)! == maps_pin
	for name, pin in dex_pins {
		assert hash(out + '/entries/' + name)! == pin, name
	}
	mut after_jars := os.ls(tools_root)!.filter(it.ends_with('.jar'))
	after_jars.sort()
	assert jars == after_jars
	for path, pin in tools {
		assert hash(path)! == pin, path
	}
	assert hash(source)! == hash(out + '/author.v')!
	for path, pin in input_pins {
		assert hash(path)! == pin, path
	}
	write_json(out + '/input-pins-after.json', input_pins)!
	write_json(out + '/tools-after.json', tools)!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	write_json(out + '/sha256.json', pins)!
	println(out + ' ' + hash(out + '/sha256.json')!)
}
