// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The native browser transport is not an Android WebView provider package.
// No Android provider is selected or loaded, so this query has no package to
// return and must not initialize either a provider or the browser transport.
pub fn framework_webview_package_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	mut fields := lines.filter(it.fields().len > 0 && it.fields()[0] == '.field')
	fields.sort()
	if lines.filter(it.fields().len > 0 && it.fields()[0] == '.class') != [
		'.class public Landroid/webkit/WebView;',
	] || lines.filter(it.fields().len > 0 && it.fields()[0] == '.super') != [
		'.super Landroid/view/ViewGroup;',
	] || fields != [
		'.field private vinixWebSettings:Landroid/webkit/WebSettings;',
		'.field private webViewClient:Landroid/webkit/WebViewClient;',
	] || lines.any(it.fields().len > 0 && it.fields()[0] == '.implements') {
		return error('canonical WebView class and retained fields required')
	}
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end' && it.fields()[1] == 'method')
	blocks := original.split('.method ')[1..]
	if headers.len != 42 || blocks.len != headers.len || ends.len != headers.len
		|| ends.any(it != '.end method') {
		return error('42 balanced canonical WebView methods required')
	}
	mut signatures := map[string]bool{}
	mut natives := []string{}
	for block in blocks {
		header := block.all_before('\n')
		name := header.all_after_last(' ')
		if header.trim_space() != header || !name.contains('(') || name in signatures
			|| block.count('.end method') != 1 {
			return error('unique complete WebView methods required')
		}
		if name.all_before('(') == 'getCurrentWebViewPackage' {
			return error('WebView package query already exists')
		}
		signatures[name] = true
		if header.fields().contains('native') {
			declaration := '.method ' + block.all_before('.end method') + '.end method'
			if declaration.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '') != [
				'.method ' + header,
				'.end method',
			] {
				return error('unchanged native WebView declarations required')
			}
			natives << '.method ' + header
		}
	}
	// The generator and DEX disassembler order declarations differently.
	// Compare the complete sets while returning the original bytes unchanged.
	natives.sort()
	if natives != [
		'.method private native native_destroy()V',
		'.method private native native_loadDataWithBaseURL(JLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V',
		'.method private native native_loadUrl(JLjava/lang/String;)V',
		'.method private native native_onTouchEvent(Landroid/view/MotionEvent;)Z',
		'.method private native native_setJavaScriptEnabled(Z)V',
		'.method protected native native_constructor(Landroid/content/Context;Landroid/util/AttributeSet;)J',
	] {
		return error('six original native WebView declarations required')
	}
	return original + '\n.method public static getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;\n.registers 1\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
}

pub fn framework_webview_package(smali string) ! {
	path := smali + '/android/webkit/WebView.smali'
	patched := framework_webview_package_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}
