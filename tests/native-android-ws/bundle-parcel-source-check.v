// SPDX-License-Identifier: GPL-2.0-or-later
// Copy this driver and its providers beneath a frozen V root before compiling.
// Source and Smali proof complements the separate same-APK ART regression.
module main

import androidtools
import crypto.sha256
import json2
import os
import startupfixture

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular source proof input: ' + key) }
		}
	}
}

fn command(root string, label string, argv []string) ! {
	r := os.exec(argv)
	os.write_file(root + '/' + label + '.log', r.output)!
	os.write_file(root + '/' + label + '.json', json2.encode({
		'argv':      json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, label + ': ' + r.output
	assert r.output.trim_space() == '', label + ': unexpected assembler diagnostics'
}

fn rejected_unchanged(dir string) ! {
	mut before := map[string]string{}
	inventory(dir, '', mut before)!
	mut rejected := false
	androidtools.framework_bundle_parcel(dir) or { rejected = true }
	assert rejected, 'invalid Bundle/Parcel provider input accepted'
	mut after := map[string]string{}
	inventory(dir, '', mut after)!
	assert before == after, 'rejected provider application mutated files'
}

fn extract(text string, signature string) !string {
	start := text.index(signature) or { return error('method missing: ' + signature) }
	tail := text[start..]
	end := tail.index('.end method') or { return error('method end missing') }
	return tail[..end + '.end method'.len]
}

fn write_inputs(dir string, originals map[string]string) ! {
	os.mkdir_all(dir + '/android/os')!
	for name, text in originals { os.write_file(dir + '/android/os/' + name, text)! }
}

fn map_reads(text string) int {
	mut count := 0
	for line in text.split('\n') {
		trimmed := line.trim_space()
		if trimmed.starts_with('iget-object ') && trimmed.contains(';->mMap:Landroid/util/ArrayMap;') {
			count++
		}
	}
	return count
}

fn map_accessors_guarded(old string, patched string, expected int) ! {
	assert map_reads(old) == expected, 'unexpected baseline Bundle map read count'
	for body in old.split('.method ')[1..] {
		signature := '.method ' + body.all_before('\n') + '\n'
		assert map_reads(extract(patched, signature)!) == 0, 'original Bundle method bypasses deferred map access: ' + signature
	}
}

fn monitor_guarded(text string, signature string, receiver string) ! {
	body := extract(text, signature)!
	assert body.count('monitor-enter ' + receiver) == 1
	assert body.count('monitor-exit ' + receiver) == 2, 'Bundle monitor must release on normal and exceptional exits'
	assert body.count('.catchall ') == 1 && body.contains('throw v0'), 'Bundle monitor has no exceptional cleanup'
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 5, 'WORK_ROOT BASELINE_SMALI_ROOT JAVA JARS'
	root := os.abs_path(os.args[1])
	baseline := os.abs_path(os.args[2])
	java := os.abs_path(os.args[3])
	jars := os.abs_path(os.args[4])
	assert !os.exists(root + '/smali') && !os.exists(root + '/classes.dex')
	mut inputs := map[string]string{}
	inputs[java] = hash(java)!
	for name in os.ls(jars)! { inputs[jars + '/' + name] = hash(jars + '/' + name)! }
	mut originals := map[string]string{}
	for name in ['BaseBundle', 'Bundle', 'Parcel', 'PersistableBundle', 'Parcelable',
		'Parcelable$Creator', 'Parcelable$ClassLoaderCreator'] {
		path := baseline + '/android/os/' + name + '.smali'
		inputs[path] = hash(path)!
		originals[name + '.smali'] = os.read_file(path)!
	}
	// Every malformed case is a fresh complete input tree. Rejection must leave
	// the entire tree, including occupied destinations, byte-for-byte unchanged.
	for n in 0 .. 5 {
		dir := root + '/rejected-' + n.str()
		write_inputs(dir, originals)!
		if n == 3 {
			os.write_file(dir + '/android/os/VinixBundleCreator.smali', 'destination already occupied\n')!
			rejected_unchanged(dir)!
			continue
		}
		if n == 4 {
			os.write_file(dir + '/android/os/Parcelable$ClassLoaderCreator.smali',
				originals['Parcelable$ClassLoaderCreator.smali'] + '\n.method public abstract createFromParcel(Landroid/os/Parcel;Ljava/lang/ClassLoader;)Ljava/lang/Object;\n.end method\n')!
			rejected_unchanged(dir)!
			continue
		}
		name := if n == 0 {
			'Parcel'
		} else if n == 1 {
			'Bundle'
		} else {
			'BaseBundle'
		}
		old := originals[name + '.smali']
		anchor := match n {
			0 { '.method public readBundle()Landroid/os/Bundle;' }
			1 { '.method public readFromParcel(Landroid/os/Parcel;)V' }
			else { '.field mMap:Landroid/util/ArrayMap;' }
		}
		assert old.count(anchor) == 1
		os.write_file(dir + '/android/os/' + name + '.smali', old.replace(anchor,
			anchor.replace('readBundle', 'missingReadBundle').replace('readFromParcel',
				'missingReadFromParcel').replace('mMap:', 'missingMap:')))!
		rejected_unchanged(dir)!
	}
	dir := root + '/smali'
	write_inputs(dir, originals)!
	androidtools.framework_bundle_parcel(dir)!
	rejected_unchanged(dir)!
	base := os.read_file(dir + '/android/os/BaseBundle.smali')!
	bundle := os.read_file(dir + '/android/os/Bundle.smali')!
	map_accessors_guarded(originals['BaseBundle.smali'], base, 20)!
	map_accessors_guarded(originals['Bundle.smali'], bundle, 58)!
	for signature in [
		'.method final declared-synchronized vinixGetMap()Landroid/util/ArrayMap;\n',
		'.method final declared-synchronized vinixReadFromParcel(Landroid/os/Parcel;I)V\n',
		'.method final declared-synchronized vinixWriteToParcel(Landroid/os/Parcel;)V\n',
		'.method final declared-synchronized vinixClear()V\n',
		'.method final declared-synchronized vinixIsParcelled()Z\n',
	] {
		monitor_guarded(base, signature, 'p0')!
	}
	monitor_guarded(base, '.method final vinixCopyFrom(Landroid/os/BaseBundle;)V\n', 'p1')!
	monitor_guarded(bundle, '.method public declared-synchronized toString()Ljava/lang/String;\n', 'p0')!
	for signature in ['.method final vinixCopyFrom(Landroid/os/BaseBundle;)V\n',
		'.method final declared-synchronized vinixReadFromParcel(Landroid/os/Parcel;I)V\n',
		'.method final declared-synchronized vinixWriteToParcel(Landroid/os/Parcel;)V\n'] {
		assert extract(base, signature)!.contains('Landroid/os/Parcel;->appendFrom(Landroid/os/Parcel;II)V'), 'Bundle snapshot loses local Binder references'
	}
	for name in ['PersistableBundle', 'Parcelable', 'Parcelable$Creator'] {
		assert os.read_file(dir + '/android/os/' + name + '.smali')! == originals[name + '.smali'], 'unrelated framework class changed: ' + name
	}
	creator := os.read_file(dir + '/android/os/Parcelable$ClassLoaderCreator.smali')!
	loader_creator := '.method public abstract createFromParcel(Landroid/os/Parcel;Ljava/lang/ClassLoader;)Ljava/lang/Object;\n'
	assert creator.count(loader_creator) == 1, 'ClassLoaderCreator overload declaration missing'
	assert creator.replace(extract(creator, loader_creator)!, '').trim_space() == originals['Parcelable$ClassLoaderCreator.smali'].trim_space(), 'unrelated ClassLoaderCreator interface source changed'
	parcel := os.read_file(dir + '/android/os/Parcel.smali')!
	mut unrelated := parcel
	for signature in ['.method public readBundle()Landroid/os/Bundle;\n',
		'.method public readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;\n',
		'.method public writeBundle(Landroid/os/Bundle;)V\n',
		'.method public readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;\n'] {
		unrelated = unrelated.replace(extract(parcel, signature)!, extract(originals['Parcel.smali'], signature)!)
	}
	assert unrelated == originals['Parcel.smali'], 'unrelated Parcel encoding or Binder behavior changed'
	assert extract(parcel, '.method public readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;\n')!.contains('Landroid/os/Parcelable$ClassLoaderCreator;->createFromParcel(Landroid/os/Parcel;Ljava/lang/ClassLoader;)Ljava/lang/Object;'), 'Parcel does not dispatch to the loader-aware creator overload'
	for signature in ['.method public readBundle()Landroid/os/Bundle;\n',
		'.method public readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;\n'] {
		body := extract(parcel, signature)!
		assert !body.contains('->readValue('), 'Bundle values decoded before a caller can set its loader'
		assert !body.contains('->readParcelable('), 'Bundle parcelable decoded eagerly'
	}
	for signature in [
		'.method public readPersistableBundle()Landroid/os/PersistableBundle;\n',
		'.method public readPersistableBundle(Ljava/lang/ClassLoader;)Landroid/os/PersistableBundle;\n',
		'.method public writePersistableBundle(Landroid/os/PersistableBundle;)V\n',
	] {
		assert extract(parcel, signature)! == extract(originals['Parcel.smali'], signature)!, 'PersistableBundle encoding changed'
	}
	fixture := dir + '/org/vinix/bootstrap'
	os.mkdir_all(fixture)!
	startupfixture.install_bundle_parcel_probe(fixture)!
	assert os.ls(fixture)!.len == 4, 'unexpected Bundle parcel fixture inventory'
	command(root, 'assemble', [java, '-cp', jars + '/*', 'org.jf.smali.Main', 'assemble', '--api',
		'28', '--jobs', '2', dir, '-o', root + '/classes.dex'])!
	assert os.file_size(root + '/classes.dex') > 0, 'assembler did not create DEX'
	command(root, 'disassemble', [java, '-cp', jars + '/*', 'org.jf.baksmali.Main', 'disassemble',
		'--api', '28', '--jobs', '2', root + '/classes.dex', '-o', root + '/disassembled'])!
	mut generated := map[string]string{}
	inventory(dir, '', mut generated)!
	mut classes := map[string]string{}
	inventory(root + '/disassembled', '', mut classes)!
	assert generated.len == 12, 'expected seven baseline, one provider and four fixture classes'
	assert classes.len == generated.len, 'assembled class inventory differs from generated input'
	for name in generated.keys() {
		assert name in classes, 'missing assembled class: ' + name
	}
	for name in ['BundleParcelProbe', 'BundleParcelValue', 'BundleParcelCreator',
		'BundleParcelRejectLoader'] {
		assert 'org/vinix/bootstrap/' + name + '.smali' in classes
	}
	assert 'android/os/VinixBundleCreator.smali' in classes
	for path, pin in inputs {
		assert hash(path)! == pin, 'input changed during source proof: ' + path
	}
	os.write_file(root + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(root + '/validation.json', json2.encode({
		'scope':               'Host source generation, malformed/destination/interface and duplicate rejection without mutation, deferred Bundle reads and 78 map accesses, explicit monitor cleanup, Binder-preserving snapshots, unchanged unrelated Parcel and PersistableBundle encoding, twelve-class API28 assemble/disassemble; separate ART evidence is required.'
		'malformed_cases':     '5'
		'duplicate_unchanged': 'true'
		'guarded_map_reads':   '78'
		'assembled_classes':   classes.len.str()
		'dex_sha256':          hash(root + '/classes.dex')!
	}, prettify: true) + '\n')!
	println('BUNDLE-PARCEL-SOURCE-CHECK-PASS guards=6 classes=' + classes.len.str() + ' dex=' + hash(root + '/classes.dex')!)
}
