// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn network_request_method(signature string, body string) string {
 return '.method public ' + signature + '\n.locals 6\n' + body + '\n.end method\n'
}

// Request filters describe requirements, not observed connectivity. In
// particular an INTERNET request does not establish a validated Internet link.
fn framework_network_requests(smali string) ! {
 caps := 'Landroid/net/NetworkCapabilities;'
 request := 'Landroid/net/NetworkRequest;'
 builder := 'Landroid/net/NetworkRequest$Builder;'
 bits := 'Ljava/util/BitSet;'
 mut text := '.class public final ${caps}\n.super Ljava/lang/Object;\n'
 for field in ['Capabilities', 'TransportTypes'] { text += '.field public vinix${field}:${bits}\n' }
 mut initialize := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
 for field in ['Capabilities', 'TransportTypes'] {
  initialize += 'new-instance v0, ${bits}\ninvoke-direct {v0}, ${bits}-><init>()V\niput-object v0, p0, ${caps}->vinix${field}:${bits}\n'
 }
 // Baseline Android request defaults: unrestricted, trusted, not a VPN.
 initialize += 'iget-object v0, p0, ${caps}->vinixCapabilities:${bits}\n'
 for value in [13, 14, 15] { initialize += 'const/16 v1, ${value}\ninvoke-virtual {v0, v1}, ${bits}->set(I)V\n' }
 text += network_request_method('constructor <init>()V', initialize + 'return-void')
 mut copy := 'invoke-direct {p0}, ${caps}-><init>()V\ninvoke-virtual {p0}, ${caps}->vinixClear()V\nif-eqz p1, :done\n'
 for field in ['Capabilities', 'TransportTypes'] {
  copy += 'iget-object v0, p1, ${caps}->vinix${field}:${bits}\ninvoke-virtual {v0}, ${bits}->clone()Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ${bits}\niput-object v0, p0, ${caps}->vinix${field}:${bits}\n'
 }
 text += network_request_method('constructor <init>(${caps})V', copy + ':done\nreturn-void')
 mut clear := ''
 for field in ['Capabilities', 'TransportTypes'] {
  clear += 'iget-object v0, p0, ${caps}->vinix${field}:${bits}\ninvoke-virtual {v0}, ${bits}->clear()V\n'
 }
 text += network_request_method('vinixClear()V', clear + 'return-void')
 for row in [['Capabilities', 'Capability', '38'], ['TransportTypes', 'TransportType', '10']] {
  field, singular, limit := row[0], row[1], row[2]
  test := if singular == 'Capability' { 'hasCapability' } else { 'hasTransport' }
  valid := 'if-ltz p1, :invalid\nconst/16 v1, ${limit}\nif-gt p1, v1, :invalid\n'
  text += network_request_method('${test}(I)Z', valid + 'iget-object v0, p0, ${caps}->vinix${field}:${bits}\ninvoke-virtual {v0, p1}, ${bits}->get(I)Z\nmove-result v0\nreturn v0\n:invalid\nconst/4 v0, 0\nreturn v0')
  for verb in ['add', 'remove'] {
   operation := if verb == 'add' { 'set' } else { 'clear' }
   text += network_request_method('${verb}${singular}(I)${caps}', valid + 'iget-object v0, p0, ${caps}->vinix${field}:${bits}\ninvoke-virtual {v0, p1}, ${bits}->${operation}(I)V\nreturn-object p0\n:invalid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "Invalid network filter"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0')
  }
  text += network_request_method('get${field}()[I', 'iget-object v0, p0, ${caps}->vinix${field}:${bits}\ninvoke-virtual {v0}, ${bits}->cardinality()I\nmove-result v1\nnew-array v1, v1, [I\nconst/4 v2, 0\nconst/4 v3, 0\n:loop\ninvoke-virtual {v0, v3}, ${bits}->nextSetBit(I)I\nmove-result v3\nif-ltz v3, :done\naput v3, v1, v2\nadd-int/lit8 v2, v2, 1\nadd-int/lit8 v3, v3, 1\ngoto :loop\n:done\nreturn-object v1')
 }
 text += network_request_method('vinixSatisfiedBy(${caps})Z', '
if-eqz p1, :no
iget-object v0, p0, ${caps}->vinixCapabilities:${bits}
invoke-virtual {v0}, ${bits}->clone()Ljava/lang/Object;
move-result-object v0
check-cast v0, ${bits}
iget-object v1, p1, ${caps}->vinixCapabilities:${bits}
invoke-virtual {v0, v1}, ${bits}->andNot(${bits})V
invoke-virtual {v0}, ${bits}->isEmpty()Z
move-result v0
if-eqz v0, :no
iget-object v0, p0, ${caps}->vinixTransportTypes:${bits}
invoke-virtual {v0}, ${bits}->isEmpty()Z
move-result v1
if-nez v1, :yes
iget-object v1, p1, ${caps}->vinixTransportTypes:${bits}
invoke-virtual {v0, v1}, ${bits}->intersects(${bits})Z
move-result v0
return v0
:yes
const/4 v0, 1
return v0
:no
const/4 v0, 0
return v0')
 for direction in ['Downstream', 'Upstream'] {
  text += network_request_method('getLink${direction}BandwidthKbps()I', 'const/4 v0, 0\nreturn v0')
 }
 text += network_request_method('getNetworkSpecifier()Landroid/net/NetworkSpecifier;', 'const/4 v0, 0\nreturn-object v0')
 os.write_file(smali + '/android/net/NetworkCapabilities.smali', text)!
 text = '.class public final ${request}\n.super Ljava/lang/Object;\n.field public vinixCapabilities:${caps}\n'
 text += network_request_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, ${caps}\ninvoke-direct {v0}, ${caps}-><init>()V\niput-object v0, p0, ${request}->vinixCapabilities:${caps}\nreturn-void')
 text += network_request_method('constructor <init>(${caps})V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, ${caps}\ninvoke-direct {v0, p1}, ${caps}-><init>(${caps})V\niput-object v0, p0, ${request}->vinixCapabilities:${caps}\nreturn-void')
 for signature in ['hasCapability(I)Z', 'hasTransport(I)Z', 'getCapabilities()[I', 'getTransportTypes()[I', 'getNetworkSpecifier()Landroid/net/NetworkSpecifier;', 'canBeSatisfiedBy(${caps})Z'] {
  target := signature.replace('canBeSatisfiedBy', 'vinixSatisfiedBy')
  parameter := if signature.contains('()') { '' } else { ', p1' }
  object := !signature.ends_with('Z')
  suffix := if object { '-object' } else { '' }
  text += network_request_method(signature, 'iget-object v0, p0, ${request}->vinixCapabilities:${caps}\ninvoke-virtual {v0${parameter}}, ${caps}->${target}\nmove-result${suffix} v0\nreturn${suffix} v0')
 }
 os.write_file(smali + '/android/net/NetworkRequest.smali', text)!
 text = '.class public ${builder}\n.super Ljava/lang/Object;\n.field private capabilities:${caps}\n'
 text += network_request_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, ${caps}\ninvoke-direct {v0}, ${caps}-><init>()V\niput-object v0, p0, ${builder}->capabilities:${caps}\nreturn-void')
 text += network_request_method('constructor <init>(${request})V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niget-object v0, p1, ${request}->vinixCapabilities:${caps}\nnew-instance v1, ${caps}\ninvoke-direct {v1, v0}, ${caps}-><init>(${caps})V\niput-object v1, p0, ${builder}->capabilities:${caps}\nreturn-void')
 for option in ['Capability', 'TransportType'] {
  for verb in ['add', 'remove'] {
   text += network_request_method('${verb}${option}(I)${builder}', 'iget-object v0, p0, ${builder}->capabilities:${caps}\ninvoke-virtual {v0, p1}, ${caps}->${verb}${option}(I)${caps}\nreturn-object p0')
  }
 }
 text += network_request_method('clearCapabilities()${builder}', 'iget-object v0, p0, ${builder}->capabilities:${caps}\ninvoke-virtual {v0}, ${caps}->vinixClear()V\nreturn-object p0')
 text += network_request_method('build()${request}', 'iget-object v0, p0, ${builder}->capabilities:${caps}\nnew-instance v1, ${request}\ninvoke-direct {v1, v0}, ${request}-><init>(${caps})V\nreturn-object v1')
 os.write_file(smali + '/android/net/NetworkRequest$Builder.smali', text)!
 os.write_file(smali + '/android/net/NetworkSpecifier.smali', '.class public abstract Landroid/net/NetworkSpecifier;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' + network_request_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void'))!
}
