// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const target = 'android/webkit/WebView.smali'
const signature = 'getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;'
const expected = '.method public static getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;\n.registers 1\nconst/4 v0, 0x0\nreturn-object v0\n.end method'

fn norm(text string) string {
	return text.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn methods(text string) !map[string]string {
	mut result := map[string]string{}
	for block in text.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || block.count('.end method') != 1 {
			return error('unique complete methods required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn verify(before string, after string, raw bool) ! {
	old, changed := methods(before)!, methods(after)!
	if old.len != 42 || changed.len != 43 || signature in old
		|| signature !in changed || norm(changed[signature]) != expected {
		return error('one exact public static null package query required')
	}
	for name, body in old {
		if name !in changed || body != changed[name] {
			return error('retained WebView method changed: ' + name)
		}
	}
	if norm(after.replace(changed[signature], '')) != norm(before) {
		return error('WebView metadata or fields changed')
	}
	if raw && after != before + '\n' + expected + '\n' {
		return error('only appended query may change raw source')
	}
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		before := os.read_file(work + '/baseline-roundtrip/' + target)!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 1
			verify(before, os.read_file(work + '/' + directory + '/' + target)!, false)!
		}
		assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!
		println('WEBVIEW-PACKAGE-ROUNDTRIP-PASS retained42 six-native-declarations null-package stable-second-DEX')
		return
	}
	path := work + '/proof/' + target
	before := os.read_file(path)!
	after := androidtools.framework_webview_package_source(before)!
	verify(before, after, true)!
	old := methods(before)!
	// Exercise generator ordering independently of canonical DEX ordering.
	mut reordered := before
	fields := ['.field private vinixWebSettings:Landroid/webkit/WebSettings;',
		'.field private webViewClient:Landroid/webkit/WebViewClient;']
	for field in fields { reordered = reordered.replace(field, '') }
	for field in fields.reverse() { reordered += '\n' + field + '\n' }
	mut native_names := old.keys().filter(old[it].all_before('\n').fields().contains('native'))
	native_names.sort()
	for name in native_names { reordered = reordered.replace(old[name], '') }
	for name in native_names.reverse() { reordered += '\n' + old[name] + '\n' }
	assert reordered != before
	verify(reordered, androidtools.framework_webview_package_source(reordered)!, true)!
	invalids := [after,
		before.replace('.class public Landroid/webkit/WebView;', '.class public final Landroid/webkit/WebView;'),
		before + '\n.class public Landroid/webkit/WebView;\n',
		before.replace('.super Landroid/view/ViewGroup;', '.super Landroid/view/View;'),
		before + '\n.super Landroid/view/ViewGroup;\n',
		before + '\n.field private fakePackage:Landroid/content/pm/PackageInfo;\n',
		before + '\n' + fields[0] + '\n',
		before.replace(fields[0], fields[1]),
		before + '\n.implements Ljava/lang/Runnable;\n', before + '\n.end method\n',
		before.replace('.method private static getFactory()', '.method\tprivate static getFactory()'),
		before.replace('.end method', ''), before + '\n' + old['<init>(Landroid/content/Context;)V'],
		before.replace('.method private static getFactory()Ljava/lang/Object;', '.method private static getCurrentWebViewPackage()Ljava/lang/Object;'),
		before.replace('.method private native native_destroy()V', '.method public native native_destroy()V'),
		before.replace('.method private native native_destroy()V', '.method private native native_destroy()V\n.registers 1\nreturn-void')]
	for invalid in invalids {
		assert invalid != before
		os.write_file(path, invalid)!
		mut rejected := false
		androidtools.framework_webview_package(work + '/proof') or { rejected = true }
		assert rejected && os.read_file(path)! == invalid, 'refusal must precede writes'
	}
	controls := [
		after.replace(expected, expected.replace('const/4 v0, 0x0', 'new-instance v0, Landroid/content/pm/PackageInfo;\ninvoke-direct {v0}, Landroid/content/pm/PackageInfo;-><init>()V')),
		after.replace(expected, expected.replace('public static', 'public')),
		after.replace(expected, expected.replace('public static', 'private static')),
		after.replace(expected, expected.replace('return-object v0', 'return v0')),
		after.replace(expected, expected.replace('const/4 v0, 0x0', 'invoke-static {}, Landroid/webkit/WebView;->getFactory()Ljava/lang/Object;\nmove-result-object v0\nconst/4 v0, 0x0')),
		after + '\n.field private static fakePackage:Landroid/content/pm/PackageInfo;\n',
		after.replace('invoke-direct {p0, p1, p2, p3}, Landroid/view/ViewGroup;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V', 'return-void'),
		after.replace('native_loadUrl(JLjava/lang/String;)V', 'native_loadUrl(JLjava/lang/String;I)V'),
		after.replace(old['internalLoadChanged(ILjava/lang/String;)V'], old['internalLoadChanged(ILjava/lang/String;)V'].replace('return-void', 'nop\nreturn-void')),
	]
	for broken in controls {
		assert broken != after
		mut rejected := false
		verify(before, broken, true) or { rejected = true }
		assert rejected, 'query semantics, surface or native callback control escaped oracle'
	}
	os.write_file(path, before)!
	androidtools.framework_webview_package(work + '/proof')!
	assert os.read_file(path)! == after
	println('WEBVIEW-PACKAGE-SOURCE-PASS refusals=' + invalids.len.str() + ' semantic-controls=' + controls.len.str() + ' generator-order retained42 null-package no-initialization six-native-declarations')
}
