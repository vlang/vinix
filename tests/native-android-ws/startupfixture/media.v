// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_media_probe(dir string) ! {
 os.write_file(dir + '/MediaProbe.smali', '.class public Lorg/vinix/bootstrap/MediaProbe;\n.super Landroid/media/MediaRouter$SimpleCallback;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/media/MediaRouter$SimpleCallback;-><init>()V\nreturn-void') +
  method('public onRouteUngrouped(Landroid/media/MediaRouter;Landroid/media/MediaRouter$RouteInfo;Landroid/media/MediaRouter$RouteGroup;)V', 'return-void') +
  method('public onRouteGrouped(Landroid/media/MediaRouter;Landroid/media/MediaRouter$RouteInfo;Landroid/media/MediaRouter$RouteGroup;I)V', 'return-void') +
  method('public onRouteAdded(Landroid/media/MediaRouter;Landroid/media/MediaRouter$RouteInfo;)V', 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "unexpected media device discovery"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0') +
  method('public static check(Landroid/content/Context;)V', '
const-string v0, "media_router"
const-class v0, Landroid/media/MediaRouter$VolumeCallback;
const-string v0, "media_router"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/media/MediaRouter;
if-eqz v0, :bad
invoke-virtual {v0}, Landroid/media/MediaRouter;->getDefaultRoute()Landroid/media/MediaRouter$RouteInfo;
move-result-object v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/media/MediaRouter;->getRouteCount()I
move-result v2
const/4 v3, 1
if-ne v2, v3, :bad
const/4 v2, 0
invoke-virtual {v0, v2}, Landroid/media/MediaRouter;->getRouteAt(I)Landroid/media/MediaRouter$RouteInfo;
move-result-object v3
if-ne v1, v3, :bad
const/4 v2, 3
invoke-virtual {v0, v2}, Landroid/media/MediaRouter;->getSelectedRoute(I)Landroid/media/MediaRouter$RouteInfo;
move-result-object v3
if-ne v1, v3, :bad
invoke-virtual {v1}, Landroid/media/MediaRouter$RouteInfo;->getPresentationDisplay()Landroid/view/Display;
move-result-object v3
if-nez v3, :bad
invoke-virtual {v1}, Landroid/media/MediaRouter$RouteInfo;->getSupportedTypes()I
move-result v3
if-nez v3, :bad
invoke-virtual {v1}, Landroid/media/MediaRouter$RouteInfo;->isEnabled()Z
move-result v3
if-nez v3, :bad
const/16 v3, 100
invoke-virtual {v1, v3}, Landroid/media/MediaRouter$RouteInfo;->requestSetVolume(I)V
invoke-virtual {v1}, Landroid/media/MediaRouter$RouteInfo;->getVolume()I
move-result v3
if-nez v3, :bad
invoke-virtual {v0, v2, v1}, Landroid/media/MediaRouter;->selectRoute(ILandroid/media/MediaRouter$RouteInfo;)V
const v2, 0x800000
invoke-virtual {v0, v2}, Landroid/media/MediaRouter;->getSelectedRoute(I)Landroid/media/MediaRouter$RouteInfo;
move-result-object v2
if-nez v2, :bad
new-instance v2, Landroid/media/MediaRouter;
invoke-direct {v2}, Landroid/media/MediaRouter;-><init>()V
invoke-virtual {v2}, Landroid/media/MediaRouter;->getDefaultRoute()Landroid/media/MediaRouter$RouteInfo;
move-result-object v3
if-ne v1, v3, :bad
invoke-virtual {v1, p0}, Landroid/media/MediaRouter$RouteInfo;->setTag(Ljava/lang/Object;)V
invoke-virtual {v3}, Landroid/media/MediaRouter$RouteInfo;->getTag()Ljava/lang/Object;
move-result-object v3
if-ne v3, p0, :bad
const/4 v3, 0
invoke-virtual {v1, v3}, Landroid/media/MediaRouter$RouteInfo;->setTag(Ljava/lang/Object;)V
new-instance v3, Lorg/vinix/bootstrap/MediaProbe;
invoke-direct {v3}, Lorg/vinix/bootstrap/MediaProbe;-><init>()V
const/4 v4, 1
invoke-virtual {v0, v4, v3}, Landroid/media/MediaRouter;->addCallback(ILandroid/media/MediaRouter$Callback;)V
const/4 v4, 2
const/4 v5, 3
invoke-virtual {v0, v4, v3, v5}, Landroid/media/MediaRouter;->addCallback(ILandroid/media/MediaRouter$Callback;I)V
invoke-virtual {v2, v3}, Landroid/media/MediaRouter;->removeCallback(Landroid/media/MediaRouter$Callback;)V
invoke-virtual {v0, v3}, Landroid/media/MediaRouter;->removeCallback(Landroid/media/MediaRouter$Callback;)V
const/4 v2, 1
:bounds
invoke-virtual {v0, v2}, Landroid/media/MediaRouter;->getRouteAt(I)Landroid/media/MediaRouter$RouteInfo;
:bounds_end
.catch Ljava/lang/IndexOutOfBoundsException; {:bounds .. :bounds_end} :bounds_ok
goto :bad
:bounds_ok
move-exception v2
const/4 v2, -1
:negative
invoke-virtual {v0, v2}, Landroid/media/MediaRouter;->getRouteAt(I)Landroid/media/MediaRouter$RouteInfo;
:negative_end
.catch Ljava/lang/IndexOutOfBoundsException; {:negative .. :negative_end} :negative_ok
goto :bad
:negative_ok
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-MEDIA-PASS shared-default absent-output no-presentation callbacks bounds"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "media route availability"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
