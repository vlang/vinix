// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn native_declarations(registration string) string {
 mut result := ''
 for entry in registration.split('NativeMethod{')[1..] {
  parts := entry.split("c'")
  result += '.method public native ' + parts[1].all_before("'") + parts[2].all_before("'") + '\n.end method\n'
 }
 return result
}

fn interface_class(name string, methods []string) string {
 mut result := '.class public interface abstract L' + name + ';\n.super Ljava/lang/Object;\n'
 for method in methods { result += '.method public abstract ' + method + '\n.end method\n' }
 return result
}

pub fn framework_extra_classes(source string) map[string]string {
 widgets := source
 mut simple := '.class public Landroid/widget/SimpleCursorAdapter;\n.super Landroid/widget/CursorAdapter;\n' +
  '.field private vinixLayout:I\n.field private vinixFrom:[Ljava/lang/String;\n.field private vinixTo:[I\n' +
  '.field private vinixBinder:Landroid/widget/SimpleCursorAdapter$ViewBinder;\n'
 for flags in [false, true] {
  simple += '.method public constructor <init>(Landroid/content/Context;ILandroid/database/Cursor;[Ljava/lang/String;[I' + if flags { 'I' } else { '' } + ')V\n.locals 0\n'
  simple += if flags {
   'invoke-direct {p0, p1, p3, p6}, Landroid/widget/CursorAdapter;-><init>(Landroid/content/Context;Landroid/database/Cursor;I)V\n'
  } else {
   'invoke-direct {p0, p1, p3}, Landroid/widget/CursorAdapter;-><init>(Landroid/content/Context;Landroid/database/Cursor;)V\n'
  }
  simple += 'invoke-virtual {p0, p2, p4, p5}, Landroid/widget/SimpleCursorAdapter;->vinixInit(I[Ljava/lang/String;[I)V\nreturn-void\n.end method\n'
 }
 simple += native_declarations(widgets.all_after('fn register_simple_cursor(').all_before('\n}'))
 mut search := '.class public Landroid/widget/SearchView;\n.super Landroid/widget/LinearLayout;\n' +
  '.field private vinixEdit:Landroid/widget/EditText;\n.field private vinixSubmit:Landroid/widget/Button;\n.field private vinixListener:Landroid/widget/SearchView$OnQueryTextListener;\n.field private vinixSubmitEnabled:I\n'
 for index, signature in ['Landroid/content/Context;', 'Landroid/content/Context;Landroid/util/AttributeSet;', 'Landroid/content/Context;Landroid/util/AttributeSet;I'] {
  search += '.method public constructor <init>(' + signature + ')V\n.locals 0\n'
  search += 'invoke-direct {' + ['p0, p1', 'p0, p1, p2', 'p0, p1, p2, p3'][index] + '}, Landroid/widget/LinearLayout;-><init>(' + signature + ')V\n'
  search += 'invoke-virtual {p0, p1}, Landroid/widget/SearchView;->vinixInit(Landroid/content/Context;)V\nreturn-void\n.end method\n'
 }
 search += native_declarations(widgets.all_after('fn register_search(').all_before('\n}'))
 callbacks := '.class public Landroid/widget/VinixSearchCallbacks;\n.super Ljava/lang/Object;\n' +
  '.implements Landroid/text/TextWatcher;\n.implements Landroid/widget/TextView$OnEditorActionListener;\n.implements Landroid/view/View$OnClickListener;\n' +
  '.field public owner:Landroid/widget/SearchView;\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  native_declarations(widgets.all_after('fn register_search_callbacks(').all_before('\n}'))
 return {
  'android/content/ContentProvider$PipeDataWriter': interface_class('android/content/ContentProvider$PipeDataWriter', ['writeDataToPipe(Landroid/os/ParcelFileDescriptor;Landroid/net/Uri;Ljava/lang/String;Landroid/os/Bundle;Ljava/lang/Object;)V'])
  'android/widget/SimpleCursorAdapter': simple
  'android/widget/SimpleCursorAdapter$ViewBinder': interface_class('android/widget/SimpleCursorAdapter$ViewBinder', ['setViewValue(Landroid/view/View;Landroid/database/Cursor;I)Z'])
  'android/widget/SearchView': search
  'android/widget/SearchView$OnQueryTextListener': interface_class('android/widget/SearchView$OnQueryTextListener', ['onQueryTextChange(Ljava/lang/String;)Z', 'onQueryTextSubmit(Ljava/lang/String;)Z'])
  'android/widget/VinixSearchCallbacks': callbacks
 }
}

