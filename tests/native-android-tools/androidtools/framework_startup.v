// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_startup_apis(smali string) ! {
 framework_accessibility_traversal(smali)!
 framework_texture_transforms(smali)!
 // No Android accessibility services are installed in the native WS backend.
 // Android exposes immutable snapshots for both installed and enabled lists.
 accessibility := smali + '/android/view/accessibility/AccessibilityManager.smali'
 mut accessibility_text := os.read_file(accessibility)!
 for signature in ['getInstalledAccessibilityServiceList()Ljava/util/List;',
  'getAccessibilityServiceList()Ljava/util/List;', 'getEnabledAccessibilityServiceList(I)Ljava/util/List;'] {
  accessibility_text = framework_replace_method(accessibility_text, signature,
   '.method public ' + signature + '\n.locals 1\ninvoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;\nmove-result-object v0\nreturn-object v0\n.end method')!
 }
 os.write_file(accessibility, accessibility_text)!
 // Native WS does not implement Android picture-in-picture window mode.
 activity := smali + '/android/app/Activity.smali'
 os.write_file(activity, framework_replace_method(os.read_file(activity)!, 'isInPictureInPictureMode()Z',
  '.method public isInPictureInPictureMode()Z\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!)!
 // A refresh preference is advisory; WS currently keeps its fixed rate.
 params := smali + '/android/view/WindowManager$LayoutParams.smali'
 os.write_file(params, os.read_file(params)! + '\n.field public preferredRefreshRate:F\n')!
 // Vinix owns the system chrome. Retain the app's divider color preference
 // without introducing a second Android navigation bar inside its window.
 window := smali + '/android/view/Window.smali'
 mut window_text := os.read_file(window)! + '\n.field private vinixNavigationBarDividerColor:I\n'
 window_text = framework_replace_method(window_text, 'setNavigationBarDividerColor(I)V',
  '.method public setNavigationBarDividerColor(I)V\n.locals 0\niput p1, p0, Landroid/view/Window;->vinixNavigationBarDividerColor:I\nreturn-void\n.end method')!
 window_text = framework_replace_method(window_text, 'getNavigationBarDividerColor()I',
  '.method public getNavigationBarDividerColor()I\n.locals 1\niget v0, p0, Landroid/view/Window;->vinixNavigationBarDividerColor:I\nreturn v0\n.end method')!
 // Floating is a theme property, independent of the WS window dimensions.
 // Resolve the public windowIsFloating attribute, including theme references.
 window_text = framework_replace_method(window_text, 'isFloating()Z',
  '.method public isFloating()Z\n.locals 4\n' +
  'invoke-virtual {p0}, Landroid/view/Window;->getContext()Landroid/content/Context;\nmove-result-object v0\n' +
  'invoke-virtual {v0}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;\nmove-result-object v0\n' +
  'new-instance v1, Landroid/util/TypedValue;\ninvoke-direct {v1}, Landroid/util/TypedValue;-><init>()V\n' +
  'const v2, 0x1010057\nconst/4 v3, 1\n' +
  'invoke-virtual {v0, v2, v1, v3}, Landroid/content/res/Resources$Theme;->resolveAttribute(ILandroid/util/TypedValue;Z)Z\nmove-result v0\n' +
  'if-eqz v0, :done\niget v0, v1, Landroid/util/TypedValue;->data:I\nif-eqz v0, :done\nconst/4 v0, 1\n' +
  ':done\nreturn v0\n.end method')!
 os.write_file(window, window_text)!
 listener := smali + '/android/hardware/SensorEventListener.smali'
 mut text := os.read_file(listener)!
 if !text.contains('onAccuracyChanged(') {
  text += '\n.method public abstract onAccuracyChanged(Landroid/hardware/Sensor;I)V\n.end method\n'
 }
 os.write_file(listener, text)!
 os.write_file(smali + '/android/hardware/SensorEventListener2.smali',
  '.class public interface abstract Landroid/hardware/SensorEventListener2;\n.super Ljava/lang/Object;\n.implements Landroid/hardware/SensorEventListener;\n' +
  '.method public abstract onFlushCompleted(Landroid/hardware/Sensor;)V\n.end method\n')!
 // No sensor driver is connected to this backend. Advertise no devices.
 sensors := smali + '/android/hardware/SensorManager.smali'
 mut sensor_text := os.read_file(sensors)!
 for signature in ['getDefaultSensor(I)Landroid/hardware/Sensor;', 'getDefaultSensor(IZ)Landroid/hardware/Sensor;'] {
  sensor_text = framework_replace_method(sensor_text, signature, '.method public ' + signature + '\n.locals 1\nconst/4 v0, 0\nreturn-object v0\n.end method')!
 }
 sensor_text = framework_replace_method(sensor_text, 'getSensorList(I)Ljava/util/List;',
  '.method public getSensorList(I)Ljava/util/List;\n.locals 1\ninvoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;\nmove-result-object v0\nreturn-object v0\n.end method')!
 for signature in ['registerListener(Landroid/hardware/SensorEventListener;Landroid/hardware/Sensor;I)Z',
  'registerListener(Landroid/hardware/SensorEventListener;Landroid/hardware/Sensor;ILandroid/os/Handler;)Z',
  'registerListener(Landroid/hardware/SensorEventListener;Landroid/hardware/Sensor;II)Z',
  'registerListener(Landroid/hardware/SensorEventListener;Landroid/hardware/Sensor;IILandroid/os/Handler;)Z',
  'flush(Landroid/hardware/SensorEventListener;)Z'] {
  sensor_text = framework_replace_method(sensor_text, signature, '.method public ' + signature + '\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!
 }
 // Standard-atmosphere barometric height. This pure calculation also works
 // without a connected pressure sensor; preserve Android's float rounding.
 sensor_text = framework_replace_method(sensor_text, 'getAltitude(FF)F',
  '.method public static getAltitude(FF)F\n.locals 4\n' +
  'div-float v0, p1, p0\nfloat-to-double v0, v0\n' +
  'const/high16 v2, 0x3f800000\nconst v3, 0x40a828f6\n' +
  'div-float v2, v2, v3\nfloat-to-double v2, v2\n' +
  'invoke-static {v0, v1, v2, v3}, Ljava/lang/Math;->pow(DD)D\nmove-result-wide v0\n' +
  'double-to-float v0, v0\nconst/high16 v1, 0x3f800000\nsub-float v0, v1, v0\n' +
  'const v1, 0x472d2a00\nmul-float v0, v0, v1\nreturn v0\n.end method')!
 os.write_file(sensors, sensor_text)!
 context := smali + '/android/content/Context.smali'
 mut context_text := os.read_file(context)!
 for signature in ['registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;',
  'registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;I)Landroid/content/Intent;',
  'registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;Ljava/lang/String;Landroid/os/Handler;)Landroid/content/Intent;',
  'registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;Ljava/lang/String;Landroid/os/Handler;I)Landroid/content/Intent;',
  'unregisterReceiver(Landroid/content/BroadcastReceiver;)V', 'sendBroadcast(Landroid/content/Intent;)V'] {
  context_text = framework_replace_method(context_text, signature, '.method public native ' + signature + '\n.end method')!
 }
 os.write_file(context, context_text)!
 os.write_file(smali + '/android/atl/VinixBroadcast.smali',
  '.class public final Landroid/atl/VinixBroadcast;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field public static final registrations:Ljava/util/concurrent/CopyOnWriteArrayList;\n' +
  '.field public receiver:Landroid/content/BroadcastReceiver;\n.field public context:Landroid/content/Context;\n' +
  '.field public filter:Landroid/content/IntentFilter;\n.field public handler:Landroid/os/Handler;\n.field public intent:Landroid/content/Intent;\n' +
  '.method static constructor <clinit>()V\n.locals 1\nnew-instance v0, Ljava/util/concurrent/CopyOnWriteArrayList;\ninvoke-direct {v0}, Ljava/util/concurrent/CopyOnWriteArrayList;-><init>()V\n' +
  'sput-object v0, Landroid/atl/VinixBroadcast;->registrations:Ljava/util/concurrent/CopyOnWriteArrayList;\nreturn-void\n.end method\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public static getRegistrations()Ljava/util/concurrent/CopyOnWriteArrayList;\n.locals 1\nsget-object v0, Landroid/atl/VinixBroadcast;->registrations:Ljava/util/concurrent/CopyOnWriteArrayList;\nreturn-object v0\n.end method\n' +
  '.method public native run()V\n.end method\n')!
}

// Retain traversal relationships even when no accessibility service is installed.
// They are IDs, so unresolved targets and NO_ID must round-trip unchanged.
fn framework_accessibility_traversal(smali string) ! {
 path := smali + '/android/view/View.smali'
 mut text := os.read_file(path)!
 for kind in ['Before', 'After'] {
  field := 'vinixAccessibilityTraversal' + kind
  text += '\n.field private ' + field + ':I\n'
  text = framework_replace_method(text, 'getAccessibilityTraversal' + kind + '()I',
   '.method public getAccessibilityTraversal' + kind + '()I\n.locals 1\niget v0, p0, Landroid/view/View;->' + field + ':I\nreturn v0\n.end method')!
  text = framework_replace_method(text, 'setAccessibilityTraversal' + kind + '(I)V',
   '.method public setAccessibilityTraversal' + kind + '(I)V\n.locals 0\niput p1, p0, Landroid/view/View;->' + field + ':I\nreturn-void\n.end method')!
 }
 // All public constructors delegate here. Read the public attributes with the
 // same theme and default styles as View, independently of the ATL styleable.
 constructor := '<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'
 start := text.index(' ' + constructor + '\n') or { return error('missing View constructor') }
 end := start + (text[start..].index('.end method') or { return error('unterminated View constructor') })
 init := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V'
 assert text[start..end].count(init) == 1
 text = text[..start] + text[start..end].replace(init, init + '\ninvoke-direct {p0, p1, p2, p3, p4}, Landroid/view/View;->vinixInitAccessibilityTraversal(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n') + text[end..]
 text += '.method private vinixInitAccessibilityTraversal(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n.locals 4\n' +
  'const/4 v0, 2\nnew-array v0, v0, [I\nfill-array-data v0, :attributes\n' +
  'invoke-virtual {p1, p2, v0, p3, p4}, Landroid/content/Context;->obtainStyledAttributes(Landroid/util/AttributeSet;[III)Landroid/content/res/TypedArray;\nmove-result-object v0\n' +
  ':try_start\nconst/4 v1, 0\nconst/4 v2, -1\ninvoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getResourceId(II)I\nmove-result v3\niput v3, p0, Landroid/view/View;->vinixAccessibilityTraversalBefore:I\n' +
  'const/4 v1, 1\ninvoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getResourceId(II)I\nmove-result v3\niput v3, p0, Landroid/view/View;->vinixAccessibilityTraversalAfter:I\n:try_end\n' +
  '.catchall {:try_start .. :try_end} :failed\ninvoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V\nreturn-void\n' +
  ':failed\nmove-exception v1\ninvoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V\nthrow v1\n' +
  ':attributes\n.array-data 4\n0x010104d1\n0x010104d2\n.end array-data\n.end method\n'
 os.write_file(path, text)!
}
