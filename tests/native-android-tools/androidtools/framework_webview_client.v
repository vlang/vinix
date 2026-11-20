// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

const webview_client_load_changed = '.method internalLoadChanged(ILjava/lang/String;)V\n    .registers 4\n'
const webview_client_started_two = 'invoke-virtual {v0, p0, p2}, Landroid/webkit/WebViewClient;->onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;)V'

// Remaining android.webkit members GMS 26.41.31 references (framework-api-gaps
// over every webkit method reference in the APK) whose AOSP behavior needs no
// engine support. Client callbacks get their AOSP default bodies; deprecated
// or process-wide settings are no-ops. Members that need engine operations we
// do not have (postUrl, back/forward lists, hit testing, saved state) are left
// absent so a caller fails visibly instead of silently misbehaving.
//
// Page-start dispatch now uses the public onPageStarted(WebView, String,
// Bitmap); its existing default still forwards to the two-argument form.
pub fn framework_webview_client_webview(original string) !string {
	for declaration in ['.class public Landroid/webkit/WebView;\n', webview_client_load_changed,
		webview_client_started_two + '\n', '.field private vinixUrl:Ljava/lang/String;\n'] {
		if original.count(declaration) != 1 {
			return error('canonical WebView client input required')
		}
	}
	for member in ['<init>(Landroid/content/Context;Landroid/util/AttributeSet;IZ)V', 'setDataDirectorySuffix(',
		'disableWebView(', 'getTitle(', 'getContentHeight(', 'reload(', 'pageUp(', 'pageDown('] {
		if original.contains(member) {
			return error('WebView client member already exists')
		}
	}
	mut source := original.replace(webview_client_load_changed,
		webview_client_load_changed.replace('.registers 4', '.registers 5'))
	source = source.replace(webview_client_started_two, 'const/4 v1, 0x0\n    invoke-virtual {v0, p0, p2, v1}, Landroid/webkit/WebViewClient;->onPageStarted(Landroid/webkit/WebView;Ljava/lang/String;Landroid/graphics/Bitmap;)V')
	return source + r'
.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;IZ)V
.locals 0
invoke-direct {p0, p1, p2, p3}, Landroid/webkit/WebView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V
return-void
.end method
.method public static setDataDirectorySuffix(Ljava/lang/String;)V
.locals 0
return-void
.end method
.method public static disableWebView()V
.locals 0
return-void
.end method
.method public getTitle()Ljava/lang/String;
.locals 1
const/4 v0, 0x0
return-object v0
.end method
.method public getContentHeight()I
.locals 1
const/4 v0, 0x0
return v0
.end method
.method public reload()V
.locals 1
iget-object v0, p0, Landroid/webkit/WebView;->vinixUrl:Ljava/lang/String;
if-eqz v0, :done
invoke-virtual {p0, v0}, Landroid/webkit/WebView;->loadUrl(Ljava/lang/String;)V
:done
return-void
.end method
.method public pageUp(Z)Z
.locals 1
const/4 v0, 0x0
return v0
.end method
.method public pageDown(Z)Z
.locals 1
const/4 v0, 0x0
return v0
.end method
'
}

pub fn framework_webview_client_settings(original string) !string {
	if original.count('.class public Landroid/webkit/WebSettings;\n') != 1 {
		return error('canonical WebSettings client input required')
	}
	for member in ['setDisabledActionModeMenuItems(', 'setForceDark(', 'setAllowFileAccessFromFileURLs('] {
		if original.contains(member) {
			return error('WebSettings client member already exists')
		}
	}
	return original + r'
.method public setDisabledActionModeMenuItems(I)V
.locals 0
return-void
.end method
.method public setForceDark(I)V
.locals 0
return-void
.end method
.method public setAllowFileAccessFromFileURLs(Z)V
.locals 0
return-void
.end method
'
}

