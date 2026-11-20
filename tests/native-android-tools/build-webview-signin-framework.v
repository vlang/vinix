// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const webview_path = '/android/webkit/WebView.smali'
const settings_path = '/android/webkit/WebSettings.smali'

fn refused(source string, settings bool) bool {
	if settings {
		androidtools.framework_websettings_signin_source(source) or { return true }
	} else {
		androidtools.framework_webview_signin_source(source) or { return true }
	}
	return false
}

fn main() {
	if os.args.len != 3 {
		panic('usage: build-webview-signin-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT')
	}
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') {
		panic('fresh external output required')
	}
	tools := os.getenv_opt('VINIX_SMALI_TOOLS') or { os.real_path('build/android-framework/tools') }
	webview := os.read_file(base + '/smali' + webview_path)!
	settings := os.read_file(base + '/smali' + settings_path)!
	changed_webview := androidtools.framework_webview_signin_source(webview)!
	changed_settings := androidtools.framework_websettings_signin_source(settings)!
	mut refusals := 0
	for declaration in ['.class public Landroid/webkit/WebView;', '.super Landroid/view/ViewGroup;',
		'.method public loadUrl(Ljava/lang/String;)V', '.method internalLoadChanged(ILjava/lang/String;)V'] {
		assert refused(webview.replace(declaration, ''), false)
		refusals++
	}
	for member in ['.field private vinixUrl:Ljava/lang/String;', '.method public getUrl()Ljava/lang/String;',
		'.method public canGoBack()Z', '.method public goBack()V', '.method public setMapTrackballToArrowKeys(Z)V',
		'.method public removeJavascriptInterface(Ljava/lang/String;)V'] {
		assert refused(webview + '\n' + member + '\n', false)
		refusals++
	}
	assert refused(changed_webview, false)
	assert refused(settings.replace('.class public Landroid/webkit/WebSettings;', ''), true)
	assert refused(changed_settings, true)
	refusals += 3
	assert changed_webview.count('iput-object p1, p0, Landroid/webkit/WebView;->vinixUrl:Ljava/lang/String;') == 1
	assert changed_webview.count('iput-object p2, p0, Landroid/webkit/WebView;->vinixUrl:Ljava/lang/String;') == 1
	os.mkdir_all(root)!
	os.cp_all(base + '/smali', root + '/smali', false)!
	os.write_file(root + '/smali' + webview_path, changed_webview)!
	os.write_file(root + '/smali' + settings_path, changed_settings)!
	os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	cp := tools + '/*'
	for args in [
		[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2',
			root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
		[java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes',
			'Landroid/webkit/WebView;,Landroid/webkit/WebSettings;', '--jobs', '2', root + '/classes.dex',
			'-o', root + '/roundtrip'],
	] {
		if os.system_args(args) != 0 {
			panic('SDK assembly/readback failed')
		}
	}
	readback := os.read_file(root + '/roundtrip' + webview_path)!
	for method in ['getUrl()Ljava/lang/String;', 'getOriginalUrl()Ljava/lang/String;',
		'loadUrl(Ljava/lang/String;Ljava/util/Map;)V', 'canGoBack()Z', 'goBack()V',
		'removeJavascriptInterface(Ljava/lang/String;)V', 'setMapTrackballToArrowKeys(Z)V'] {
		assert readback.contains('.method public ' + method)
	}
	settings_readback := os.read_file(root + '/roundtrip' + settings_path)!
	assert settings_readback.contains('.method public setLightTouchEnabled(Z)V')
	assert settings_readback.contains('.method public setNeedInitialFocus(Z)V')
	println('WEBVIEW-SIGNIN-SDK-PASS assembly readback ${refusals}-input-refusals')
}
