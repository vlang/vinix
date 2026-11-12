// SPDX-License-Identifier: GPL-2.0-or-later
module networkactiveprobe

import os

pub fn install(root string) ! {
	os.write_file(root + '/smali/NetworkActiveProbe.smali', r'
.class public Lorg/vinix/bootstrap/NetworkActiveProbe;
.super Ljava/lang/Object;
.implements Landroid/net/ConnectivityManager$OnNetworkActiveListener;
.field public calls:I
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public onNetworkActive()V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/NetworkActiveProbe;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/NetworkActiveProbe;->calls:I
return-void
.end method
.method private static missing(Landroid/net/ConnectivityManager;Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
.locals 1
:begin
invoke-virtual {p0, p1}, Landroid/net/ConnectivityManager;->removeDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
:end
.catch Ljava/lang/IllegalArgumentException; {:begin .. :end} :expected
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:expected
move-exception v0
return-void
.end method
.method public static check()V
.locals 6
const-class v0, Landroid/net/ConnectivityManager$OnNetworkActiveListener;
invoke-virtual {v0}, Ljava/lang/Class;->getModifiers()I
move-result v1
const/16 v2, 0x609
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Ljava/lang/Class;->getDeclaringClass()Ljava/lang/Class;
move-result-object v1
const-class v2, Landroid/net/ConnectivityManager;
invoke-virtual {v1, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v1
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/net/ConnectivityManager;
invoke-direct {v0}, Landroid/net/ConnectivityManager;-><init>()V
new-instance v1, Landroid/net/ConnectivityManager;
invoke-direct {v1}, Landroid/net/ConnectivityManager;-><init>()V
new-instance v2, Lorg/vinix/bootstrap/NetworkActiveProbe;
invoke-direct {v2}, Lorg/vinix/bootstrap/NetworkActiveProbe;-><init>()V
new-instance v3, Lorg/vinix/bootstrap/NetworkActiveProbe;
invoke-direct {v3}, Lorg/vinix/bootstrap/NetworkActiveProbe;-><init>()V
invoke-static {v0, v2}, Lorg/vinix/bootstrap/NetworkActiveProbe;->missing(Landroid/net/ConnectivityManager;Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-virtual {v0, v2}, Landroid/net/ConnectivityManager;->addDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-virtual {v0, v2}, Landroid/net/ConnectivityManager;->addDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-virtual {v0, v3}, Landroid/net/ConnectivityManager;->addDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-static {v1, v2}, Lorg/vinix/bootstrap/NetworkActiveProbe;->missing(Landroid/net/ConnectivityManager;Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-virtual {v0, v2}, Landroid/net/ConnectivityManager;->removeDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-static {v0, v2}, Lorg/vinix/bootstrap/NetworkActiveProbe;->missing(Landroid/net/ConnectivityManager;Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-virtual {v0, v3}, Landroid/net/ConnectivityManager;->removeDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-static {v0, v3}, Lorg/vinix/bootstrap/NetworkActiveProbe;->missing(Landroid/net/ConnectivityManager;Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-virtual {v1, v2}, Landroid/net/ConnectivityManager;->addDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
invoke-virtual {v1, v2}, Landroid/net/ConnectivityManager;->removeDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
iget v4, v2, Lorg/vinix/bootstrap/NetworkActiveProbe;->calls:I
const/4 v5, 0
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v3, Lorg/vinix/bootstrap/NetworkActiveProbe;->calls:I
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v2, 0
:add_begin
invoke-virtual {v0, v2}, Landroid/net/ConnectivityManager;->addDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
:add_end
.catch Ljava/lang/NullPointerException; {:add_begin .. :add_end} :null_add
new-instance v3, Ljava/lang/AssertionError;
invoke-direct {v3}, Ljava/lang/AssertionError;-><init>()V
throw v3
:null_add
move-exception v3
:remove_begin
invoke-virtual {v0, v2}, Landroid/net/ConnectivityManager;->removeDefaultNetworkActiveListener(Landroid/net/ConnectivityManager$OnNetworkActiveListener;)V
:remove_end
.catch Ljava/lang/NullPointerException; {:remove_begin .. :remove_end} :null_remove
new-instance v3, Ljava/lang/AssertionError;
invoke-direct {v3}, Ljava/lang/AssertionError;-><init>()V
throw v3
:null_remove
move-exception v3
invoke-virtual {v0}, Landroid/net/ConnectivityManager;->isDefaultNetworkActive()Z
move-result v4
const/4 v5, 1
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "NETWORK-ACTIVE-LISTENER-PASS nested-interface per-manager-registration removal null-validation no-synthetic-transition"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
}
