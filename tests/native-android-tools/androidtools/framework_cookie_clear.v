// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// nativeClear completes against the real engine before returning whether any
// matching cookies existed. JNI throws on failure, so false means empty.
pub fn framework_webview_cookie_clear(source string) !string {
	if source.split_into_lines().filter(it.trim_space().starts_with('.class ')).len != 1
		|| !source.split_into_lines().any(it.trim_space().starts_with('.class ')
		&& it.trim_space().ends_with(' Landroid/webkit/CookieManager;')) {
		return error('expected CookieManager declaration')
	}
	mut text := framework_replace_method(source, 'nativeClear(Z)Z',
		'.method private static native nativeClear(Z)Z\n.end method')!
	for flag, names in {
		'0': ['removeAllCookie', 'removeAllCookies']
		'1': ['removeSessionCookie', 'removeSessionCookies']
	} {
		text = framework_replace_method(text, names[0] + '()V',
			'.method public ' + names[0] + '()V\n.locals 1\nconst/4 v0, ' + flag + '\n' +
				'invoke-static {v0}, Landroid/webkit/CookieManager;->nativeClear(Z)Z\nreturn-void\n.end method')!
		// Construct the caller's Handler before mutation. Null callbacks do not
		// need a Looper; non-null callbacks are posted after successful deletion.
		text = framework_replace_method(text, names[1] + '(Landroid/webkit/ValueCallback;)V',
			'.method public ' + names[1] + '(Landroid/webkit/ValueCallback;)V\n.locals 4\n' +
				'const/4 v0, 0\nif-eqz p1, :clear\nnew-instance v0, Landroid/os/Handler;\n' +
				'invoke-direct {v0}, Landroid/os/Handler;-><init>()V\n:clear\nconst/4 v1, ' + flag + '\n' +
				'invoke-static {v1}, Landroid/webkit/CookieManager;->nativeClear(Z)Z\nmove-result v2\n' +
				'if-eqz v0, :done\nnew-instance v3, Landroid/webkit/VinixCookieCallback;\n' +
				'invoke-direct {v3, p1, v2}, Landroid/webkit/VinixCookieCallback;-><init>(Landroid/webkit/ValueCallback;Z)V\n' +
				'invoke-virtual {v0, v3}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\n:done\nreturn-void\n.end method')!
	}
	return text
}
