// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn connectivity_method(signature string, body string) string {
 return '.method ' + signature + '\n.locals 8\n' + body + '\n.end method\n'
}

// Vinix currently exposes one selected configured link to Android. Callbacks
// poll kernel state on the supplied Handler; registration never calls user code
// inline. Requests cannot activate unavailable radios or validate Internet access.
fn framework_connectivity(smali string) ! {
 cm := 'Landroid/net/ConnectivityManager;'
 cb := 'Landroid/net/ConnectivityManager$NetworkCallback;'
 task := 'Landroid/atl/VinixNetworkUpdate;'
 caps := 'Landroid/net/NetworkCapabilities;'
 network := 'Landroid/net/Network;'
 request := 'Landroid/net/NetworkRequest;'
 handler := 'Landroid/os/Handler;'
 registry := 'Ljava/util/concurrent/ConcurrentHashMap;'
 mut text := '.class public ${cm}\n.super Ljava/lang/Object;\n.field private static callbacks:${registry}\n'
 for index, name in ['DISABLED', 'WHITELISTED', 'ENABLED'] {
  text += '.field public static final RESTRICT_BACKGROUND_STATUS_${name}:I = ${index + 1}\n'
 }
 text += connectivity_method('static constructor <clinit>()V', 'new-instance v0, ${registry}\ninvoke-direct {v0}, ${registry}-><init>()V\nsput-object v0, ${cm}->callbacks:${registry}\nreturn-void')
 text += connectivity_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 text += '.method protected native nativeGetNetworkAvailable()Z\n.end method\n.method protected native nativeGetNetworkState()I\n.end method\n'
 text += connectivity_method('public getActiveNetwork()${network}', 'invoke-virtual {p0}, ${cm}->nativeGetNetworkState()I\nmove-result v0\nif-eqz v0, :none\nushr-int/lit8 v0, v0, 16\nnew-instance v1, ${network}\ninvoke-direct {v1, v0}, ${network}-><init>(I)V\nreturn-object v1\n:none\nconst/4 v0, 0\nreturn-object v0')
 text += connectivity_method('public getAllNetworks()[${network}', 'invoke-virtual {p0}, ${cm}->getActiveNetwork()${network}\nmove-result-object v0\nconst/4 v1, 0\nif-eqz v0, :array\nconst/4 v1, 1\n:array\nnew-array v1, v1, [${network}\nif-eqz v0, :done\nconst/4 v2, 0\naput-object v0, v1, v2\n:done\nreturn-object v1')
 text += connectivity_method('public static vinixCapabilities(I)${caps}', '
if-eqz p0, :none
new-instance v0, ${caps}
invoke-direct {v0}, ${caps}-><init>()V
and-int/lit8 v1, p0, 2
if-eqz v1, :transport
const/16 v1, 12
invoke-virtual {v0, v1}, ${caps}->addCapability(I)${caps}
:transport
ushr-int/lit8 v1, p0, 8
and-int/lit16 v1, v1, 255
if-eqz v1, :done
add-int/lit8 v1, v1, -1
invoke-virtual {v0, v1}, ${caps}->addTransportType(I)${caps}
:done
return-object v0
:none
const/4 v0, 0
return-object v0')
 for row in [['NetworkCapabilities', 'NetworkCapabilities', 'vinixCapabilities'], ['LinkProperties', 'LinkProperties', 'vinixLinkProperties']] {
  name, result, target := row[0], row[1], row[2]
  text += connectivity_method('public get${name}(${network})Landroid/net/${result};', '
if-eqz p1, :none
invoke-virtual {p0}, ${cm}->nativeGetNetworkState()I
move-result v0
if-eqz v0, :none
ushr-int/lit8 v1, v0, 16
iget v2, p1, ${network}->vinixInterface:I
if-ne v1, v2, :none
invoke-static {v0}, ${cm}->${target}(I)Landroid/net/${result};
move-result-object v0
return-object v0
:none
const/4 v0, 0
return-object v0')
 }
 text += connectivity_method('public static vinixLinkProperties(I)Landroid/net/LinkProperties;', 'ushr-int/lit8 v0, p0, 16\nnew-instance v1, Landroid/net/LinkProperties;\ninvoke-direct {v1, v0}, Landroid/net/LinkProperties;-><init>(I)V\nreturn-object v1')
 text += connectivity_method('public getActiveNetworkInfo()Landroid/net/NetworkInfo;', 'invoke-virtual {p0}, ${cm}->nativeGetNetworkState()I\nmove-result v0\nif-eqz v0, :none\nnew-instance v1, Landroid/net/NetworkInfo;\ninvoke-direct {v1, v0}, Landroid/net/NetworkInfo;-><init>(I)V\nreturn-object v1\n:none\nconst/4 v0, 0\nreturn-object v0')
 text += connectivity_method('public getNetworkInfo(I)Landroid/net/NetworkInfo;', 'invoke-virtual {p0}, ${cm}->getActiveNetworkInfo()Landroid/net/NetworkInfo;\nmove-result-object v0\nif-eqz v0, :done\ninvoke-virtual {v0}, Landroid/net/NetworkInfo;->getType()I\nmove-result v1\nif-eq v1, p1, :done\nconst/4 v0, 0\n:done\nreturn-object v0')
 text += connectivity_method('public getAllNetworkInfo()[Landroid/net/NetworkInfo;', 'invoke-virtual {p0}, ${cm}->getActiveNetworkInfo()Landroid/net/NetworkInfo;\nmove-result-object v0\nconst/4 v1, 0\nif-eqz v0, :array\nconst/4 v1, 1\n:array\nnew-array v1, v1, [Landroid/net/NetworkInfo;\nif-eqz v0, :done\nconst/4 v2, 0\naput-object v0, v1, v2\n:done\nreturn-object v1')
 // Without an administrator's cost policy, treat the link as metered. Do not
 // grant NOT_METERED merely because the host uses Ethernet or Wi-Fi.
 for signature in ['isActiveNetworkMetered()Z', 'getBackgroundDataSetting()Z'] {
  text += connectivity_method('public ${signature}', 'const/4 v0, 1\nreturn v0')
 }
 // Vinix has no Data Saver policy or background network restriction. This
 // policy is independent of the conservative metered-link classification.
 text += connectivity_method('public getRestrictBackgroundStatus()I', 'const/4 v0, 1\nreturn v0')
 text += connectivity_method('public getDefaultProxy()Landroid/net/ProxyInfo;', 'const/4 v0, 0\nreturn-object v0')
 // Reports cannot promote an unvalidated link: validation is not implemented.
 text += connectivity_method('public reportNetworkConnectivity(${network}Z)V', 'return-void')
 text += connectivity_method('private vinixRegister(${request}${cb}${handler})V', '
invoke-static {p2}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-static {p3}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
new-instance v0, ${task}
invoke-direct {v0, p0, p1, p2, p3}, ${task}-><init>(${cm}${request}${cb}${handler})V
sget-object v1, ${cm}->callbacks:${registry}
invoke-virtual {v1, p2, v0}, ${registry}->putIfAbsent(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v2
if-nez v2, :duplicate
invoke-virtual {p3, v0}, ${handler}->post(Ljava/lang/Runnable;)Z
move-result v2
if-nez v2, :done
invoke-static {p2, v0}, ${cm}->vinixRemove(${cb}${task})V
new-instance v0, Ljava/util/concurrent/RejectedExecutionException;
invoke-direct {v0}, Ljava/util/concurrent/RejectedExecutionException;-><init>()V
throw v0
:duplicate
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "network callback already registered"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void')
 text += connectivity_method('public static vinixRemove(${cb}${task})V', 'sget-object v0, ${cm}->callbacks:${registry}\ninvoke-virtual {v0, p0, p1}, ${registry}->remove(Ljava/lang/Object;Ljava/lang/Object;)Z\nreturn-void')
 text += connectivity_method('public unregisterNetworkCallback(${cb})V', 'invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\nsget-object v0, ${cm}->callbacks:${registry}\ninvoke-virtual {v0, p1}, ${registry}->remove(Ljava/lang/Object;)Ljava/lang/Object;\nmove-result-object v0\nif-eqz v0, :done\ncheck-cast v0, ${task}\ninvoke-virtual {v0}, ${task}->cancel()V\n:done\nreturn-void')
 for default_callback in [true, false] {
  for with_handler in [false, true] {
   name := if default_callback { 'registerDefaultNetworkCallback' } else { 'registerNetworkCallback' }
   parameters := if default_callback { cb } else { request + cb }
   callback_reg := if default_callback { 'p1' } else { 'p2' }
   handler_reg := if with_handler { if default_callback { 'p2' } else { 'p3' } } else { 'v1' }
   mut body := ''
   if !default_callback { body += 'invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\n' }
   if !with_handler { body += 'invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v0\nnew-instance v1, ${handler}\ninvoke-direct {v1, v0}, ${handler}-><init>(Landroid/os/Looper;)V\n' }
   if default_callback { body += 'const/4 v2, 0\n' }
   body += 'invoke-direct {p0, ${if default_callback { 'v2' } else { 'p1' }}, ${callback_reg}, ${handler_reg}}, ${cm}->vinixRegister(${request}${cb}${handler})V\nreturn-void'
   text += connectivity_method('public ${name}(${parameters}${if with_handler { handler } else { '' }})V', body)
   if !default_callback {
    text += connectivity_method('public requestNetwork(${parameters}${if with_handler { handler } else { '' }})V', 'invoke-virtual {p0, p1, p2${if with_handler { ', p3' } else { '' }}}, ${cm}->${name}(${parameters}${if with_handler { handler } else { '' }})V\nreturn-void')
   }
  }
 }
 os.write_file(smali + '/android/net/ConnectivityManager.smali', text)!
 text = '.class public ${cb}\n.super Ljava/lang/Object;\n'
 for parameters in ['', 'I', cm] { text += connectivity_method('public constructor <init>(${parameters})V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') }
 for signature in ['onAvailable(${network})V', 'onLost(${network})V', 'onUnavailable()V', 'onLosing(${network}I)V', 'onCapabilitiesChanged(${network}${caps})V', 'onLinkPropertiesChanged(${network}Landroid/net/LinkProperties;)V', 'onBlockedStatusChanged(${network}Z)V'] { text += connectivity_method('public ${signature}', 'return-void') }
 os.write_file(smali + '/android/net/ConnectivityManager$NetworkCallback.smali', text)!
 text = '.class public ${network}\n.super Ljava/lang/Object;\n.field public final vinixInterface:I\n'
 text += connectivity_method('public constructor <init>()V', 'const/4 v0, 0\ninvoke-direct {p0, v0}, ${network}-><init>(I)V\nreturn-void')
 text += connectivity_method('public constructor <init>(I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput p1, p0, ${network}->vinixInterface:I\nreturn-void')
 text += connectivity_method('public getNetworkHandle()J', 'iget v0, p0, ${network}->vinixInterface:I\nif-nez v0, :valid\nconst-wide/16 v0, 0\nreturn-wide v0\n:valid\nint-to-long v0, v0\nconst/16 v2, 32\nshl-long/2addr v0, v2\nconst-wide v2, 0xcafed00dL\nor-long/2addr v0, v2\nreturn-wide v0')
 text += connectivity_method('public hashCode()I', 'iget v0, p0, ${network}->vinixInterface:I\nreturn v0')
 text += connectivity_method('public equals(Ljava/lang/Object;)Z', 'instance-of v0, p1, ${network}\nif-eqz v0, :no\ncheck-cast p1, ${network}\niget v0, p0, ${network}->vinixInterface:I\niget v1, p1, ${network}->vinixInterface:I\nif-ne v0, v1, :no\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
 os.write_file(smali + '/android/net/Network.smali', text)!
 framework_network_updates(smali)!
 framework_link_properties(smali)!
 framework_network_info(smali)!
}

fn framework_network_updates(smali string) ! {
 cm := 'Landroid/net/ConnectivityManager;'
 cb := 'Landroid/net/ConnectivityManager$NetworkCallback;'
 task := 'Landroid/atl/VinixNetworkUpdate;'
 caps := 'Landroid/net/NetworkCapabilities;'
 network := 'Landroid/net/Network;'
 request := 'Landroid/net/NetworkRequest;'
 handler := 'Landroid/os/Handler;'
 mut text := '.class public final ${task}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n'
 for row in [['manager', cm], ['callback', cb], ['request', request], ['handler', handler], ['network', network], ['state', 'I'], ['active', 'Z']] { text += '.field private ${row[0]}:${row[1]}\n' }
 text += connectivity_method('public constructor <init>(${cm}${request}${cb}${handler})V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${task}->manager:${cm}\niput-object p3, p0, ${task}->callback:${cb}\niput-object p4, p0, ${task}->handler:${handler}\nconst/4 v0, 1\niput-boolean v0, p0, ${task}->active:Z\nif-eqz p2, :done\niget-object v0, p2, ${request}->vinixCapabilities:${caps}\nnew-instance v1, ${request}\ninvoke-direct {v1, v0}, ${request}-><init>(${caps})V\niput-object v1, p0, ${task}->request:${request}\n:done\nreturn-void')
 text += connectivity_method('public cancel()V', '
monitor-enter p0
:locked
const/4 v0, 0
iput-boolean v0, p0, ${task}->active:Z
iget-object v0, p0, ${task}->handler:${handler}
invoke-virtual {v0, p0}, ${handler}->removeCallbacks(Ljava/lang/Runnable;)V
:unlock
monitor-exit p0
return-void
.catchall {:locked .. :unlock} :error
:error
move-exception v0
monitor-exit p0
throw v0')
 // p0's monitor serializes cancellation against delivery. Reentrant unregister
 // from a callback suppresses the rest of that update and future polling.
 text += connectivity_method('public run()V', '
monitor-enter p0
:locked
iget-boolean v0, p0, ${task}->active:Z
if-eqz v0, :unlock
iget-object v0, p0, ${task}->manager:${cm}
invoke-virtual {v0}, ${cm}->nativeGetNetworkState()I
move-result v1
invoke-static {v1}, ${cm}->vinixCapabilities(I)${caps}
move-result-object v2
iget-object v0, p0, ${task}->request:${request}
if-eqz v0, :matched
invoke-virtual {v0, v2}, ${request}->canBeSatisfiedBy(${caps})Z
move-result v0
if-nez v0, :matched
const/4 v1, 0
:matched
iget v3, p0, ${task}->state:I
if-eq v1, v3, :schedule
iput v1, p0, ${task}->state:I
iget-object v4, p0, ${task}->callback:${cb}
ushr-int/lit8 v5, v1, 16
ushr-int/lit8 v6, v3, 16
if-eq v5, v6, :capabilities
if-eqz v3, :available
iget-object v0, p0, ${task}->network:${network}
invoke-virtual {v4, v0}, ${cb}->onLost(${network})V
iget-boolean v0, p0, ${task}->active:Z
if-eqz v0, :unlock
:available
if-eqz v1, :schedule
new-instance v0, ${network}
invoke-direct {v0, v5}, ${network}-><init>(I)V
iput-object v0, p0, ${task}->network:${network}
invoke-virtual {v4, v0}, ${cb}->onAvailable(${network})V
iget-boolean v0, p0, ${task}->active:Z
if-eqz v0, :unlock
:capabilities
if-eqz v1, :schedule
iget-object v0, p0, ${task}->network:${network}
invoke-virtual {v4, v0, v2}, ${cb}->onCapabilitiesChanged(${network}${caps})V
iget-boolean v2, p0, ${task}->active:Z
if-eqz v2, :unlock
invoke-static {v1}, ${cm}->vinixLinkProperties(I)Landroid/net/LinkProperties;
move-result-object v2
invoke-virtual {v4, v0, v2}, ${cb}->onLinkPropertiesChanged(${network}Landroid/net/LinkProperties;)V
iget-boolean v2, p0, ${task}->active:Z
if-eqz v2, :unlock
const/4 v2, 0
invoke-virtual {v4, v0, v2}, ${cb}->onBlockedStatusChanged(${network}Z)V
:schedule
iget-boolean v0, p0, ${task}->active:Z
if-eqz v0, :unlock
iget-object v0, p0, ${task}->handler:${handler}
const-wide/16 v1, 1000
invoke-virtual {v0, p0, v1, v2}, ${handler}->postDelayed(Ljava/lang/Runnable;J)Z
move-result v0
if-nez v0, :unlock
invoke-virtual {p0}, ${task}->cancel()V
iget-object v0, p0, ${task}->callback:${cb}
invoke-static {v0, p0}, ${cm}->vinixRemove(${cb}${task})V
:unlock
monitor-exit p0
return-void
.catchall {:locked .. :unlock} :error
:error
move-exception v7
const/4 v0, 0
iput-boolean v0, p0, ${task}->active:Z
iget-object v0, p0, ${task}->callback:${cb}
invoke-static {v0, p0}, ${cm}->vinixRemove(${cb}${task})V
monitor-exit p0
throw v7')
 // The poller invokes the protected native query through a public bridge.
 text = text.replace('->nativeGetNetworkState()I', '->vinixNetworkState()I')
 os.write_file(smali + '/android/atl/VinixNetworkUpdate.smali', text)!
 path := smali + '/android/net/ConnectivityManager.smali'
 os.write_file(path, os.read_file(path)! + connectivity_method('public vinixNetworkState()I', 'invoke-virtual {p0}, ${cm}->nativeGetNetworkState()I\nmove-result v0\nreturn v0'))!
}

fn framework_network_info(smali string) ! {
 info := 'Landroid/net/NetworkInfo;'
 path := smali + '/android/net/NetworkInfo.smali'
 mut text := os.read_file(path)! + '\n.field private vinixType:I\n'
 text = text.replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nconst/4 v0, -1\niput v0, p0, ${info}->vinixType:I')
 text += connectivity_method('public constructor <init>(I)V', 'const/4 v0, 1\ninvoke-direct {p0, v0}, ${info}-><init>(Z)V\nushr-int/lit8 v0, p1, 8\nand-int/lit16 v0, v0, 255\nconst/4 v1, -1\nconst/4 v2, 1\nif-ne v0, v2, :wifi\nconst/4 v1, 0\n:wifi\nconst/4 v2, 2\nif-ne v0, v2, :ethernet\nconst/4 v1, 1\n:ethernet\nconst/4 v2, 4\nif-ne v0, v2, :done\nconst/16 v1, 9\n:done\niput v1, p0, ${info}->vinixType:I\nreturn-void')
 text = framework_replace_method(text, 'getType()I', connectivity_method('public getType()I', 'iget v0, p0, ${info}->vinixType:I\nreturn v0'))!
 text = framework_replace_method(text, 'getTypeName()Ljava/lang/String;', connectivity_method('public getTypeName()Ljava/lang/String;', 'iget v0, p0, ${info}->vinixType:I\nconst/4 v1, 0\nif-eq v0, v1, :mobile\nconst/4 v1, 1\nif-eq v0, v1, :wifi\nconst/16 v1, 9\nif-eq v0, v1, :ethernet\nconst-string v0, "UNKNOWN"\nreturn-object v0\n:mobile\nconst-string v0, "MOBILE"\nreturn-object v0\n:wifi\nconst-string v0, "WIFI"\nreturn-object v0\n:ethernet\nconst-string v0, "ETHERNET"\nreturn-object v0'))!
 for signature in ['isAvailable()Z', 'isConnectedOrConnecting()Z'] { text = framework_replace_method(text, signature, connectivity_method('public ${signature}', 'invoke-virtual {p0}, ${info}->isConnected()Z\nmove-result v0\nreturn v0'))! }
 text = framework_replace_method(text, 'getDetailedState()Landroid/net/NetworkInfo$DetailedState;', connectivity_method('public getDetailedState()Landroid/net/NetworkInfo$DetailedState;', 'invoke-virtual {p0}, ${info}->isConnected()Z\nmove-result v0\nif-eqz v0, :offline\nsget-object v0, Landroid/net/NetworkInfo$DetailedState;->CONNECTED:Landroid/net/NetworkInfo$DetailedState;\nreturn-object v0\n:offline\nsget-object v0, Landroid/net/NetworkInfo$DetailedState;->DISCONNECTED:Landroid/net/NetworkInfo$DetailedState;\nreturn-object v0'))!
 os.write_file(path, text)!
}

fn framework_link_properties(smali string) ! {
 link := 'Landroid/net/LinkProperties;'
 mut text := '.class public ${link}\n.super Ljava/lang/Object;\n.field private name:Ljava/lang/String;\n.field private mtu:I\n.field private addresses:Ljava/util/List;\n'
 text += connectivity_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\niput-object v0, p0, ${link}->addresses:Ljava/util/List;\nreturn-void')
 text += connectivity_method('public constructor <init>(I)V', '
invoke-direct {p0}, ${link}-><init>()V
:start
invoke-static {p1}, Ljava/net/NetworkInterface;->getByIndex(I)Ljava/net/NetworkInterface;
move-result-object v0
if-eqz v0, :done
invoke-virtual {v0}, Ljava/net/NetworkInterface;->getName()Ljava/lang/String;
move-result-object v1
iput-object v1, p0, ${link}->name:Ljava/lang/String;
invoke-virtual {v0}, Ljava/net/NetworkInterface;->getMTU()I
move-result v1
iput v1, p0, ${link}->mtu:I
invoke-virtual {v0}, Ljava/net/NetworkInterface;->getInterfaceAddresses()Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v0
:loop
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Ljava/net/InterfaceAddress;
invoke-virtual {v1}, Ljava/net/InterfaceAddress;->getAddress()Ljava/net/InetAddress;
move-result-object v2
invoke-virtual {v1}, Ljava/net/InterfaceAddress;->getNetworkPrefixLength()S
move-result v1
new-instance v3, Landroid/net/LinkAddress;
invoke-direct {v3, v2, v1}, Landroid/net/LinkAddress;-><init>(Ljava/net/InetAddress;I)V
iget-object v1, p0, ${link}->addresses:Ljava/util/List;
invoke-interface {v1, v3}, Ljava/util/List;->add(Ljava/lang/Object;)Z
goto :loop
:done
return-void
.catch Ljava/net/SocketException; {:start .. :done} :error
:error
move-exception v0
return-void')
 text += connectivity_method('public getInterfaceName()Ljava/lang/String;', 'iget-object v0, p0, ${link}->name:Ljava/lang/String;\nreturn-object v0')
 text += connectivity_method('public getMtu()I', 'iget v0, p0, ${link}->mtu:I\nreturn v0')
 text += connectivity_method('public getLinkAddresses()Ljava/util/List;', 'iget-object v0, p0, ${link}->addresses:Ljava/util/List;\ninvoke-static {v0}, Ljava/util/Collections;->unmodifiableList(Ljava/util/List;)Ljava/util/List;\nmove-result-object v0\nreturn-object v0')
 os.write_file(smali + '/android/net/LinkProperties.smali', text)!
 text = '.class public final Landroid/net/LinkAddress;\n.super Ljava/lang/Object;\n.field private address:Ljava/net/InetAddress;\n.field private prefix:I\n'
 text += connectivity_method('public constructor <init>(Ljava/net/InetAddress;I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\ninvoke-virtual {p1}, Ljava/net/InetAddress;->getAddress()[B\nmove-result-object v0\narray-length v0, v0\nmul-int/lit8 v0, v0, 8\nif-ltz p2, :bad\nif-gt p2, v0, :bad\niput-object p1, p0, Landroid/net/LinkAddress;->address:Ljava/net/InetAddress;\niput p2, p0, Landroid/net/LinkAddress;->prefix:I\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/IllegalArgumentException;\ninvoke-direct {v0}, Ljava/lang/IllegalArgumentException;-><init>()V\nthrow v0')
 text += connectivity_method('public getAddress()Ljava/net/InetAddress;', 'iget-object v0, p0, Landroid/net/LinkAddress;->address:Ljava/net/InetAddress;\nreturn-object v0')
 text += connectivity_method('public getPrefixLength()I', 'iget v0, p0, Landroid/net/LinkAddress;->prefix:I\nreturn v0')
 os.write_file(smali + '/android/net/LinkAddress.smali', text)!
}
