// SPDX-License-Identifier: GPL-2.0-or-later
module webviewloaderprobe
import os
pub fn install(root string) ! {
 os.write_file(root + '/smali/WebViewLoaderProbe.smali', r'
.class public final Lorg/vinix/bootstrap/WebViewLoaderProbe;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private volatile done:Z
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method private static loader()V
.locals 7
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Thread;->getContextClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
new-instance v2, Lorg/vinix/bootstrap/WebViewHostileLoader;
invoke-direct {v2}, Lorg/vinix/bootstrap/WebViewHostileLoader;-><init>()V
invoke-virtual {v0, v2}, Ljava/lang/Thread;->setContextClassLoader(Ljava/lang/ClassLoader;)V
:try_loader
invoke-static {}, Landroid/webkit/WebView;->getWebViewClassLoader()Ljava/lang/ClassLoader;
move-result-object v3
if-eqz v3, :bad
const-class v4, Landroid/webkit/WebView;
invoke-virtual {v4}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v5
if-ne v3, v5, :bad
const-string v5, "android.webkit.WebView"
invoke-virtual {v3, v5}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v5
if-ne v4, v5, :bad
const-string v5, "android.webkit.WebSettings"
invoke-virtual {v3, v5}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v5
const-class v4, Landroid/webkit/WebSettings;
if-ne v4, v5, :bad
const-string v5, "android.webkit.CookieManager"
invoke-virtual {v3, v5}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v5
const-class v4, Landroid/webkit/CookieManager;
if-ne v4, v5, :bad
invoke-static {}, Landroid/webkit/WebView;->getWebViewClassLoader()Ljava/lang/ClassLoader;
move-result-object v4
if-ne v3, v4, :bad
invoke-static {}, Landroid/webkit/WebView;->getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;
move-result-object v4
if-nez v4, :bad
iget v4, v2, Lorg/vinix/bootstrap/WebViewHostileLoader;->calls:I
if-nez v4, :bad
goto :end_loader
:bad
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:end_loader
invoke-virtual {v0, v1}, Ljava/lang/Thread;->setContextClassLoader(Ljava/lang/ClassLoader;)V
return-void
.catchall {:try_loader .. :end_loader} :failed
:failed
move-exception v4
invoke-virtual {v0, v1}, Ljava/lang/Thread;->setContextClassLoader(Ljava/lang/ClassLoader;)V
throw v4
.end method
.method public run()V
.locals 1
invoke-static {}, Lorg/vinix/bootstrap/WebViewLoaderProbe;->loader()V
const/4 v0, 1
iput-boolean v0, p0, Lorg/vinix/bootstrap/WebViewLoaderProbe;->done:Z
return-void
.end method
.method public static check()V
.locals 5
invoke-static {}, Lorg/vinix/bootstrap/WebViewLoaderProbe;->loader()V
new-instance v0, Lorg/vinix/bootstrap/WebViewLoaderProbe;
invoke-direct {v0}, Lorg/vinix/bootstrap/WebViewLoaderProbe;-><init>()V
new-instance v1, Ljava/lang/Thread;
invoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
const-wide/16 v2, 3000
invoke-virtual {v1, v2, v3}, Ljava/lang/Thread;->join(J)V
iget-boolean v2, v0, Lorg/vinix/bootstrap/WebViewLoaderProbe;->done:Z
const/4 v3, 1
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {}, Lorg/vinix/bootstrap/WebViewLoaderProbe;->loader()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "WEBVIEW-LOADER-PASS defining-loader stable framework-types hostile-tccl worker no-provider-package"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
 os.write_file(root + '/smali/WebViewHostileLoader.smali', r'
.class public final Lorg/vinix/bootstrap/WebViewHostileLoader;
.super Ljava/lang/ClassLoader;
.field public calls:I
.method public constructor <init>()V
.locals 1
const/4 v0, 0
invoke-direct {p0, v0}, Ljava/lang/ClassLoader;-><init>(Ljava/lang/ClassLoader;)V
return-void
.end method
.method public loadClass(Ljava/lang/String;)Ljava/lang/Class;
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/WebViewHostileLoader;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/WebViewHostileLoader;->calls:I
new-instance v0, Ljava/lang/ClassNotFoundException;
invoke-direct {v0, p1}, Ljava/lang/ClassNotFoundException;-><init>(Ljava/lang/String;)V
throw v0
.end method
')!
}
