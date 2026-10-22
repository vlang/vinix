// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn channel_method(signature string, body string) string {
 if signature.contains('static synchronized ') {
  locked := body.replace('return-void', 'monitor-exit v6\nreturn-void').replace('return-object ', 'monitor-exit v6\nreturn-object ')
  return '.method public ' + signature.replace('synchronized ', '') + '\n.locals 7\nconst-class v6, Landroid/app/VinixNotificationChannels;\nmonitor-enter v6\n:registry_start\n' + locked + '\n:registry_end\n.catchall {:registry_start .. :registry_end} :registry_error\n:registry_error\nmove-exception v5\nmonitor-exit v6\nthrow v5\n.end method\n'
 }
 return '.method public ' + signature + '\n.locals 6\n' + body + '\n.end method\n'
}

fn channel_property(class string, field string, kind string, getter string, setter string) string {
 object := kind.starts_with('L') || kind.starts_with('[')
 suffix := if object { '-object' } else { if kind == 'Z' { '-boolean' } else { '' } }
 ret := if object { '-object' } else { '' }
 mut text := '.field public vinix${field}:${kind}\n'
 if getter != '' { text += channel_method('${getter}()${kind}', 'iget${suffix} v0, p0, ${class}->vinix${field}:${kind}\nreturn${ret} v0') }
 if setter != '' { text += channel_method('${setter}(${kind})V', 'iput${suffix} p1, p0, ${class}->vinix${field}:${kind}\nreturn-void') }
 return text
}

