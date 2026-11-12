// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_subscription_listener(smali string) ! {
	listener := r'Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;'
	path := smali + '/android/telephony/SubscriptionManager.smali'
	mut text := os.read_file(path)!
	// There is no telephony registry or ISub backend on this target. As with
	// Android's absent-registry path, report registration failure through the
	// selected handler/executor, without emitting a subscription snapshot.
	text = framework_replace_method(text, 'addOnSubscriptionsChangedListener(' + listener + ')V',
		'.method public addOnSubscriptionsChangedListener(' + listener + ')V\n.locals 2\nif-eqz p1, :done\niget-object v0, p1, ' + listener + '->handler:Landroid/os/Handler;\nnew-instance v1, Landroid/telephony/VinixSubscriptionFailure;\ninvoke-direct {v1, p1}, Landroid/telephony/VinixSubscriptionFailure;-><init>(' + listener + ')V\ninvoke-virtual {v0, v1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\n:done\nreturn-void\n.end method')!
	text = framework_replace_method(text, 'addOnSubscriptionsChangedListener(Ljava/util/concurrent/Executor;' + listener + ')V',
		'.method public addOnSubscriptionsChangedListener(Ljava/util/concurrent/Executor;' + listener + ')V\n.locals 1\ninvoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\ninvoke-static {p2}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\nnew-instance v0, Landroid/telephony/VinixSubscriptionFailure;\ninvoke-direct {v0, p2}, Landroid/telephony/VinixSubscriptionFailure;-><init>(' + listener + ')V\ninvoke-interface {p1, v0}, Ljava/util/concurrent/Executor;->execute(Ljava/lang/Runnable;)V\nreturn-void\n.end method')!
	text = framework_replace_method(text, 'removeOnSubscriptionsChangedListener(' + listener + ')V',
		'.method public removeOnSubscriptionsChangedListener(' + listener + ')V\n.locals 0\nreturn-void\n.end method')!
	os.write_file(path, text)!
	os.write_file(smali + r'/android/telephony/SubscriptionManager$OnSubscriptionsChangedListener.smali', '.class public ' + listener + r'
.super Ljava/lang/Object;
.annotation system Ldalvik/annotation/EnclosingClass;
value = Landroid/telephony/SubscriptionManager;
.end annotation
.annotation system Ldalvik/annotation/InnerClass;
accessFlags = 0x9
name = "OnSubscriptionsChangedListener"
.end annotation
.field final handler:Landroid/os/Handler;
.method public constructor <init>()V
.locals 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
new-instance v0, Landroid/os/Handler;
invoke-direct {v0}, Landroid/os/Handler;-><init>()V
iput-object v0, p0, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;->handler:Landroid/os/Handler;
return-void
.end method
.method public constructor <init>(Landroid/os/Looper;)V
.locals 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
new-instance v0, Landroid/os/Handler;
invoke-direct {v0, p1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object v0, p0, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;->handler:Landroid/os/Handler;
return-void
.end method
.method public onSubscriptionsChanged()V
.locals 0
return-void
.end method
.method public onAddListenerFailed()V
.locals 0
return-void
.end method
')!
	os.write_file(smali + '/android/telephony/VinixSubscriptionFailure.smali', '.class public final Landroid/telephony/VinixSubscriptionFailure;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field private final listener:' + listener + '\n.method public constructor <init>(' + listener + ')V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/telephony/VinixSubscriptionFailure;->listener:' + listener + '\nreturn-void\n.end method\n.method public run()V\n.locals 1\niget-object v0, p0, Landroid/telephony/VinixSubscriptionFailure;->listener:' + listener + '\ninvoke-virtual {v0}, ' + listener + '->onAddListenerFailed()V\nreturn-void\n.end method\n')!
}
