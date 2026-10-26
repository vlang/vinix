// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn webview_method(flags string, name string, locals int, body string) string {
	return '.method ' + flags + ' ' + name + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

// Android wrappers retain the client and settings. Only events from the real
// engine enter internalLoadChanged/internalShouldOverrideUrlLoading on Looper.
pub fn framework_webview_sources(view_source string, settings_source string,
	client_source string, cookie_source string) !map[string]string {
	if !view_source.contains('.field private webViewClient:Landroid/webkit/WebViewClient;')
		|| view_source.contains('vinixWebSettings:') {
		return error('unexpected or already extended WebView declaration')
	}
	mut view := view_source + '\n.field private vinixWebSettings:Landroid/webkit/WebSettings;\n'
	view = framework_replace_method(view, '<init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V',
		webview_method('public constructor', '<init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V', 1,
			'invoke-direct {p0, p1, p2, p3}, Landroid/view/ViewGroup;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V\n' +
				'const/4 v0, 1\ninvoke-virtual {p0, v0}, Landroid/webkit/WebView;->setFocusable(Z)V\n' +
				'invoke-virtual {p0, v0}, Landroid/webkit/WebView;->setFocusableInTouchMode(Z)V\nreturn-void'))!
	view = framework_replace_method(view, 'getSettings()Landroid/webkit/WebSettings;',
		webview_method('public', 'getSettings()Landroid/webkit/WebSettings;', 1,
			'iget-object v0, p0, Landroid/webkit/WebView;->vinixWebSettings:Landroid/webkit/WebSettings;\nif-nez v0, :done\n' +
				'new-instance v0, Landroid/webkit/WebSettings;\ninvoke-direct {v0}, Landroid/webkit/WebSettings;-><init>()V\n' +
				'iput-object p0, v0, Landroid/webkit/WebSettings;->vinixOwner:Landroid/webkit/WebView;\n' +
				'iput-object v0, p0, Landroid/webkit/WebView;->vinixWebSettings:Landroid/webkit/WebSettings;\n:done\nreturn-object v0'))!
	for method in ['native_destroy()V', 'native_setJavaScriptEnabled(Z)V',
		'native_onTouchEvent(Landroid/view/MotionEvent;)Z'] {
		view = framework_replace_method(view, method, '.method private native ' + method + '\n.end method')!
	}
	view = framework_replace_method(view, 'destroy()V', webview_method('public', 'destroy()V', 0,
		'invoke-direct {p0}, Landroid/webkit/WebView;->native_destroy()V\nreturn-void'))!
	view = framework_replace_method(view, 'vinixSetJavaScriptEnabled(Z)V',
		webview_method('public', 'vinixSetJavaScriptEnabled(Z)V', 0,
			'invoke-direct {p0, p1}, Landroid/webkit/WebView;->native_setJavaScriptEnabled(Z)V\nreturn-void'))!
	view = framework_replace_method(view, 'onTouchEvent(Landroid/view/MotionEvent;)Z',
		webview_method('public', 'onTouchEvent(Landroid/view/MotionEvent;)Z', 1,
			'invoke-direct {p0, p1}, Landroid/webkit/WebView;->native_onTouchEvent(Landroid/view/MotionEvent;)Z\nmove-result v0\nreturn v0'))!
	view = framework_replace_method(view, 'loadUrl(Ljava/lang/String;)V',
		webview_method('public', 'loadUrl(Ljava/lang/String;)V', 2,
			'iget-wide v0, p0, Landroid/webkit/WebView;->widget:J\n' +
				'invoke-direct {p0, v0, v1, p1}, Landroid/webkit/WebView;->native_loadUrl(JLjava/lang/String;)V\nreturn-void'))!
	view = framework_replace_method(view, 'evaluateJavascript(Ljava/lang/String;Landroid/webkit/ValueCallback;)V',
		webview_method('public', 'evaluateJavascript(Ljava/lang/String;Landroid/webkit/ValueCallback;)V', 2,
			'new-instance v0, Ljava/lang/UnsupportedOperationException;\nconst-string v1, "WebView evaluateJavascript is unavailable"\n' +
				'invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V\nthrow v0'))!
	view = framework_replace_method(view, 'internalShouldOverrideUrlLoading(Ljava/lang/String;)Z',
		webview_method('public', 'internalShouldOverrideUrlLoading(Ljava/lang/String;)Z', 1,
			'iget-object v0, p0, Landroid/webkit/WebView;->webViewClient:Landroid/webkit/WebViewClient;\nif-eqz v0, :allow\n' +
				'invoke-virtual {v0, p0, p1}, Landroid/webkit/WebViewClient;->shouldOverrideUrlLoading(Landroid/webkit/WebView;Ljava/lang/String;)Z\n' +
				'move-result v0\nreturn v0\n:allow\nconst/4 v0, 0\nreturn v0'))!
	view = framework_replace_method(view, 'internalLoadChanged(ILjava/lang/String;)V',
		webview_method('public', 'internalLoadChanged(ILjava/lang/String;)V', 2,
			'iget-object v0, p0, Landroid/webkit/WebView;->webViewClient:Landroid/webkit/WebViewClient;\nif-eqz v0, :done\n' +
				'if-nez p1, :finished\nconst/4 v1, 0\n' +
				'invoke-virtual {v0, p0, p2, v1}, Landroid/webkit/WebViewClient;->onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;Landroid/graphics/Bitmap;)V\ngoto :done\n' +
				':finished\nconst/4 v1, 3\nif-ne p1, v1, :done\n' +
				'invoke-virtual {v0, p0, p2}, Landroid/webkit/WebViewClient;->onPageFinished(Landroid/webkit/WebView;Ljava/lang/String;)V\n:done\nreturn-void'))!
	view = framework_replace_method(view, 'internalLoadFailed(Ljava/lang/String;)V',
		webview_method('public', 'internalLoadFailed(Ljava/lang/String;)V', 3,
			'iget-object v0, p0, Landroid/webkit/WebView;->webViewClient:Landroid/webkit/WebViewClient;\nif-eqz v0, :done\n' +
				'const/4 v1, -1\nconst-string v2, "Web engine navigation failed"\n' +
				'invoke-virtual {v0, p0, v1, v2, p1}, Landroid/webkit/WebViewClient;->onReceivedError(Landroid/webkit/WebView;ILjava/lang/String;Ljava/lang/String;)V\n:done\nreturn-void'))!
	mut settings := settings_source + '\n.field public vinixOwner:Landroid/webkit/WebView;\n.field private vinixJavaScriptEnabled:Z\n'
	settings = framework_replace_method(settings, 'setJavaScriptEnabled(Z)V',
		webview_method('public', 'setJavaScriptEnabled(Z)V', 1,
			'iget-object v0, p0, Landroid/webkit/WebSettings;->vinixOwner:Landroid/webkit/WebView;\nif-eqz v0, :store\n' +
				'invoke-virtual {v0, p1}, Landroid/webkit/WebView;->vinixSetJavaScriptEnabled(Z)V\n' +
				':store\niput-boolean p1, p0, Landroid/webkit/WebSettings;->vinixJavaScriptEnabled:Z\nreturn-void'))!
	settings = framework_replace_method(settings, 'getJavaScriptEnabled()Z',
		webview_method('public', 'getJavaScriptEnabled()Z', 1,
			'iget-boolean v0, p0, Landroid/webkit/WebSettings;->vinixJavaScriptEnabled:Z\nreturn v0'))!
	mut client := client_source
	client = framework_replace_method(client, 'shouldOverrideUrlLoading(Landroid/webkit/WebView;Ljava/lang/String;)Z',
		webview_method('public', 'shouldOverrideUrlLoading(Landroid/webkit/WebView;Ljava/lang/String;)Z', 1,
			'const/4 v0, 0\nreturn v0'))!
	client = framework_replace_method(client, 'onReceivedError(Landroid/webkit/WebView;ILjava/lang/String;Ljava/lang/String;)V',
		webview_method('public', 'onReceivedError(Landroid/webkit/WebView;ILjava/lang/String;Ljava/lang/String;)V', 0, 'return-void'))!
	// Preserve applications overriding the old ATL callback while exposing the
	// Android callback signature used by Play Services.
	client = framework_replace_method(client, 'onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;Landroid/graphics/Bitmap;)V',
		webview_method('public', 'onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;Landroid/graphics/Bitmap;)V', 0,
			'invoke-virtual {p0, p1, p2}, Landroid/webkit/WebViewClient;->onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;)V\nreturn-void'))!
	mut cookies := cookie_source + '\n.field private static vinixInstance:Landroid/webkit/CookieManager;\n'
	cookies = framework_replace_method(cookies, 'getInstance()Landroid/webkit/CookieManager;',
		webview_method('public static synchronized', 'getInstance()Landroid/webkit/CookieManager;', 1,
			'sget-object v0, Landroid/webkit/CookieManager;->vinixInstance:Landroid/webkit/CookieManager;\nif-nez v0, :done\n' +
				'new-instance v0, Landroid/webkit/CookieManager;\ninvoke-direct {v0}, Landroid/webkit/CookieManager;-><init>()V\n' +
				'sput-object v0, Landroid/webkit/CookieManager;->vinixInstance:Landroid/webkit/CookieManager;\n:done\nreturn-object v0'))!
	for method in ['nativeSetCookie(Ljava/lang/String;Ljava/lang/String;)Z',
		'nativeGetCookie(Ljava/lang/String;)Ljava/lang/String;', 'nativeFlush()Z'] {
		cookies = framework_replace_method(cookies, method, '.method private static native ' + method + '\n.end method')!
	}
	cookies = framework_replace_method(cookies, 'setCookie(Ljava/lang/String;Ljava/lang/String;)V',
		webview_method('public', 'setCookie(Ljava/lang/String;Ljava/lang/String;)V', 0,
			'invoke-static {p1, p2}, Landroid/webkit/CookieManager;->nativeSetCookie(Ljava/lang/String;Ljava/lang/String;)Z\nreturn-void'))!
	cookies = framework_replace_method(cookies, 'getCookie(Ljava/lang/String;)Ljava/lang/String;',
		webview_method('public', 'getCookie(Ljava/lang/String;)Ljava/lang/String;', 1,
			'invoke-static {p1}, Landroid/webkit/CookieManager;->nativeGetCookie(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\nreturn-object v0'))!
	cookies = framework_replace_method(cookies, 'flush()V', webview_method('public', 'flush()V', 2,
		'invoke-static {}, Landroid/webkit/CookieManager;->nativeFlush()Z\nmove-result v0\nif-nez v0, :done\n' +
			'new-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "Unable to persist cookies"\n' +
			'invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0\n:done\nreturn-void'))!
	// Construct the caller's Handler before mutating cookies. A missing Looper
	// fails at the same point as Android rather than invoking on the engine loop.
	cookies = framework_replace_method(cookies, 'setCookie(Ljava/lang/String;Ljava/lang/String;Landroid/webkit/ValueCallback;)V',
		webview_method('public', 'setCookie(Ljava/lang/String;Ljava/lang/String;Landroid/webkit/ValueCallback;)V', 3,
			'const/4 v0, 0\nif-eqz p3, :set\nnew-instance v0, Landroid/os/Handler;\ninvoke-direct {v0}, Landroid/os/Handler;-><init>()V\n' +
				':set\ninvoke-static {p1, p2}, Landroid/webkit/CookieManager;->nativeSetCookie(Ljava/lang/String;Ljava/lang/String;)Z\nmove-result v1\n' +
				'if-eqz v0, :done\nnew-instance v2, Landroid/webkit/VinixCookieCallback;\n' +
				'invoke-direct {v2, p3, v1}, Landroid/webkit/VinixCookieCallback;-><init>(Landroid/webkit/ValueCallback;Z)V\n' +
				'invoke-virtual {v0, v2}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\n:done\nreturn-void'))!
	cookies = framework_webview_cookie_clear(cookies)!
	return {
		'WebView':       view
		'WebSettings':   settings
		'WebViewClient': client
		'CookieManager': cookies
	}
}

