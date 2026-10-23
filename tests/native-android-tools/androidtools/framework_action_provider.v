// SPDX-License-Identifier: Apache-2.0
// ActionProvider contract adapted from Android Open Source Project (2011).
module androidtools

import os

// Keep application callbacks virtual, including visibility predicates and the
// legacy action-view factory. Menu presentation is handled by VinixMenuItem.
fn framework_action_provider(smali string) ! {
	os.write_file(smali + '/android/view/ActionProvider.smali', r'.class public abstract Landroid/view/ActionProvider;
.super Ljava/lang/Object;
.field private mSubUiVisibilityListener:Landroid/view/ActionProvider$SubUiVisibilityListener;
.field private mVisibilityListener:Landroid/view/ActionProvider$VisibilityListener;
.annotation system Ldalvik/annotation/MemberClasses;
value = {Landroid/view/ActionProvider$SubUiVisibilityListener;, Landroid/view/ActionProvider$VisibilityListener;}
.end annotation

.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method

.method public abstract onCreateActionView()Landroid/view/View;
.end method

.method public onCreateActionView(Landroid/view/MenuItem;)Landroid/view/View;
.locals 1
invoke-virtual {p0}, Landroid/view/ActionProvider;->onCreateActionView()Landroid/view/View;
move-result-object v0
return-object v0
.end method

.method public overridesItemVisibility()Z
.locals 1
const/4 v0, 0
return v0
.end method

.method public isVisible()Z
.locals 1
const/4 v0, 1
return v0
.end method

.method public refreshVisibility()V
.locals 2
iget-object v0, p0, Landroid/view/ActionProvider;->mVisibilityListener:Landroid/view/ActionProvider$VisibilityListener;
if-eqz v0, :done
invoke-virtual {p0}, Landroid/view/ActionProvider;->overridesItemVisibility()Z
move-result v0
if-eqz v0, :done
iget-object v0, p0, Landroid/view/ActionProvider;->mVisibilityListener:Landroid/view/ActionProvider$VisibilityListener;
invoke-virtual {p0}, Landroid/view/ActionProvider;->isVisible()Z
move-result v1
invoke-interface {v0, v1}, Landroid/view/ActionProvider$VisibilityListener;->onActionProviderVisibilityChanged(Z)V
:done
return-void
.end method

.method public onPerformDefaultAction()Z
.locals 1
const/4 v0, 0
return v0
.end method

.method public hasSubMenu()Z
.locals 1
const/4 v0, 0
return v0
.end method

.method public onPrepareSubMenu(Landroid/view/SubMenu;)V
.locals 0
return-void
.end method

.method public subUiVisibilityChanged(Z)V
.locals 1
iget-object v0, p0, Landroid/view/ActionProvider;->mSubUiVisibilityListener:Landroid/view/ActionProvider$SubUiVisibilityListener;
if-eqz v0, :done
invoke-interface {v0, p1}, Landroid/view/ActionProvider$SubUiVisibilityListener;->onSubUiVisibilityChanged(Z)V
:done
return-void
.end method

.method public setSubUiVisibilityListener(Landroid/view/ActionProvider$SubUiVisibilityListener;)V
.locals 0
iput-object p1, p0, Landroid/view/ActionProvider;->mSubUiVisibilityListener:Landroid/view/ActionProvider$SubUiVisibilityListener;
return-void
.end method

.method public setVisibilityListener(Landroid/view/ActionProvider$VisibilityListener;)V
.locals 3
iget-object v0, p0, Landroid/view/ActionProvider;->mVisibilityListener:Landroid/view/ActionProvider$VisibilityListener;
if-eqz v0, :store
new-instance v0, Ljava/lang/StringBuilder;
invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
const-string v1, "setVisibilityListener: Setting a new ActionProvider.VisibilityListener when one is already set. Are you reusing this "
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Class;->getSimpleName()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " instance while it is still in use somewhere else?"
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
const-string v2, "ActionProvider"
invoke-static {v2, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I
:store
iput-object p1, p0, Landroid/view/ActionProvider;->mVisibilityListener:Landroid/view/ActionProvider$VisibilityListener;
return-void
.end method

.method public reset()V
.locals 1
const/4 v0, 0
iput-object v0, p0, Landroid/view/ActionProvider;->mVisibilityListener:Landroid/view/ActionProvider$VisibilityListener;
iput-object v0, p0, Landroid/view/ActionProvider;->mSubUiVisibilityListener:Landroid/view/ActionProvider$SubUiVisibilityListener;
return-void
.end method
')!
	for name, method in {
		'VisibilityListener':      'onActionProviderVisibilityChanged'
		'SubUiVisibilityListener': 'onSubUiVisibilityChanged'
	} {
		os.write_file(smali + '/android/view/ActionProvider$' + name + '.smali',
			'.class public interface abstract Landroid/view/ActionProvider$' + name + ';\n.super Ljava/lang/Object;\n' +
				'.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/view/ActionProvider;\n.end annotation\n' +
				'.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x609\nname = "' + name + '"\n.end annotation\n' +
				'.method public abstract ' + method + '(Z)V\n.end method\n')!
	}
	// The measured PopupMenu path needs provider retention and default actions.
	// Native action-view creation, visibility and submenu presentation remain
	// separate backend work; do not replace methods still registered with JNI.
	interface_path := smali + '/android/view/MenuItem.smali'
	os.write_file(interface_path, os.read_file(interface_path)! + r'
.method public abstract setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;
.end method
.method public abstract getActionProvider()Landroid/view/ActionProvider;
.end method
')!
	item_path := smali + '/android/view/VinixMenuItem.smali'
	os.write_file(item_path, os.read_file(item_path)! + r'
.field private vinixActionProvider:Landroid/view/ActionProvider;
.method public setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;
.locals 1
iget-object v0, p0, Landroid/view/VinixMenuItem;->vinixActionProvider:Landroid/view/ActionProvider;
if-eqz v0, :store
invoke-virtual {v0}, Landroid/view/ActionProvider;->reset()V
:store
const/4 v0, 0
iput-object v0, p0, Landroid/view/VinixMenuItem;->action:Landroid/view/View;
iput-object p1, p0, Landroid/view/VinixMenuItem;->vinixActionProvider:Landroid/view/ActionProvider;
return-object p0
.end method
.method public getActionProvider()Landroid/view/ActionProvider;
.locals 1
iget-object v0, p0, Landroid/view/VinixMenuItem;->vinixActionProvider:Landroid/view/ActionProvider;
return-object v0
.end method
')!
	popup_path := smali + '/android/widget/PopupMenu.smali'
	os.write_file(popup_path, framework_replace_method(os.read_file(popup_path)!,
		'vinixDispatchItem(Landroid/view/MenuItem;)Z', r'.method private vinixDispatchItem(Landroid/view/MenuItem;)Z
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
if-eqz v0, :provider
invoke-interface {v0, p1}, Landroid/widget/PopupMenu$OnMenuItemClickListener;->onMenuItemClick(Landroid/view/MenuItem;)Z
move-result v0
if-nez v0, :handled
:provider
invoke-interface {p1}, Landroid/view/MenuItem;->getActionProvider()Landroid/view/ActionProvider;
move-result-object v0
if-eqz v0, :unhandled
invoke-virtual {v0}, Landroid/view/ActionProvider;->onPerformDefaultAction()Z
move-result v0
return v0
:handled
const/4 v0, 1
return v0
:unhandled
const/4 v0, 0
return v0
.end method')!)!
}