pub fn write_framework_classes(smali string) ! {
 os.write_file(smali + '/android/atl/VinixUncaughtException.smali',
  '.class public final Landroid/atl/VinixUncaughtException;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Thread$UncaughtExceptionHandler;\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public native uncaughtException(Ljava/lang/Thread;Ljava/lang/Throwable;)V\n.end method\n')!
 framework_async_trace(smali)!
 framework_main_executor(smali)!
 framework_permission_listeners(smali)!
 framework_application_uid(smali)!
 framework_appops(smali)!
 framework_activity_manager(smali)!
 framework_geofence(smali)!
 framework_uri_permissions(smali)!
 framework_atomic_file(smali)!
 framework_traffic_stats(smali)!
 framework_power(smali)!
 framework_battery(smali)!
 framework_device_policy(smali)!
 framework_sqlite_params(smali)!
 framework_location_state(smali)!
 framework_gnss(smali)!
 framework_wifi(smali)!
 framework_time_utils(smali)!
 framework_location_value(smali)!
 framework_alarm(smali)!
 framework_intent(smali)!
 framework_clipdata(smali)!
 framework_pending_intent(smali)!
 framework_strict_mode(smali)!
 framework_work_source(smali)!
 framework_package_enumeration(smali)!
 framework_vibrator(smali)!
 framework_media_router(smali)!
 framework_account_listeners(smali)!
 framework_storage_queries(smali)!
 framework_startup_apis(smali)!
 framework_absent_hardware(smali)!
 framework_hardware_buffer(smali)!
 framework_time_animator(smali)!
 framework_path_animator(smali)!
 framework_interpolators(smali)!
 framework_layout_suppression(smali)!
 framework_message_queue(smali)!
 framework_resource_fonts(smali)!
 framework_font_builders(smali)!
 framework_text_locales(smali)!
 framework_font_metrics(smali)!
 framework_character_styles(smali)!
 framework_absolute_size_span(smali)!
 framework_static_layout_fallback(smali)!
 framework_asset_streams(smali)!
 framework_view_geometry(smali)!
 framework_view_configuration(smali)!
 framework_egl(smali)!
 framework_glutils(smali)!
 framework_view_attachment(smali)!
 framework_content_capture(smali)!
 framework_autofill(smali)!
 framework_view_traversal(smali)!
 framework_view_frame_bounds(smali)!
 framework_layout_listeners(smali)!
 framework_view_touch(smali)!
 framework_view_scroll(smali)!
 framework_drawing_ids(smali)!
 framework_view_layers(smali)!
 framework_view_shadow_colors(smali)!
 framework_child_states(smali)!
 framework_child_order(smali)!
 framework_gradient_colors(smali)!
 framework_paths(smali)!
 framework_render_nodes(smali)!
 framework_render_node_outline(smali)!
 framework_layout_canvas(smali)!
 framework_pictures(smali)!
 framework_paint_color_longs(smali)!
 framework_paint_filters(smali)!
 framework_rect_parcels(smali)!
 framework_notification_channels(smali)!
 framework_network_requests(smali)!
 framework_connectivity(smali)!
 framework_content_clients(smali)!
 framework_text_widgets(smali)!
 framework_editor_actions(smali)!
 framework_image_filters(smali)!
 framework_check_widgets(smali)!
 source := os.read_file(root() + '/build-support/android/atlframework/widgets.v')!
 for name, text in framework_extra_classes(source) { os.write_file(smali + '/' + name + '.smali', text)! }
 dialogs := os.read_file(root() + '/build-support/android/atlframework/dialogs.v')!
 for class, function in {'android/app/AlertDialog': 'register_dialog', 'android/app/AlertDialog$Builder': 'register_dialog_builder'} {
  path := smali + '/' + class + '.smali'
  registration := dialogs.all_after('fn ' + function + '(').all_before('\n}')
  mut text := os.read_file(path)!
  if class == 'android/app/AlertDialog' { text += '\n.field private vinixCustomView:Landroid/view/View;\n' }
  for block in native_declarations(registration).split('.method ')[1..] {
   signature := block.all_before('\n').all_after('native ')
   text = framework_replace_method(text, signature, '.method ' + block)!
  }
  os.write_file(path, text)!
 }
 click := '.class public Landroid/app/VinixDialogClick;\n.super Ljava/lang/Object;\n.implements Landroid/view/View$OnClickListener;\n' +
  '.field public dialog:Landroid/app/AlertDialog;\n.field public listener:Landroid/content/DialogInterface$OnClickListener;\n.field public which:I\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  native_declarations(dialogs.all_after('fn register_dialog_click(').all_before('\n}'))
 os.write_file(smali + '/android/app/VinixDialogClick.smali', click)!
 menus := os.read_file(root() + '/build-support/android/atlframework/menus.v')!
 object_constructor := '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n'
 menu := '.class public Landroid/view/VinixMenu;\n.super Ljava/lang/Object;\n.implements Landroid/view/SubMenu;\n' +
  '.field private items:Ljava/util/ArrayList;\n.field private owner:Landroid/app/Activity;\n.field private item:Landroid/view/VinixMenuItem;\n' +
  object_constructor + native_declarations(menus.all_after('fn register_menu(').all_before('\n}'))
 os.write_file(smali + '/android/view/VinixMenu.smali', menu)!
 mut item := '.class public Landroid/view/VinixMenuItem;\n.super Ljava/lang/Object;\n.implements Landroid/view/MenuItem;\n'
 for field in ['id:I', 'group:I', 'order:I', 'visible:I', 'enabled:I', 'checked:I', 'checkable:I', 'exclusive:I', 'expanded:I', 'showAction:I', 'numeric:I', 'alphabetic:I',
  'menu:Landroid/view/VinixMenu;', 'submenu:Landroid/view/VinixMenu;', 'title:Ljava/lang/CharSequence;', 'condensed:Ljava/lang/CharSequence;', 'icon:Landroid/graphics/drawable/Drawable;', 'action:Landroid/view/View;',
  'listener:Landroid/view/MenuItem$OnMenuItemClickListener;', 'expandListener:Landroid/view/MenuItem$OnActionExpandListener;'] { item += '.field private ' + field + '\n' }
 item += object_constructor + native_declarations(menus.all_after('fn register_menu_item(').all_before('\n}'))
 os.write_file(smali + '/android/view/VinixMenuItem.smali', item)!
 menu_click := '.class public Landroid/view/VinixMenuClick;\n.super Ljava/lang/Object;\n.implements Landroid/view/View$OnClickListener;\n' +
  '.field public owner:Landroid/app/Activity;\n.field public item:Landroid/view/VinixMenuItem;\n' + object_constructor +
  native_declarations(menus.all_after('fn register_menu_click(').all_before('\n}'))
 os.write_file(smali + '/android/view/VinixMenuClick.smali', menu_click)!
 framework_popup_menus(smali)!
 framework_action_provider(smali)!
 context := smali + '/android/app/ContextImpl.smali'
 os.write_file(context, framework_replace_method(os.read_file(context)!, 'getTheme()Landroid/content/res/Resources$Theme;', '.method public native getTheme()Landroid/content/res/Resources$Theme;\n.end method')!)!
 bitmap := smali + '/android/graphics/Bitmap.smali'
 mut bitmap_text := os.read_file(bitmap)! + '\n.field private vinixPixelLock:J\n.field private vinixPixelLocks:I\n'
 for signature in ['getSnapshot()J', 'getTexture()J', 'eraseColor(I)V'] {
  bitmap_text = framework_replace_method(bitmap_text, signature, '.method public native ' + signature + '\n.end method')!
 }
 os.write_file(bitmap, bitmap_text)!
 canvas := smali + '/android/atl/GskCanvas.smali'
 canvas_text := os.read_file(canvas)! + '\n.field private vinixDrawState:J\n'
 os.write_file(canvas, framework_replace_method(canvas_text, 'finalize()V', '.method protected native finalize()V\n.end method')!)!
 framework_view_canvas(smali)!
 // A Java Surface may outlive its holder. Retain the view owning the native
 // window, so Surface.widget cannot become a dangling WsView pointer.
 surface := smali + '/android/view/Surface.smali'
 os.write_file(surface, os.read_file(surface)! + '\n.field public vinixOwner:Landroid/view/SurfaceView;\n')!
 surface_view := smali + '/android/view/SurfaceView.smali'
 surface_view_text := os.read_file(surface_view)!
 surface_assignment := 'iput-object v0, p0, Landroid/view/SurfaceView;->mSurface:Landroid/view/Surface;'
 if surface_view_text.count(surface_assignment) != 3 { return error('unexpected ATL SurfaceView constructors') }
 os.write_file(surface_view, surface_view_text.replace(surface_assignment,
  surface_assignment + '\n\n    iput-object p0, v0, Landroid/view/Surface;->vinixOwner:Landroid/view/SurfaceView;'))!
 recreate := os.read_file(root() + '/build-support/android/atlframework/recreate.v')!
 task := '.class public Landroid/app/VinixRecreate;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field public old:Landroid/app/Activity;\n.field public next:Landroid/app/Activity;\n' + object_constructor +
  native_declarations(recreate.all_after('fn register_recreate(').all_before('\n}'))
 os.write_file(smali + '/android/app/VinixRecreate.smali', task)!
 views := os.read_file(root() + '/build-support/android/atlframework/views.v')!
 for class, function in {'android/view/View': 'register_view', 'android/app/ListActivity$2': 'register_list_click', 'android/widget/ScrollView': 'register_scroll'} {
  path := smali + '/' + class + '.smali'
  mut text := os.read_file(path)!
  if class == 'android/view/View' { text += '\n.field private vinixHandler:Landroid/os/Handler;\n.field private vinixWsWatchers:Ljava/util/ArrayList;\n.field protected vinixWsEditorAction:Ljava/lang/Object;\n.field private vinixRawDirection:I\n' }
  else if class == 'android/app/ListActivity$2' && !text.contains('this$0:Landroid/app/ListActivity;') { return error('unexpected ATL ListActivity click listener') }
  for block in native_declarations(views.all_after('fn ' + function + '(').all_before('\n}')).split('.method ')[1..] {
   text = framework_replace_method(text, block.all_before('\n').all_after('native '), '.method ' + block)!
  }
  os.write_file(path, text)!
 }
 button := smali + '/android/widget/Button.smali'
 os.write_file(button, framework_replace_method(os.read_file(button)!, '<init>(Landroid/content/Context;Landroid/util/AttributeSet;)V',
  '.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V\n.locals 1\n' +
  'sget v0, Landroid/R$attr;->buttonStyle:I\n' +
  'invoke-direct {p0, p1, p2, v0}, Landroid/widget/Button;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V\nreturn-void\n.end method')!)!
}

