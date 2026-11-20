// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

const webview_bridge_add = '.method public addJavascriptInterface(Ljava/lang/Object;Ljava/lang/String;)V\n    .registers 6\n'
// framework_webview_signin added this placeholder; the bridge replaces it.
const webview_bridge_remove = '.method public removeJavascriptInterface(Ljava/lang/String;)V\n.locals 0\nreturn-void\n.end method\n'

// WebView.addJavascriptInterface over the engine's JavaScript bridge
// (build-support/android/browseripc/jsbridge.v). WebView keeps its interface
// objects in insertion order, publishes the exposed method names through
// native_setJavascriptInterfaces whenever they change, and answers the
// engine's calls through internalJavascriptCall, which the native client calls
// with the interface, method and tagged arguments. Reflection and value
// conversion live in java/android/webkit/VinixJavascriptBridge.java.
pub fn framework_webview_bridge_source(original string) !string {
	for declaration in ['.class public Landroid/webkit/WebView;\n', webview_bridge_add,
		webview_bridge_remove] {
		if original.count(declaration) != 1 {
			return error('canonical WebView bridge input required')
		}
	}
	for member in ['vinixJsInterfaces:', 'native_setJavascriptInterfaces(', 'internalJavascriptCall(',
		'vinixAddJavascriptInterface(', 'vinixPublishJavascriptInterfaces('] {
		if original.contains(member) {
			return error('WebView bridge member already exists')
		}
	}
	mut source := original.replace(webview_bridge_add, webview_bridge_add +
		'    invoke-direct {p0, p1, p2}, Landroid/webkit/WebView;->vinixAddJavascriptInterface(Ljava/lang/Object;Ljava/lang/String;)V\n')
	source = source.replace(webview_bridge_remove, r'.method public removeJavascriptInterface(Ljava/lang/String;)V
.locals 1
invoke-direct {p0}, Landroid/webkit/WebView;->vinixJavascriptInterfaces()Ljava/util/LinkedHashMap;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/util/LinkedHashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;
invoke-direct {p0}, Landroid/webkit/WebView;->vinixPublishJavascriptInterfaces()V
return-void
.end method
')
	return source + r'
.field private vinixJsInterfaces:Ljava/util/LinkedHashMap;
.method private native native_setJavascriptInterfaces(JLjava/lang/String;)V
.end method
.method private vinixJavascriptInterfaces()Ljava/util/LinkedHashMap;
.locals 1
iget-object v0, p0, Landroid/webkit/WebView;->vinixJsInterfaces:Ljava/util/LinkedHashMap;
if-nez v0, :done
new-instance v0, Ljava/util/LinkedHashMap;
invoke-direct {v0}, Ljava/util/LinkedHashMap;-><init>()V
iput-object v0, p0, Landroid/webkit/WebView;->vinixJsInterfaces:Ljava/util/LinkedHashMap;
:done
return-object v0
.end method
.method private vinixPublishJavascriptInterfaces()V
.locals 3
invoke-direct {p0}, Landroid/webkit/WebView;->vinixJavascriptInterfaces()Ljava/util/LinkedHashMap;
move-result-object v0
invoke-static {v0}, Landroid/webkit/VinixJavascriptBridge;->spec(Ljava/util/Map;)Ljava/lang/String;
move-result-object v0
iget-wide v1, p0, Landroid/webkit/WebView;->widget:J
invoke-direct {p0, v1, v2, v0}, Landroid/webkit/WebView;->native_setJavascriptInterfaces(JLjava/lang/String;)V
return-void
.end method
.method private vinixAddJavascriptInterface(Ljava/lang/Object;Ljava/lang/String;)V
.locals 1
if-eqz p1, :done
if-eqz p2, :done
invoke-direct {p0}, Landroid/webkit/WebView;->vinixJavascriptInterfaces()Ljava/util/LinkedHashMap;
move-result-object v0
invoke-virtual {v0, p2, p1}, Ljava/util/LinkedHashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
invoke-direct {p0}, Landroid/webkit/WebView;->vinixPublishJavascriptInterfaces()V
:done
return-void
.end method
.method public internalJavascriptCall(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
.locals 1
invoke-direct {p0}, Landroid/webkit/WebView;->vinixJavascriptInterfaces()Ljava/util/LinkedHashMap;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/util/LinkedHashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
if-nez v0, :found
const-string v0, "!Unknown Java bridge interface"
return-object v0
:found
invoke-static {v0, p2, p3}, Landroid/webkit/VinixJavascriptBridge;->call(Ljava/lang/Object;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
return-object v0
.end method
'
}

const webview_bridge_java = ['android/webkit/JavascriptInterface', 'android/webkit/VinixJavascriptBridge']

// Compiles java/android/webkit (Java 8 bytecode, D8 to dex) and adds its
// classes to the framework smali. tools must hold r8-8.3.37.jar and smali.
pub fn framework_webview_bridge_classes(smali string, work string, tools string, java string) ! {
	for name in webview_bridge_java {
		if os.exists(smali + '/' + name + '.smali') {
			return error('WebView bridge class already exists: ' + name)
		}
	}
	if framework_digest(tools + '/r8-8.3.37.jar')! != r8_sha256 {
		return error('D8 checksum mismatch')
	}
	sources := os.dir(@FILE) + '/java'
	classes := work + '/webview-bridge-classes'
	dex := work + '/webview-bridge-dex'
	disassembled := work + '/webview-bridge-smali'
	for directory in [classes, dex, disassembled] {
		if os.exists(directory) {
			return error('fresh WebView bridge work directory required')
		}
		os.mkdir_all(directory)!
	}
	javac := os.dir(java) + '/javac'
	mut compile := [javac, '--release', '8', '-Xlint:-options', '-d', classes]
	for name in webview_bridge_java {
		compile << sources + '/' + name + '.java'
	}
	checked(compile)!
	mut convert := [java, '-cp', tools + '/r8-8.3.37.jar', 'com.android.tools.r8.D8', '--release',
		'--no-desugaring', '--min-api', '28', '--output', dex]
	for name in webview_bridge_java {
		convert << classes + '/' + name + '.class'
	}
	checked(convert)!
	checked([java, '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2',
		dex + '/classes.dex', '-o', disassembled])!
	for name in webview_bridge_java {
		os.mkdir_all(os.dir(smali + '/' + name))!
		os.cp(disassembled + '/' + name + '.smali', smali + '/' + name + '.smali')!
	}
}

pub fn framework_webview_bridge(smali string, work string, tools string, java string) ! {
	framework_webview_bridge_classes(smali, work, tools, java)!
	path := smali + '/android/webkit/WebView.smali'
	os.write_file(path, framework_webview_bridge_source(os.read_file(path)!)!)!
}
