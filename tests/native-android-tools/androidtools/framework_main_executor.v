// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_main_executor(smali string) ! {
 // Executor callbacks must be queued even when submitted on the main thread.
 // Keep the Handler's shutdown semantics instead of silently dropping work.
 os.write_file(smali + '/android/os/HandlerExecutor.smali', '.class public Landroid/os/HandlerExecutor;
.super Ljava/lang/Object;
.implements Ljava/util/concurrent/Executor;
.field private final handler:Landroid/os/Handler;
.method public constructor <init>(Landroid/os/Handler;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iput-object p1, p0, Landroid/os/HandlerExecutor;->handler:Landroid/os/Handler;
return-void
.end method
.method public execute(Ljava/lang/Runnable;)V
.locals 2
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iget-object v0, p0, Landroid/os/HandlerExecutor;->handler:Landroid/os/Handler;
invoke-virtual {v0, p1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-nez v0, :done
new-instance v0, Ljava/util/concurrent/RejectedExecutionException;
const-string v1, "Handler is shutting down"
invoke-direct {v0, v1}, Ljava/util/concurrent/RejectedExecutionException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void
.end method
')!
 context := smali + '/android/content/Context.smali'
 os.write_file(context, framework_replace_method(os.read_file(context)!,
  'getMainExecutor()Ljava/util/concurrent/Executor;', '.method public getMainExecutor()Ljava/util/concurrent/Executor;
.locals 2
invoke-virtual {p0}, Landroid/content/Context;->getMainLooper()Landroid/os/Looper;
move-result-object v0
new-instance v1, Landroid/os/Handler;
invoke-direct {v1, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v0, Landroid/os/HandlerExecutor;
invoke-direct {v0, v1}, Landroid/os/HandlerExecutor;-><init>(Landroid/os/Handler;)V
return-object v0
.end method')!)!
 wrapper := smali + '/android/content/ContextWrapper.smali'
 os.write_file(wrapper, framework_replace_method(os.read_file(wrapper)!,
  'getMainExecutor()Ljava/util/concurrent/Executor;', '.method public getMainExecutor()Ljava/util/concurrent/Executor;
.locals 1
iget-object v0, p0, Landroid/content/ContextWrapper;->baseContext:Landroid/content/Context;
invoke-virtual {v0}, Landroid/content/Context;->getMainExecutor()Ljava/util/concurrent/Executor;
move-result-object v0
return-object v0
.end method')!)!
}
