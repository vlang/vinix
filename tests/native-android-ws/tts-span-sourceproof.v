// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import net.http
import os

const source = 'tests/native-android-ws/tts-span-sourceproof.v'
const maps_pin = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
const dex_cache = '/Users/alex/.local/state/vinix/android/nine-patch-tint-sourceproof315-qualified-2026-10-25'
const dex_cache_seal = '3fc905f97a238bd3916840b8ee4ec3ac3e172117d59ed29a1049ffd16169740b'
const framework = '/Users/alex/.local/state/vinix/android/nine-patch-tint315-v2-framework-build-2026-10-25'
const framework_seal = '630cd5f07509553f86fead29c998be2678dc5bbc94e5ab44f4706d3b213f5f56'
const maps317 = '/Users/alex/.local/state/vinix/android/maps317-2026-10-25'
const maps317_seal = '7d7ad98af1170fed5e1b20b147fef5f1a1b540803966833c7a696f60224593d2'
const aosp_revision = '1cdfff555f4a21f71ccc978290e2e212e2f8b168'
const tts = 'Landroid/text/style/TtsSpan;'
const pb = 'Landroid/os/PersistableBundle;'

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
		'argv': json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
		'output': json2.Any(r.output)
	})!
	assert r.exit_code == 0, r.output
	return r.output
}