// The APK process owns this metadata registry. It does not claim to provide an
// Android notification settings service or persist user policy across launches.
fn framework_notification_channels(smali string) ! {
 channel := 'Landroid/app/NotificationChannel;'
 group := 'Landroid/app/NotificationChannelGroup;'
 store := 'Landroid/app/VinixNotificationChannels;'
 mut text := '.class public ${channel}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Cloneable;\n'
 for row in [
  ['Id', 'Ljava/lang/String;', 'getId', ''], ['Name', 'Ljava/lang/CharSequence;', 'getName', 'setName'],
  ['Importance', 'I', 'getImportance', 'setImportance'], ['Description', 'Ljava/lang/String;', 'getDescription', 'setDescription'],
  ['Group', 'Ljava/lang/String;', 'getGroup', 'setGroup'], ['Lights', 'Z', 'shouldShowLights', 'enableLights'],
  ['Vibration', 'Z', 'shouldVibrate', 'enableVibration'], ['LightColor', 'I', 'getLightColor', 'setLightColor'],
  ['BypassDnd', 'Z', 'canBypassDnd', 'setBypassDnd'], ['Visibility', 'I', 'getLockscreenVisibility', 'setLockscreenVisibility'],
  ['Badge', 'Z', 'canShowBadge', 'setShowBadge'], ['Sound', 'Landroid/net/Uri;', 'getSound', ''],
  ['Audio', 'Landroid/media/AudioAttributes;', 'getAudioAttributes', ''],
 ] { text += channel_property(channel, row[0], row[1], row[2], row[3]) }
 text += '.field public vinixPattern:[J\n'
 text += channel_method('constructor <init>(Ljava/lang/String;Ljava/lang/CharSequence;I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'iput-object p1, p0, ${channel}->vinixId:Ljava/lang/String;\niput-object p2, p0, ${channel}->vinixName:Ljava/lang/CharSequence;\niput p3, p0, ${channel}->vinixImportance:I\nconst/4 v0, 1\niput-boolean v0, p0, ${channel}->vinixBadge:Z\nconst/16 v0, -1000\niput v0, p0, ${channel}->vinixVisibility:I\nreturn-void')
 text += channel_method('setSound(Landroid/net/Uri;Landroid/media/AudioAttributes;)V', 'iput-object p1, p0, ${channel}->vinixSound:Landroid/net/Uri;\niput-object p2, p0, ${channel}->vinixAudio:Landroid/media/AudioAttributes;\nreturn-void')
 text += channel_method('setVibrationPattern([J)V', 'const/4 v0, 0\nif-eqz p1, :done\narray-length v0, p1\nif-eqz v0, :copy\nconst/4 v0, 1\n:copy\ninvoke-virtual {p1}, [J->clone()Ljava/lang/Object;\nmove-result-object p1\ncheck-cast p1, [J\n:done\niput-object p1, p0, ${channel}->vinixPattern:[J\niput-boolean v0, p0, ${channel}->vinixVibration:Z\nreturn-void')
 text += channel_method('getVibrationPattern()[J', 'iget-object v0, p0, ${channel}->vinixPattern:[J\nif-eqz v0, :done\ninvoke-virtual {v0}, [J->clone()Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, [J\n:done\nreturn-object v0')
 text += channel_method('vinixCopy()${channel}', 'invoke-super {p0}, Ljava/lang/Object;->clone()Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ${channel}\ninvoke-virtual {p0}, ${channel}->getVibrationPattern()[J\nmove-result-object v1\niput-object v1, v0, ${channel}->vinixPattern:[J\niget-object v1, p0, ${channel}->vinixName:Ljava/lang/CharSequence;\nif-eqz v1, :done\ninvoke-interface {v1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v1\niput-object v1, v0, ${channel}->vinixName:Ljava/lang/CharSequence;\n:done\nreturn-object v0')
 os.write_file(smali + '/android/app/NotificationChannel.smali', text)!
 text = '.class public ${group}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Cloneable;\n'
 for row in [['Id', 'Ljava/lang/String;', 'getId', ''], ['Name', 'Ljava/lang/CharSequence;', 'getName', ''], ['Description', 'Ljava/lang/String;', 'getDescription', 'setDescription']] {
  text += channel_property(group, row[0], row[1], row[2], row[3])
 }
 text += '.field public vinixChannels:Ljava/util/List;\n'
 text += channel_method('constructor <init>(Ljava/lang/String;Ljava/lang/CharSequence;)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${group}->vinixId:Ljava/lang/String;\niput-object p2, p0, ${group}->vinixName:Ljava/lang/CharSequence;\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\niput-object v0, p0, ${group}->vinixChannels:Ljava/util/List;\nreturn-void')
 text += channel_method('isBlocked()Z', 'const/4 v0, 0\nreturn v0')
 text += channel_method('getChannels()Ljava/util/List;', 'iget-object v0, p0, ${group}->vinixChannels:Ljava/util/List;\nreturn-object v0')
 text += channel_method('vinixCopy()${group}', 'iget-object v1, p0, ${group}->vinixId:Ljava/lang/String;\niget-object v2, p0, ${group}->vinixName:Ljava/lang/CharSequence;\nif-eqz v2, :name\ninvoke-interface {v2}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v2\n:name\nnew-instance v0, ${group}\ninvoke-direct {v0, v1, v2}, ${group}-><init>(Ljava/lang/String;Ljava/lang/CharSequence;)V\niget-object v1, p0, ${group}->vinixDescription:Ljava/lang/String;\niput-object v1, v0, ${group}->vinixDescription:Ljava/lang/String;\nreturn-object v0')
 os.write_file(smali + '/android/app/NotificationChannelGroup.smali', text)!
 text = '.class public final ${store}\n.super Ljava/lang/Object;\n.field private static channels:Ljava/util/LinkedHashMap;\n.field private static groups:Ljava/util/LinkedHashMap;\n.field private static deleted:Ljava/util/HashSet;\n.method static constructor <clinit>()V\n.locals 1\n'
 for field in ['channels', 'groups', 'deleted'] {
  kind := if field == 'deleted' { 'HashSet' } else { 'LinkedHashMap' }
  text += 'new-instance v0, Ljava/util/${kind};\ninvoke-direct {v0}, Ljava/util/${kind};-><init>()V\nsput-object v0, ${store}->${field}:Ljava/util/${kind};\n'
 }
 text += 'return-void\n.end method\n'
 text += channel_method('static synchronized putChannel(${channel})V', '
invoke-virtual {p0}, ${channel}->getId()Ljava/lang/String;
move-result-object v0
invoke-virtual {p0}, ${channel}->getImportance()I
move-result v1
if-eqz v0, :bad
invoke-virtual {v0}, Ljava/lang/String;->length()I
move-result v2
if-eqz v2, :bad
if-ltz v1, :bad
const/4 v2, 5
if-gt v1, v2, :bad
invoke-virtual {p0}, ${channel}->getGroup()Ljava/lang/String;
move-result-object v2
if-eqz v2, :group
sget-object v3, ${store}->groups:Ljava/util/LinkedHashMap;
invoke-virtual {v3, v2}, Ljava/util/LinkedHashMap;->containsKey(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
:group
sget-object v3, ${store}->channels:Ljava/util/LinkedHashMap;
invoke-virtual {v3, v0}, Ljava/util/LinkedHashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v4
check-cast v4, ${channel}
if-nez v4, :update
invoke-virtual {p0}, ${channel}->vinixCopy()${channel}
move-result-object v4
goto :save
:update
invoke-virtual {v4}, ${channel}->getImportance()I
move-result v5
if-ge v1, v5, :importance
invoke-virtual {v4, v1}, ${channel}->setImportance(I)V
:importance
invoke-virtual {v4}, ${channel}->getGroup()Ljava/lang/String;
move-result-object v1
if-nez v1, :name
invoke-virtual {v4, v2}, ${channel}->setGroup(Ljava/lang/String;)V
:name
invoke-virtual {p0}, ${channel}->getName()Ljava/lang/CharSequence;
move-result-object v1
if-eqz v1, :description
invoke-interface {v1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;
move-result-object v1
:description
invoke-virtual {v4, v1}, ${channel}->setName(Ljava/lang/CharSequence;)V
invoke-virtual {p0}, ${channel}->getDescription()Ljava/lang/String;
move-result-object v1
invoke-virtual {v4, v1}, ${channel}->setDescription(Ljava/lang/String;)V
:save
invoke-virtual {v3, v0, v4}, Ljava/util/LinkedHashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
sget-object v1, ${store}->deleted:Ljava/util/HashSet;
invoke-virtual {v1, v0}, Ljava/util/HashSet;->remove(Ljava/lang/Object;)Z
return-void
:bad
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Invalid notification channel or missing group"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0')
 text += channel_method('static synchronized getChannel(Ljava/lang/String;)${channel}', 'sget-object v0, ${store}->deleted:Ljava/util/HashSet;\ninvoke-virtual {v0, p0}, Ljava/util/HashSet;->contains(Ljava/lang/Object;)Z\nmove-result v0\nif-nez v0, :missing\nsget-object v0, ${store}->channels:Ljava/util/LinkedHashMap;\ninvoke-virtual {v0, p0}, Ljava/util/LinkedHashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ${channel}\nif-eqz v0, :done\ninvoke-virtual {v0}, ${channel}->vinixCopy()${channel}\nmove-result-object v0\n:done\nreturn-object v0\n:missing\nconst/4 v0, 0\nreturn-object v0')
 text += channel_method('static synchronized deleteChannel(Ljava/lang/String;)V', 'sget-object v0, ${store}->deleted:Ljava/util/HashSet;\ninvoke-virtual {v0, p0}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z\nreturn-void')
 text += channel_method('static synchronized putGroup(${group})V', 'invoke-virtual {p0}, ${group}->getId()Ljava/lang/String;\nmove-result-object v0\nif-eqz v0, :bad\ninvoke-virtual {v0}, Ljava/lang/String;->length()I\nmove-result v1\nif-eqz v1, :bad\ninvoke-virtual {p0}, ${group}->vinixCopy()${group}\nmove-result-object v1\nsget-object v2, ${store}->groups:Ljava/util/LinkedHashMap;\ninvoke-virtual {v2, v0, v1}, Ljava/util/LinkedHashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/IllegalArgumentException;\ninvoke-direct {v0}, Ljava/lang/IllegalArgumentException;-><init>()V\nthrow v0')
 text += channel_method('static synchronized getGroup(Ljava/lang/String;)${group}', '
sget-object v0, ${store}->groups:Ljava/util/LinkedHashMap;
invoke-virtual {v0, p0}, Ljava/util/LinkedHashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, ${group}
if-eqz v0, :done
invoke-virtual {v0}, ${group}->vinixCopy()${group}
move-result-object v0
invoke-static {}, ${store}->getChannels()Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v1
:loop
invoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z
move-result v2
if-eqz v2, :done
invoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, ${channel}
invoke-virtual {v2}, ${channel}->getGroup()Ljava/lang/String;
move-result-object v3
invoke-virtual {p0, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :loop
iget-object v3, v0, ${group}->vinixChannels:Ljava/util/List;
invoke-interface {v3, v2}, Ljava/util/List;->add(Ljava/lang/Object;)Z
goto :loop
:done
return-object v0')
 text += channel_method('static synchronized deleteGroup(Ljava/lang/String;)V', 'sget-object v0, ${store}->groups:Ljava/util/LinkedHashMap;\ninvoke-virtual {v0, p0}, Ljava/util/LinkedHashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;\ninvoke-static {p0}, ${store}->getChannels()Ljava/util/List;\nmove-result-object v0\ninvoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;\nmove-result-object v0\n:loop\ninvoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z\nmove-result v1\nif-eqz v1, :done\ninvoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;\nmove-result-object v1\ncheck-cast v1, ${channel}\ninvoke-virtual {v1}, ${channel}->getGroup()Ljava/lang/String;\nmove-result-object v2\ninvoke-virtual {p0, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v2\nif-eqz v2, :loop\ninvoke-virtual {v1}, ${channel}->getId()Ljava/lang/String;\nmove-result-object v1\ninvoke-static {v1}, ${store}->deleteChannel(Ljava/lang/String;)V\ngoto :loop\n:done\nreturn-void'.replace('invoke-static {p0}, ${store}->getChannels()', 'invoke-static {}, ${store}->getChannels()'))
 for name in ['Channel', 'Group'] {
  plural := if name == 'Channel' { 'channels' } else { 'groups' }
  result := if name == 'Channel' { channel } else { group }
  text += channel_method('static synchronized get${name}s()Ljava/util/List;', 'new-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\nsget-object v1, ${store}->${plural}:Ljava/util/LinkedHashMap;\ninvoke-virtual {v1}, Ljava/util/LinkedHashMap;->keySet()Ljava/util/Set;\nmove-result-object v1\ninvoke-interface {v1}, Ljava/util/Set;->iterator()Ljava/util/Iterator;\nmove-result-object v1\n:loop\ninvoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z\nmove-result v2\nif-eqz v2, :done\ninvoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;\nmove-result-object v2\ncheck-cast v2, Ljava/lang/String;\ninvoke-static {v2}, ${store}->get${name}(Ljava/lang/String;)${result}\nmove-result-object v2\nif-eqz v2, :loop\ninvoke-virtual {v0, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\ngoto :loop\n:done\nreturn-object v0')
 }
 os.write_file(smali + '/android/app/VinixNotificationChannels.smali', text)!
 path := smali + '/android/app/NotificationManager.smali'
 mut manager := os.read_file(path)!
 for name in ['Channel', 'Group'] {
  result := if name == 'Channel' { channel } else { group }
  api := if name == 'Channel' { 'Channel' } else { 'ChannelGroup' }
  for row in [['createNotification${api}(${result})V', 'put${name}(${result})V'], ['deleteNotification${api}(Ljava/lang/String;)V', 'delete${name}(Ljava/lang/String;)V'], ['getNotification${api}(Ljava/lang/String;)${result}', 'get${name}(Ljava/lang/String;)${result}']] {
   returned := row[0].starts_with('get')
   body := 'invoke-static {p1}, ${store}->${row[1]}\n' + if returned { 'move-result-object v0\nreturn-object v0' } else { 'return-void' }
   manager = framework_replace_method(manager, row[0], channel_method(row[0], body))!
  }
  sig := 'getNotification${api}s()Ljava/util/List;'
  manager = framework_replace_method(manager, sig, channel_method(sig, 'invoke-static {}, ${store}->get${name}s()Ljava/util/List;\nmove-result-object v0\nreturn-object v0'))!
  sig_bulk := 'createNotification${api}s(Ljava/util/List;)V'
  manager = framework_replace_method(manager, sig_bulk, channel_method(sig_bulk, 'invoke-interface {p1}, Ljava/util/List;->iterator()Ljava/util/Iterator;\nmove-result-object v0\n:loop\ninvoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z\nmove-result v1\nif-eqz v1, :done\ninvoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;\nmove-result-object v1\ncheck-cast v1, ${result}\ninvoke-static {v1}, ${store}->put${name}(${result})V\ngoto :loop\n:done\nreturn-void'))!
 }
 os.write_file(path, manager)!
}
