// SPDX-License-Identifier: GPL-2.0-or-later
module valuecallbackprobe
import os
pub fn install(root string) ! {
 os.write_file(root + '/smali/ValueCallbackProbe.smali', r'
.class public final Lorg/vinix/bootstrap/ValueCallbackProbe;
.super Ljava/lang/Object;
.implements Landroid/webkit/ValueCallback;
.implements Ljava/lang/Runnable;
.field private count:I
.field private value:Ljava/lang/Object;
.field private volatile done:Z
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public onReceiveValue(Ljava/lang/Object;)V
.locals 1
iput-object p1, p0, Lorg/vinix/bootstrap/ValueCallbackProbe;->value:Ljava/lang/Object;
iget v0, p0, Lorg/vinix/bootstrap/ValueCallbackProbe;->count:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/ValueCallbackProbe;->count:I
return-void
.end method
.method private static exercise(Lorg/vinix/bootstrap/ValueCallbackProbe;)V
.locals 4
new-instance v0, Ljava/lang/Object;
invoke-direct {v0}, Ljava/lang/Object;-><init>()V
invoke-interface {p0, v0}, Landroid/webkit/ValueCallback;->onReceiveValue(Ljava/lang/Object;)V
iget-object v1, p0, Lorg/vinix/bootstrap/ValueCallbackProbe;->value:Ljava/lang/Object;
invoke-static {v1, v0}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
const/4 v1, 1
new-instance v0, Landroid/webkit/VinixCookieCallback;
invoke-direct {v0, p0, v1}, Landroid/webkit/VinixCookieCallback;-><init>(Landroid/webkit/ValueCallback;Z)V
invoke-virtual {v0}, Landroid/webkit/VinixCookieCallback;->run()V
iget-object v0, p0, Lorg/vinix/bootstrap/ValueCallbackProbe;->value:Ljava/lang/Object;
sget-object v2, Ljava/lang/Boolean;->TRUE:Ljava/lang/Boolean;
invoke-static {v0, v2}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
const/4 v1, 0
new-instance v0, Landroid/webkit/VinixCookieCallback;
invoke-direct {v0, p0, v1}, Landroid/webkit/VinixCookieCallback;-><init>(Landroid/webkit/ValueCallback;Z)V
invoke-virtual {v0}, Landroid/webkit/VinixCookieCallback;->run()V
iget-object v0, p0, Lorg/vinix/bootstrap/ValueCallbackProbe;->value:Ljava/lang/Object;
sget-object v2, Ljava/lang/Boolean;->FALSE:Ljava/lang/Boolean;
invoke-static {v0, v2}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
iget v0, p0, Lorg/vinix/bootstrap/ValueCallbackProbe;->count:I
const/4 v1, 3
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public run()V
.locals 1
invoke-static {p0}, Lorg/vinix/bootstrap/ValueCallbackProbe;->exercise(Lorg/vinix/bootstrap/ValueCallbackProbe;)V
const/4 v0, 1
iput-boolean v0, p0, Lorg/vinix/bootstrap/ValueCallbackProbe;->done:Z
return-void
.end method
.method public static check()V
.locals 6
const-class v0, Landroid/webkit/ValueCallback;
invoke-virtual {v0}, Ljava/lang/Class;->isInterface()Z
move-result v1
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Ljava/lang/Class;->getTypeParameters()[Ljava/lang/reflect/TypeVariable;
move-result-object v1
array-length v1, v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v1, 1
new-array v1, v1, [Ljava/lang/Class;
const/4 v2, 0
const-class v3, Ljava/lang/Object;
aput-object v3, v1, v2
const-string v2, "onReceiveValue"
invoke-virtual {v0, v2, v1}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v0
sget-object v1, Ljava/lang/Void;->TYPE:Ljava/lang/Class;
invoke-static {v0, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
new-instance v0, Lorg/vinix/bootstrap/ValueCallbackProbe;
invoke-direct {v0}, Lorg/vinix/bootstrap/ValueCallbackProbe;-><init>()V
invoke-static {v0}, Lorg/vinix/bootstrap/ValueCallbackProbe;->exercise(Lorg/vinix/bootstrap/ValueCallbackProbe;)V
new-instance v0, Lorg/vinix/bootstrap/ValueCallbackProbe;
invoke-direct {v0}, Lorg/vinix/bootstrap/ValueCallbackProbe;-><init>()V
new-instance v1, Ljava/lang/Thread;
invoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
const-wide/16 v2, 3000
invoke-virtual {v1, v2, v3}, Ljava/lang/Thread;->join(J)V
iget-boolean v2, v0, Lorg/vinix/bootstrap/ValueCallbackProbe;->done:Z
const/4 v3, 1
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "VALUE-CALLBACK-PASS interface erased-method generic-type dispatch cookie-wrapper worker"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
}
