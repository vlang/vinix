// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_notification_channel_probe(dir string) ! {
 channel := 'Landroid/app/NotificationChannel;'
 manager := 'Landroid/app/NotificationManager;'
 group := 'Landroid/app/NotificationChannelGroup;'
 probe := 'Lorg/vinix/bootstrap/NotificationChannelProbe;'
 mut body := '
new-instance v0, ${manager}
invoke-direct {v0}, ${manager}-><init>()V
const-string v1, "fixture-account"
invoke-virtual {v0, v1}, ${manager}->getNotificationChannelGroup(Ljava/lang/String;)${group}
move-result-object v2
if-nez v2, :bad
new-instance v2, Ljava/lang/StringBuilder;
const-string v3, "Account"
invoke-direct {v2, v3}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
new-instance v3, ${group}
invoke-direct {v3, v1, v2}, ${group}-><init>(Ljava/lang/String;Ljava/lang/CharSequence;)V
invoke-virtual {v0, v3}, ${manager}->createNotificationChannelGroup(${group})V
const-string v3, " changed"
invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
new-instance v2, ${channel}
const-string v3, "fixture-updates"
const-string v4, "Updates"
const/4 v5, 3
invoke-direct {v2, v3, v4, v5}, ${channel}-><init>(Ljava/lang/String;Ljava/lang/CharSequence;I)V
invoke-virtual {v2, v1}, ${channel}->setGroup(Ljava/lang/String;)V
const/4 v4, 2
new-array v4, v4, [J
const/4 v5, 0
const-wide/16 v6, 10
aput-wide v6, v4, v5
invoke-virtual {v2, v4}, ${channel}->setVibrationPattern([J)V
const-wide/16 v6, 99
aput-wide v6, v4, v5
invoke-virtual {v2, v5}, ${channel}->setShowBadge(Z)V
invoke-virtual {v0, v2}, ${manager}->createNotificationChannel(${channel})V
invoke-virtual {v2, v5}, ${channel}->enableVibration(Z)V
const-string v4, "local mutation"
invoke-virtual {v2, v4}, ${channel}->setName(Ljava/lang/CharSequence;)V
new-instance v0, ${manager}
invoke-direct {v0}, ${manager}-><init>()V
invoke-virtual {v0, v3}, ${manager}->getNotificationChannel(Ljava/lang/String;)${channel}
move-result-object v4
invoke-static {v4}, ${probe}->expectSnapshot(${channel})V
const-string v5, "returned mutation"
invoke-virtual {v4, v5}, ${channel}->setName(Ljava/lang/CharSequence;)V
invoke-virtual {v0, v3}, ${manager}->getNotificationChannel(Ljava/lang/String;)${channel}
move-result-object v4
invoke-static {v4}, ${probe}->expectSnapshot(${channel})V
invoke-virtual {v0, v1}, ${manager}->getNotificationChannelGroup(Ljava/lang/String;)${group}
move-result-object v4
invoke-virtual {v4}, ${group}->isBlocked()Z
move-result v5
if-nez v5, :bad
invoke-virtual {v4}, ${group}->getName()Ljava/lang/CharSequence;
move-result-object v5
const-string v6, "Account"
invoke-virtual {v6, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
if-eqz v5, :bad
invoke-virtual {v4}, ${group}->getChannels()Ljava/util/List;
move-result-object v4
invoke-interface {v4}, Ljava/util/List;->size()I
move-result v5
const/4 v6, 1
if-ne v5, v6, :bad
invoke-interface {v4}, Ljava/util/List;->clear()V
const/4 v4, 5
invoke-virtual {v2, v4}, ${channel}->setImportance(I)V
invoke-virtual {v0, v2}, ${manager}->createNotificationChannel(${channel})V
invoke-virtual {v0, v3}, ${manager}->getNotificationChannel(Ljava/lang/String;)${channel}
move-result-object v4
invoke-virtual {v4}, ${channel}->getImportance()I
move-result v5
const/4 v6, 3
if-ne v5, v6, :bad
invoke-virtual {v4}, ${channel}->shouldVibrate()Z
move-result v5
if-eqz v5, :bad
const/4 v4, 2
invoke-virtual {v2, v4}, ${channel}->setImportance(I)V
invoke-virtual {v0, v2}, ${manager}->createNotificationChannel(${channel})V
invoke-virtual {v0, v3}, ${manager}->deleteNotificationChannel(Ljava/lang/String;)V
invoke-virtual {v0, v3}, ${manager}->getNotificationChannel(Ljava/lang/String;)${channel}
move-result-object v4
if-nez v4, :bad
const/4 v4, 5
invoke-virtual {v2, v4}, ${channel}->setImportance(I)V
invoke-virtual {v0, v2}, ${manager}->createNotificationChannel(${channel})V
invoke-virtual {v0, v3}, ${manager}->getNotificationChannel(Ljava/lang/String;)${channel}
move-result-object v4
invoke-virtual {v4}, ${channel}->getImportance()I
move-result v4
const/4 v5, 2
if-ne v4, v5, :bad
invoke-virtual {v0, v1}, ${manager}->deleteNotificationChannelGroup(Ljava/lang/String;)V
invoke-virtual {v0, v1}, ${manager}->getNotificationChannelGroup(Ljava/lang/String;)${group}
move-result-object v4
if-nez v4, :bad
invoke-virtual {v0, v3}, ${manager}->getNotificationChannel(Ljava/lang/String;)${channel}
move-result-object v4
if-nez v4, :bad
invoke-virtual {v0}, ${manager}->getNotificationChannels()Ljava/util/List;
move-result-object v4
invoke-interface {v4}, Ljava/util/List;->isEmpty()Z
move-result v4
if-eqz v4, :bad
:invalid_start
invoke-virtual {v0, v2}, ${manager}->createNotificationChannel(${channel})V
:invalid_end
.catch Ljava/lang/IllegalArgumentException; {:invalid_start .. :invalid_end} :invalid
goto :bad
:invalid
move-exception v4
'
 // Exercise bulk APIs after a caught validation failure.
 for name in ['Group', 'Channel'] {
  api := if name == 'Channel' { 'Channel' } else { 'ChannelGroup' }
  body += 'new-instance v4, Ljava/util/ArrayList;\ninvoke-direct {v4}, Ljava/util/ArrayList;-><init>()V\n'
  if name == 'Group' {
   body += 'new-instance v5, ${group}\nconst-string v6, "Restored"\ninvoke-direct {v5, v1, v6}, ${group}-><init>(Ljava/lang/String;Ljava/lang/CharSequence;)V\n'
  } else { body += 'move-object v5, v2\n' }
  body += 'invoke-virtual {v4, v5}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\ninvoke-virtual {v0, v4}, ${manager}->createNotification${api}s(Ljava/util/List;)V\ninvoke-virtual {v0}, ${manager}->getNotification${api}s()Ljava/util/List;\nmove-result-object v4\ninvoke-interface {v4}, Ljava/util/List;->size()I\nmove-result v4\nconst/4 v5, 1\nif-ne v4, v5, :bad\n'
 }
 body += 'invoke-virtual {v0, v1}, ${manager}->deleteNotificationChannelGroup(Ljava/lang/String;)V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-NOTIFICATION-CHANNELS-PASS shared-registry snapshots group-membership update lower-importance deletion restore bulk validation"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "notification channel lifecycle"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 expect := '
invoke-virtual {p0}, ${channel}->getImportance()I
move-result v0
const/4 v1, 3
if-ne v0, v1, :bad
invoke-virtual {p0}, ${channel}->getName()Ljava/lang/CharSequence;
move-result-object v0
const-string v1, "Updates"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, ${channel}->shouldVibrate()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, ${channel}->canShowBadge()Z
move-result v0
if-nez v0, :bad
invoke-virtual {p0}, ${channel}->getVibrationPattern()[J
move-result-object v0
const/4 v1, 0
aget-wide v2, v0, v1
const-wide/16 v4, 10
cmp-long v2, v2, v4
if-nez v2, :bad
const-wide/16 v2, 99
aput-wide v2, v0, v1
invoke-virtual {p0}, ${channel}->getVibrationPattern()[J
move-result-object v0
aget-wide v2, v0, v1
cmp-long v2, v2, v4
if-nez v2, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "notification channel snapshot"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/NotificationChannelProbe.smali', '.class public ${probe}\n.super Ljava/lang/Object;\n' + method('public static check()V', body) + method('private static expectSnapshot(${channel})V', expect))!
}
