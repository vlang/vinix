// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_network_request_probe(dir string) ! {
 caps := 'Landroid/net/NetworkCapabilities;'
 request := 'Landroid/net/NetworkRequest;'
 builder := 'Landroid/net/NetworkRequest$Builder;'
 mut check := '
new-instance v0, ${builder}
invoke-direct {v0}, ${builder}-><init>()V
invoke-virtual {v0}, ${builder}->build()${request}
move-result-object v1
'
 for value in [13, 14, 15] {
  check += 'const/16 v2, ${value}\ninvoke-virtual {v1, v2}, ${request}->hasCapability(I)Z\nmove-result v2\nif-eqz v2, :bad\n'
 }
 check += '
const/16 v2, 16
invoke-virtual {v1, v2}, ${request}->hasCapability(I)Z
move-result v2
if-nez v2, :bad
const/16 v2, 15
invoke-virtual {v0, v2}, ${builder}->removeCapability(I)${builder}
move-result-object v2
if-ne v2, v0, :bad
const/16 v2, 12
invoke-virtual {v0, v2}, ${builder}->addCapability(I)${builder}
const/4 v2, 1
invoke-virtual {v0, v2}, ${builder}->addTransportType(I)${builder}
const/4 v2, 3
invoke-virtual {v0, v2}, ${builder}->addTransportType(I)${builder}
invoke-virtual {v0}, ${builder}->build()${request}
move-result-object v1
const/16 v2, 15
invoke-virtual {v1, v2}, ${request}->hasCapability(I)Z
move-result v2
if-nez v2, :bad
const/16 v2, 12
invoke-virtual {v0, v2}, ${builder}->removeCapability(I)${builder}
const/4 v2, 3
invoke-virtual {v0, v2}, ${builder}->removeTransportType(I)${builder}
invoke-virtual {v1, v2}, ${request}->hasTransport(I)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, ${request}->getCapabilities()[I
move-result-object v2
array-length v3, v2
const/4 v4, 3
if-ne v3, v4, :bad
const/4 v3, 0
aget v4, v2, v3
const/16 v5, 12
if-ne v4, v5, :bad
const/16 v4, 99
aput v4, v2, v3
invoke-virtual {v1, v5}, ${request}->hasCapability(I)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, ${request}->getTransportTypes()[I
move-result-object v2
array-length v3, v2
const/4 v4, 2
if-ne v3, v4, :bad
const/4 v3, 0
aget v4, v2, v3
const/4 v5, 1
if-ne v4, v5, :bad
const/4 v3, 1
aget v4, v2, v3
const/4 v5, 3
if-ne v4, v5, :bad
const/4 v2, 0
invoke-virtual {v1, v2}, ${request}->canBeSatisfiedBy(${caps})Z
move-result v2
if-nez v2, :bad
new-instance v2, ${caps}
invoke-direct {v2}, ${caps}-><init>()V
const/4 v3, 3
invoke-virtual {v2, v3}, ${caps}->addTransportType(I)${caps}
invoke-virtual {v1, v2}, ${request}->canBeSatisfiedBy(${caps})Z
move-result v3
if-nez v3, :bad
const/16 v3, 12
invoke-virtual {v2, v3}, ${caps}->addCapability(I)${caps}
invoke-virtual {v1, v2}, ${request}->canBeSatisfiedBy(${caps})Z
move-result v3
if-eqz v3, :bad
new-instance v3, ${caps}
invoke-direct {v3, v2}, ${caps}-><init>(${caps})V
const/4 v4, 3
invoke-virtual {v2, v4}, ${caps}->removeTransportType(I)${caps}
const/4 v4, 0
invoke-virtual {v2, v4}, ${caps}->addTransportType(I)${caps}
invoke-virtual {v1, v2}, ${request}->canBeSatisfiedBy(${caps})Z
move-result v4
if-nez v4, :bad
invoke-virtual {v1, v3}, ${request}->canBeSatisfiedBy(${caps})Z
move-result v4
if-eqz v4, :bad
new-instance v4, ${builder}
invoke-direct {v4, v1}, ${builder}-><init>(${request})V
const/16 v5, 12
invoke-virtual {v4, v5}, ${builder}->removeCapability(I)${builder}
invoke-virtual {v1, v5}, ${request}->hasCapability(I)Z
move-result v5
if-eqz v5, :bad
invoke-virtual {v4}, ${builder}->clearCapabilities()${builder}
invoke-virtual {v4}, ${builder}->build()${request}
move-result-object v4
invoke-virtual {v4}, ${request}->getCapabilities()[I
move-result-object v5
array-length v5, v5
if-nez v5, :bad
invoke-virtual {v4}, ${request}->getTransportTypes()[I
move-result-object v5
array-length v5, v5
if-nez v5, :bad
invoke-virtual {v4, v2}, ${request}->canBeSatisfiedBy(${caps})Z
move-result v5
if-eqz v5, :bad
invoke-virtual {v4}, ${request}->getNetworkSpecifier()Landroid/net/NetworkSpecifier;
move-result-object v5
if-nez v5, :bad
const/4 v5, 0
new-instance v4, ${caps}
invoke-direct {v4, v5}, ${caps}-><init>(${caps})V
invoke-virtual {v4}, ${caps}->getCapabilities()[I
move-result-object v5
array-length v5, v5
if-nez v5, :bad
const/16 v5, 38
invoke-virtual {v0, v5}, ${builder}->addCapability(I)${builder}
invoke-virtual {v0}, ${builder}->build()${request}
move-result-object v4
invoke-virtual {v4, v5}, ${request}->hasCapability(I)Z
move-result v4
if-eqz v4, :bad
'
 for index, row in [['addCapability', '-1'], ['removeCapability', '39'], ['addTransportType', '11'], ['removeTransportType', '-1']] {
  check += 'const/16 v5, ${row[1]}\n:invalid_${index}\ninvoke-virtual {v0, v5}, ${builder}->${row[0]}(I)${builder}\n:invalid_end_${index}\ngoto :bad\n:invalid_catch_${index}\nmove-exception v5\n.catch Ljava/lang/IllegalArgumentException; {:invalid_${index} .. :invalid_end_${index}} :invalid_catch_${index}\n'
 }
 check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-NETWORK-REQUESTS-PASS defaults add remove snapshots copied-arrays clear capabilities-and transports-or null validation"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "network request filters"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 os.write_file(dir + '/NetworkRequestProbe.smali', '.class public Lorg/vinix/bootstrap/NetworkRequestProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', check))!
}
