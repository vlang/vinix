// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import json2
import crypto.sha256

const subscription_source = r'
.method public static stableDensity()V
.locals 5
sget v0, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I
sget v1, Landroid/util/DisplayMetrics;->DENSITY_DEVICE_STABLE:I
const/16 v2, 160
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
:density_start
const/16 v2, 240
sput v2, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I
new-instance v3, Landroid/util/DisplayMetrics;
invoke-direct {v3}, Landroid/util/DisplayMetrics;-><init>()V
iget v4, v3, Landroid/util/DisplayMetrics;->densityDpi:I
invoke-static {v4, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget v4, Landroid/util/DisplayMetrics;->DENSITY_DEVICE_STABLE:I
invoke-static {v4, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v2, 320
iput v2, v3, Landroid/util/DisplayMetrics;->densityDpi:I
sget v4, Landroid/util/DisplayMetrics;->DENSITY_DEVICE_STABLE:I
invoke-static {v4, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
:density_end
sput v0, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I
return-void
:density_failed
move-exception v1
sput v0, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I
throw v1
.catchall {:density_start .. :density_end} :density_failed
.end method
.method public static restrictions(Landroid/content/Context;)V
.locals 6
const-string v0, "restrictions"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/content/RestrictionsManager;
const-class v1, Landroid/content/RestrictionsManager;
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
if-ne v0, v1, :failed
if-eqz v0, :failed
invoke-virtual {v0}, Landroid/content/RestrictionsManager;->hasRestrictionsProvider()Z
move-result v1
const/4 v2, 0
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/content/RestrictionsManager;->getApplicationRestrictions()Landroid/os/Bundle;
move-result-object v1
invoke-virtual {v1}, Landroid/os/Bundle;->size()I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "fixture"
const/4 v4, 1
invoke-virtual {v1, v3, v4}, Landroid/os/Bundle;->putBoolean(Ljava/lang/String;Z)V
invoke-virtual {v0}, Landroid/content/RestrictionsManager;->getApplicationRestrictions()Landroid/os/Bundle;
move-result-object v3
if-eq v1, v3, :failed
invoke-virtual {v3}, Landroid/os/Bundle;->size()I
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "user"
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/os/UserManager;
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v3
invoke-virtual {v1, v3}, Landroid/os/UserManager;->getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v1
invoke-virtual {v1}, Landroid/os/Bundle;->size()I
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/RestrictionsManager;
invoke-direct {v0}, Landroid/content/RestrictionsManager;-><init>()V
invoke-virtual {v0}, Landroid/content/RestrictionsManager;->getApplicationRestrictions()Landroid/os/Bundle;
move-result-object v0
if-nez v0, :failed
return-void
:failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public static shortcuts()V
.locals 5
new-instance v0, Landroid/content/pm/ShortcutManager;
invoke-direct {v0}, Landroid/content/pm/ShortcutManager;-><init>()V
invoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
new-instance v1, Ljava/util/ArrayList;
invoke-direct {v1}, Ljava/util/ArrayList;-><init>()V
const-string v2, "absent-shortcut"
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
invoke-virtual {v1}, Ljava/util/ArrayList;->size()I
move-result v2
const/4 v3, 2
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/content/pm/ShortcutManager;->getDynamicShortcuts()Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v2
const/4 v3, 0
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
:null_ids_start
invoke-virtual {v0, v3}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
:null_ids_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:null_ids
move-exception v4
invoke-virtual {v1}, Ljava/util/ArrayList;->clear()V
invoke-virtual {v1, v3}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
:null_id_start
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
:null_id_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:null_id
move-exception v4
invoke-virtual {v1}, Ljava/util/ArrayList;->clear()V
const-string v2, ""
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
:empty_id_start
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
:empty_id_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:empty_id
move-exception v4
return-void
.catch Ljava/lang/NullPointerException; {:null_ids_start .. :null_ids_end} :null_ids
.catch Ljava/lang/IllegalArgumentException; {:null_id_start .. :null_id_end} :null_id
.catch Ljava/lang/IllegalArgumentException; {:empty_id_start .. :empty_id_end} :empty_id
.end method
.method public static subscriptions()V
.locals 6
new-instance v0, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;
invoke-direct {v0}, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;-><init>()V
invoke-virtual {v0}, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;->onSubscriptionsChanged()V
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v0
new-instance v1, Lorg/vinix/bootstrap/TestSubscriptions;
invoke-direct {v1, v0}, Lorg/vinix/bootstrap/TestSubscriptions;-><init>(Landroid/os/Looper;)V
new-instance v0, Landroid/telephony/SubscriptionManager;
invoke-direct {v0}, Landroid/telephony/SubscriptionManager;-><init>()V
invoke-virtual {v0, v1}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
invoke-virtual {v0, v1}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
new-instance v2, Lorg/vinix/bootstrap/TestSubscriptionExecutor;
invoke-direct {v2}, Lorg/vinix/bootstrap/TestSubscriptionExecutor;-><init>()V
invoke-virtual {v0, v2, v1}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Ljava/util/concurrent/Executor;Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
invoke-virtual {v0, v1}, Landroid/telephony/SubscriptionManager;->removeOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
invoke-virtual {v0, v1}, Landroid/telephony/SubscriptionManager;->removeOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
const/4 v3, 0
invoke-virtual {v0, v3}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
invoke-virtual {v0, v3}, Landroid/telephony/SubscriptionManager;->removeOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
iget v4, v1, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v2, Lorg/vinix/bootstrap/TestSubscriptionExecutor;->calls:I
const/4 v5, 1
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v1, Lorg/vinix/bootstrap/TestSubscriptions;->failures:I
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Lorg/vinix/bootstrap/TestSubscriptions;->onSubscriptionsChanged()V
iget v4, v1, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
const/4 v5, 1
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
:null_executor_start
invoke-virtual {v0, v3, v1}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Ljava/util/concurrent/Executor;Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
:null_executor_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:null_executor
move-exception v4
:null_listener_start
invoke-virtual {v0, v2, v3}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Ljava/util/concurrent/Executor;Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
:null_listener_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:null_listener
move-exception v4
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v2
invoke-direct {v0, v2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v2, Lorg/vinix/bootstrap/TestSubscriptionFence;
invoke-direct {v2, v1}, Lorg/vinix/bootstrap/TestSubscriptionFence;-><init>(Lorg/vinix/bootstrap/TestSubscriptions;)V
invoke-virtual {v0, v2}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
.catch Ljava/lang/NullPointerException; {:null_executor_start .. :null_executor_end} :null_executor
.catch Ljava/lang/NullPointerException; {:null_listener_start .. :null_listener_end} :null_listener
.end method
'

fn subscription_fixture(root string) ! {
	os.write_file(root + '/smali/TestSubscriptionFence.smali', r'.class public Lorg/vinix/bootstrap/TestSubscriptionFence;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private final listener:Lorg/vinix/bootstrap/TestSubscriptions;
.method public constructor <init>(Lorg/vinix/bootstrap/TestSubscriptions;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/TestSubscriptionFence;->listener:Lorg/vinix/bootstrap/TestSubscriptions;
return-void
.end method
.method public run()V
.locals 3
iget-object v0, p0, Lorg/vinix/bootstrap/TestSubscriptionFence;->listener:Lorg/vinix/bootstrap/TestSubscriptions;
iget v1, v0, Lorg/vinix/bootstrap/TestSubscriptions;->failures:I
const/4 v2, 3
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v1, v0, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CURRENT-API-PASS"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
	os.write_file(root + '/smali/TestSubscriptions.smali', r'.class public Lorg/vinix/bootstrap/TestSubscriptions;
.super Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;
.field public calls:I
.field public failures:I
.method public constructor <init>(Landroid/os/Looper;)V
.locals 0
invoke-direct {p0, p1}, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;-><init>(Landroid/os/Looper;)V
return-void
.end method
.method public onSubscriptionsChanged()V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
return-void
.end method
.method public onAddListenerFailed()V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestSubscriptions;->failures:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestSubscriptions;->failures:I
return-void
.end method
')!
	os.write_file(root + '/smali/TestSubscriptionExecutor.smali', r'.class public Lorg/vinix/bootstrap/TestSubscriptionExecutor;
.super Ljava/lang/Object;
.implements Ljava/util/concurrent/Executor;
.field public calls:I
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public execute(Ljava/lang/Runnable;)V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestSubscriptionExecutor;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestSubscriptionExecutor;->calls:I
invoke-interface {p1}, Ljava/lang/Runnable;->run()V
return-void
.end method
')!
}

fn boolean_source() string {
	// Reflect only to seed this isolated test process's existing property map;
	// do not expose a pretend system-wide property setter in the framework.
	mut source := r'
.method public static properties()V
.locals 6
const-class v0, Landroid/os/SystemProperties;
const-string v1, "properties"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/util/Properties;
const-string v1, "vinix.fixture.boolean"
'
	for token in ['<missing>', '', 'unknown', 'TRUE', ' true', '1', 'y', 'yes', 'on', 'true', '0', 'n', 'no', 'off', 'false'] {
		if token == '<missing>' {
			source += 'invoke-virtual {v0, v1}, Ljava/util/Properties;->remove(Ljava/lang/Object;)Ljava/lang/Object;\n'
		} else {
			source += 'const-string v2, "${token}"\ninvoke-virtual {v0, v1, v2}, Ljava/util/Properties;->setProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;\n'
		}
		for fallback in [0, 1] {
			expected := if token in ['1', 'y', 'yes', 'on', 'true'] { 1 } else if token in ['0', 'n', 'no', 'off', 'false'] { 0 } else { fallback }
			source += 'const/4 v3, ${fallback}\ninvoke-static {v1, v3}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z\nmove-result v4\nconst/4 v5, ${expected}\ninvoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
		}
	}
	source += 'invoke-virtual {v0, v1}, Ljava/util/Properties;->remove(Ljava/lang/Object;)Ljava/lang/Object;\nreturn-void\n.end method\n'
	return source
}

const user_source = r'
.method public static users()V
.locals 6
const/4 v0, 2
new-array v1, v0, [Landroid/os/UserHandle;
invoke-static {v1}, Lorg/vinix/bootstrap/Main;->acceptUsers([Landroid/os/Parcelable;)I
move-result v2
invoke-static {v2, v0}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/os/UserHandle;
const/16 v1, 42
invoke-direct {v0, v1}, Landroid/os/UserHandle;-><init>(I)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const/4 v3, 0
invoke-virtual {v0, v2, v3}, Landroid/os/UserHandle;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v4, Landroid/os/UserHandle;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v4, v2}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v5
check-cast v5, Landroid/os/UserHandle;
invoke-virtual {v5}, Landroid/os/UserHandle;->getIdentifier()I
move-result v5
invoke-static {v5, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-interface {v4, v1}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v5
instance-of v5, v5, [Landroid/os/UserHandle;
const/4 v4, 1
invoke-static {v5, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
invoke-static {v0, v2}, Landroid/os/UserHandle;->writeToParcel(Landroid/os/UserHandle;Landroid/os/Parcel;)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-static {v2}, Landroid/os/UserHandle;->readFromParcel(Landroid/os/Parcel;)Landroid/os/UserHandle;
move-result-object v5
invoke-virtual {v5}, Landroid/os/UserHandle;->getIdentifier()I
move-result v5
invoke-static {v5, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const/4 v0, 0
invoke-static {v0, v2}, Landroid/os/UserHandle;->writeToParcel(Landroid/os/UserHandle;Landroid/os/Parcel;)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-static {v2}, Landroid/os/UserHandle;->readFromParcel(Landroid/os/Parcel;)Landroid/os/UserHandle;
move-result-object v5
if-eqz v5, :null_ok
new-instance v5, Ljava/lang/AssertionError;
invoke-direct {v5}, Ljava/lang/AssertionError;-><init>()V
throw v5
:null_ok
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
return-void
.end method
.method public static acceptUsers([Landroid/os/Parcelable;)I
.locals 1
array-length v0, p0
return v0
.end method
'

const intent_source = r'
.method public static intent()V
.locals 10
new-instance v0, Landroid/content/Intent;
const-string v1, "android.intent.action.MAIN"
invoke-direct {v0, v1}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
new-instance v1, Landroid/content/ComponentName;
const-string v2, "com.example"
const-string v3, "com.example.Main"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;
invoke-virtual {v0, v2}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "android.intent.category.LAUNCHER"
invoke-virtual {v0, v1}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
move-result-object v2
const-string v3, "intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;package=com.example;component=com.example/.Main;end"
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v1, 2
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
move-result-object v2
const-string v3, "android-app://com.example#Intent;category=android.intent.category.LAUNCHER;component=com.example/.Main;end"
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "demo+map://host/a%20b?x=1#fragment"
invoke-static {v1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v1
const-string v2, "text/plain"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setDataAndType(Landroid/net/Uri;Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "s;雪"
const-string v2, "value;=☃"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "count"
const/16 v2, -7
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;
const-string v1, "yes"
invoke-virtual {v0, v1, v6}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Z)Landroid/content/Intent;
const-string v1, "wide"
const-wide v8, 0x1020304050607080L
invoke-virtual {v0, v1, v8, v9}, Landroid/content/Intent;->putExtra(Ljava/lang/String;J)Landroid/content/Intent;
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
move-result-object v2
invoke-static {v2, v1}, Landroid/content/Intent;->parseUri(Ljava/lang/String;I)Landroid/content/Intent;
move-result-object v3
invoke-static {v0, v3}, Lorg/vinix/bootstrap/Main;->sameIntent(Landroid/content/Intent;Landroid/content/Intent;)V
const/4 v1, 2
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
move-result-object v2
invoke-static {v2, v1}, Landroid/content/Intent;->parseUri(Ljava/lang/String;I)Landroid/content/Intent;
move-result-object v3
invoke-static {v0, v3}, Lorg/vinix/bootstrap/Main;->sameIntent(Landroid/content/Intent;Landroid/content/Intent;)V
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
:package_start
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
:package_end
new-instance v2, Ljava/lang/AssertionError;
invoke-direct {v2}, Ljava/lang/AssertionError;-><init>()V
throw v2
.catch Ljava/lang/IllegalArgumentException; {:package_start .. :package_end} :package_expected
:package_expected
move-exception v2
return-void
.end method
.method public static sameIntent(Landroid/content/Intent;Landroid/content/Intent;)V
.locals 6
invoke-virtual {p0}, Landroid/content/Intent;->getDataString()Ljava/lang/String;
move-result-object v0
invoke-virtual {p1}, Landroid/content/Intent;->getDataString()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v2, 1
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/content/ComponentName;->equals(Ljava/lang/Object;)Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "s;雪"
invoke-virtual {p1, v0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "value;=☃"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "count"
const/4 v1, 0
invoke-virtual {p1, v0, v1}, Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I
move-result v0
const/16 v1, -7
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "yes"
const/4 v1, 0
invoke-virtual {p1, v0, v1}, Landroid/content/Intent;->getBooleanExtra(Ljava/lang/String;Z)Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "wide"
const-wide/16 v4, 0
invoke-virtual {p1, v0, v4, v5}, Landroid/content/Intent;->getLongExtra(Ljava/lang/String;J)J
move-result-wide v4
const-wide v0, 0x1020304050607080L
cmp-long v0, v0, v4
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
'

const main_source = r'.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method protected onCreate(Landroid/os/Bundle;)V
.locals 2
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->mime()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->parcel()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->accounts()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->intent()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->users()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->properties()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->stableDensity()V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->restrictions(Landroid/content/Context;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->subscriptions()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->shortcuts()V
new-instance v0, Landroid/content/pm/ShortcutManager;
invoke-direct {v0}, Landroid/content/pm/ShortcutManager;-><init>()V
invoke-virtual {v0}, Landroid/content/pm/ShortcutManager;->getDynamicShortcuts()Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/telephony/TelephonyManager;
invoke-direct {v0}, Landroid/telephony/TelephonyManager;-><init>()V
invoke-virtual {v0}, Landroid/telephony/TelephonyManager;->isVoiceCapable()Z
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/net/ConnectivityManager;
invoke-direct {v0}, Landroid/net/ConnectivityManager;-><init>()V
invoke-virtual {v0}, Landroid/net/ConnectivityManager;->isTetheringSupported()Z
move-result v0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static expect(II)V
.locals 1
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:ok
return-void
.end method
.method public static mime()V
.locals 10
new-instance v0, Landroid/content/IntentFilter;
const-string v1, "A"
invoke-direct {v0, v1}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
const-string v2, "image/*"
invoke-virtual {v0, v2}, Landroid/content/IntentFilter;->addDataType(Ljava/lang/String;)V
invoke-virtual {v0, v2}, Landroid/content/IntentFilter;->addDataType(Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/content/IntentFilter;->countDataTypes()I
move-result v7
const/4 v8, 1
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v2, "image/png"
invoke-virtual {v0, v2}, Landroid/content/IntentFilter;->hasDataType(Ljava/lang/String;)Z
move-result v7
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "content"
const-string v4, "content://test/image"
invoke-static {v4}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v4
const/4 v5, 0
const/4 v6, 0
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const v8, 0x608000
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "B"
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const/4 v8, -3
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "A"
const-string v2, "text/plain"
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const/4 v8, -1
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v2, "image/png"
const-string v3, "https"
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const/4 v8, -2
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "content"
new-instance v5, Ljava/util/HashSet;
invoke-direct {v5}, Ljava/util/HashSet;-><init>()V
const-string v9, "missing"
invoke-interface {v5, v9}, Ljava/util/Set;->add(Ljava/lang/Object;)Z
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const/4 v8, -4
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
:bad_start
const-string v9, "broken"
invoke-virtual {v0, v9}, Landroid/content/IntentFilter;->addDataType(Ljava/lang/String;)V
:bad_end
new-instance v9, Ljava/lang/AssertionError;
invoke-direct {v9}, Ljava/lang/AssertionError;-><init>()V
throw v9
.catch Landroid/content/IntentFilter$MalformedMimeTypeException; {:bad_start .. :bad_end} :bad_expected
:bad_expected
move-exception v9
invoke-virtual {v0}, Landroid/content/IntentFilter;->countDataTypes()I
move-result v7
const/4 v8, 1
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/IntentFilter;
invoke-direct {v0}, Landroid/content/IntentFilter;-><init>()V
const/4 v3, 0
const/4 v4, 0
invoke-virtual {v0, v2, v3, v4}, Landroid/content/IntentFilter;->matchData(Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;)I
move-result v7
const/4 v8, -2
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static parcel()V
.locals 8
const-string v0, "01234567-89ab-cdef-8123-456789abcdef"
invoke-static {v0}, Landroid/os/ParcelUuid;->fromString(Ljava/lang/String;)Landroid/os/ParcelUuid;
move-result-object v0
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/os/ParcelUuid;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v3, Landroid/os/ParcelUuid;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v1}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v4
invoke-virtual {v0, v4}, Landroid/os/ParcelUuid;->equals(Ljava/lang/Object;)Z
move-result v5
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-interface {v3, v6}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v4
instance-of v5, v4, [Landroid/os/ParcelUuid;
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const v0, 0x200404
invoke-virtual {v1, v0}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v3, Landroid/bluetooth/BluetoothClass;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v1}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v4
check-cast v4, Landroid/bluetooth/BluetoothClass;
invoke-virtual {v4}, Landroid/bluetooth/BluetoothClass;->getDeviceClass()I
move-result v5
const/16 v7, 0x404
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
const v7, 0x200000
invoke-virtual {v4, v7}, Landroid/bluetooth/BluetoothClass;->hasService(I)Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const-string v0, "01:23:45:67:89:AB"
invoke-virtual {v1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V
invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v3, Landroid/bluetooth/BluetoothDevice;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v1}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v4
check-cast v4, Landroid/bluetooth/BluetoothDevice;
invoke-virtual {v4}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
move-result-object v4
invoke-virtual {v0, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
return-void
.end method
.method public static accounts()V
.locals 8
new-instance v0, Lorg/vinix/bootstrap/TestAccounts;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestAccounts;-><init>()V
const/4 v7, 0
new-array v1, v7, [Landroid/accounts/Account;
iput-object v1, v0, Lorg/vinix/bootstrap/TestAccounts;->snapshot:[Landroid/accounts/Account;
const-string v1, "type"
const/4 v7, 1
new-array v2, v7, [Ljava/lang/String;
const/4 v6, 0
const-string v5, "feature"
aput-object v5, v2, v6
const/4 v3, 0
const/4 v4, 0
invoke-virtual {v0, v1, v2, v3, v4}, Landroid/accounts/AccountManager;->getAccountsByTypeAndFeatures(Ljava/lang/String;[Ljava/lang/String;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
move-result-object v5
invoke-interface {v5}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;
move-result-object v5
check-cast v5, [Landroid/accounts/Account;
array-length v5, v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-array v5, v7, [Landroid/accounts/Account;
new-instance v6, Landroid/accounts/Account;
const-string v7, "name"
invoke-direct {v6, v7, v1}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/4 v7, 0
aput-object v6, v5, v7
iput-object v5, v0, Lorg/vinix/bootstrap/TestAccounts;->snapshot:[Landroid/accounts/Account;
:features_start
invoke-virtual {v0, v1, v2, v3, v4}, Landroid/accounts/AccountManager;->getAccountsByTypeAndFeatures(Ljava/lang/String;[Ljava/lang/String;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
move-result-object v5
invoke-interface {v5}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;
:features_end
new-instance v5, Ljava/lang/AssertionError;
invoke-direct {v5}, Ljava/lang/AssertionError;-><init>()V
throw v5
.catch Landroid/accounts/AuthenticatorException; {:features_start .. :features_end} :unsupported
:unsupported
move-exception v5
const/4 v2, 0
invoke-virtual {v0, v1, v2, v3, v4}, Landroid/accounts/AccountManager;->getAccountsByTypeAndFeatures(Ljava/lang/String;[Ljava/lang/String;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
move-result-object v5
invoke-interface {v5}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;
move-result-object v5
check-cast v5, [Landroid/accounts/Account;
array-length v5, v5
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
'

fn main() {
	if os.args.len == 4 && os.args[1] == '--plan' {
		serial := os.read_file(os.args[2])!
		if serial.len > 8 * 1024 * 1024 || os.exists(os.args[3]) { panic('bounded input and fresh plan required') }
		prefix := 'VINIX-SERVICE-QUERY-RESULTS-1 '
		headers := serial.split_into_lines().filter(it.starts_with(prefix + 'BEGIN '))
		if headers.len != 1 { panic('one complete fixture export required') }
		fields := headers[0].fields()
		if fields.len != 5 || !serial.contains(prefix + 'END ' + fields[2..].join(' ')) { panic('incomplete fixture export') }
		os.write_file(os.args[3], json2.encode({
			'version': json2.Any(2), 'frame_prefix': json2.Any(prefix),
			'serial_sha256': json2.Any(sha256.sum(serial.bytes()).hex()),
			'archive_sha256': json2.Any(fields[2]), 'archive_bytes': json2.Any(fields[3].int()),
			'archive_chunks': json2.Any(fields[4].int()), 'removals': json2.Any([]json2.Any{})
		}, prettify: true))!
		return
	}
	if os.args.len != 3 { panic('usage: current-api-fixture TEMPLATE_FIXTURE FRESH_OUTPUT') }
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) { panic('fresh output required') }
	os.mkdir_all(root + '/smali')!
	os.write_file(root + '/smali/Main.smali', main_source + intent_source + user_source + boolean_source() + subscription_source)!
	subscription_fixture(root)!
	os.write_file(root + '/smali/TestAccounts.smali', r'.class public Lorg/vinix/bootstrap/TestAccounts;
.super Landroid/accounts/AccountManager;
.field public snapshot:[Landroid/accounts/Account;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/accounts/AccountManager;-><init>()V
return-void
.end method
.method public getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;
.locals 1
iget-object v0, p0, Lorg/vinix/bootstrap/TestAccounts;->snapshot:[Landroid/accounts/Account;
return-object v0
.end method
')!
	os.cp(base + '/unsigned.apk', root + '/unsigned.apk')!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	tools := '/Users/alex/code/vinix/build/android-framework/tools'
	signer := '/Users/alex/code/vinix/build/android-native-ws/android-15/lib/apksigner.jar'
	for args in [[java, '-Xmx256m', '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/unsigned.apk', root + '/classes.dex'],
		[java, '-Xmx256m', '-jar', signer, 'sign', '--ks', base + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', root + '/probe.apk', root + '/unsigned.apk'],
		[java, '-Xmx256m', '-jar', signer, 'verify', '--verbose', root + '/probe.apk']] {
		if os.system_args(args) != 0 { panic('fixture build failed') }
	}
	println('CURRENT-API-FIXTURE ' + root + '/probe.apk')
}
