// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const webview_type = 'Landroid/webkit/WebView;'
const settings_type = 'Landroid/webkit/WebSettings;'
const query_signature = 'getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;'
const pass_marker = 'WEBVIEW-PACKAGE-PASS public-static nullable-no-provider cold-repeat off-ui bounded-worker settings-identity javascript-preserved static-data-smoke destroyed-requery'
const fail_marker = 'WEBVIEW-PACKAGE-FAIL'
const fixture_scope = 'One actual Activity checks the public static non-native zero-argument PackageInfo query and repeated null results before WebView construction, on a bounded plain worker with no Looper, and around existing UI-thread construction, cached settings, JavaScript state, static loadData and destruction. Settings state is restored and the WebView destroyed with primary-failure preservation. No Android provider package is fabricated or initialized by the query; no network, page callback, visual rendering, browser-engine availability, Google module, account or authentication success is asserted.'

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
return-void')
}

fn shape_source() string {
	return method('private static shape()V', 5, '
const-class v0, ${webview_type}
const-string v1, "getCurrentWebViewPackage"
const/4 v2, 0
new-array v2, v2, [Ljava/lang/Class;
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getDeclaringClass()Ljava/lang/Class;
move-result-object v2
const-string v4, "the provider-package query must be declared by WebView"
invoke-static {v2, v0, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v2
const-class v3, Landroid/content/pm/PackageInfo;
const-string v4, "the nullable query must have the exact PackageInfo return type"
invoke-static {v2, v3, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v2
and-int/lit16 v2, v2, 0x109
const/16 v3, 0x9
const-string v4, "the query must be public static and non-native"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static query()V', 4, '
const/4 v0, 0
:again
invoke-static {}, ${webview_type}->${query_signature}
move-result-object v1
const/4 v2, 0
const-string v3, "an absent Android provider has no selected or loaded PackageInfo"
invoke-static {v1, v2, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
add-int/lit8 v0, v0, 1
const/16 v1, 32
if-lt v0, v1, :again
return-void')
}

fn worker_source() string {
	return method('public run()V', 4, '
:try_start
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iget-object v1, p0, ${main_type}->ownerThread:Ljava/lang/Thread;
const-string v2, "the static query must also run away from the Activity thread"
invoke-static {v0, v1, v2}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
const/4 v1, 0
const-string v2, "the worker query must not require an Android Looper"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {}, ${main_type}->query()V
const/4 v0, 1
iput-boolean v0, p0, ${main_type}->workerDone:Z
:try_end
return-void
:failed
move-exception v3
iput-object v3, p0, ${main_type}->workerFailure:Ljava/lang/Throwable;
return-void
.catchall {:try_start .. :try_end} :failed') + method('private static stopWorker(Ljava/lang/Thread;Ljava/lang/Throwable;)V', 3, '
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
const-string v1, "webview-package-query"
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
const-string v4, "the worker query must terminate within its bounded join"
invoke-static {v3, v1, v4}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v3, p0, ${main_type}->workerFailure:Ljava/lang/Throwable;
if-eqz v3, :completed
throw v3
:completed
iget-boolean v3, p0, ${main_type}->workerDone:Z
const/4 v1, 1
const-string v4, "the worker must finish all repeated queries without a captured exception"
invoke-static {v3, v1, v4}, ${main_type}->equal(IILjava/lang/String;)V
:try_end
return-void
:failed
move-exception v5
invoke-static {v0, v5}, ${main_type}->stopWorker(Ljava/lang/Thread;Ljava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn settings_source() string {
	return method('private static settings(${webview_type}${settings_type}Z)V', 3, '
invoke-virtual {p0}, ${webview_type}->getSettings()${settings_type}
move-result-object v0
const-string v2, "repeated package queries must preserve the actual cached WebSettings"
invoke-static {v0, p1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p1}, ${settings_type}->getJavaScriptEnabled()Z
move-result v0
const-string v2, "repeated package queries must preserve the current JavaScript setting"
invoke-static {v0, p2, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static cleanup(${webview_type}${settings_type}ZZLjava/lang/Throwable;)V', 1, '
:restore_start
if-eqz p3, :restore_end
invoke-virtual {p1, p2}, ${settings_type}->setJavaScriptEnabled(Z)V
invoke-static {p0, p1, p2}, ${main_type}->settings(${webview_type}${settings_type}Z)V
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
invoke-virtual {p0}, ${webview_type}->destroy()V
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
.catchall {:destroy_start .. :destroy_end} :destroy_failed') + method('private static smoke(Landroid/content/Context;)V', 7, '
new-instance v0, ${webview_type}
invoke-direct {v0, p0}, ${webview_type}-><init>(Landroid/content/Context;)V
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
:try_start
invoke-virtual {v0}, ${webview_type}->getSettings()${settings_type}
move-result-object v1
invoke-virtual {v1}, ${settings_type}->getJavaScriptEnabled()Z
move-result v2
const/4 v3, 1
invoke-static {}, ${main_type}->query()V
invoke-static {v0, v1, v2}, ${main_type}->settings(${webview_type}${settings_type}Z)V
xor-int/lit8 v4, v2, 1
invoke-virtual {v1, v4}, ${settings_type}->setJavaScriptEnabled(Z)V
invoke-static {}, ${main_type}->query()V
invoke-static {v0, v1, v4}, ${main_type}->settings(${webview_type}${settings_type}Z)V
const-string v4, "<html><body>Vinix WebView package query smoke</body></html>"
const-string v5, "text/html"
const-string v6, "UTF-8"
invoke-virtual {v0, v4, v5, v6}, ${webview_type}->loadData(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-static {}, ${main_type}->query()V
xor-int/lit8 v4, v2, 1
invoke-static {v0, v1, v4}, ${main_type}->settings(${webview_type}${settings_type}Z)V
:try_end
const/4 v6, 0
invoke-static {v0, v1, v2, v3, v6}, ${main_type}->cleanup(${webview_type}${settings_type}ZZLjava/lang/Throwable;)V
invoke-static {}, ${main_type}->query()V
return-void
:failed
move-exception v6
invoke-static {v0, v1, v2, v3, v6}, ${main_type}->cleanup(${webview_type}${settings_type}ZZLjava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn fixture_sources() map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n' +
		'.field private ownerThread:Ljava/lang/Thread;\n.field private volatile workerFailure:Ljava/lang/Throwable;\n.field private volatile workerDone:Z\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		helpers_source() + shape_source() + worker_source() + settings_source() +
		method('private checks()V', 0, '
invoke-static {}, ${main_type}->shape()V
invoke-static {}, ${main_type}->query()V
invoke-direct {p0}, ${main_type}->worker()V
invoke-static {}, ${main_type}->query()V
invoke-static {p0}, ${main_type}->smoke(Landroid/content/Context;)V
return-void') + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-direct {p0}, ${main_type}->checks()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Nullable WebView package and preserved settings passed"
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
.catchall {:try_start .. :try_end} :failed')}
}

fn expected_classes() []string { return ['org/vinix/bootstrap/Main.smali'] }

fn verify_source_references(source string) {
	assert source.starts_with('.class public final ${main_type}'), 'one actual fixture Activity required'
	for reference in ['.implements Ljava/lang/Runnable;', '${webview_type}->${query_signature}',
		'"getCurrentWebViewPackage"', 'Landroid/content/pm/PackageInfo;', 'Ljava/lang/reflect/Method;->getModifiers()I',
		'${webview_type}-><init>(Landroid/content/Context;)V', '${webview_type}->getSettings()${settings_type}',
		'${settings_type}->getJavaScriptEnabled()Z', '${settings_type}->setJavaScriptEnabled(Z)V',
		'${webview_type}->loadData(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V',
		'${webview_type}->destroy()V', 'Landroid/os/Looper;->myLooper()Landroid/os/Looper;',
		'Ljava/lang/Thread;->join(J)V', 'Ljava/lang/Thread;->setDaemon(Z)V',
		'Ljava/lang/Thread;->interrupt()V', '->addSuppressed(', '${main_type}->cleanup(',
		'${main_type}->stopWorker(', '${main_type}->workerFailure:Ljava/lang/Throwable;',
		'${main_type}->workerDone:Z'] {
		assert source.contains(reference), 'missing actual WebView package fixture assertion: ' + reference
	}
	assert !source.contains('${webview_type}->loadUrl(') && !source.contains('Landroid/webkit/WebViewClient;'),
		'no network or page-callback proof is part of this fixture'
	assert !source.contains('new-instance v0, Landroid/content/pm/PackageInfo;'), 'no fabricated provider identity permitted'
}
