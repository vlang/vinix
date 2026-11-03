// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const probe_type = 'Lorg/vinix/bootstrap/Probe;'
const context_type = 'Landroid/content/Context;'
const loader_type = 'Ljava/lang/ClassLoader;'
const app_string_name = 'bootclasspath_cookie_probe'
const app_string_value = 'Vinix application resource cookie two'
const pass_marker = 'BOOTCLASSPATH-PASS shared-platform boot-parent isolated-path-dex reflected-context framework-manifest-once cookie-one native-webview digest bounded-worker'
const fail_marker = 'BOOTCLASSPATH-FAIL'
const fixture_scope = 'Two application classes exercise real boot/system/application and two isolated boot-parent module loaders, exact shared platform identities, reflected Context/boolean module invocation with the actual Activity, boot/system exclusion of application classes, unique framework and application manifests, real Android system string cookie one and a tiny signed application string cookie two, native View/WebView/settings cleanup and native SHA-256, and bounded worker identity lookups. No platform stubs, custom ClassLoader overrides, boot or system path mutation, network, visual rendering, Google module completion, Maps, account or authentication success is supplied.'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn helpers_source() string {
	return method('private static equal(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-ne p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static truth(ZLjava/lang/String;)V', 1, '
if-nez p0, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V', 1, '
if-eqz p0, :failed
invoke-virtual {p0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :done
:failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void')
}

fn identity_source() string {
	mut body := ''
	for item in [
		['java.lang.Object', 'Ljava/lang/Object;'],
		['android.content.Context', context_type],
		['android.os.Bundle', 'Landroid/os/Bundle;'],
		['android.view.View', 'Landroid/view/View;'],
	] {
		body += 'const-string v0, "${item[0]}"\n' +
			'invoke-virtual {p0, v0}, ${loader_type}->loadClass(Ljava/lang/String;)Ljava/lang/Class;\nmove-result-object v0\n' +
			'const-class v1, ${item[1]}\nconst-string v2, "all real loaders must share ${item[0]} identity"\n' +
			'invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
	}
	body += 'return-void'
	return method('private static identity(${loader_type})V', 3, body) +
		method('private static identities([Ljava/lang/ClassLoader;)V', 3, '
const/4 v0, 0
:again
array-length v1, p0
if-ge v0, v1, :done
aget-object v2, p0, v0
invoke-static {v2}, ${main_type}->identity(${loader_type})V
add-int/lit8 v0, v0, 1
goto :again
:done
return-void') + method('private static absent(${loader_type}Ljava/lang/String;)V', 1, '
:try_start
invoke-virtual {p0, p1}, ${loader_type}->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v0
:try_end
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:missing
move-exception v0
return-void
.catch Ljava/lang/ClassNotFoundException; {:try_start .. :try_end} :missing') +
		method('private static boot(${loader_type}${loader_type})V', 3, '
const-class v0, ${context_type}
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v0
const-string v2, "Context must be defined by the same boot loader as Object"
invoke-static {v0, p0, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-class v0, Landroid/os/Bundle;
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v0
const-string v2, "Bundle must be defined by the real boot loader"
invoke-static {v0, p0, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-class v0, Landroid/view/View;
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v0
const-string v2, "View must be defined by the real boot loader"
invoke-static {v0, p0, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v1, "org.vinix.bootstrap.Main"
invoke-static {p0, v1}, ${main_type}->absent(${loader_type}Ljava/lang/String;)V
invoke-static {p1, v1}, ${main_type}->absent(${loader_type}Ljava/lang/String;)V
const-string v1, "org.vinix.bootstrap.Probe"
invoke-static {p0, v1}, ${main_type}->absent(${loader_type}Ljava/lang/String;)V
invoke-static {p1, v1}, ${main_type}->absent(${loader_type}Ljava/lang/String;)V
return-void')
}

fn module_source() string {
	return method('private static module(${loader_type}${context_type})Ljava/lang/Class;', 7, '
const-string v0, "org.vinix.bootstrap.Probe"
invoke-virtual {p0, v0}, ${loader_type}->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v1
const-string v2, "the module Probe must be defined by its isolated loader"
invoke-static {v1, p0, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-class v1, ${probe_type}
const-string v2, "the isolated Probe must differ from the application Probe"
invoke-static {v0, v1, v2}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v1, 2
new-array v1, v1, [Ljava/lang/Class;
const/4 v2, 0
const-class v3, ${context_type}
aput-object v3, v1, v2
const/4 v2, 1
sget-object v4, Ljava/lang/Boolean;->TYPE:Ljava/lang/Class;
aput-object v4, v1, v2
const-string v2, "initializeModuleV2"
invoke-virtual {v0, v2, v1}, Ljava/lang/Class;->getDeclaredMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v2
const-string v4, "module reflection must resolve the same Context return type"
invoke-static {v2, v3, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v2
and-int/lit16 v2, v2, 0x109
const/16 v3, 0x9
const-string v4, "the module entry must be public static and non-native"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v2, 2
new-array v2, v2, [Ljava/lang/Object;
const/4 v3, 0
aput-object p1, v2, v3
const/4 v3, 1
sget-object v4, Ljava/lang/Boolean;->TRUE:Ljava/lang/Boolean;
aput-object v4, v2, v3
const/4 v3, 0
invoke-virtual {v1, v3, v2}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v1
const-string v2, "the reflected module must return the actual Activity unchanged"
invoke-static {v1, p1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-object v0')
}

fn manifests_source() string {
	return method('private static manifests(${loader_type}Ljava/lang/String;II)V', 8, '
const-string v0, "AndroidManifest.xml"
invoke-virtual {p0, v0}, ${loader_type}->getResources(Ljava/lang/String;)Ljava/util/Enumeration;
move-result-object v0
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
:again
invoke-interface {v0}, Ljava/util/Enumeration;->hasMoreElements()Z
move-result v4
if-eqz v4, :done
invoke-interface {v0}, Ljava/util/Enumeration;->nextElement()Ljava/lang/Object;
move-result-object v4
check-cast v4, Ljava/net/URL;
invoke-virtual {v4}, Ljava/net/URL;->getPath()Ljava/lang/String;
move-result-object v4
const-string v5, "UTF-8"
invoke-static {v4, v5}, Ljava/net/URLDecoder;->decode(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v4
const-string v5, "framework-res.apk!/AndroidManifest.xml"
invoke-virtual {v4, v5}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
move-result v6
if-eqz v6, :own
const/4 v6, 0
const-string v7, "a framework manifest must precede any application manifest"
invoke-static {v2, v6, v7}, ${main_type}->equal(IILjava/lang/String;)V
add-int/lit8 v1, v1, 1
goto :count
:own
const-string v7, "all expected parent manifests must precede the application manifest"
invoke-static {v1, p2, v7}, ${main_type}->equal(IILjava/lang/String;)V
const-string v5, "!/AndroidManifest.xml"
invoke-virtual {p1, v5}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v5
invoke-virtual {v4, v5}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
move-result v6
const-string v7, "manifest enumeration may only contain the framework and this APK"
invoke-static {v6, v7}, ${main_type}->truth(ZLjava/lang/String;)V
add-int/lit8 v2, v2, 1
:count
add-int/lit8 v3, v3, 1
const/4 v4, 3
if-le v3, v4, :again
const/4 v4, 0
const-string v5, "manifest enumeration must remain bounded"
invoke-static {v4, v5}, ${main_type}->truth(ZLjava/lang/String;)V
goto :again
:done
const-string v5, "the framework manifest must have exact parent visibility without duplicates"
invoke-static {v1, p2, v5}, ${main_type}->equal(IILjava/lang/String;)V
add-int v4, p2, p3
const-string v5, "manifest enumeration must have the exact expected membership"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
const-string v5, "this APK manifest must have exact loader visibility without duplicates"
invoke-static {v2, p3, v5}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static resources(${context_type})V', 6, '
invoke-static {}, Landroid/content/res/Resources;->getSystem()Landroid/content/res/Resources;
move-result-object v0
invoke-virtual {p0}, ${context_type}->getResources()Landroid/content/res/Resources;
move-result-object v1
const v2, 0x104000a
invoke-virtual {v0, v2}, Landroid/content/res/Resources;->getString(I)Ljava/lang/String;
move-result-object v3
invoke-virtual {v1, v2}, Landroid/content/res/Resources;->getString(I)Ljava/lang/String;
move-result-object v4
const-string v5, "Activity and system android.R.string.ok must agree"
invoke-static {v3, v4, v5}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v3}, Ljava/lang/String;->isEmpty()Z
move-result v2
const/4 v4, 0
const-string v5, "the real Android system OK string must be nonempty"
invoke-static {v2, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
const v2, 0x104000a
const/4 v4, 1
invoke-static {v0, v2, v4}, ${main_type}->resourceCookie(Landroid/content/res/Resources;II)V
invoke-static {v1, v2, v4}, ${main_type}->resourceCookie(Landroid/content/res/Resources;II)V
const-string v2, "${app_string_name}"
const-string v3, "string"
const-string v4, "${package_name}"
invoke-virtual {v1, v2, v3, v4}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v2
if-gtz v2, :app_found
new-instance v3, Ljava/lang/AssertionError;
const-string v4, "the signed APK string resource must be discoverable by its unique name"
invoke-direct {v3, v4}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v3
:app_found
invoke-virtual {v1, v2}, Landroid/content/res/Resources;->getString(I)Ljava/lang/String;
move-result-object v3
const-string v4, "${app_string_value}"
const-string v5, "the actual signed APK string must have its exact fixture value"
invoke-static {v3, v4, v5}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
const/4 v4, 2
invoke-static {v1, v2, v4}, ${main_type}->resourceCookie(Landroid/content/res/Resources;II)V
return-void') + method('private static resourceCookie(Landroid/content/res/Resources;II)V', 4, '
new-instance v0, Landroid/util/TypedValue;
invoke-direct {v0}, Landroid/util/TypedValue;-><init>()V
const/4 v1, 1
invoke-virtual {p0, p1, v0, v1}, Landroid/content/res/Resources;->getValue(ILandroid/util/TypedValue;Z)V
iget v1, v0, Landroid/util/TypedValue;->assetCookie:I
const-string v3, "the actual native string value must retain its expected asset cookie"
invoke-static {v1, p2, v3}, ${main_type}->equal(IILjava/lang/String;)V
iget v1, v0, Landroid/util/TypedValue;->type:I
const/4 v2, 3
const-string v3, "the native framework value must retain TYPE_STRING"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn worker_source() string {
	return method('public run()V', 4, '
:try_start
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iget-object v1, p0, ${main_type}->ownerThread:Ljava/lang/Thread;
const-string v2, "worker identities must run away from the Activity thread"
invoke-static {v0, v1, v2}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
const/4 v1, 0
const-string v2, "class identity lookup on a plain worker must require no Looper"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v0, 0
:again
iget-object v1, p0, ${main_type}->checkedLoaders:[Ljava/lang/ClassLoader;
invoke-static {v1}, ${main_type}->identities([Ljava/lang/ClassLoader;)V
add-int/lit8 v0, v0, 1
const/16 v1, 32
if-lt v0, v1, :again
const/4 v0, 1
iput-boolean v0, p0, ${main_type}->workerDone:Z
:try_end
return-void
:failed
move-exception v3
iput-object v3, p0, ${main_type}->workerFailure:Ljava/lang/Throwable;
return-void
.catchall {:try_start .. :try_end} :failed') +
		method('private static stopWorker(Ljava/lang/Thread;Ljava/lang/Throwable;)V', 3, '
:try_start
invoke-virtual {p0}, Ljava/lang/Thread;->interrupt()V
const-wide/16 v0, 1000
invoke-virtual {p0, v0, v1}, Ljava/lang/Thread;->join(J)V
:try_end
goto :primary
:failed
move-exception v2
if-eq p1, v2, :primary
invoke-virtual {p1, v2}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
:primary
throw p1
.catchall {:try_start .. :try_end} :failed') + method('private worker()V', 6, '
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v1
iput-object v1, p0, ${main_type}->ownerThread:Ljava/lang/Thread;
const/4 v1, 0
iput-object v1, p0, ${main_type}->workerFailure:Ljava/lang/Throwable;
iput-boolean v1, p0, ${main_type}->workerDone:Z
new-instance v0, Ljava/lang/Thread;
const-string v1, "bootclasspath-identities"
invoke-direct {v0, p0, v1}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;Ljava/lang/String;)V
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/Thread;->setDaemon(Z)V
:try_start
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
const-wide/16 v1, 8000
invoke-virtual {v0, v1, v2}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v0}, Ljava/lang/Thread;->isAlive()Z
move-result v3
const/4 v1, 0
const-string v4, "identity worker must finish within its bounded join"
invoke-static {v3, v1, v4}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v3, p0, ${main_type}->workerFailure:Ljava/lang/Throwable;
if-eqz v3, :completed
throw v3
:completed
iget-boolean v3, p0, ${main_type}->workerDone:Z
const/4 v1, 1
const-string v4, "worker must complete all identities without a captured exception"
invoke-static {v3, v1, v4}, ${main_type}->equal(IILjava/lang/String;)V
:try_end
return-void
:failed
move-exception v5
invoke-static {v0, v5}, ${main_type}->stopWorker(Ljava/lang/Thread;Ljava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn native_source() string {
	return method('private static settings(Landroid/webkit/WebView;Landroid/webkit/WebSettings;Z)V', 2, '
invoke-virtual {p0}, Landroid/webkit/WebView;->getSettings()Landroid/webkit/WebSettings;
move-result-object v0
const-string v1, "native WebSettings must retain identity"
invoke-static {v0, p1, v1}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p1}, Landroid/webkit/WebSettings;->getJavaScriptEnabled()Z
move-result v0
const-string v1, "native settings must retain the current JavaScript state"
invoke-static {v0, p2, v1}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static cleanup(Landroid/webkit/WebView;Landroid/webkit/WebSettings;ZZLjava/lang/Throwable;)V', 1, '
:restore_start
if-eqz p3, :restore_end
invoke-virtual {p1, p2}, Landroid/webkit/WebSettings;->setJavaScriptEnabled(Z)V
invoke-static {p0, p1, p2}, ${main_type}->settings(Landroid/webkit/WebView;Landroid/webkit/WebSettings;Z)V
:restore_end
goto :destroy_start
:restore_failed
move-exception v0
if-eqz p4, :restore_primary
if-eq p4, v0, :destroy_start
invoke-virtual {p4, v0}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
goto :destroy_start
:restore_primary
move-object p4, v0
:destroy_start
invoke-virtual {p0}, Landroid/webkit/WebView;->destroy()V
:destroy_end
goto :primary
:destroy_failed
move-exception v0
if-eqz p4, :destroy_primary
if-eq p4, v0, :primary
invoke-virtual {p4, v0}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
goto :primary
:destroy_primary
move-object p4, v0
:primary
if-eqz p4, :done
throw p4
:done
return-void
.catchall {:restore_start .. :restore_end} :restore_failed
.catchall {:destroy_start .. :destroy_end} :destroy_failed') + method('private static nativeSmoke(${context_type})V', 7, '
new-instance v0, Landroid/view/View;
invoke-direct {v0, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v0}, Landroid/view/View;->getContext()Landroid/content/Context;
move-result-object v1
const-string v2, "real View construction must retain the actual Activity context"
invoke-static {v1, p0, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/16 v1, 0x1234
invoke-virtual {v0, v1}, Landroid/view/View;->setId(I)V
invoke-virtual {v0}, Landroid/view/View;->getId()I
move-result v2
const-string v3, "the real native-backed View must remain usable"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
new-instance v0, Landroid/webkit/WebView;
invoke-direct {v0, p0}, Landroid/webkit/WebView;-><init>(Landroid/content/Context;)V
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
:try_start
invoke-virtual {v0}, Landroid/webkit/WebView;->getSettings()Landroid/webkit/WebSettings;
move-result-object v1
invoke-virtual {v1}, Landroid/webkit/WebSettings;->getJavaScriptEnabled()Z
move-result v2
const/4 v3, 1
invoke-static {v0, v1, v2}, ${main_type}->settings(Landroid/webkit/WebView;Landroid/webkit/WebSettings;Z)V
xor-int/lit8 v4, v2, 1
invoke-virtual {v1, v4}, Landroid/webkit/WebSettings;->setJavaScriptEnabled(Z)V
invoke-static {v0, v1, v4}, ${main_type}->settings(Landroid/webkit/WebView;Landroid/webkit/WebSettings;Z)V
const-string v4, "<html><body>Boot classpath native smoke</body></html>"
const-string v5, "text/html"
const-string v6, "UTF-8"
invoke-virtual {v0, v4, v5, v6}, Landroid/webkit/WebView;->loadData(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
xor-int/lit8 v4, v2, 1
invoke-static {v0, v1, v4}, ${main_type}->settings(Landroid/webkit/WebView;Landroid/webkit/WebSettings;Z)V
:try_end
const/4 v6, 0
invoke-static {v0, v1, v2, v3, v6}, ${main_type}->cleanup(Landroid/webkit/WebView;Landroid/webkit/WebSettings;ZZLjava/lang/Throwable;)V
return-void
:failed
move-exception v6
invoke-static {v0, v1, v2, v3, v6}, ${main_type}->cleanup(Landroid/webkit/WebView;Landroid/webkit/WebSettings;ZZLjava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed') + method('private static digest()V', 5, '
const-string v0, "SHA-256"
invoke-static {v0}, Ljava/security/MessageDigest;->getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;
move-result-object v0
invoke-virtual {v0}, Ljava/security/MessageDigest;->getProvider()Ljava/security/Provider;
move-result-object v1
invoke-virtual {v1}, Ljava/security/Provider;->getName()Ljava/lang/String;
move-result-object v1
const-string v2, "VinixNative"
const-string v3, "SHA-256 must exercise the installed native provider"
invoke-static {v1, v2, v3}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
const-string v1, "abc"
const-string v2, "UTF-8"
invoke-virtual {v1, v2}, Ljava/lang/String;->getBytes(Ljava/lang/String;)[B
move-result-object v1
invoke-virtual {v0, v1}, Ljava/security/MessageDigest;->digest([B)[B
move-result-object v0
const/16 v1, 32
new-array v1, v1, [B
fill-array-data v1, :sha256_abc
invoke-static {v0, v1}, Ljava/util/Arrays;->equals([B[B)Z
move-result v2
const-string v3, "native SHA-256 must match the standard abc known answer"
invoke-static {v2, v3}, ${main_type}->truth(ZLjava/lang/String;)V
return-void
:sha256_abc
.array-data 1
-70
120
22
-65
-113
1
-49
-22
65
65
64
-34
93
-82
34
35
-80
3
97
-93
-106
23
122
-100
-76
16
-1
97
-14
0
21
-83
.end array-data')
}

fn checks_source() string {
	return method('private checks()V', 11, '
invoke-virtual {p0}, ${context_type}->getPackageCodePath()Ljava/lang/String;
move-result-object v0
invoke-virtual {p0}, ${context_type}->getCacheDir()Ljava/io/File;
move-result-object v1
invoke-virtual {v1}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;
move-result-object v1
const-class v4, Ljava/lang/Object;
invoke-virtual {v4}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v4
const/4 v2, 0
const-string v6, "pinned ART must expose a real BootClassLoader singleton"
invoke-static {v4, v2, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
new-instance v3, Ldalvik/system/PathClassLoader;
invoke-direct {v3, v0, v4}, Ldalvik/system/PathClassLoader;-><init>(Ljava/lang/String;Ljava/lang/ClassLoader;)V
new-instance v5, Ldalvik/system/DexClassLoader;
invoke-direct {v5, v0, v1, v2, v4}, Ldalvik/system/DexClassLoader;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V
const-class v6, ${main_type}
invoke-virtual {v6}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v6
invoke-virtual {p0}, ${context_type}->getClassLoader()${loader_type}
move-result-object v8
const-string v9, "Activity Context and the actual Main class must share the app loader"
invoke-static {v8, v6, v9}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {}, ${loader_type}->getSystemClassLoader()${loader_type}
move-result-object v7
invoke-virtual {v6}, ${loader_type}->getParent()${loader_type}
move-result-object v8
const-string v9, "the real application loader must retain the system resource parent"
invoke-static {v8, v7, v9}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v4, v7}, ${main_type}->boot(${loader_type}${loader_type})V
const/4 v8, 5
new-array v8, v8, [Ljava/lang/ClassLoader;
const/4 v9, 0
aput-object v4, v8, v9
const/4 v9, 1
aput-object v7, v8, v9
const/4 v9, 2
aput-object v6, v8, v9
const/4 v9, 3
aput-object v3, v8, v9
const/4 v9, 4
aput-object v5, v8, v9
iput-object v8, p0, ${main_type}->checkedLoaders:[Ljava/lang/ClassLoader;
invoke-static {v8}, ${main_type}->identities([Ljava/lang/ClassLoader;)V
invoke-static {v3, p0}, ${main_type}->module(${loader_type}${context_type})Ljava/lang/Class;
move-result-object v8
invoke-static {v5, p0}, ${main_type}->module(${loader_type}${context_type})Ljava/lang/Class;
move-result-object v9
const-string v10, "PathClassLoader and DexClassLoader must define distinct Probe classes"
invoke-static {v8, v9, v10}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v8, 0
const/4 v9, 0
invoke-static {v4, v0, v8, v9}, ${main_type}->manifests(${loader_type}Ljava/lang/String;II)V
const/4 v8, 1
invoke-static {v7, v0, v8, v9}, ${main_type}->manifests(${loader_type}Ljava/lang/String;II)V
const/4 v9, 1
invoke-static {v6, v0, v8, v9}, ${main_type}->manifests(${loader_type}Ljava/lang/String;II)V
const/4 v8, 0
invoke-static {v3, v0, v8, v9}, ${main_type}->manifests(${loader_type}Ljava/lang/String;II)V
invoke-static {v5, v0, v8, v9}, ${main_type}->manifests(${loader_type}Ljava/lang/String;II)V
invoke-static {p0}, ${main_type}->resources(${context_type})V
invoke-direct {p0}, ${main_type}->worker()V
invoke-static {p0}, ${main_type}->nativeSmoke(${context_type})V
invoke-static {}, ${main_type}->digest()V
iget-object v8, p0, ${main_type}->checkedLoaders:[Ljava/lang/ClassLoader;
invoke-static {v8}, ${main_type}->identities([Ljava/lang/ClassLoader;)V
return-void')
}

fn probe_source() string {
	return '.class public final ${probe_type}\n.super Ljava/lang/Object;\n' +
		method('public static initializeModuleV2(${context_type}Z)${context_type}', 5, '
if-eqz p0, :failed
if-eqz p1, :failed
new-instance v0, Landroid/os/Bundle;
invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
const-string v1, "bootclasspath-probe"
invoke-virtual {v0, v1, p1}, Landroid/os/Bundle;->putBoolean(Ljava/lang/String;Z)V
invoke-virtual {v0, v1}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;)Z
move-result v0
if-ne v0, p1, :failed
const-class v0, ${probe_type}
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v0
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v1
if-eq v0, v1, :failed
const-class v0, Landroid/view/View;
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v0
const-class v1, Ljava/lang/Object;
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()${loader_type}
move-result-object v1
if-ne v0, v1, :failed
return-object p0
:failed
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "isolated module Context/boolean linkage and platform identities must hold"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
}

fn fixture_sources() map[string]string {
	return {
		'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n' +
			'.field private checkedLoaders:[Ljava/lang/ClassLoader;\n.field private ownerThread:Ljava/lang/Thread;\n' +
			'.field private volatile workerFailure:Ljava/lang/Throwable;\n.field private volatile workerDone:Z\n' +
			method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
			helpers_source() + identity_source() + module_source() + manifests_source() +
			worker_source() + native_source() + checks_source() +
			method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-direct {p0}, ${main_type}->checks()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Boot-parent modules and native platform classes passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2
.catchall {:try_start .. :try_end} :failed')
		'org/vinix/bootstrap/Probe.smali': probe_source()
	}
}

fn expected_classes() []string { return ['org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/Probe.smali'] }

fn verify_source_references(name string, source string) {
	if name == 'org/vinix/bootstrap/Probe.smali' {
		assert source.starts_with('.class public final ${probe_type}')
		for reference in ['initializeModuleV2(${context_type}Z)${context_type}',
			'Landroid/os/Bundle;->putBoolean(', 'Landroid/os/Bundle;->getBoolean(',
			'const-class v0, Landroid/view/View;', 'Ljava/lang/Class;->getClassLoader()${loader_type}'] {
			assert source.contains(reference), 'missing isolated Probe linkage: ' + reference
		}
		assert !source.contains(main_type), 'Probe must not depend on the application Main class'
		return
	}
	assert name == 'org/vinix/bootstrap/Main.smali' && source.starts_with('.class public final ${main_type}')
	for reference in ['.implements Ljava/lang/Runnable;', 'Ldalvik/system/PathClassLoader;-><init>(',
		'Ldalvik/system/DexClassLoader;-><init>(', '"initializeModuleV2"',
		'Ljava/lang/Class;->getDeclaredMethod(', 'Ljava/lang/reflect/Method;->invoke(',
		'Ljava/lang/ClassLoader;->getResources(', '"AndroidManifest.xml"',
		'Landroid/content/res/Resources;->getValue(ILandroid/util/TypedValue;Z)',
		'Landroid/content/res/Resources;->getIdentifier(', '"${app_string_name}"', '"${app_string_value}"',
		'Landroid/util/TypedValue;->assetCookie:I', 'Landroid/content/res/Resources;->getSystem()',
		'Landroid/view/View;-><init>(', 'Landroid/webkit/WebView;-><init>(',
		'Landroid/webkit/WebView;->getSettings()', 'Landroid/webkit/WebSettings;->setJavaScriptEnabled(',
		'Landroid/webkit/WebView;->destroy()', 'Ljava/security/MessageDigest;->getInstance(',
		'"VinixNative"', 'Ljava/lang/Thread;->join(J)', 'Landroid/os/Looper;->myLooper()',
		'${main_type}->workerDone:Z', '${main_type}->workerFailure:Ljava/lang/Throwable;'] {
		assert source.contains(reference), 'missing actual boot-classpath fixture assertion: ' + reference
	}
	assert !source.contains('Ljava/lang/System;->setProperty(') && !source.contains('Ljava/lang/ClassLoader;->set'),
		'fixture must not alter platform loader configuration'
}