// API 29 exposes application-tag aliases for the older async trace API.
// Retain the provider's enabled-tag checks (tracing is disabled on Vinix).
fn framework_async_trace(smali string) ! {
 path := smali + '/android/os/Trace.smali'
 mut text := os.read_file(path)!
 for method, target in {'beginAsyncSection': 'asyncTraceBegin', 'endAsyncSection': 'asyncTraceEnd'} {
  signature := method + '(Ljava/lang/String;I)V'
  text = framework_replace_method(text, signature,
   '.method public static ' + signature + '\n.locals 2\nconst-wide/16 v0, 0x1000\n' +
   'invoke-static {v0, v1, p0, p1}, Landroid/os/Trace;->' + target + '(JLjava/lang/String;I)V\nreturn-void\n.end method')!
 }
 // This provider has no tracing backend: cacheEnabledTags always returns zero.
 // The API 29 counter therefore records nothing, including for 64-bit values.
 // Do not narrow it through the older traceCounter(..., int) overload.
 text = framework_replace_method(text, 'setCounter(Ljava/lang/String;J)V',
  '.method public static setCounter(Ljava/lang/String;J)V\n.locals 0\nreturn-void\n.end method')!
 os.write_file(path, text)!
}

fn framework_application_uid(smali string) ! {
 user := smali + '/android/os/UserHandle.smali'
 os.write_file(user, framework_replace_method(os.read_file(user)!, 'isApp(I)Z',
  '.method public static isApp(I)Z\n.locals 2\nif-lez p0, :no\n' +
  'invoke-static {p0}, Landroid/os/UserHandle;->getAppId(I)I\nmove-result v0\n' +
  'const/16 v1, 10000\nif-lt v0, v1, :no\nconst/16 v1, 19999\nif-gt v0, v1, :no\n' +
  'const/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0\n.end method')!)!
 process := smali + '/android/os/Process.smali'
 os.write_file(process, framework_replace_method(os.read_file(process)!, 'isApplicationUid(I)Z',
  '.method public static isApplicationUid(I)Z\n.locals 1\n' +
  'invoke-static {p0}, Landroid/os/UserHandle;->isApp(I)Z\nmove-result v0\nreturn v0\n.end method')!)!
}

