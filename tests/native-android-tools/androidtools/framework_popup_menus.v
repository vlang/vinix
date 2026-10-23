// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// PopupMenu uses the same menu model as Activity menus, but presents it inside
// a real WS Dialog. No GTK menu handles are created. The Dialog is currently
// centered: anchor positioning and outside-click dismissal require backend
// support and are deliberately not emulated with native handle placeholders.
fn framework_popup_menus(smali string) ! {
	menu_path := smali + '/android/view/VinixMenu.smali'
	mut menu := os.read_file(menu_path)!
	assert !menu.contains('vinixContext:')
	menu += '\n.field private vinixContext:Landroid/content/Context;\n' + r'
.method public constructor <init>(Landroid/content/Context;)V
.locals 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/view/VinixMenu;->vinixContext:Landroid/content/Context;
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
iput-object v0, p0, Landroid/view/VinixMenu;->items:Ljava/util/ArrayList;
return-void
.end method
'
	os.write_file(menu_path, menu)!
	item_path := smali + '/android/view/VinixMenuItem.smali'
	mut item := os.read_file(item_path)!
	assert !item.contains('vinixInvokeClick()Z')
	item += r'
.method public vinixInvokeClick()Z
.locals 1
iget-object v0, p0, Landroid/view/VinixMenuItem;->listener:Landroid/view/MenuItem$OnMenuItemClickListener;
if-eqz v0, :unhandled
invoke-interface {v0, p0}, Landroid/view/MenuItem$OnMenuItemClickListener;->onMenuItemClick(Landroid/view/MenuItem;)Z
move-result v0
return v0
:unhandled
const/4 v0, 0x0
return v0
.end method
'
	os.write_file(item_path, item)!
	os.write_file(smali + '/android/widget/PopupMenu.smali', popup_menu_class())!
	os.write_file(smali + '/android/widget/VinixPopupMenuClick.smali', r'
.class public final Landroid/widget/VinixPopupMenuClick;
.super Ljava/lang/Object;
.implements Landroid/view/View$OnClickListener;
.field private popup:Landroid/widget/PopupMenu;
.field private item:Landroid/view/MenuItem;
.field private dialog:Landroid/app/Dialog;
.method public constructor <init>(Landroid/widget/PopupMenu;Landroid/view/MenuItem;)V
.locals 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/widget/VinixPopupMenuClick;->popup:Landroid/widget/PopupMenu;
iput-object p2, p0, Landroid/widget/VinixPopupMenuClick;->item:Landroid/view/MenuItem;
invoke-virtual {p1}, Landroid/widget/PopupMenu;->vinixGetDialog()Landroid/app/Dialog;
move-result-object v0
iput-object v0, p0, Landroid/widget/VinixPopupMenuClick;->dialog:Landroid/app/Dialog;
return-void
.end method
.method public onClick(Landroid/view/View;)V
.locals 3
iget-object v0, p0, Landroid/widget/VinixPopupMenuClick;->popup:Landroid/widget/PopupMenu;
iget-object v1, p0, Landroid/widget/VinixPopupMenuClick;->item:Landroid/view/MenuItem;
iget-object v2, p0, Landroid/widget/VinixPopupMenuClick;->dialog:Landroid/app/Dialog;
invoke-virtual {v0, v1, v2}, Landroid/widget/PopupMenu;->vinixActivate(Landroid/view/MenuItem;Landroid/app/Dialog;)V
return-void
.end method
')!
	os.write_file(smali + '/android/widget/VinixPopupMenuDismiss.smali', r'
.class public final Landroid/widget/VinixPopupMenuDismiss;
.super Ljava/lang/Object;
.implements Landroid/content/DialogInterface$OnDismissListener;
.field private popup:Landroid/widget/PopupMenu;
.field private notified:Z
.method public constructor <init>(Landroid/widget/PopupMenu;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/widget/VinixPopupMenuDismiss;->popup:Landroid/widget/PopupMenu;
return-void
.end method
.method public onDismiss(Landroid/content/DialogInterface;)V
.locals 1
iget-boolean v0, p0, Landroid/widget/VinixPopupMenuDismiss;->notified:Z
if-nez v0, :done
const/4 v0, 0x1
iput-boolean v0, p0, Landroid/widget/VinixPopupMenuDismiss;->notified:Z
iget-object v0, p0, Landroid/widget/VinixPopupMenuDismiss;->popup:Landroid/widget/PopupMenu;
invoke-virtual {v0, p1}, Landroid/widget/PopupMenu;->vinixOnDismiss(Landroid/content/DialogInterface;)V
:done
return-void
.end method
')!
}

fn popup_menu_class() string {
	return r'.class public Landroid/widget/PopupMenu;
.super Ljava/lang/Object;
.field private final mAnchor:Landroid/view/View;
.field private final mContext:Landroid/content/Context;
.field private final menu:Landroid/view/VinixMenu;
.field private mMenuItemClickListener:Landroid/widget/PopupMenu$OnMenuItemClickListener;
.field private mOnDismissListener:Landroid/widget/PopupMenu$OnDismissListener;
.field private vinixGravity:I
.field private vinixDialog:Landroid/app/Dialog;
.field private vinixCurrentMenu:Landroid/view/Menu;
.field private vinixParents:Ljava/util/ArrayList;

.method public constructor <init>(Landroid/content/Context;Landroid/view/View;)V
.locals 1
const/4 v0, 0x0
invoke-direct {p0, p1, p2, v0}, Landroid/widget/PopupMenu;-><init>(Landroid/content/Context;Landroid/view/View;I)V
return-void
.end method

.method public constructor <init>(Landroid/content/Context;Landroid/view/View;I)V
.locals 6
move-object v0, p0
move-object v1, p1
move-object v2, p2
move v3, p3
const v4, 0x1010300
const/4 v5, 0x0
invoke-direct/range {v0 .. v5}, Landroid/widget/PopupMenu;-><init>(Landroid/content/Context;Landroid/view/View;III)V
return-void
.end method

.method public constructor <init>(Landroid/content/Context;Landroid/view/View;III)V
.locals 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/widget/PopupMenu;->mContext:Landroid/content/Context;
iput-object p2, p0, Landroid/widget/PopupMenu;->mAnchor:Landroid/view/View;
iput p3, p0, Landroid/widget/PopupMenu;->vinixGravity:I
new-instance v0, Landroid/view/VinixMenu;
invoke-direct {v0, p1}, Landroid/view/VinixMenu;-><init>(Landroid/content/Context;)V
iput-object v0, p0, Landroid/widget/PopupMenu;->menu:Landroid/view/VinixMenu;
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
iput-object v0, p0, Landroid/widget/PopupMenu;->vinixParents:Ljava/util/ArrayList;
return-void
.end method

.method public getMenu()Landroid/view/Menu;
.locals 1
iget-object v0, p0, Landroid/widget/PopupMenu;->menu:Landroid/view/VinixMenu;
return-object v0
.end method

.method public getMenuInflater()Landroid/view/MenuInflater;
.locals 2
new-instance v0, Landroid/view/MenuInflater;
iget-object v1, p0, Landroid/widget/PopupMenu;->mContext:Landroid/content/Context;
invoke-direct {v0, v1}, Landroid/view/MenuInflater;-><init>(Landroid/content/Context;)V
return-object v0
.end method

.method public inflate(I)V
.locals 2
invoke-virtual {p0}, Landroid/widget/PopupMenu;->getMenuInflater()Landroid/view/MenuInflater;
move-result-object v0
invoke-virtual {p0}, Landroid/widget/PopupMenu;->getMenu()Landroid/view/Menu;
move-result-object v1
invoke-virtual {v0, p1, v1}, Landroid/view/MenuInflater;->inflate(ILandroid/view/Menu;)V
return-void
.end method

.method public setGravity(I)V
.locals 0
iput p1, p0, Landroid/widget/PopupMenu;->vinixGravity:I
return-void
.end method

.method public getGravity()I
.locals 1
iget v0, p0, Landroid/widget/PopupMenu;->vinixGravity:I
return v0
.end method

.method public setOnDismissListener(Landroid/widget/PopupMenu$OnDismissListener;)V
.locals 0
iput-object p1, p0, Landroid/widget/PopupMenu;->mOnDismissListener:Landroid/widget/PopupMenu$OnDismissListener;
return-void
.end method

.method public setOnMenuItemClickListener(Landroid/widget/PopupMenu$OnMenuItemClickListener;)V
.locals 0
iput-object p1, p0, Landroid/widget/PopupMenu;->mMenuItemClickListener:Landroid/widget/PopupMenu$OnMenuItemClickListener;
return-void
.end method

.method public show()V
.locals 3
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
if-eqz v0, :create
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixCurrentMenu:Landroid/view/Menu;
invoke-direct {p0, v0}, Landroid/widget/PopupMenu;->vinixShowMenu(Landroid/view/Menu;)V
return-void
:create
iget-object v0, p0, Landroid/widget/PopupMenu;->menu:Landroid/view/VinixMenu;
invoke-virtual {v0}, Landroid/view/VinixMenu;->hasVisibleItems()Z
move-result v0
if-eqz v0, :done
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixParents:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->clear()V
new-instance v0, Landroid/app/Dialog;
iget-object v1, p0, Landroid/widget/PopupMenu;->mContext:Landroid/content/Context;
invoke-direct {v0, v1}, Landroid/app/Dialog;-><init>(Landroid/content/Context;)V
iput-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
new-instance v1, Landroid/widget/VinixPopupMenuDismiss;
invoke-direct {v1, p0}, Landroid/widget/VinixPopupMenuDismiss;-><init>(Landroid/widget/PopupMenu;)V
invoke-virtual {v0, v1}, Landroid/app/Dialog;->setOnDismissListener(Landroid/content/DialogInterface$OnDismissListener;)V
iget-object v1, p0, Landroid/widget/PopupMenu;->menu:Landroid/view/VinixMenu;
invoke-direct {p0, v1}, Landroid/widget/PopupMenu;->vinixShowMenu(Landroid/view/Menu;)V
invoke-virtual {v0}, Landroid/app/Dialog;->show()V
:done
return-void
.end method

.method public dismiss()V
.locals 2
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
if-eqz v0, :done
const/4 v1, 0x0
iput-object v1, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
iput-object v1, p0, Landroid/widget/PopupMenu;->vinixCurrentMenu:Landroid/view/Menu;
iget-object v1, p0, Landroid/widget/PopupMenu;->vinixParents:Ljava/util/ArrayList;
invoke-virtual {v1}, Ljava/util/ArrayList;->clear()V
invoke-virtual {v0}, Landroid/app/Dialog;->dismiss()V
:done
return-void
.end method

.method public vinixOnDismiss(Landroid/content/DialogInterface;)V
.locals 2
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
if-ne v0, p1, :notify
const/4 v0, 0x0
iput-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
iput-object v0, p0, Landroid/widget/PopupMenu;->vinixCurrentMenu:Landroid/view/Menu;
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixParents:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->clear()V
:notify
iget-object v0, p0, Landroid/widget/PopupMenu;->mOnDismissListener:Landroid/widget/PopupMenu$OnDismissListener;
if-eqz v0, :done
invoke-interface {v0, p0}, Landroid/widget/PopupMenu$OnDismissListener;->onDismiss(Landroid/widget/PopupMenu;)V
:done
return-void
.end method

.method private vinixDispatchItem(Landroid/view/MenuItem;)Z
.locals 1
instance-of v0, p1, Landroid/view/VinixMenuItem;
if-eqz v0, :popup
move-object v0, p1
check-cast v0, Landroid/view/VinixMenuItem;
invoke-virtual {v0}, Landroid/view/VinixMenuItem;->vinixInvokeClick()Z
move-result v0
if-nez v0, :handled
:popup
iget-object v0, p0, Landroid/widget/PopupMenu;->mMenuItemClickListener:Landroid/widget/PopupMenu$OnMenuItemClickListener;
if-eqz v0, :unhandled
invoke-interface {v0, p1}, Landroid/widget/PopupMenu$OnMenuItemClickListener;->onMenuItemClick(Landroid/view/MenuItem;)Z
move-result v0
return v0
:handled
const/4 v0, 0x1
return v0
:unhandled
const/4 v0, 0x0
return v0
.end method

.method protected menuItemClickCallback(I)V
.locals 1
iget-object v0, p0, Landroid/widget/PopupMenu;->menu:Landroid/view/VinixMenu;
invoke-virtual {v0, p1}, Landroid/view/VinixMenu;->findItem(I)Landroid/view/MenuItem;
move-result-object v0
if-eqz v0, :done
invoke-direct {p0, v0}, Landroid/widget/PopupMenu;->vinixDispatchItem(Landroid/view/MenuItem;)Z
:done
return-void
.end method

.method public vinixSelect(Landroid/view/MenuItem;)V
.locals 3
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
if-eqz v0, :done
invoke-interface {p1}, Landroid/view/MenuItem;->isVisible()Z
move-result v1
if-eqz v1, :done
invoke-interface {p1}, Landroid/view/MenuItem;->isEnabled()Z
move-result v1
if-eqz v1, :done
invoke-direct {p0, p1}, Landroid/widget/PopupMenu;->vinixDispatchItem(Landroid/view/MenuItem;)Z
# A callback may dismiss or replace this presentation. Do not affect its successor.
iget-object v1, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
if-ne v0, v1, :done
invoke-interface {p1}, Landroid/view/MenuItem;->hasSubMenu()Z
move-result v1
if-eqz v1, :leaf
invoke-interface {p1}, Landroid/view/MenuItem;->getSubMenu()Landroid/view/SubMenu;
move-result-object v1
if-eqz v1, :leaf
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixParents:Ljava/util/ArrayList;
iget-object v2, p0, Landroid/widget/PopupMenu;->vinixCurrentMenu:Landroid/view/Menu;
invoke-virtual {v0, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
invoke-direct {p0, v1}, Landroid/widget/PopupMenu;->vinixShowMenu(Landroid/view/Menu;)V
return-void
:leaf
invoke-virtual {p0}, Landroid/widget/PopupMenu;->dismiss()V
:done
return-void
.end method

.method public vinixGetDialog()Landroid/app/Dialog;
.locals 1
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
return-object v0
.end method

.method public vinixActivate(Landroid/view/MenuItem;Landroid/app/Dialog;)V
.locals 1
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
if-eqz v0, :done
if-ne v0, p2, :done
if-eqz p1, :back
invoke-virtual {p0, p1}, Landroid/widget/PopupMenu;->vinixSelect(Landroid/view/MenuItem;)V
return-void
:back
invoke-virtual {p0}, Landroid/widget/PopupMenu;->vinixBack()V
:done
return-void
.end method

.method public vinixBack()V
.locals 2
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
if-eqz v0, :done
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixParents:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->size()I
move-result v1
if-eqz v1, :done
add-int/lit8 v1, v1, -0x1
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->remove(I)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/view/Menu;
invoke-direct {p0, v0}, Landroid/widget/PopupMenu;->vinixShowMenu(Landroid/view/Menu;)V
:done
return-void
.end method

.method private vinixShowMenu(Landroid/view/Menu;)V
.locals 8
iput-object p1, p0, Landroid/widget/PopupMenu;->vinixCurrentMenu:Landroid/view/Menu;
iget-object v0, p0, Landroid/widget/PopupMenu;->mContext:Landroid/content/Context;
new-instance v1, Landroid/widget/ScrollView;
invoke-direct {v1, v0}, Landroid/widget/ScrollView;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/widget/LinearLayout;
invoke-direct {v2, v0}, Landroid/widget/LinearLayout;-><init>(Landroid/content/Context;)V
const/4 v3, 0x1
invoke-virtual {v2, v3}, Landroid/widget/LinearLayout;->setOrientation(I)V
const/4 v3, -0x1
const/4 v4, -0x2
invoke-virtual {v1, v2, v3, v4}, Landroid/view/ViewGroup;->addView(Landroid/view/View;II)V
iget-object v3, p0, Landroid/widget/PopupMenu;->vinixParents:Ljava/util/ArrayList;
invoke-virtual {v3}, Ljava/util/ArrayList;->isEmpty()Z
move-result v3
if-nez v3, :items
new-instance v3, Landroid/widget/Button;
invoke-direct {v3, v0}, Landroid/widget/Button;-><init>(Landroid/content/Context;)V
const-string v4, "Back"
invoke-virtual {v3, v4}, Landroid/widget/Button;->setText(Ljava/lang/CharSequence;)V
new-instance v4, Landroid/widget/VinixPopupMenuClick;
const/4 v5, 0x0
invoke-direct {v4, p0, v5}, Landroid/widget/VinixPopupMenuClick;-><init>(Landroid/widget/PopupMenu;Landroid/view/MenuItem;)V
invoke-virtual {v3, v4}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V
const/4 v4, -0x1
const/4 v5, -0x2
invoke-virtual {v2, v3, v4, v5}, Landroid/view/ViewGroup;->addView(Landroid/view/View;II)V
:items
const/4 v3, 0x0
invoke-interface {p1}, Landroid/view/Menu;->size()I
move-result v4
:next
if-ge v3, v4, :content
invoke-interface {p1, v3}, Landroid/view/Menu;->getItem(I)Landroid/view/MenuItem;
move-result-object v5
invoke-interface {v5}, Landroid/view/MenuItem;->isVisible()Z
move-result v6
if-eqz v6, :advance
new-instance v6, Landroid/widget/Button;
invoke-direct {v6, v0}, Landroid/widget/Button;-><init>(Landroid/content/Context;)V
invoke-interface {v5}, Landroid/view/MenuItem;->getTitle()Ljava/lang/CharSequence;
move-result-object v7
invoke-virtual {v6, v7}, Landroid/widget/Button;->setText(Ljava/lang/CharSequence;)V
invoke-interface {v5}, Landroid/view/MenuItem;->isEnabled()Z
move-result v7
invoke-virtual {v6, v7}, Landroid/view/View;->setEnabled(Z)V
invoke-interface {v5}, Landroid/view/MenuItem;->isChecked()Z
move-result v7
invoke-virtual {v6, v7}, Landroid/view/View;->setSelected(Z)V
new-instance v7, Landroid/widget/VinixPopupMenuClick;
invoke-direct {v7, p0, v5}, Landroid/widget/VinixPopupMenuClick;-><init>(Landroid/widget/PopupMenu;Landroid/view/MenuItem;)V
invoke-virtual {v6, v7}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V
const/4 v5, -0x1
const/4 v7, -0x2
invoke-virtual {v2, v6, v5, v7}, Landroid/view/ViewGroup;->addView(Landroid/view/View;II)V
:advance
add-int/lit8 v3, v3, 0x1
goto :next
:content
iget-object v0, p0, Landroid/widget/PopupMenu;->vinixDialog:Landroid/app/Dialog;
invoke-virtual {v0, v1}, Landroid/app/Dialog;->setContentView(Landroid/view/View;)V
return-void
.end method
'
}