// Full tables are reproducible from retained original DEX; retain all matching
// descriptors and the digest/size of each complete output, not unrelated APIs.
fn method_refs(out string, name string, argv []string) ![]string {
	r := os.exec(argv)
	lines := r.output.split_into_lines()
	refs := lines.filter(it.starts_with('Landroid/text/style/TtsSpan') || it.starts_with(pb))
	write_json(out + '/' + name + '-receipt.json', {
		'argv': json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
		'output_sha256': json2.Any(sha256.sum(r.output.bytes()).hex())
		'output_bytes': json2.Any(r.output.len)
		'output_lines': json2.Any(lines.len)
		'relevant_descriptors': json2.Any(refs)
	})!
	assert r.exit_code == 0
	return refs
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

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len == 2, 'OUTPUT (fresh external directory)'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), out
	apk := os.abs_path('build/android-maps/GoogleMaps.apk')
	java := '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
	unzip := '/usr/bin/unzip'
	tools_root := os.abs_path('build/android-framework/tools')
	provider_classes := ['android/os/PersistableBundle', 'android/os/BaseBundle',
		'android/os/Parcel', 'android/text/ParcelableSpan', 'android/text/TextUtils']
	mut inputs := [os.abs_path(source), os.executable(), apk, dex_cache + '/sha256.json',
		dex_cache + '/inputs.json', dex_cache + '/maps-dex-extract-receipt.json',
		framework + '/sha256.json', framework + '/framework/api-impl.jar', maps317 + '/sha256.json',
		maps317 + '/results/attempt317/google-maps/serial.log']
	mut dex_names := os.ls(dex_cache + '/entries')!
	dex_names.sort()
	assert dex_names.len == 10
	for name in dex_names { inputs << dex_cache + '/entries/' + name }
	for name in provider_classes { inputs << framework + '/disassembled-315/' + name + '.smali' }
	mut before := map[string]string{}
	for path in inputs { before[path] = hash(path)! }
	os.mkdir_all(out + '/entries')!
	write_json(out + '/input-pins-before.json', before)!
	write_json(out + '/author-invocation.json', os.args)!
	os.cp(source, out + '/author.v')!
	os.cp(os.executable(), out + '/author')!
	assert hash(apk)! == maps_pin
	mut jars := os.ls(tools_root)!.filter(it.ends_with('.jar'))
	jars.sort()
	assert jars.len > 0
	mut tools := map[string]string{}
	for path in [java, unzip] { tools[path] = hash(path)! }
	for jar in jars { tools[tools_root + '/' + jar] = hash(tools_root + '/' + jar)! }
	write_json(out + '/tools-before.json', tools)!
	cache_pins := reference(dex_cache, dex_cache_seal, 'maps-dex-origin', out)!
	for relative in ['inputs.json', 'maps-dex-extract-receipt.json'] {
		retain(dex_cache, cache_pins, relative, out + '/dex-origin-' + relative)!
	}
	origin := json2.decode[map[string]json2.Any](os.read_file(out + '/dex-origin-inputs.json')!)!
	assert origin['apk_sha256']!.str() == maps_pin
	mut all_refs := map[string]bool{}
	mut dex_pins := map[string]string{}
	for name in dex_names {
		assert name.starts_with('classes') && name.ends_with('.dex'), name
		retain(dex_cache, cache_pins, 'entries/' + name, out + '/entries/' + name)!
		dex_pins[name] = hash(out + '/entries/' + name)!
		refs := method_refs(out, 'maps-methods-' + name, [java, '-cp', tools_root + '/*',
			'org.jf.baksmali.Main', 'list', 'methods', out + '/entries/' + name])!
		for ref in refs { if ref.starts_with('Landroid/text/style/TtsSpan') { all_refs[ref] = true } }
	}
	mut actual_refs := all_refs.keys()
	actual_refs.sort()
	mut expected_refs := [tts + '-><init>(Ljava/lang/String;Landroid/os/PersistableBundle;)V']
	for name in ['TextBuilder', 'VerbatimBuilder'] {
		for signature in ['<init>(Ljava/lang/String;)V', 'build()' + tts] {
			expected_refs << 'Landroid/text/style/TtsSpan$' + name + ';->' + signature
		}
	}
	expected_refs.sort()
	assert actual_refs == expected_refs, actual_refs.str()
	checked(out, 'maps-agdh-disassemble', [java, '-cp', tools_root + '/*', 'org.jf.baksmali.Main',
		'disassemble', '--classes', 'Lagdh;', '-o', out + '/maps-smali', out + '/entries/classes.dex'])!
	agdh := os.read_file(out + '/maps-smali/agdh.smali')!
	f := method(agdh, '.method public static final f(Ljava/lang/CharSequence;Ljava/lang/String;)Landroid/text/Spannable;')
	new_at := f.index('.line 20\n    new-instance v2, ' + tts) or { panic('first TtsSpan operation') }
	pb_at := f.index(pb + '-><init>(I)V') or { panic('capacity constructor') }
	assert new_at < pb_at
	for value in ['android.arg.text', 'android.type.text', tts + '-><init>(Ljava/lang/String;Landroid/os/PersistableBundle;)V',
		'Landroid/text/SpannableString;->valueOf(Ljava/lang/CharSequence;)Landroid/text/SpannableString;',
		'Lagdh;->g(Landroid/text/Spannable;Lctyb;[Ljava/lang/Object;)V'] { assert f.contains(value), value }
	for call in ['putString(Ljava/lang/String;Ljava/lang/String;)V', 'putBoolean(Ljava/lang/String;Z)V',
		'putDouble(Ljava/lang/String;D)V', 'putInt(Ljava/lang/String;I)V', 'putLong(Ljava/lang/String;J)V',
		'putPersistableBundle(Ljava/lang/String;Landroid/os/PersistableBundle;)V', 'putBooleanArray(Ljava/lang/String;[Z)V',
		'putDoubleArray(Ljava/lang/String;[D)V', 'putIntArray(Ljava/lang/String;[I)V', 'putLongArray(Ljava/lang/String;[J)V',
		'putStringArray(Ljava/lang/String;[Ljava/lang/String;)V'] { assert f.contains(pb + '->' + call), call }
	g := method(agdh, '.method public static final varargs g(Landroid/text/Spannable;Lctyb;[Ljava/lang/Object;)V')
	assert g.contains('const/16 v5, 0x21') && g.contains('Landroid/text/Spannable;->setSpan(Ljava/lang/Object;III)V')
	framework_pins := reference(framework, framework_seal, 'framework315', out)!
	retain(framework, framework_pins, 'framework/api-impl.jar', out + '/provider315/api-impl.jar')!
	assert hash(out + '/provider315/api-impl.jar')! == '1e9ebbe318ae030ed22f06bc99553872fa43d820e0981d143586304560161cc6'
	checked(out, 'provider-dex-extract', [unzip, '-q', '-j', out + '/provider315/api-impl.jar', 'classes.dex', '-d', out + '/provider315'])!
	classes := checked(out, 'provider-list-classes', [java, '-cp', tools_root + '/*', 'org.jf.baksmali.Main', 'list', 'classes', out + '/provider315/classes.dex'])!
	assert !classes.split_into_lines().any(it.starts_with('Landroid/text/style/TtsSpan'))
	owners := provider_classes.map('L' + it + ';').join(',')
	checked(out, 'provider-disassemble', [java, '-cp', tools_root + '/*', 'org.jf.baksmali.Main', 'disassemble', '--classes', owners, '-o', out + '/provider315/smali', out + '/provider315/classes.dex'])!
	for name in provider_classes {
		relative := 'disassembled-315/' + name + '.smali'
		assert hash(framework + '/' + relative)! == framework_pins[relative]!
		assert hash(out + '/provider315/smali/' + name + '.smali')! == framework_pins[relative]!
	}
	bundle := os.read_file(out + '/provider315/smali/android/os/PersistableBundle.smali')!
	assert !bundle.contains('<init>(I)V')
	base := os.read_file(out + '/provider315/smali/android/os/BaseBundle.smali')!
	assert method(base, '.method public putString(Ljava/lang/String;Ljava/lang/String;)V').contains('Landroid/util/ArrayMap;->put(')
	parcel := os.read_file(out + '/provider315/smali/android/os/Parcel.smali')!
	assert !parcel.contains('readPersistableBundle(') && !parcel.contains('writePersistableBundle(')
	run_pins := reference(maps317, maps317_seal, 'maps317', out)!
	retain(maps317, run_pins, 'results/attempt317/google-maps/serial.log', out + '/maps317-serial.log')!
	serial := os.read_file(out + '/maps317-serial.log')!
	assert serial.contains('java.lang.NoClassDefFoundError: Failed resolution of: Landroid/text/style/TtsSpan;')
	assert serial.contains('at agdh.f(') && serial.contains(':20)')
	mut aosp := map[string]string{}
	for name in ['text/style/TtsSpan', 'os/PersistableBundle', 'text/TextUtils', 'os/Parcel', 'os/BaseBundle', 'util/ArrayMap'] {
		url := 'https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/' + aosp_revision + '/core/java/android/' + name + '.java'
		response := http.get(url)!
		assert response.status_code == 200, url
		file := 'AOSP-' + name.all_after_last('/') + '.java'
		os.write_file(out + '/' + file, response.body)!
		aosp[url] = hash(out + '/' + file)!
	}
	contract := os.read_file(out + '/AOSP-TtsSpan.java')!.fields().join(' ')
	for body in ['public TtsSpan(String type, PersistableBundle args) { mType = type; mArgs = args; }',
		'public TtsSpan(Parcel src) { mType = src.readString(); mArgs = src.readPersistableBundle(); }',
		'public String getType() { return mType; }', 'public PersistableBundle getArgs() { return mArgs; }',
		'public int describeContents() { return 0; }', 'public void writeToParcelInternal(Parcel dest, int flags) { dest.writeString(mType); dest.writePersistableBundle(mArgs); }',
		'public int getSpanTypeIdInternal() { return TextUtils.TTS_SPAN; }', 'public TtsSpan build() { return new TtsSpan(mType, mArgs); }',
		'public C setStringArgument(String arg, String value) { mArgs.putString(arg, value); return (C) this; }',
		'public TextBuilder(String text) { this(); setText(text); }', 'public VerbatimBuilder(String verbatim) { this(); setVerbatim(verbatim); }',
		'public static class VerbatimBuilder extends SemioticClassBuilder<VerbatimBuilder>'] {
		assert contract.contains(body), body
	}
	assert os.read_file(out + '/AOSP-TextUtils.java')!.contains('public static final int TTS_SPAN = 24;')
	assert os.read_file(out + '/AOSP-PersistableBundle.java')!.fields().join(' ').contains('public PersistableBundle(int capacity) { super(capacity); mFlags = FLAG_DEFUSABLE; }')
	write_json(out + '/inputs.json', {
		'apk_sha256': maps_pin
		'dex_cache_root': dex_cache
		'dex_cache_manifest_sha256': dex_cache_seal
		'framework315_root': framework
		'framework315_manifest_sha256': framework_seal
		'maps317_root': maps317
		'maps317_manifest_sha256': maps317_seal
		'aosp_revision': aosp_revision
		'scope': 'Static API/provider proof and authenticated observed317 failure; runtime repair requires separate318/319 replay.'
		'immediate_path': 'classes.dex Lagdh;.f(CharSequence,String)Spannable: .line20 new TtsSpan; PersistableBundle(int), putString(android.arg.text,String), TtsSpan(android.type.text,bundle), setSpan flags0x21 over full text. Other put branches are generic and not needed by this String pair.'
	})!
	write_json(out + '/maps-dex-pins.json', dex_pins)!
	write_json(out + '/maps-tts-descriptors.json', actual_refs)!
	write_json(out + '/aosp-downloads.json', aosp)!
	mut after_jars := os.ls(tools_root)!.filter(it.ends_with('.jar'))
	after_jars.sort()
	assert jars == after_jars
	for path, pin in tools { assert hash(path)! == pin, path }
	for path, pin in before { assert hash(path)! == pin, path }
	for name, pin in dex_pins { assert hash(out + '/entries/' + name)! == pin, name }
	write_json(out + '/input-pins-after.json', before)!
	write_json(out + '/tools-after.json', tools)!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	write_json(out + '/sha256.json', pins)!
	println(out + ' ' + hash(out + '/sha256.json')!)
}
