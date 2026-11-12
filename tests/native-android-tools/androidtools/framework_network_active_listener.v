// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The target has no radio idle timers (see isDefaultNetworkActive). Keep
// registrations until removed, without inventing power-state transitions or
// confusing them with link availability/Internet reachability callbacks.
pub fn framework_network_active_listener(smali string) ! {
	path := smali + '/android/net/ConnectivityManager.smali'
	listener := r'Landroid/net/ConnectivityManager$OnNetworkActiveListener;'
	mut text := os.read_file(path)!
	if text.contains('vinixActiveListeners') || text.contains('DefaultNetworkActiveListener(')
		|| os.exists(smali + r'/android/net/ConnectivityManager$OnNetworkActiveListener.smali') {
		return error('network activity listener already present')
	}
	// Retain the original constructor contract and initialize a per-instance,
	// thread-safe registration set before the manager can escape.
	window_animations_method(text, 'public constructor <init>()V', '.registers 9\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')!
	text = framework_replace_method(text, '<init>()V', r'
.method public constructor <init>()V
.locals 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
new-instance v0, Ljava/util/concurrent/ConcurrentHashMap;
invoke-direct {v0}, Ljava/util/concurrent/ConcurrentHashMap;-><init>()V
iput-object v0, p0, Landroid/net/ConnectivityManager;->vinixActiveListeners:Ljava/util/concurrent/ConcurrentHashMap;
return-void
.end method')!
	text += r'
.annotation system Ldalvik/annotation/MemberClasses;
value = { Landroid/net/ConnectivityManager$OnNetworkActiveListener; }
.end annotation
.field private final vinixActiveListeners:Ljava/util/concurrent/ConcurrentHashMap;
.method public addDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
.locals 2
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iget-object v0, p0, Landroid/net/ConnectivityManager;->vinixActiveListeners:Ljava/util/concurrent/ConcurrentHashMap;
sget-object v1, Ljava/lang/Boolean;->TRUE:Ljava/lang/Boolean;
invoke-virtual {v0, p1, v1}, Ljava/util/concurrent/ConcurrentHashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
return-void
.end method
.method public removeDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
.locals 2
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iget-object v0, p0, Landroid/net/ConnectivityManager;->vinixActiveListeners:Ljava/util/concurrent/ConcurrentHashMap;
invoke-virtual {v0, p1}, Ljava/util/concurrent/ConcurrentHashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
if-nez v0, :done
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Listener was not registered."
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void
.end method
'
	os.write_file(path, text)!
	os.write_file(smali + r'/android/net/ConnectivityManager$OnNetworkActiveListener.smali',
		'.class public interface abstract ' + listener + r'
.super Ljava/lang/Object;
.annotation system Ldalvik/annotation/EnclosingClass;
value = Landroid/net/ConnectivityManager;
.end annotation
.annotation system Ldalvik/annotation/InnerClass;
accessFlags = 0x609
name = "OnNetworkActiveListener"
.end annotation
.method public abstract onNetworkActive()V
.end method
')!
}
