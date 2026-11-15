// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Vinix implements its Java WebView internals in the framework itself. Return
// their defining loader, without consulting app/TCCL loaders or starting the
// native web transport. This does not advertise a Chromium provider package.
pub fn framework_webview_loader_source(original string) !string {
	for declaration in ['.class public Landroid/webkit/WebView;',
		'.super Landroid/view/ViewGroup;',
		'.method public static getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;',
		'.method private native native_loadUrl(JLjava/lang/String;)V'] {
		if original.count(declaration + '\n') != 1 { return error('canonical WebView loader input required') }
	}
	if original.contains('getWebViewClassLoader(') { return error('WebView loader query already exists') }
	return original + r'
.method public static getWebViewClassLoader()Ljava/lang/ClassLoader;
.locals 2
const-class v0, Landroid/webkit/WebView;
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
if-nez v0, :done
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "WebView defining loader is unavailable"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-object v0
.end method
'
}

pub fn framework_webview_loader(smali string) ! {
	path := smali + '/android/webkit/WebView.smali'
	os.write_file(path, framework_webview_loader_source(os.read_file(path)!)!)!
}
