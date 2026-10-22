// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_connectivity_probe(dir string) ! {
 probe := 'Lorg/vinix/bootstrap/ConnectivityProbe;'
 manager := 'Lorg/vinix/bootstrap/TestConnectivity;'
 cm := 'Landroid/net/ConnectivityManager;'
 cb := 'Landroid/net/ConnectivityManager$NetworkCallback;'
 network := 'Landroid/net/Network;'
 caps := 'Landroid/net/NetworkCapabilities;'
 handler := 'Landroid/os/Handler;'
 request := 'Landroid/net/NetworkRequest;'
 os.write_file(dir + '/TestConnectivity.smali', '.class public ${manager}\n.super ${cm}\n.field public state:I\n' + method('public constructor <init>()V', 'invoke-direct {p0}, ${cm}-><init>()V\nreturn-void') + method('protected nativeGetNetworkState()I', 'iget v0, p0, ${manager}->state:I\nreturn v0'))!
 mut text := '.class public ${probe}\n.super ${cb}\n.implements Ljava/lang/Runnable;\n.field private manager:${manager}\n.field private handler:${handler}\n.field private internet:${probe}\n.field private wifi:${probe}\n.field private cancelled:${probe}\n'
 for field in ['stage', 'mode', 'available', 'capabilities', 'links', 'blocked', 'lost', 'order'] { text += '.field private ${field}:I\n' }
 failure := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "connectivity callback state or ordering"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 text += method('public constructor <init>()V', 'invoke-direct {p0}, ${cb}-><init>()V\nreturn-void')
 text += method('private mainThread()V', 'invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;\nmove-result-object v0\ninvoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v1\nif-ne v0, v1, :bad\nreturn-void\n' + failure)
 text += method('public onAvailable(${network})V', '
invoke-direct {p0}, ${probe}->mainThread()V
iget v0, p0, ${probe}->order:I
if-nez v0, :bad
const/4 v0, 1
iput v0, p0, ${probe}->order:I
iget v0, p0, ${probe}->available:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${probe}->available:I
iget v0, p0, ${probe}->mode:I
const/4 v1, 4
if-ne v0, v1, :done
iget-object v0, p0, ${probe}->manager:${manager}
invoke-virtual {v0, p0}, ${cm}->unregisterNetworkCallback(${cb})V
const/4 v0, 0
iput v0, p0, ${probe}->order:I
:done
return-void
' + failure)
 text += method('public onCapabilitiesChanged(${network}${caps})V', '
invoke-direct {p0}, ${probe}->mainThread()V
iget v0, p0, ${probe}->order:I
const/4 v1, 1
if-eq v0, v1, :order_ok
if-nez v0, :bad
:order_ok
const/4 v0, 2
iput v0, p0, ${probe}->order:I
const/16 v0, 16
invoke-virtual {p2, v0}, ${caps}->hasCapability(I)Z
move-result v0
if-nez v0, :bad
iget v0, p0, ${probe}->capabilities:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${probe}->capabilities:I
return-void
' + failure)
 text += method('public onLinkPropertiesChanged(${network}Landroid/net/LinkProperties;)V', '
invoke-direct {p0}, ${probe}->mainThread()V
if-eqz p2, :bad
iget v0, p0, ${probe}->order:I
const/4 v1, 2
if-ne v0, v1, :bad
const/4 v0, 3
iput v0, p0, ${probe}->order:I
iget v0, p0, ${probe}->links:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${probe}->links:I
return-void
' + failure)
 text += method('public onBlockedStatusChanged(${network}Z)V', '
invoke-direct {p0}, ${probe}->mainThread()V
if-nez p2, :bad
iget v0, p0, ${probe}->order:I
const/4 v1, 3
if-ne v0, v1, :bad
const/4 v0, 0
iput v0, p0, ${probe}->order:I
iget v0, p0, ${probe}->blocked:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${probe}->blocked:I
return-void
' + failure)
 text += method('public onLost(${network})V', 'invoke-direct {p0}, ${probe}->mainThread()V\niget v0, p0, ${probe}->order:I\nif-nez v0, :bad\niget v0, p0, ${probe}->lost:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${probe}->lost:I\nreturn-void\n' + failure)
 text += method('private counts(IIIII)V', 'iget v0, p0, ${probe}->available:I\nif-ne v0, p1, :bad\niget v0, p0, ${probe}->capabilities:I\nif-ne v0, p2, :bad\niget v0, p0, ${probe}->links:I\nif-ne v0, p3, :bad\niget v0, p0, ${probe}->blocked:I\nif-ne v0, p4, :bad\niget v0, p0, ${probe}->lost:I\nif-ne v0, p5, :bad\nreturn-void\n' + failure)
 // counts has six argument registers: use invoke-direct/range with v0..v5.
 mut run := '
invoke-direct {p0}, ${probe}->mainThread()V
iget-object v6, p0, ${probe}->manager:${manager}
iget v7, p0, ${probe}->stage:I
if-eqz v7, :zero
const/4 v0, 1
if-eq v7, v0, :one
const/4 v0, 2
if-eq v7, v0, :two
const/4 v0, 3
if-eq v7, v0, :three
goto :four
:zero
move-object v0, p0
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
const/4 v4, 0
const/4 v5, 0
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
const v0, 0x10403
iput v0, v6, ${manager}->state:I
goto :again
:one
move-object v0, p0
const/4 v1, 1
const/4 v2, 1
const/4 v3, 1
const/4 v4, 1
const/4 v5, 0
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
iget-object v0, p0, ${probe}->internet:${probe}
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
const v0, 0x10401
iput v0, v6, ${manager}->state:I
goto :again
:two
move-object v0, p0
const/4 v1, 1
const/4 v2, 2
const/4 v3, 2
const/4 v4, 2
const/4 v5, 0
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
iget-object v0, p0, ${probe}->internet:${probe}
const/4 v2, 1
const/4 v3, 1
const/4 v4, 1
const/4 v5, 1
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
const v0, 0x20203
iput v0, v6, ${manager}->state:I
goto :again
:three
move-object v0, p0
const/4 v1, 2
const/4 v2, 3
const/4 v3, 3
const/4 v4, 3
const/4 v5, 1
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
iget-object v0, p0, ${probe}->internet:${probe}
const/4 v2, 2
const/4 v3, 2
const/4 v4, 2
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
iget-object v0, p0, ${probe}->wifi:${probe}
const/4 v1, 1
const/4 v2, 1
const/4 v3, 1
const/4 v4, 1
const/4 v5, 0
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
'
 for source in ['internet', 'wifi'] { run += 'iget-object v0, p0, ${probe}->${source}:${probe}\ninvoke-virtual {v6, v0}, ${cm}->unregisterNetworkCallback(${cb})V\n' }
 run += '
invoke-virtual {v6, p0}, ${cm}->unregisterNetworkCallback(${cb})V
const/4 v0, 4
iput v0, p0, ${probe}->mode:I
invoke-virtual {v6, p0}, ${cm}->registerDefaultNetworkCallback(${cb})V
goto :again
:four
move-object v0, p0
const/4 v1, 3
const/4 v2, 3
const/4 v3, 3
const/4 v4, 3
const/4 v5, 1
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
iget-object v0, p0, ${probe}->cancelled:${probe}
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
const/4 v4, 0
const/4 v5, 0
invoke-direct/range {v0 .. v5}, ${probe}->counts(IIIII)V
new-instance v0, ${cm}
invoke-direct {v0}, ${cm}-><init>()V
invoke-virtual {v0}, ${cm}->vinixNetworkState()I
move-result v1
sget-object v2, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v3, "BOOTSTRAP-CONNECTIVITY-KERNEL-STATE"
invoke-virtual {v2, v3}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v2, v1}, Ljava/io/PrintStream;->println(I)V
and-int/lit8 v2, v1, 3
const/4 v3, 3
if-eq v2, v3, :kernel_ready
const/16 v2, 16
if-ge v7, v2, :bad
goto :again
:kernel_ready
invoke-virtual {v0}, ${cm}->getActiveNetwork()${network}
move-result-object v1
invoke-virtual {v0, v1}, ${cm}->getNetworkCapabilities(${network})${caps}
move-result-object v1
const/16 v2, 12
invoke-virtual {v1, v2}, ${caps}->hasCapability(I)Z
move-result v2
if-eqz v2, :bad
const/16 v2, 16
invoke-virtual {v1, v2}, ${caps}->hasCapability(I)Z
move-result v2
if-nez v2, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-CONNECTIVITY-PASS kernel-route offline snapshots ordering handler capability-change filtering loss unregister reentrant-cancel"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:again
add-int/lit8 v7, v7, 1
iput v7, p0, ${probe}->stage:I
iget-object v0, p0, ${probe}->handler:${handler}
const-wide/16 v1, 1250
invoke-virtual {v0, p0, v1, v2}, ${handler}->postDelayed(Ljava/lang/Runnable;J)Z
return-void
' + failure
 text += method('public run()V', run)
 mut check := '
new-instance v0, ${manager}
invoke-direct {v0}, ${manager}-><init>()V
invoke-virtual {v0}, ${cm}->getActiveNetwork()${network}
move-result-object v1
if-nez v1, :bad
invoke-virtual {v0}, ${cm}->getActiveNetworkInfo()Landroid/net/NetworkInfo;
move-result-object v1
if-nez v1, :bad
invoke-virtual {v0}, ${cm}->getAllNetworks()[${network}
move-result-object v1
array-length v1, v1
if-nez v1, :bad
const v1, 0x10403
iput v1, v0, ${manager}->state:I
invoke-virtual {v0}, ${cm}->getActiveNetwork()${network}
move-result-object v1
invoke-virtual {v0}, ${cm}->getActiveNetwork()${network}
move-result-object v2
invoke-virtual {v1, v2}, ${network}->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v0, v1}, ${cm}->getNetworkCapabilities(${network})${caps}
move-result-object v2
const/4 v3, 3
invoke-virtual {v2, v3}, ${caps}->hasTransport(I)Z
move-result v3
if-eqz v3, :bad
const/16 v3, 12
invoke-virtual {v2, v3}, ${caps}->removeCapability(I)${caps}
invoke-virtual {v0, v1}, ${cm}->getNetworkCapabilities(${network})${caps}
move-result-object v2
invoke-virtual {v2, v3}, ${caps}->hasCapability(I)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v0}, ${cm}->getActiveNetworkInfo()Landroid/net/NetworkInfo;
move-result-object v2
invoke-virtual {v2}, Landroid/net/NetworkInfo;->getType()I
move-result v3
const/16 v4, 9
if-ne v3, v4, :bad
invoke-virtual {v2}, Landroid/net/NetworkInfo;->isAvailable()Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v0}, ${cm}->isActiveNetworkMetered()Z
move-result v3
if-eqz v3, :bad
const/4 v2, 0
iput v2, v0, ${manager}->state:I
invoke-virtual {v0, v1}, ${cm}->getNetworkCapabilities(${network})${caps}
move-result-object v1
if-nez v1, :bad
new-instance v1, ${probe}
invoke-direct {v1}, ${probe}-><init>()V
iput-object v0, v1, ${probe}->manager:${manager}
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v2
new-instance v3, ${handler}
invoke-direct {v3, v2}, ${handler}-><init>(Landroid/os/Looper;)V
iput-object v3, v1, ${probe}->handler:${handler}
invoke-virtual {v0, v1, v3}, ${cm}->registerDefaultNetworkCallback(${cb}${handler})V
:duplicate
invoke-virtual {v0, v1}, ${cm}->registerDefaultNetworkCallback(${cb})V
:duplicate_end
goto :bad
:duplicate_catch
move-exception v2
.catch Ljava/lang/IllegalArgumentException; {:duplicate .. :duplicate_end} :duplicate_catch
'
 for index, call in [
  'invoke-virtual {v0, v8}, ${cm}->registerDefaultNetworkCallback(${cb})V',
  'invoke-virtual {v0, v8, v1}, ${cm}->registerNetworkCallback(${request}${cb})V',
  'invoke-virtual {v0, v1, v8}, ${cm}->registerDefaultNetworkCallback(${cb}${handler})V',
  'invoke-virtual {v0, v8}, ${cm}->unregisterNetworkCallback(${cb})V',
 ] {
  check += 'const/4 v8, 0\n:null_${index}\n${call}\n:null_end_${index}\ngoto :bad\n:null_catch_${index}\nmove-exception v2\n.catch Ljava/lang/NullPointerException; {:null_${index} .. :null_end_${index}} :null_catch_${index}\n'
 }
 for row in [['internet', '12', '-1'], ['wifi', '12', '1']] {
  field, capability, transport := row[0], row[1], row[2]
  check += 'new-instance v2, ${probe}\ninvoke-direct {v2}, ${probe}-><init>()V\niput-object v0, v2, ${probe}->manager:${manager}\niput-object v2, v1, ${probe}->${field}:${probe}\nnew-instance v4, Landroid/net/NetworkRequest$Builder;\ninvoke-direct {v4}, Landroid/net/NetworkRequest$Builder;-><init>()V\nconst/16 v5, ${capability}\ninvoke-virtual {v4, v5}, Landroid/net/NetworkRequest$Builder;->addCapability(I)Landroid/net/NetworkRequest$Builder;\n'
  if transport != '-1' { check += 'const/16 v5, ${transport}\ninvoke-virtual {v4, v5}, Landroid/net/NetworkRequest$Builder;->addTransportType(I)Landroid/net/NetworkRequest$Builder;\n' }
  check += 'invoke-virtual {v4}, Landroid/net/NetworkRequest$Builder;->build()${request}\nmove-result-object v4\ninvoke-virtual {v0, v4, v2}, ${cm}->requestNetwork(${request}${cb})V\n'
 }
 check += '
new-instance v2, ${probe}
invoke-direct {v2}, ${probe}-><init>()V
iput-object v2, v1, ${probe}->cancelled:${probe}
invoke-virtual {v0, v2}, ${cm}->registerDefaultNetworkCallback(${cb})V
invoke-virtual {v0, v2}, ${cm}->unregisterNetworkCallback(${cb})V
const-wide/16 v4, 250
invoke-virtual {v3, v1, v4, v5}, ${handler}->postDelayed(Ljava/lang/Runnable;J)Z
return-void
' + failure
 text += method('public static check()V', check)
 os.write_file(dir + '/ConnectivityProbe.smali', text)!
}
