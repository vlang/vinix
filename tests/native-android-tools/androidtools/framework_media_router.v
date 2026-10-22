// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn media_method(signature string, body string) string {
 return '.method public ' + signature + '\n.locals 4\n' + body + '\n.end method\n'
}

// WS currently has no media output or remote display provider. Expose the
// required default route, but advertise no playable types or presentation
// display. Registering discovery callbacks must not manufacture devices.
fn framework_media_router(smali string) ! {
 router := 'Landroid/media/MediaRouter;'
 route := 'Landroid/media/MediaRouter$RouteInfo;'
 callback := 'Landroid/media/MediaRouter$Callback;'
 mut text := '.class public ' + router + '\n.super Ljava/lang/Object;\n' +
  '.field static defaultRoute:' + route + '\n' +
  '.field private static callbacks:Ljava/util/IdentityHashMap;\n'
 for name, value in {'ROUTE_TYPE_LIVE_AUDIO': 1, 'ROUTE_TYPE_LIVE_VIDEO': 2,
  'ROUTE_TYPE_USER': 8388608, 'CALLBACK_FLAG_PERFORM_ACTIVE_SCAN': 1,
  'CALLBACK_FLAG_UNFILTERED_EVENTS': 2, 'CALLBACK_FLAG_REQUEST_DISCOVERY': 4,
  'CALLBACK_FLAG_PASSIVE_DISCOVERY': 8} {
  text += '.field public static final ' + name + ':I = ' + value.str() + '\n'
 }
 text += '.method static constructor <clinit>()V\n.locals 1\nnew-instance v0, ' + route + '\n' +
  'invoke-direct {v0}, ' + route + '-><init>()V\nsput-object v0, ' + router + '->defaultRoute:' + route + '\n' +
  'new-instance v0, Ljava/util/IdentityHashMap;\ninvoke-direct {v0}, Ljava/util/IdentityHashMap;-><init>()V\n' +
  'sput-object v0, ' + router + '->callbacks:Ljava/util/IdentityHashMap;\nreturn-void\n.end method\n'
 text += media_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 for signature in ['getDefaultRoute()' + route, 'getSelectedRoute()' + route] {
  text += media_method(signature, 'sget-object v0, ' + router + '->defaultRoute:' + route + '\nreturn-object v0')
 }
 text += media_method('getSelectedRoute(I)' + route, 'const v0, 0x800000\nif-eq p1, v0, :user\n' +
  'sget-object v0, ' + router + '->defaultRoute:' + route + '\nreturn-object v0\n:user\nconst/4 v0, 0\nreturn-object v0')
 text += media_method('getRouteCount()I', 'const/4 v0, 1\nreturn v0')
 text += media_method('createRouteCategory(Ljava/lang/CharSequence;Z)Landroid/media/MediaRouter$RouteCategory;',
  'new-instance v0, Landroid/media/MediaRouter$RouteCategory;\n' +
  'invoke-direct {v0, p1, p2}, Landroid/media/MediaRouter$RouteCategory;-><init>(Ljava/lang/CharSequence;Z)V\nreturn-object v0')
 text += media_method('getRouteAt(I)' + route, 'if-nez p1, :bad\nsget-object v0, ' + router + '->defaultRoute:' + route + '\n' +
  'return-object v0\n:bad\nnew-instance v0, Ljava/lang/IndexOutOfBoundsException;\n' +
  'invoke-direct {v0}, Ljava/lang/IndexOutOfBoundsException;-><init>()V\nthrow v0')
 // Registration is shared between Context service instances, just like routes.
 // Retain the union of types and flags when a callback is registered again.
 text += media_method('addCallback(I' + callback + ')V', 'const/4 v0, 0\ninvoke-virtual {p0, p1, p2, v0}, ' +
  router + '->addCallback(I' + callback + 'I)V\nreturn-void')
 text += media_method('addCallback(I' + callback + 'I)V',
  'sget-object v0, ' + router + '->callbacks:Ljava/util/IdentityHashMap;\n' +
  'invoke-virtual {v0, p2}, Ljava/util/IdentityHashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;\n' +
  'move-result-object v1\ncheck-cast v1, [I\nif-nez v1, :merge\nconst/4 v1, 2\nnew-array v1, v1, [I\n' +
  'invoke-virtual {v0, p2, v1}, Ljava/util/IdentityHashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\n' +
  ':merge\nconst/4 v0, 0\naget v2, v1, v0\nor-int/2addr v2, p1\naput v2, v1, v0\n' +
  'const/4 v0, 1\naget v2, v1, v0\nor-int/2addr v2, p3\naput v2, v1, v0\nreturn-void')
 text += media_method('removeCallback(' + callback + ')V', 'sget-object v0, ' + router + '->callbacks:Ljava/util/IdentityHashMap;\n' +
  'invoke-virtual {v0, p1}, Ljava/util/IdentityHashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;\nreturn-void')
 // There is no selectable remote route. Selecting the already selected default
 // is idempotent; never report that an unknown route became active.
 text += media_method('selectRoute(I' + route + ')V', 'sget-object v0, ' + router + '->defaultRoute:' + route + '\n' +
  'if-eq p2, v0, :done\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "route is not registered"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:done\nreturn-void')
 os.write_file(smali + '/android/media/MediaRouter.smali', text)!

 mut info := '.class public ' + route + '\n.super Ljava/lang/Object;\n.field private tag:Ljava/lang/Object;\n' +
  media_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 for signature in ['getDescription()Ljava/lang/CharSequence;', 'getPresentationDisplay()Landroid/view/Display;',
  'getStatus()Ljava/lang/CharSequence;', 'getIconDrawable()Landroid/graphics/drawable/Drawable;'] {
  info += media_method(signature, 'const/4 v0, 0\nreturn-object v0')
 }
 for signature in ['getName()Ljava/lang/CharSequence;', 'getName(Landroid/content/Context;)Ljava/lang/CharSequence;'] {
  info += media_method(signature, 'const-string v0, "Vinix (media output unavailable)"\nreturn-object v0')
 }
 for signature in ['getDeviceType()I', 'getPlaybackType()I', 'getSupportedTypes()I', 'getVolume()I',
  'getVolumeMax()I', 'getVolumeHandling()I', 'isConnecting()Z', 'isEnabled()Z', 'matchesTypes(I)Z'] {
  info += media_method(signature, 'const/4 v0, 0\nreturn v0')
 }
 info += media_method('getPlaybackStream()I', 'const/4 v0, 3\nreturn v0')
 for signature in ['isSelected()Z', 'isDefault()Z'] {
  info += media_method(signature, 'sget-object v0, ' + router + '->defaultRoute:' + route + '\n' +
   'if-eq p0, v0, :yes\nconst/4 v0, 0\nreturn v0\n:yes\nconst/4 v0, 1\nreturn v0')
 }
 info += media_method('getTag()Ljava/lang/Object;', 'iget-object v0, p0, ' + route + '->tag:Ljava/lang/Object;\nreturn-object v0')
 info += media_method('setTag(Ljava/lang/Object;)V', 'iput-object p1, p0, ' + route + '->tag:Ljava/lang/Object;\nreturn-void')
 for signature in ['requestSetVolume(I)V', 'requestUpdateVolume(I)V'] {
  info += media_method(signature, 'return-void')
 }
 os.write_file(smali + '/android/media/MediaRouter$RouteInfo.smali', info)!

 mut cb := '.class public abstract ' + callback + '\n.super Ljava/lang/Object;\n' +
  media_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 mut simple := '.class public Landroid/media/MediaRouter$SimpleCallback;\n.super ' + callback + '\n' +
  media_method('constructor <init>()V', 'invoke-direct {p0}, ' + callback + '-><init>()V\nreturn-void')
 for signature in ['onRouteSelected(' + router + 'I' + route + ')V', 'onRouteUnselected(' + router + 'I' + route + ')V',
  'onRouteAdded(' + router + route + ')V', 'onRouteRemoved(' + router + route + ')V',
  'onRouteChanged(' + router + route + ')V', 'onRouteVolumeChanged(' + router + route + ')V',
  'onRouteGrouped(' + router + route + 'Landroid/media/MediaRouter$RouteGroup;I)V',
  'onRouteUngrouped(' + router + route + 'Landroid/media/MediaRouter$RouteGroup;)V'] {
  cb += '.method public abstract ' + signature + '\n.end method\n'
  simple += media_method(signature, 'return-void')
 }
 cb += media_method('onRoutePresentationDisplayChanged(' + router + route + ')V', 'return-void')
 os.write_file(smali + '/android/media/MediaRouter$Callback.smali', cb)!
 os.write_file(smali + '/android/media/MediaRouter$SimpleCallback.smali', simple)!
 // Callback overrides resolve their argument types when ART links subclasses.
 // No group instances are created by the provider, but the public signature's
 // type must exist even when the device has no grouped routes.
 os.write_file(smali + '/android/media/MediaRouter$RouteGroup.smali',
  '.class public Landroid/media/MediaRouter$RouteGroup;\n.super ' + route + '\n' +
  media_method('getRouteCount()I', 'const/4 v0, 0\nreturn v0') +
  media_method('getRouteAt(I)' + route, 'new-instance v0, Ljava/lang/IndexOutOfBoundsException;\n' +
   'invoke-direct {v0}, Ljava/lang/IndexOutOfBoundsException;-><init>()V\nthrow v0'))!
 os.write_file(smali + '/android/media/MediaRouter$VolumeCallback.smali',
  '.class public abstract Landroid/media/MediaRouter$VolumeCallback;\n.super Ljava/lang/Object;\n' +
  media_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
  '.method public abstract onVolumeSetRequest(' + route + 'I)V\n.end method\n' +
  '.method public abstract onVolumeUpdateRequest(' + route + 'I)V\n.end method\n')!
 category := 'Landroid/media/MediaRouter$RouteCategory;'
 mut category_text := '.class public ' + category + '\n.super Ljava/lang/Object;\n' +
  '.field private name:Ljava/lang/CharSequence;\n.field private groupable:Z\n' +
  media_method('constructor <init>(Ljava/lang/CharSequence;Z)V',
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + category + '->name:Ljava/lang/CharSequence;\n' +
   'iput-boolean p2, p0, ' + category + '->groupable:Z\nreturn-void')
 for signature in ['getName()Ljava/lang/CharSequence;', 'getName(Landroid/content/Context;)Ljava/lang/CharSequence;'] {
  category_text += media_method(signature, 'iget-object v0, p0, ' + category + '->name:Ljava/lang/CharSequence;\nreturn-object v0')
 }
 category_text += media_method('isGroupable()Z', 'iget-boolean v0, p0, ' + category + '->groupable:Z\nreturn v0')
 category_text += media_method('getSupportedTypes()I', 'const v0, 0x800000\nreturn v0')
 // Categories describe app routes, not discovered hardware. Creating one does
 // not register it or a route. This provider currently has no app-route API.
 category_text += media_method('getRoutes(Ljava/util/List;)Ljava/util/List;',
  'if-nez p1, :clear\nnew-instance p1, Ljava/util/ArrayList;\ninvoke-direct {p1}, Ljava/util/ArrayList;-><init>()V\n' +
  ':clear\ninvoke-interface {p1}, Ljava/util/List;->clear()V\nreturn-object p1')
 os.write_file(smali + '/android/media/MediaRouter$RouteCategory.smali', category_text)!
}
