// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

fn main() {
	assert os.args.len in [1, 3], 'usage: check-framework-webview [SMALI_TOOLS JAVA]'
	view := '.class public Landroid/webkit/WebView;\n.super Landroid/view/ViewGroup;\n' +
		'.field private webViewClient:Landroid/webkit/WebViewClient;\n' +
		'.method private native native_loadUrl(JLjava/lang/String;)V\n.end method\n'
	settings := '.class public Landroid/webkit/WebSettings;\n.super Ljava/lang/Object;\n'
	client := '.class public Landroid/webkit/WebViewClient;\n.super Ljava/lang/Object;\n' +
		'.method public onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;)V\n.locals 0\nreturn-void\n.end method\n'
	cookie := '.class public Landroid/webkit/CookieManager;\n.super Ljava/lang/Object;\n' +
		'.method public unrelated()V\n.locals 0\nreturn-void\n.end method\n'
	patched := androidtools.framework_webview_sources(view, settings, client, cookie)!
	w := patched['WebView']!
	s := patched['WebSettings']!
	c := patched['CookieManager']!
	assert w.contains('iput-object v0, p0, Landroid/webkit/WebView;->vinixWebSettings:')
	assert w.contains('if-nez v0, :done\nnew-instance v0, Landroid/webkit/WebSettings;')
	assert w.contains('->setFocusableInTouchMode(Z)V')
	assert w.contains('native_destroy()V') && w.contains('native_onTouchEvent(Landroid/view/MotionEvent;)Z')
	assert w.contains('native_setJavaScriptEnabled(Z)V') && s.contains('->vinixSetJavaScriptEnabled(Z)V')
	assert w.contains('->onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;Landroid/graphics/Bitmap;)V')
	assert w.contains('->shouldOverrideUrlLoading(Landroid/webkit/WebView;Ljava/lang/String;)Z')
	assert w.contains('->onReceivedError(Landroid/webkit/WebView;ILjava/lang/String;Ljava/lang/String;)V')
	assert !w.contains('System;->out')
	assert c.contains('.method public unrelated()V\n.locals 0\nreturn-void\n.end method')
	assert c.contains('nativeGetCookie(Ljava/lang/String;)Ljava/lang/String;')
	assert c.contains('nativeSetCookie(Ljava/lang/String;Ljava/lang/String;)Z')
	assert c.contains('nativeFlush()Z')
	callback := c.all_after('.method public setCookie(Ljava/lang/String;Ljava/lang/String;Landroid/webkit/ValueCallback;)V').all_before('.end method')
	handler_at := callback.index('Handler;-><init>()V') or { panic('missing callback Handler') }
	set_at := callback.index('->nativeSetCookie(') or { panic('missing cookie set') }
	post_at := callback.index('Handler;->post(') or { panic('missing callback post') }
	assert handler_at < set_at && set_at < post_at
	assert callback.count('Handler;->post(') == 1
	assert androidtools.framework_webview_callback().count('->onReceiveValue(') == 1
	assert c.count('.method private static native nativeClear(Z)Z\n.end method') == 1
	for flag, names in {
		'0': ['removeAllCookie', 'removeAllCookies']
		'1': ['removeSessionCookie', 'removeSessionCookies']
	} {
		legacy := c.all_after('.method public ' + names[0] + '()V\n').all_before('.end method')
		assert legacy.contains('const/4 v0, ' + flag + '\ninvoke-static {v0}, Landroid/webkit/CookieManager;->nativeClear(Z)Z')
		assert !legacy.contains('Handler;') && !legacy.contains('.catch')
		clear := c.all_after('.method public ' + names[1] + '(Landroid/webkit/ValueCallback;)V\n').all_before('.end method')
		handler := clear.index('Handler;-><init>()V') or { panic('missing clear callback Handler') }
		remove := clear.index('->nativeClear(Z)Z') or { panic('missing cookie deletion') }
		post := clear.index('Handler;->post(') or { panic('missing clear callback post') }
		assert handler < remove && remove < post
		assert clear.contains('if-eqz p1, :clear') && clear.contains('if-eqz v0, :done')
		assert clear.contains('const/4 v1, ' + flag + '\ninvoke-static {v1}')
		assert clear.contains('move-result v2') && clear.contains('invoke-direct {v3, p1, v2}')
		assert clear.count('->nativeClear(') == 1 && clear.count('Handler;->post(') == 1
		assert !clear.contains('->onReceiveValue(') && !clear.contains('.catch')
	}
	assert androidtools.framework_webview_cookie_clear(c)! == c
	mut clear_rejected := 0
	for invalid in [c.replace(' Landroid/webkit/CookieManager;\n', ' LOther;\n'),
		c + '\n.method public removeAllCookie()V\n.locals 0\nreturn-void\n.end method\n'] {
		androidtools.framework_webview_cookie_clear(invalid) or { clear_rejected++; continue }
	}
	assert clear_rejected == 2
	mut rejected := false
	androidtools.framework_webview_sources(w, s, patched['WebViewClient']!, c) or { rejected = true }
	assert rejected
	if os.args.len == 3 {
		work := os.join_path(os.temp_dir(), 'vinix-framework-webview-' + os.getpid().str())
		os.mkdir_all(work + '/smali/android/webkit')!
		defer { os.rmdir_all(work) or {} }
		for name, source in patched {
			os.write_file(work + '/smali/android/webkit/' + name + '.smali', source)!
		}
		os.write_file(work + '/smali/android/webkit/VinixCookieCallback.smali', androidtools.framework_webview_callback())!
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[1]), os.args[2])!
		assert os.read_bytes(work + '/classes.dex')!.len > 112
	}
	println('FRAMEWORK-WEBVIEW-PASS retained-settings engine-native-bindings standard-client-callbacks caller-handler clear-all-and-session backend-boolean idempotence-guard')
}