fn framework_text_widgets(smali string) ! {
 path := smali + '/android/widget/TextView.smali'
 mut text := os.read_file(path)!
 for signature in ['setMaxLines(I)V', 'getMaxLines()I', 'setMinLines(I)V', 'getMinLines()I', 'setMinHeight(I)V', 'getMinHeight()I',
  'setSingleLine()V', 'setSingleLine(Z)V', 'setHorizontallyScrolling(Z)V', 'getHorizontallyScrolling()Z'] {
  text = framework_replace_method(text, signature, '.method public native ' + signature + '\n.end method')!
 }
 text += '\n.method public setGravity(I)V\n.locals 0\niput p1, p0, Landroid/widget/TextView;->gravity:I\n' +
  'invoke-virtual {p0}, Landroid/view/View;->requestLayout()V\nreturn-void\n.end method\n'
 os.write_file(path, text)!
 // Preserve TextView overload dispatch for subclasses such as styled chips.
 for class in ['Button', 'CompoundButton', 'CheckBox', 'RadioButton'] {
  widget := smali + '/android/widget/' + class + '.smali'
  mut source := os.read_file(widget)!
  source = framework_replace_method(source, 'setText(Ljava/lang/CharSequence;)V',
   '.method public setText(Ljava/lang/CharSequence;)V\n.locals 1\n' +
   'sget-object v0, Landroid/widget/TextView$BufferType;->NORMAL:Landroid/widget/TextView$BufferType;\n' +
   'invoke-virtual {p0, p1, v0}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;Landroid/widget/TextView$BufferType;)V\nreturn-void\n.end method')!
  if class == 'Button' {
   source = framework_replace_method(source, 'getText()Ljava/lang/CharSequence;',
    '.method public getText()Ljava/lang/CharSequence;\n.locals 1\n' +
    'invoke-super {p0}, Landroid/widget/TextView;->getText()Ljava/lang/CharSequence;\nmove-result-object v0\nreturn-object v0\n.end method')!
  }
  os.write_file(widget, source)!
 }
 html := smali + '/android/text/Html.smali'
 os.write_file(html, framework_replace_method(os.read_file(html)!, 'fromHtml(Ljava/lang/String;I)Landroid/text/Spanned;',
  '.method public static native fromHtml(Ljava/lang/String;I)Landroid/text/Spanned;\n.end method')!)!
}

