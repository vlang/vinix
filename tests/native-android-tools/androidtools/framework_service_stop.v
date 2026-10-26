// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Service lifecycle and the running-services map belong to the main looper.
// Worker callers still receive the actual stop result and original exception.
pub fn framework_service_stop(smali string) ! {
	app := smali + '/android/atl/ATLLoadedApp.smali'
	request := smali + '/android/atl/VinixServiceStop.smali'
	text := os.read_file(app)!
	signature := '.method public stopService(Landroid/content/Intent;)Z\n'
	if text.count(signature) != 1 || text.contains('vinixStopServiceMain(')
		|| os.exists(request) || os.is_link(request) {
		return error('unmodified service stop provider required')
	}
	start := text.index(signature) or { return error('service stop method missing') }
	tail := text[start..]
	end := tail.index('.end method') or { return error('service stop method end missing') }
	original := tail[..end + '.end method'.len]
	if original.count('Landroid/atl/ATLLoadedApp;->running_services:Ljava/util/HashMap;') != 1
		|| original.count('Landroid/app/Service;->vinixStarted:Z') != 1
		|| original.count('Landroid/atl/VinixServiceBinding;->maybeDestroy(Landroid/app/Service;)V') != 1
		|| original.count('Ljava/util/HashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;') != 1
		|| original.contains('onDestroy') || original.contains('Handler;') {
		return error('bound-service stop body required')
	}
	helper := original.replace(signature, '.method final vinixStopServiceMain(Landroid/content/Intent;)Z\n')
	declaration := '.method public stopService(Landroid/content/Intent;)Z
.locals 5
# Snapshot before a worker request can wait behind queued starts or bindings.
new-instance v2, Landroid/content/Intent;
invoke-direct {v2, p1}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V
move-object p1, v2
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :worker
invoke-virtual {p0, p1}, Landroid/atl/ATLLoadedApp;->vinixStopServiceMain(Landroid/content/Intent;)Z
move-result v0
return v0
:worker
new-instance v2, Landroid/atl/VinixServiceStop;
invoke-direct {v2, p0, p1}, Landroid/atl/VinixServiceStop;-><init>(Landroid/atl/ATLLoadedApp;Landroid/content/Intent;)V
new-instance v3, Ljava/util/concurrent/FutureTask;
invoke-direct {v3, v2}, Ljava/util/concurrent/FutureTask;-><init>(Ljava/util/concurrent/Callable;)V
new-instance v4, Landroid/os/Handler;
invoke-direct {v4, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
invoke-virtual {v4, v3}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-nez v0, :accepted
new-instance v0, Ljava/util/concurrent/RejectedExecutionException;
const-string v1, "Main looper is shutting down"
invoke-direct {v0, v1}, Ljava/util/concurrent/RejectedExecutionException;-><init>(Ljava/lang/String;)V
throw v0
:accepted
const/4 v1, 0
:wait
:try_start
invoke-virtual {v3}, Ljava/util/concurrent/FutureTask;->get()Ljava/lang/Object;
move-result-object v0
:try_end
.catch Ljava/lang/InterruptedException; {:try_start .. :try_end} :interrupted
.catch Ljava/util/concurrent/ExecutionException; {:try_start .. :try_end} :failed
if-eqz v1, :result
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v2
invoke-virtual {v2}, Ljava/lang/Thread;->interrupt()V
:result
check-cast v0, Ljava/lang/Boolean;
invoke-virtual {v0}, Ljava/lang/Boolean;->booleanValue()Z
move-result v0
return v0
:interrupted
move-exception v0
# Finish the already accepted operation; preserve interruption for the caller.
const/4 v1, 1
goto :wait
:failed
move-exception v0
invoke-virtual {v0}, Ljava/util/concurrent/ExecutionException;->getCause()Ljava/lang/Throwable;
move-result-object v2
if-eqz v1, :throw
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Thread;->interrupt()V
:throw
throw v2
.end method'
	body := '.class public final Landroid/atl/VinixServiceStop;
.super Ljava/lang/Object;
.implements Ljava/util/concurrent/Callable;
.field private final app:Landroid/atl/ATLLoadedApp;
.field private final intent:Landroid/content/Intent;
.method public constructor <init>(Landroid/atl/ATLLoadedApp;Landroid/content/Intent;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/atl/VinixServiceStop;->app:Landroid/atl/ATLLoadedApp;
iput-object p2, p0, Landroid/atl/VinixServiceStop;->intent:Landroid/content/Intent;
return-void
.end method
.method public call()Ljava/lang/Object;
.locals 2
iget-object v0, p0, Landroid/atl/VinixServiceStop;->app:Landroid/atl/ATLLoadedApp;
iget-object v1, p0, Landroid/atl/VinixServiceStop;->intent:Landroid/content/Intent;
invoke-virtual {v0, v1}, Landroid/atl/ATLLoadedApp;->vinixStopServiceMain(Landroid/content/Intent;)Z
move-result v0
invoke-static {v0}, Ljava/lang/Boolean;->valueOf(Z)Ljava/lang/Boolean;
move-result-object v0
return-object v0
.end method
'
	// Validate all anchors and destinations before either output is changed.
	os.write_file(app, text.replace(original, declaration + '\n\n' + helper))!
	os.write_file(request, body)!
}
