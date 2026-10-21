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
 framework_content_clients(smali)!
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
 context := smali + '/android/app/ContextImpl.smali'
 os.write_file(context, framework_replace_method(os.read_file(context)!, 'getTheme()Landroid/content/res/Resources$Theme;', '.method public native getTheme()Landroid/content/res/Resources$Theme;\n.end method')!)!
 bitmap := smali + '/android/graphics/Bitmap.smali'
 os.write_file(bitmap, os.read_file(bitmap)! + '\n.field private vinixPixelLock:J\n.field private vinixPixelLocks:I\n')!
 recreate := os.read_file(root() + '/build-support/android/atlframework/recreate.v')!
 task := '.class public Landroid/app/VinixRecreate;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field public old:Landroid/app/Activity;\n.field public next:Landroid/app/Activity;\n' + object_constructor +
  native_declarations(recreate.all_after('fn register_recreate(').all_before('\n}'))
 os.write_file(smali + '/android/app/VinixRecreate.smali', task)!
 views := os.read_file(root() + '/build-support/android/atlframework/views.v')!
 for class, function in {'android/view/View': 'register_view', 'android/app/ListActivity$2': 'register_list_click', 'android/widget/ScrollView': 'register_scroll'} {
  path := smali + '/' + class + '.smali'
  mut text := os.read_file(path)!
  if class == 'android/view/View' { text += '\n.field private vinixHandler:Landroid/os/Handler;\n.field private vinixWsWatchers:Ljava/util/ArrayList;\n.field private vinixWsEditorAction:Ljava/lang/Object;\n.field private vinixRawDirection:I\n' }
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
