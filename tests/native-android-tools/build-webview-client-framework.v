// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

fn main() {
	if os.args.len != 3 {
		panic('usage: build-webview-client-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT')
	}
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') {
		panic('fresh external output required')
	}
	tools := os.getenv_opt('VINIX_SMALI_TOOLS') or { os.real_path('build/android-framework/tools') }
	mut changed := map[string]string{}
	mut refusals := 0
	for name in androidtools.webview_client_names {
		original := os.read_file(base + '/smali/android/webkit/' + name + '.smali')!
		output := androidtools.framework_webview_client_transform(name, original)!
		// Applying twice and losing the class declaration must both be refused.
		for variant in [output, original.replace('.class public Landroid/webkit/' + name + ';', '')] {
			mut rejected := false
			androidtools.framework_webview_client_transform(name, variant) or { rejected = true }
			assert rejected, name
			refusals++
		}
		changed[name] = output
	}
	webview := changed['WebView']
	assert webview.contains('.method internalLoadChanged(ILjava/lang/String;)V\n    .registers 5\n')
	assert webview.contains('Landroid/webkit/WebViewClient;->onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;Landroid/graphics/Bitmap;)V')
	os.mkdir_all(root)!
	os.cp_all(base + '/smali', root + '/smali', false)!
	for name, source in changed {
		os.write_file(root + '/smali/android/webkit/' + name + '.smali', source)!
	}
	os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	cp := tools + '/*'
	classes := androidtools.webview_client_names.map('Landroid/webkit/' + it + ';').join(',')
	for args in [
		[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2',
			root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
		[java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', classes,
			'--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip'],
	] {
		if os.system_args(args) != 0 {
			panic('SDK assembly/readback failed')
		}
	}
	for name, method in {
		'WebView':             'reload()V'
		'WebSettings':         'setDisabledActionModeMenuItems(I)V'
		'WebViewClient':       'shouldOverrideUrlLoading(Landroid/webkit/WebView;Landroid/webkit/WebResourceRequest;)Z'
		'WebChromeClient':     'onConsoleMessage(Landroid/webkit/ConsoleMessage;)Z'
		'URLUtil':             'static isValidUrl(Ljava/lang/String;)Z'
		'WebResourceResponse': 'getStatusCode()I'
	} {
		readback := os.read_file(root + '/roundtrip/android/webkit/' + name + '.smali')!
		assert readback.contains('.method public ' + method), name
	}
	println('WEBVIEW-CLIENT-SDK-PASS assembly readback ${refusals}-input-refusals')
}