pub fn framework_webview_client_client(original string) !string {
	if original.count('.class public Landroid/webkit/WebViewClient;\n') != 1
		|| original.count('.method public shouldOverrideUrlLoading(Landroid/webkit/WebView;Ljava/lang/String;)Z\n') != 1 {
		return error('canonical WebViewClient input required')
	}
	for member in ['onLoadResource(', 'onPageCommitVisible(', 'onReceivedHttpError(', 'onReceivedSslError(',
		'shouldInterceptRequest(', 'onFormResubmission(',
		'onReceivedError(Landroid/webkit/WebView;Landroid/webkit/WebResourceRequest;',
		'shouldOverrideUrlLoading(Landroid/webkit/WebView;Landroid/webkit/WebResourceRequest;)'] {
		if original.contains(member) {
			return error('WebViewClient member already exists')
		}
	}
	return original + r'
.method public onLoadResource(Landroid/webkit/WebView;Ljava/lang/String;)V
.locals 0
return-void
.end method
.method public onPageCommitVisible(Landroid/webkit/WebView;Ljava/lang/String;)V
.locals 0
return-void
.end method
.method public onReceivedError(Landroid/webkit/WebView;Landroid/webkit/WebResourceRequest;Landroid/webkit/WebResourceError;)V
.locals 0
return-void
.end method
.method public onReceivedHttpError(Landroid/webkit/WebView;Landroid/webkit/WebResourceRequest;Landroid/webkit/WebResourceResponse;)V
.locals 0
return-void
.end method
.method public onReceivedSslError(Landroid/webkit/WebView;Landroid/webkit/SslErrorHandler;Landroid/net/http/SslError;)V
.locals 0
return-void
.end method
.method public onFormResubmission(Landroid/webkit/WebView;Landroid/os/Message;Landroid/os/Message;)V
.locals 0
invoke-virtual {p2}, Landroid/os/Message;->sendToTarget()V
return-void
.end method
.method public shouldInterceptRequest(Landroid/webkit/WebView;Landroid/webkit/WebResourceRequest;)Landroid/webkit/WebResourceResponse;
.locals 1
const/4 v0, 0x0
return-object v0
.end method
.method public shouldOverrideUrlLoading(Landroid/webkit/WebView;Landroid/webkit/WebResourceRequest;)Z
.locals 1
invoke-interface {p2}, Landroid/webkit/WebResourceRequest;->getUrl()Landroid/net/Uri;
move-result-object v0
invoke-virtual {v0}, Landroid/net/Uri;->toString()Ljava/lang/String;
move-result-object v0
invoke-virtual {p0, p1, v0}, Landroid/webkit/WebViewClient;->shouldOverrideUrlLoading(Landroid/webkit/WebView;Ljava/lang/String;)Z
move-result v0
return v0
.end method
'
}

pub fn framework_webview_client_chrome(original string) !string {
	if original.count('.class public Landroid/webkit/WebChromeClient;\n') != 1 {
		return error('canonical WebChromeClient input required')
	}
	for member in ['onProgressChanged(', 'onReceivedTitle(', 'onConsoleMessage('] {
		if original.contains(member) {
			return error('WebChromeClient member already exists')
		}
	}
	return original + r'
.method public onProgressChanged(Landroid/webkit/WebView;I)V
.locals 0
return-void
.end method
.method public onReceivedTitle(Landroid/webkit/WebView;Ljava/lang/String;)V
.locals 0
return-void
.end method
.method public onConsoleMessage(Landroid/webkit/ConsoleMessage;)Z
.locals 1
const/4 v0, 0x0
return v0
.end method
'
}

