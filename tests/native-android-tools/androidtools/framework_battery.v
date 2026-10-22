// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// WS has no battery driver. Preserve Android's unsupported-property sentinels
// instead of inventing a charge level, current or charging-time estimate.
fn framework_battery(smali string) ! {
 battery := 'Landroid/os/BatteryManager;'
 mut text := '.class public ' + battery + '\n.super Ljava/lang/Object;\n.field private context:Landroid/content/Context;\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public constructor <init>(Landroid/content/Context;)V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'iput-object p1, p0, ' + battery + '->context:Landroid/content/Context;\nreturn-void\n.end method\n'
 for name, value in {'CHARGE_COUNTER': 1, 'CURRENT_NOW': 2, 'CURRENT_AVERAGE': 3, 'CAPACITY': 4, 'ENERGY_COUNTER': 5, 'STATUS': 6} {
  text += '.field public static final BATTERY_PROPERTY_' + name + ':I = ' + value.str() + '\n'
 }
 for name, value in {'UNKNOWN': 1, 'CHARGING': 2, 'DISCHARGING': 3, 'NOT_CHARGING': 4, 'FULL': 5} {
  text += '.field public static final BATTERY_STATUS_' + name + ':I = ' + value.str() + '\n'
 }
 text += '.method public getIntProperty(I)I\n.locals 2\niget-object v0, p0, ' + battery + '->context:Landroid/content/Context;\n' +
  'if-eqz v0, :legacy\ninvoke-virtual {v0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;\nmove-result-object v0\n' +
  'iget v0, v0, Landroid/content/pm/ApplicationInfo;->targetSdkVersion:I\nconst/16 v1, 28\nif-lt v0, v1, :legacy\n' +
  'const v0, -0x80000000\nreturn v0\n:legacy\nconst/4 v0, 0\nreturn v0\n.end method\n'
 text += '.method public getLongProperty(I)J\n.locals 2\nconst-wide v0, -0x8000000000000000L\nreturn-wide v0\n.end method\n'
 text += '.method public computeChargeTimeRemaining()J\n.locals 2\nconst-wide/16 v0, -1\nreturn-wide v0\n.end method\n'
 text += '.method public isCharging()Z\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method\n'
 os.write_file(smali + '/android/os/BatteryManager.smali', text)!
 context := smali + '/android/content/Context.smali'
 os.write_file(context, os.read_file(context)! + '\n.field public static final BATTERY_SERVICE:Ljava/lang/String; = "batterymanager"\n')!
 path := smali + '/android/app/ContextImpl.smali'
 mut implementation := os.read_file(path)!
 // Keep the existing providers and their caching. Both lookup forms must give
 // this service its Context so legacy target-SDK behavior remains correct.
 implementation = implementation.replace('.method public getSystemService(Ljava/lang/String;)', '.method private vinixSystemServiceString(Ljava/lang/String;)')
 implementation = implementation.replace('.method public getSystemService(Ljava/lang/Class;)', '.method private vinixSystemServiceClass(Ljava/lang/Class;)')
 implementation += '.method public getSystemService(Ljava/lang/String;)Ljava/lang/Object;\n.locals 1\nconst-string v0, "batterymanager"\n' +
  'invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :other\n' +
  'new-instance v0, ' + battery + '\ninvoke-direct {v0, p0}, ' + battery + '-><init>(Landroid/content/Context;)V\nreturn-object v0\n' +
  ':other\ninvoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixSystemServiceString(Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v0\nreturn-object v0\n.end method\n'
 implementation += '.method public getSystemService(Ljava/lang/Class;)Ljava/lang/Object;\n.locals 1\nconst-class v0, ' + battery + '\n' +
  'if-ne p1, v0, :other\nconst-string v0, "batterymanager"\ninvoke-virtual {p0, v0}, Landroid/app/ContextImpl;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;\n' +
  'move-result-object v0\nreturn-object v0\n:other\ninvoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixSystemServiceClass(Ljava/lang/Class;)Ljava/lang/Object;\nmove-result-object v0\nreturn-object v0\n.end method\n'
 os.write_file(path, implementation)!
}
