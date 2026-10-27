// SPDX-License-Identifier: GPL-2.0-or-later
// Signed generic API probe. Assembly is not ART execution or Google login proof.
module main

import crypto.sha256
import json2
import os

const owner = 'Lorg/vinix/servicequery/Main;'
const context = 'Landroid/content/Context;'
const client = 'org.vinix.servicequery.client'
const disabled = 'org.vinix.servicequery.disabled'
const marker = 'SERVICE-QUERY-PASS no-filter disabled-component disabled-application unexported multifilter-single missing-no-action-fallback component-package wrapper implicit-preserved metadata-preserved no-initialization direct-boot-metadata'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn failure(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn query_check() string {
	return method('private static check(${context}Ljava/lang/String;Ljava/lang/String;II)V', 6, '
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
invoke-virtual {v0, p1, p2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "org.vinix.servicequery.ACTION"
invoke-virtual {v0, v1}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0}, ${context}->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v1
invoke-virtual {v1, v0, p3}, Landroid/content/pm/PackageManager;->queryIntentServices(Landroid/content/Intent;I)Ljava/util/List;
move-result-object v1
if-eqz v1, :bad
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v2
if-ne v2, p4, :bad
if-eqz p4, :done
const/4 v2, 0
invoke-interface {v1, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/content/pm/ResolveInfo;
iget-object v1, v1, Landroid/content/pm/ResolveInfo;->serviceInfo:Landroid/content/pm/ServiceInfo;
if-eqz v1, :bad
iget-object v2, v1, Landroid/content/pm/PackageItemInfo;->name:Ljava/lang/String;
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
iget-object v2, v1, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;
invoke-virtual {p1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const-string v2, "org.vinix.servicequery.Disabled"
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :boot_metadata
iget-boolean v2, v1, Landroid/content/pm/ComponentInfo;->enabled:Z
if-nez v2, :bad
:boot_metadata
const/4 v3, 0
const-string v2, "org.vinix.servicequery.BootAware"
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-nez v2, :boot_true
const-string v2, "org.vinix.servicequery.BootResource"
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :boot_compare
:boot_true
const/4 v3, 1
:boot_compare
iget-boolean v2, v1, Landroid/content/pm/ServiceInfo;->directBootAware:Z
if-ne v2, v3, :bad
new-instance v4, Landroid/content/pm/ServiceInfo;
invoke-direct {v4, v1}, Landroid/content/pm/ServiceInfo;-><init>(Landroid/content/pm/ServiceInfo;)V
iget-boolean v2, v4, Landroid/content/pm/ServiceInfo;->directBootAware:Z
if-ne v2, v3, :bad
:app_metadata
const-string v2, "org.vinix.servicequery.disabled"
invoke-virtual {p1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :intent_identity
iget-object v2, v1, Landroid/content/pm/ComponentInfo;->applicationInfo:Landroid/content/pm/ApplicationInfo;
if-eqz v2, :bad
iget-boolean v2, v2, Landroid/content/pm/ApplicationInfo;->enabled:Z
if-nez v2, :bad
:intent_identity
invoke-virtual {v0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v2
invoke-virtual {v2}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v2
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
:done
return-void
' + failure('explicit service query result or intent identity'))
}

fn implicit_check() string {
	return method('private static implicit(${context})V', 4, '
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "org.vinix.servicequery.ACTION"
invoke-virtual {v0, v1}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0}, ${context}->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v1
const/4 v2, 0
invoke-virtual {v1, v0, v2}, Landroid/content/pm/PackageManager;->queryIntentServices(Landroid/content/Intent;I)Ljava/util/List;
move-result-object v1
if-eqz v1, :bad
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v1
const/4 v2, 2
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v1
if-nez v1, :bad
return-void
' + failure('implicit service query changed'))
}

fn query(package_name string, class_name string, flags int, count int) string {
	return 'const-string v1, "${package_name}"\nconst-string v2, "org.vinix.servicequery.${class_name}"\nconst v3, ${flags}\nconst/4 v4, ${count}\ninvoke-static {v0, v1, v2, v3, v4}, ${owner}->check(${context}Ljava/lang/String;Ljava/lang/String;II)V\n'
}

fn component_array_check() string {
 return method('private static component([Landroid/content/pm/ComponentInfo;Ljava/lang/String;Z)V', 5, '
if-eqz p0, :bad
const/4 v0, 0
array-length v1, p0
:scan
if-ge v0, v1, :bad
aget-object v2, p0, v0
iget-object v3, v2, Landroid/content/pm/PackageItemInfo;->name:Ljava/lang/String;
invoke-virtual {p1, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-nez v3, :found
add-int/lit8 v0, v0, 1
goto :scan
:found
iget-boolean v3, v2, Landroid/content/pm/ComponentInfo;->directBootAware:Z
if-ne v3, p2, :bad
new-instance v4, Landroid/content/pm/ComponentInfo;
invoke-direct {v4, v2}, Landroid/content/pm/ComponentInfo;-><init>(Landroid/content/pm/ComponentInfo;)V
iget-boolean v3, v4, Landroid/content/pm/ComponentInfo;->directBootAware:Z
if-ne v3, p2, :bad
return-void
' + failure('component direct boot metadata or copy'))
}

fn metadata_check() string {
 mut body := '
new-instance v0, Landroid/content/pm/ComponentInfo;
invoke-direct {v0}, Landroid/content/pm/ComponentInfo;-><init>()V
iget-boolean v1, v0, Landroid/content/pm/ComponentInfo;->directBootAware:Z
if-nez v1, :bad
const/4 v1, 1
iput-boolean v1, v0, Landroid/content/pm/ComponentInfo;->directBootAware:Z
new-instance v2, Landroid/content/pm/ComponentInfo;
invoke-direct {v2, v0}, Landroid/content/pm/ComponentInfo;-><init>(Landroid/content/pm/ComponentInfo;)V
iget-boolean v1, v2, Landroid/content/pm/ComponentInfo;->directBootAware:Z
if-eqz v1, :bad
invoke-virtual {p0}, ${context}->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
const-string v1, "${disabled}"
const v2, 0x20b
invoke-virtual {v0, v1, v2}, Landroid/content/pm/PackageManager;->getPackageInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;
move-result-object v0
if-eqz v0, :bad
'
 for spec in [['activities', 'ActivityInfo', 'BootActivity', '1'], ['activities', 'ActivityInfo', 'BootAlias', '1'],
  ['activities', 'ActivityInfo', 'DefaultActivity', '0'], ['receivers', 'ActivityInfo', 'BootReceiver', '1'],
  ['receivers', 'ActivityInfo', 'DefaultReceiver', '0'], ['providers', 'ProviderInfo', 'BootProvider', '1'],
  ['providers', 'ProviderInfo', 'DefaultProvider', '0']] {
  body += 'iget-object v1, v0, Landroid/content/pm/PackageInfo;->' + spec[0] + ':[Landroid/content/pm/' + spec[1] + ';\n' +
   'const-string v2, "org.vinix.servicequery.' + spec[2] + '"\nconst/4 v3, ' + spec[3] + '\n' +
   'invoke-static {v1, v2, v3}, ${owner}->component([Landroid/content/pm/ComponentInfo;Ljava/lang/String;Z)V\n'
 }
 return method('private static metadata(${context})V', 4, body + 'return-void\n' + failure('ComponentInfo default/copy or companion metadata'))
}

fn main_class() string {
	mut source := '.class public ${owner}\n.super Landroid/app/Activity;\n'
	source += method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	source += query_check()
	source += implicit_check()
	source += component_array_check()
	source += metadata_check()
	mut body := 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nmove-object v0, p0\n'
	for wrapped in [false, true] {
		if wrapped {
			body += 'new-instance v0, Landroid/content/ContextWrapper;\ninvoke-direct {v0, p0}, Landroid/content/ContextWrapper;-><init>(${context})V\n'
		}
		body += query(client, 'Enabled', 0, 1)
		body += query(client, 'Disabled', 0, 0)
		body += query(client, 'Disabled', 0x10000200, 1)
		body += query(client, 'Multi', 0, 1)
		for name in ['BootAware', 'BootResource', 'BootFalse'] { body += query(client, name, 0, 1) }
		body += query(client, 'Missing', 0, 0)
		body += query('org.vinix.servicequery.absent', 'Multi', 0x200, 0)
		body += query(disabled, 'Enabled', 0, 0)
		body += query(disabled, 'Enabled', 0x200, 1)
		body += 'invoke-static {v0}, ${owner}->implicit(${context})V\n'
		body += 'invoke-static {v0}, ${owner}->metadata(${context})V\n'
	}
	body += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${marker}"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\ninvoke-virtual {v0}, Ljava/io/PrintStream;->flush()V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(${context})V\nconst-string v1, "Explicit service metadata query passed"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\nreturn-void'
	return source + method('public onCreate(Landroid/os/Bundle;)V', 5, body)
}

fn trap_class(name string, parent string) string {
	return '.class public Lorg/vinix/servicequery/${name};\n.super Landroid/app/${parent};\n' +
		method('public constructor <init>()V', 2, 'invoke-direct {p0}, Landroid/app/${parent};-><init>()V\ngoto :bad\n' + failure('metadata query instantiated ${name}'))
}

fn manifest(name string) string {
	package_name := if name == 'client' { client } else { disabled }
	mut components := '<service android:name="org.vinix.servicequery.Enabled" android:exported="false"/>'
	if name == 'client' {
		components += '<service android:name="org.vinix.servicequery.Disabled" android:enabled="false" android:exported="false" android:directBootAware="false"/>'
		components += '<service android:name="org.vinix.servicequery.Multi" android:exported="true"><intent-filter><action android:name="org.vinix.servicequery.ACTION"/></intent-filter><intent-filter><action android:name="org.vinix.servicequery.ACTION"/></intent-filter></service>'
		components += '<service android:name="org.vinix.servicequery.BootAware" android:exported="false" android:directBootAware="true"/><service android:name="org.vinix.servicequery.BootResource" android:exported="false" android:directBootAware="@bool/direct_boot_true"/><service android:name="org.vinix.servicequery.BootFalse" android:exported="false" android:directBootAware="@bool/direct_boot_false"/>'
		components += '<activity android:name="org.vinix.servicequery.Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>'
	} else {
		// The disabled companion is parsed for metadata only. Its Application
		// constructor traps any accidental startup while resolving these entries.
		components += '<activity android:name="org.vinix.servicequery.BootActivity" android:directBootAware="true"/><activity-alias android:name="org.vinix.servicequery.BootAlias" android:targetActivity="org.vinix.servicequery.BootActivity"/><activity android:name="org.vinix.servicequery.DefaultActivity"/>'
		components += '<receiver android:name="org.vinix.servicequery.BootReceiver" android:directBootAware="@bool/direct_boot_true"/><receiver android:name="org.vinix.servicequery.DefaultReceiver"/>'
		components += '<provider android:name="org.vinix.servicequery.BootProvider" android:authorities="org.vinix.servicequery.boot" android:directBootAware="true"/><provider android:name="org.vinix.servicequery.DefaultProvider" android:authorities="org.vinix.servicequery.default"/>'
	}
	app := if name == 'client' { '' } else { ' android:enabled="false" android:name="org.vinix.servicequery.TrapApp"' }
	return '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_name}" android:versionCode="1"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="29"/><application android:label="Service query ${name}"${app}>${components}</application></manifest>'
}

fn hash(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn recorded(out string, label string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/commands/' + label + '.json', json2.encode({
		'argv': json2.Any(args), 'exit_code': json2.Any(r.exit_code), 'output': json2.Any(r.output)
	}, prettify: true) + '\n') or { panic(err) }
	if r.exit_code != 0 { panic(r.output) }
	return r.output
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		if os.is_link(path) { return error('unexpected output symlink') }
		if os.is_dir(path) { inventory(root, key, mut pins)! } else if os.is_file(path) { pins[key] = hash(path) } else { return error('unexpected output file type') }
	}
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	out, aapt, resources, tools, java, signer := os.abs_path(os.args[1]), os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	if os.exists(out) || out == repo || out.starts_with(repo + '/') { panic('fresh external output required') }
	os.mkdir_all(out + '/commands')!
	key, keytool := out + '/fixture.p12', os.dir(java) + '/keytool'
	recorded(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Service Query Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), aapt, resources, java, signer, keytool] { inputs[os.real_path(path)] = hash(path) }
	for name in os.ls(tools)! { if name.ends_with('.jar') { inputs[tools + '/' + name] = hash(tools + '/' + name) } }
	mut apks := map[string]string{}
	for name in ['client', 'disabled'] {
		dir := out + '/' + name
		smali := dir + '/smali/org/vinix/servicequery'
		os.mkdir_all(smali)!
		os.mkdir_all(dir + '/res/values')!
		os.write_file(dir + '/res/values/values.xml', '<resources><string name="probe">Service query</string><bool name="direct_boot_true">true</bool><bool name="direct_boot_false">false</bool></resources>')!
		os.write_file(dir + '/AndroidManifest.xml', manifest(name))!
		if name == 'client' { os.write_file(smali + '/Main.smali', main_class())! } else { os.write_file(smali + '/TrapApp.smali', trap_class('TrapApp', 'Application'))! }
		for service in if name == 'client' { ['Enabled', 'Disabled', 'Multi', 'BootAware', 'BootResource', 'BootFalse'] } else { ['Enabled'] } { os.write_file(smali + '/' + service + '.smali', trap_class(service, 'Service'))! }
		recorded(out, name + '-compile', [aapt, 'compile', '--dir', dir + '/res', '-o', dir + '/resources.zip'])
		recorded(out, name + '-link', [aapt, 'link', '-I', resources, dir + '/resources.zip', '--manifest', dir + '/AndroidManifest.xml', '-o', dir + '/unsigned.apk'])
		recorded(out, name + '-manifest', [aapt, 'dump', 'xmltree', dir + '/unsigned.apk', '--file', 'AndroidManifest.xml'])
		build_apk(out, name, dir, tools, java, signer, key)!
		apks[name + '/probe.apk'] = hash(dir + '/probe.apk')
	}
	finish(out, repo, inputs, apks)!
}

fn build_apk(out string, name string, dir string, tools string, java string, signer string, key string) ! {
	assembly := recorded(out, name + '-assemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', dir + '/smali', '-o', dir + '/classes.dex'])
	assert assembly.trim_space() == '', assembly
	recorded(out, name + '-roundtrip', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', dir + '/classes.dex', '-o', dir + '/roundtrip'])
	if name == 'client' { assert os.read_file(dir + '/roundtrip/org/vinix/servicequery/Main.smali')!.contains(marker) }
	recorded(out, name + '-zip', ['/usr/bin/zip', '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])
	apk := dir + '/probe.apk'
	recorded(out, name + '-sign', [java, '-Xmx512m', '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, dir + '/unsigned.apk'])
	verified := recorded(out, name + '-verify', [java, '-Xmx512m', '-jar', signer, 'verify', '--verbose', apk])
	assert verified.contains('Verified using v3 scheme (APK Signature Scheme v3): true')
}

fn finish(out string, repo string, inputs map[string]string, apks map[string]string) ! {
	for path, pin in inputs { assert hash(path) == pin, 'input changed: ' + path }
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(out + '/build.json', json2.encode({
		'argv': json2.Any(os.args), 'source_revision': json2.Any(revision.output.trim_space()),
		'inputs_sha256': json2.decode[json2.Any](json2.encode(inputs))!, 'apks_sha256': json2.decode[json2.Any](json2.encode(apks))!,
		'pass_marker': json2.Any(marker), 'scope': json2.Any('Generic explicit query API regression. Signed APK generation and DEX roundtrip only until run under ART; no account or network activity. Metadata lookup must not construct services or companion Application.')
	}, prettify: true) + '\n')!
	os.cp(@FILE, out + '/builder.v')!
	os.cp(os.executable(), out + '/builder')!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('SERVICE-QUERY-FIXTURE-APKS ' + out)
	println('SERVICE-QUERY-FIXTURE-SEAL ' + hash(out + '/sha256.json'))
}
