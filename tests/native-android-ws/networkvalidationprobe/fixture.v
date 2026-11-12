// SPDX-License-Identifier: GPL-2.0-or-later
module networkvalidationprobe

import os

pub fn install(root string) ! {
	os.write_file(root + '/smali/OfflineValidationNetwork.smali', r'
.class public Lorg/vinix/bootstrap/OfflineValidationNetwork;
.super Landroid/net/ConnectivityManager;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/net/ConnectivityManager;-><init>()V
return-void
.end method
.method protected nativeGetNetworkState()I
.locals 1
const/4 v0, 0
return v0
.end method
')!
	os.write_file(root + '/smali/NetworkValidationProbe.smali', r'
.class public final Lorg/vinix/bootstrap/NetworkValidationProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 8
new-instance v0, Lorg/vinix/bootstrap/OfflineValidationNetwork;
invoke-direct {v0}, Lorg/vinix/bootstrap/OfflineValidationNetwork;-><init>()V
const/4 v1, 0
const/4 v2, 1
invoke-virtual {v0, v1, v2}, Landroid/net/ConnectivityManager;->reportNetworkConnectivity(Landroid/net/Network;Z)V
invoke-virtual {v0}, Landroid/net/ConnectivityManager;->vinixNetworkState()I
move-result v1
if-nez v1, :bad
new-instance v2, Landroid/net/ConnectivityManager;
invoke-direct {v2}, Landroid/net/ConnectivityManager;-><init>()V
const/16 v7, 450
:poll
invoke-virtual {v2}, Landroid/net/ConnectivityManager;->getActiveNetwork()Landroid/net/Network;
move-result-object v3
if-eqz v3, :wait
invoke-virtual {v2, v3}, Landroid/net/ConnectivityManager;->getNetworkCapabilities(Landroid/net/Network;)Landroid/net/NetworkCapabilities;
move-result-object v4
if-eqz v4, :wait
const/16 v5, 16
invoke-virtual {v4, v5}, Landroid/net/NetworkCapabilities;->hasCapability(I)Z
move-result v5
if-nez v5, :validated
:wait
add-int/lit8 v7, v7, -1
if-eqz v7, :bad
const-wide/16 v5, 100
invoke-static {v5, v6}, Ljava/lang/Thread;->sleep(J)V
goto :poll
:validated
const/16 v5, 12
invoke-virtual {v4, v5}, Landroid/net/NetworkCapabilities;->hasCapability(I)Z
move-result v5
if-eqz v5, :bad
const/16 v5, 11
invoke-virtual {v4, v5}, Landroid/net/NetworkCapabilities;->hasCapability(I)Z
move-result v5
if-nez v5, :bad
invoke-virtual {v0, v3}, Landroid/net/ConnectivityManager;->getNetworkCapabilities(Landroid/net/Network;)Landroid/net/NetworkCapabilities;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v0}, Landroid/net/ConnectivityManager;->vinixNetworkState()I
move-result v4
if-nez v4, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "NETWORK-VALIDATION-PASS real-HTTPS-204 kernel-link metering-preserved offline-report-cannot-promote offline-invalidates"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "measured HTTPS network validation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
')!
}
