// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

const webview_signin_load_url = '.method public loadUrl(Ljava/lang/String;)V\n    .registers 4\n'
const webview_signin_load_changed = '.method internalLoadChanged(ILjava/lang/String;)V\n    .registers 4\n'

// WebView members GMS's MinuteMaid sign-in fragment calls (found by
// framework-api-gaps on GMS 26.41.31). The engine has no history or
// request-header operation yet, so history reports no previous page and
// extra headers are not sent; getUrl reports the last requested or loaded
// URL. setMapTrackballToArrowKeys is a no-op in AOSP since API 17.
pub fn framework_webview_signin_source(original string) !string {
	for declaration in ['.class public Landroid/webkit/WebView;', '.super Landroid/view/ViewGroup;',
		webview_signin_load_url, webview_signin_load_changed] {
		if original.count(declaration + if declaration.ends_with('\n') { '' } else { '\n' }) != 1 {
			return error('canonical WebView sign-in input required')
		}
	}
	for member in ['vinixUrl:', 'getUrl()', 'canGoBack()', 'goBack()', 'setMapTrackballToArrowKeys(',
		'removeJavascriptInterface(', 'loadUrl(Ljava/lang/String;Ljava/util/Map;)'] {
		if original.contains(member) {
			return error('WebView sign-in member already exists')
		}
	}
	store := '    iput-object p1, p0, Landroid/webkit/WebView;->vinixUrl:Ljava/lang/String;\n'
	mut source := original.replace(webview_signin_load_url, webview_signin_load_url + store)
	source = source.replace(webview_signin_load_changed, webview_signin_load_changed +
		'    if-eqz p2, :vinix_url_known\n' +
		'    iput-object p2, p0, Landroid/webkit/WebView;->vinixUrl:Ljava/lang/String;\n' +
		'    :vinix_url_known\n')
	return source + r'
.field private vinixUrl:Ljava/lang/String;
.method public getUrl()Ljava/lang/String;
.locals 1
iget-object v0, p0, Landroid/webkit/WebView;->vinixUrl:Ljava/lang/String;
return-object v0
.end method
.method public getOriginalUrl()Ljava/lang/String;
.locals 1
iget-object v0, p0, Landroid/webkit/WebView;->vinixUrl:Ljava/lang/String;
return-object v0
.end method
.method public loadUrl(Ljava/lang/String;Ljava/util/Map;)V
.locals 0
invoke-virtual {p0, p1}, Landroid/webkit/WebView;->loadUrl(Ljava/lang/String;)V
return-void
.end method
.method public canGoBack()Z
.locals 1
const/4 v0, 0
return v0
.end method
.method public goBack()V
.locals 0
return-void
.end method
.method public removeJavascriptInterface(Ljava/lang/String;)V
.locals 0
return-void
.end method
.method public setMapTrackballToArrowKeys(Z)V
.locals 0
return-void
.end method
'
}

// Deprecated WebSettings hints that have no effect in current AOSP.
pub fn framework_websettings_signin_source(original string) !string {
	if original.count('.class public abstract Landroid/webkit/WebSettings;\n') != 1
		&& original.count('.class public Landroid/webkit/WebSettings;\n') != 1 {
		return error('canonical WebSettings sign-in input required')
	}
	for member in ['setLightTouchEnabled(', 'setNeedInitialFocus('] {
		if original.contains(member) {
			return error('WebSettings sign-in member already exists')
		}
	}
	return original + r'
.method public setLightTouchEnabled(Z)V
.locals 0
return-void
.end method
.method public setNeedInitialFocus(Z)V
.locals 0
return-void
.end method
'
}

pub fn framework_webview_signin(smali string) ! {
	webview := smali + '/android/webkit/WebView.smali'
	os.write_file(webview, framework_webview_signin_source(os.read_file(webview)!)!)!
	settings := smali + '/android/webkit/WebSettings.smali'
	os.write_file(settings, framework_websettings_signin_source(os.read_file(settings)!)!)!
}