pub fn framework_webview_client_urlutil(original string) !string {
	for declaration in ['.class public Landroid/webkit/URLUtil;\n', '.method public static isHttpUrl(Ljava/lang/String;)Z\n',
		'.method public static isHttpsUrl(Ljava/lang/String;)Z\n', '.method public static isContentUrl(Ljava/lang/String;)Z\n'] {
		if original.count(declaration) != 1 {
			return error('canonical URLUtil input required')
		}
	}
	for member in ['isAboutUrl(', 'isAssetUrl(', 'isNetworkUrl(', 'isValidUrl('] {
		if original.contains(member) {
			return error('URLUtil member already exists')
		}
	}
	mut extra := ''
	for name, prefix in {
		'isAboutUrl': 'about:'
		'isAssetUrl': 'file:///android_asset/'
	} {
		extra += '.method public static ${name}(Ljava/lang/String;)Z\n.locals 1\nif-eqz p0, :no\nconst-string v0, "${prefix}"\n' +
			'invoke-virtual {p0, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z\nmove-result v0\nreturn v0\n:no\nconst/4 v0, 0x0\nreturn v0\n.end method\n'
	}
	extra += r'.method public static isNetworkUrl(Ljava/lang/String;)Z
.locals 1
if-eqz p0, :no
invoke-virtual {p0}, Ljava/lang/String;->isEmpty()Z
move-result v0
if-nez v0, :no
invoke-static {p0}, Landroid/webkit/URLUtil;->isHttpUrl(Ljava/lang/String;)Z
move-result v0
if-nez v0, :yes
invoke-static {p0}, Landroid/webkit/URLUtil;->isHttpsUrl(Ljava/lang/String;)Z
move-result v0
return v0
:yes
const/4 v0, 0x1
return v0
:no
const/4 v0, 0x0
return v0
.end method
.method public static isValidUrl(Ljava/lang/String;)Z
.locals 2
if-eqz p0, :no
invoke-virtual {p0}, Ljava/lang/String;->isEmpty()Z
move-result v0
if-nez v0, :no
invoke-static {p0}, Landroid/webkit/URLUtil;->isNetworkUrl(Ljava/lang/String;)Z
move-result v0
if-nez v0, :yes
invoke-static {p0}, Landroid/webkit/URLUtil;->isContentUrl(Ljava/lang/String;)Z
move-result v0
if-nez v0, :yes
invoke-static {p0}, Landroid/webkit/URLUtil;->isAboutUrl(Ljava/lang/String;)Z
move-result v0
if-nez v0, :yes
const-string v1, "file://"
invoke-virtual {p0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-nez v0, :yes
const-string v1, "javascript:"
invoke-virtual {p0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
return v0
:yes
const/4 v0, 0x1
return v0
:no
const/4 v0, 0x0
return v0
.end method
'
	return original + '\n' + extra
}

pub fn framework_webview_client_response(original string) !string {
	if original.count('.class public Landroid/webkit/WebResourceResponse;\n') != 1
		|| original.count('.method public constructor <init>(Ljava/lang/String;Ljava/lang/String;Ljava/io/InputStream;)V\n') != 1 {
		return error('canonical WebResourceResponse input required')
	}
	for member in ['getStatusCode(', 'getReasonPhrase(', 'vinixStatusCode:', 'ILjava/lang/String;Ljava/util/Map;'] {
		if original.contains(member) {
			return error('WebResourceResponse member already exists')
		}
	}
	return original + r'
.field private vinixStatusCode:I
.field private vinixReasonPhrase:Ljava/lang/String;
.method public constructor <init>(Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;Ljava/util/Map;Ljava/io/InputStream;)V
.locals 0
invoke-direct {p0, p1, p2, p6}, Landroid/webkit/WebResourceResponse;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/io/InputStream;)V
iput p3, p0, Landroid/webkit/WebResourceResponse;->vinixStatusCode:I
iput-object p4, p0, Landroid/webkit/WebResourceResponse;->vinixReasonPhrase:Ljava/lang/String;
return-void
.end method
.method public getStatusCode()I
.locals 1
iget v0, p0, Landroid/webkit/WebResourceResponse;->vinixStatusCode:I
return v0
.end method
.method public getReasonPhrase()Ljava/lang/String;
.locals 1
iget-object v0, p0, Landroid/webkit/WebResourceResponse;->vinixReasonPhrase:Ljava/lang/String;
return-object v0
.end method
'
}

pub fn framework_webview_client_transform(name string, source string) !string {
	return match name {
		'WebView' { framework_webview_client_webview(source)! }
		'WebSettings' { framework_webview_client_settings(source)! }
		'WebViewClient' { framework_webview_client_client(source)! }
		'WebChromeClient' { framework_webview_client_chrome(source)! }
		'URLUtil' { framework_webview_client_urlutil(source)! }
		'WebResourceResponse' { framework_webview_client_response(source)! }
		else { return error('unknown webkit class') }
	}
}

pub const webview_client_names = ['WebView', 'WebSettings', 'WebViewClient', 'WebChromeClient',
	'URLUtil', 'WebResourceResponse']

pub fn framework_webview_client(smali string) ! {
	for name in webview_client_names {
		path := smali + '/android/webkit/' + name + '.smali'
		os.write_file(path, framework_webview_client_transform(name, os.read_file(path)!)!)!
	}
}
