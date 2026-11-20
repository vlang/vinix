// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const webview_path = '/android/webkit/WebView.smali'

fn refused(source string) bool {
	androidtools.framework_webview_bridge_source(source) or { return true }
	return false
}

fn main() {
	if os.args.len != 3 {
		panic('usage: build-webview-bridge-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT')
	}
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') {
		panic('fresh external output required')
	}
	tools := os.getenv_opt('VINIX_SMALI_TOOLS') or { os.real_path('build/android-framework/tools') }
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	original := os.read_file(base + '/smali' + webview_path)!
	changed := androidtools.framework_webview_bridge_source(original)!
	mut refusals := 0
	for declaration in ['.class public Landroid/webkit/WebView;',
		'.method public addJavascriptInterface(Ljava/lang/Object;Ljava/lang/String;)V',
		'.method public removeJavascriptInterface(Ljava/lang/String;)V'] {
		assert refused(original.replace(declaration, '')), declaration
		refusals++
	}
	assert refused(changed)
	refusals++
	os.mkdir_all(root + '/work')!
	// The Java bridge's own behavior, on the host JVM before it is packaged.
	sources := os.real_path('tests/native-android-tools/androidtools')
	check := root + '/work/check-classes'
	os.mkdir_all(check)!
	mut compile := [os.dir(java) + '/javac', '--release', '8', '-Xlint:-options', '-d', check]
	for name in ['java/android/webkit/JavascriptInterface.java', 'java/android/webkit/VinixJavascriptBridge.java',
		'java-check/android/webkit/VinixJavascriptBridgeCheck.java'] {
		compile << sources + '/' + name
	}
	for args in [compile, [java, '-cp', check, 'android.webkit.VinixJavascriptBridgeCheck']] {
		if os.system_args(args) != 0 {
			panic('Java bridge check failed')
		}
	}
	os.cp_all(base + '/smali', root + '/smali', false)!
	androidtools.framework_webview_bridge(root + '/smali', root + '/work', tools, java)!
	assert os.read_file(root + '/smali' + webview_path)! == changed
	os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
	cp := tools + '/*'
	for args in [
		[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2',
			root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
		[java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes',
			'Landroid/webkit/WebView;,Landroid/webkit/VinixJavascriptBridge;,Landroid/webkit/JavascriptInterface;',
			'--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip'],
	] {
		if os.system_args(args) != 0 {
			panic('SDK assembly/readback failed')
		}
	}
	webview := os.read_file(root + '/roundtrip' + webview_path)!
	for member in ['.method private native native_setJavascriptInterfaces(JLjava/lang/String;)V',
		'.method public internalJavascriptCall(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
		'Landroid/webkit/WebView;->vinixAddJavascriptInterface(Ljava/lang/Object;Ljava/lang/String;)V'] {
		assert webview.contains(member), member
	}
	bridge := os.read_file(root + '/roundtrip/android/webkit/VinixJavascriptBridge.smali')!
	assert bridge.contains('.method static call(Ljava/lang/Object;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;')
	assert bridge.contains('.method static spec(Ljava/util/Map;)Ljava/lang/String;')
	annotation := os.read_file(root + '/roundtrip/android/webkit/JavascriptInterface.smali')!
	assert annotation.contains('.class public interface abstract annotation Landroid/webkit/JavascriptInterface;')
	assert annotation.contains('RUNTIME')
	println('WEBVIEW-BRIDGE-SDK-PASS java-check assembly readback ${refusals}-input-refusals')
}