pub fn framework_webview_callback() string {
	return '.class public final Landroid/webkit/VinixCookieCallback;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
		'.field private callback:Landroid/webkit/ValueCallback;\n.field private accepted:Z\n' +
		webview_method('public constructor', '<init>(Landroid/webkit/ValueCallback;Z)V', 0,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/webkit/VinixCookieCallback;->callback:Landroid/webkit/ValueCallback;\n' +
				'iput-boolean p2, p0, Landroid/webkit/VinixCookieCallback;->accepted:Z\nreturn-void') +
		webview_method('public', 'run()V', 2,
			'iget-object v0, p0, Landroid/webkit/VinixCookieCallback;->callback:Landroid/webkit/ValueCallback;\n' +
				'iget-boolean v1, p0, Landroid/webkit/VinixCookieCallback;->accepted:Z\n' +
				'invoke-static {v1}, Ljava/lang/Boolean;->valueOf(Z)Ljava/lang/Boolean;\nmove-result-object v1\n' +
				'invoke-interface {v0, v1}, Landroid/webkit/ValueCallback;->onReceiveValue(Ljava/lang/Object;)V\nreturn-void')
}

fn framework_webview(smali string) ! {
	dir := smali + '/android/webkit/'
	patched := framework_webview_sources(os.read_file(dir + 'WebView.smali')!,
		os.read_file(dir + 'WebSettings.smali')!, os.read_file(dir + 'WebViewClient.smali')!,
		os.read_file(dir + 'CookieManager.smali')!)!
	for name, source in patched { os.write_file(dir + name + '.smali', source)! }
	os.write_file(dir + 'VinixCookieCallback.smali', framework_webview_callback())!
}