fn framework_check_widgets(smali string) ! {
 for class in ['CompoundButton', 'CheckBox', 'RadioButton'] {
  path := smali + '/android/widget/' + class + '.smali'
  mut text := os.read_file(path)!
  if class == 'CompoundButton' {
   text += '\n.field private vinixWsCheckedListener:Landroid/widget/CompoundButton$OnCheckedChangeListener;\n'
   // Zero selects the WS default indicator; one selects the styled/app drawable,
   // including null. A custom CompoundButton style need not have an indicator.
   // The provider cannot inflate some framework animated defaults. Use the WS
   // fallback only when the app has not overridden the framework default style.
   text += '\n.field public vinixWsButtonDrawableSet:I\n'
   text = framework_replace_method(text, '<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V', r'.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
.locals 4
invoke-direct {p0, p1, p2, p3, p4}, Landroid/widget/Button;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
const/4 v0, 1
iput v0, p0, Landroid/widget/CompoundButton;->vinixWsButtonDrawableSet:I
sget-object v0, Lcom/android/internal/R$styleable;->CompoundButton:[I
invoke-virtual {p1, p2, v0, p3, p4}, Landroid/content/Context;->obtainStyledAttributes(Landroid/util/AttributeSet;[III)Landroid/content/res/TypedArray;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/content/res/TypedArray;->hasValueOrEmpty(I)Z
move-result v2
if-eqz v2, :absent_button
invoke-virtual {v0, v1}, Landroid/content/res/TypedArray;->getDrawable(I)Landroid/graphics/drawable/Drawable;
move-result-object v1
iput-object v1, p0, Landroid/widget/CompoundButton;->button_drawable:Landroid/graphics/drawable/Drawable;
iput-object v1, p0, Landroid/widget/CompoundButton;->mButtonDrawable:Landroid/graphics/drawable/Drawable;
if-nez v1, :checked
const/4 v1, 1
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getResourceId(II)I
move-result v2
ushr-int/lit8 v2, v2, 24
const/4 v3, 1
if-ne v2, v3, :checked
:absent_button
if-nez p4, :checked
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/content/res/TypedArray;->getSourceStyleResourceId(II)I
move-result v2
if-eqz v2, :button_source_default
ushr-int/lit8 v2, v2, 24
const/4 v3, 1
if-ne v2, v3, :checked
:button_source_default
if-eqz p2, :default_style
invoke-interface {p2}, Landroid/util/AttributeSet;->getStyleAttribute()I
move-result v2
if-nez v2, :checked
const-string v2, "http://schemas.android.com/apk/res/android"
const-string v3, "button"
invoke-interface {p2, v2, v3}, Landroid/util/AttributeSet;->getAttributeValue(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v2
if-nez v2, :checked
:default_style
const v1, 0x101006c
if-eq p3, v1, :default_theme
const v1, 0x101007e
if-ne p3, v1, :checked
:default_theme
invoke-virtual {p1}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;
move-result-object v2
new-instance v3, Landroid/util/TypedValue;
invoke-direct {v3}, Landroid/util/TypedValue;-><init>()V
const/4 v1, 1
invoke-virtual {v2, p3, v3, v1}, Landroid/content/res/Resources$Theme;->resolveAttribute(ILandroid/util/TypedValue;Z)Z
move-result v1
if-eqz v1, :default_button
iget v1, v3, Landroid/util/TypedValue;->resourceId:I
ushr-int/lit8 v1, v1, 24
const/4 v2, 1
if-ne v1, v2, :checked
:default_button
const/4 v1, 0
iput v1, p0, Landroid/widget/CompoundButton;->vinixWsButtonDrawableSet:I
:checked
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/content/res/TypedArray;->hasValue(I)Z
move-result v2
if-eqz v2, :done
invoke-virtual {v0, v1, v1}, Landroid/content/res/TypedArray;->getBoolean(IZ)Z
move-result v1
invoke-virtual {p0, v1}, Landroid/widget/CompoundButton;->setChecked(Z)V
:done
invoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V
invoke-virtual {p0}, Landroid/view/View;->refreshDrawableState()V
return-void
.end method')!
   text = framework_replace_method(text, 'setButtonDrawable(Landroid/graphics/drawable/Drawable;)V',
    '.method public setButtonDrawable(Landroid/graphics/drawable/Drawable;)V\n.locals 1\n' +
    'iput-object p1, p0, Landroid/widget/CompoundButton;->button_drawable:Landroid/graphics/drawable/Drawable;\n' +
    'iput-object p1, p0, Landroid/widget/CompoundButton;->mButtonDrawable:Landroid/graphics/drawable/Drawable;\n' +
    'const/4 v0, 1\niput v0, p0, Landroid/widget/CompoundButton;->vinixWsButtonDrawableSet:I\n' +
    'invoke-virtual {p0}, Landroid/view/View;->refreshDrawableState()V\n' +
    'invoke-virtual {p0}, Landroid/view/View;->requestLayout()V\n' +
    'invoke-virtual {p0}, Landroid/view/View;->invalidate()V\nreturn-void\n.end method')!
   text += '\n.method public setButtonDrawable(I)V\n.locals 1\nconst/4 v0, 0\n' +
    'if-eqz p1, :set\ninvoke-virtual {p0}, Landroid/view/View;->getContext()Landroid/content/Context;\nmove-result-object v0\n' +
    'invoke-virtual {v0, p1}, Landroid/content/Context;->getDrawable(I)Landroid/graphics/drawable/Drawable;\nmove-result-object v0\n' +
    ':set\ninvoke-virtual {p0, v0}, Landroid/widget/CompoundButton;->setButtonDrawable(Landroid/graphics/drawable/Drawable;)V\nreturn-void\n.end method\n'
   text = framework_replace_method(text, 'getText()Ljava/lang/CharSequence;',
    '.method public getText()Ljava/lang/CharSequence;\n.locals 1\n' +
    'invoke-super {p0}, Landroid/widget/Button;->getText()Ljava/lang/CharSequence;\nmove-result-object v0\nreturn-object v0\n.end method')!
   text += '\n.method public performClick()Z\n.locals 1\n' +
    'invoke-virtual {p0}, Landroid/widget/CompoundButton;->toggle()V\n' +
    'invoke-super {p0}, Landroid/widget/Button;->performClick()Z\nconst/4 v0, 1\nreturn v0\n.end method\n'
   text = framework_replace_method(text, 'onCreateDrawableState(I)[I', r'.method protected onCreateDrawableState(I)[I
.locals 3
add-int/lit8 v0, p1, 1
invoke-super {p0, v0}, Landroid/widget/Button;->onCreateDrawableState(I)[I
move-result-object v0
invoke-virtual {p0}, Landroid/widget/CompoundButton;->isChecked()Z
move-result v1
if-eqz v1, :done
const v1, 0x10100a0
filled-new-array {v1}, [I
move-result-object v1
invoke-static {v0, v1}, Landroid/view/View;->mergeDrawableStates([I[I)[I
move-result-object v0
:done
return-object v0
.end method')!
   text = framework_replace_method(text, 'drawableStateChanged()V', r'.method protected drawableStateChanged()V
.locals 2
invoke-super {p0}, Landroid/widget/Button;->drawableStateChanged()V
iget-object v0, p0, Landroid/widget/CompoundButton;->button_drawable:Landroid/graphics/drawable/Drawable;
if-eqz v0, :done
invoke-virtual {v0}, Landroid/graphics/drawable/Drawable;->isStateful()Z
move-result v1
if-eqz v1, :done
invoke-virtual {p0}, Landroid/view/View;->getDrawableState()[I
move-result-object v1
invoke-virtual {v0, v1}, Landroid/graphics/drawable/Drawable;->setState([I)Z
move-result v1
if-eqz v1, :done
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void
.end method')!
  } else {
   // Forward the platform default style only from the short constructors.
   // Subclasses such as chips pass their own style through the longer forms.
   owner := 'Landroid/widget/' + class + ';'
   default_style := if class == 'CheckBox' { '0x101006c' } else { '0x101007e' }
   for signature, body in {
    'Landroid/content/Context;': 'const/4 v0, 0\ninvoke-direct {p0, p1, v0}, ' + owner + '-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V\n'
    'Landroid/content/Context;Landroid/util/AttributeSet;': 'const v0, ' + default_style + '\ninvoke-direct {p0, p1, p2, v0}, ' + owner + '-><init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V\n'
    'Landroid/content/Context;Landroid/util/AttributeSet;I': 'const/4 v0, 0\ninvoke-direct {p0, p1, p2, p3, v0}, ' + owner + '-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n'
    'Landroid/content/Context;Landroid/util/AttributeSet;II': 'invoke-direct {p0, p1, p2, p3, p4}, Landroid/widget/CompoundButton;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n'
   } {
    text = framework_replace_method(text, '<init>(' + signature + ')V',
     '.method public constructor <init>(' + signature + ')V\n.locals 1\n' + body + 'return-void\n.end method')!
   }
  }
  for signature in ['setTextColor(I)V', 'setTextSize(F)V'] {
   text = framework_replace_method(text, signature, '.method public native ' + signature + '\n.end method')!
  }
  parent := if class == 'CompoundButton' { 'Button' } else { 'CompoundButton' }
  text = framework_replace_method(text, 'setOnClickListener(Landroid/view/View$OnClickListener;)V',
   '.method public setOnClickListener(Landroid/view/View$OnClickListener;)V\n.locals 0\n' +
   'invoke-super {p0, p1}, Landroid/widget/' + parent + ';->setOnClickListener(Landroid/view/View$OnClickListener;)V\nreturn-void\n.end method')!
  if class == 'RadioButton' {
   text += '\n.method public toggle()V\n.locals 1\ninvoke-virtual {p0}, Landroid/widget/RadioButton;->isChecked()Z\n' +
    'move-result v0\nif-nez v0, :done\nconst/4 v0, 1\ninvoke-virtual {p0, v0}, Landroid/widget/RadioButton;->setChecked(Z)V\n:done\nreturn-void\n.end method\n'
  }
  os.write_file(path, text)!
 }
}
