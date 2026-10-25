// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_child_order(smali string) ! {
	view := smali + '/android/view/View.smali'
	os.write_file(view, framework_replace_method(os.read_file(view)!, 'bringToFront()V', touch_method('public bringToFront()V', '
invoke-virtual {p0}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v0
if-eqz v0, :done
invoke-interface {v0, p0}, Landroid/view/ViewParent;->bringChildToFront(Landroid/view/View;)V
:done
return-void'))!)!
	parent := smali + '/android/view/ViewParent.smali'
	os.write_file(parent, os.read_file(parent)! + '\n.method public abstract bringChildToFront(Landroid/view/View;)V\n.end method\n')!
	root := smali + '/android/view/WindowManagerImpl$WindowViewParent.smali'
	os.write_file(root, os.read_file(root)! + touch_method('public bringChildToFront(Landroid/view/View;)V', 'return-void'))!
	group := smali + '/android/view/ViewGroup.smali'
	// The protected callback is also called directly by subclasses during
	// layout. Its default implementation is independent of the drawing-order
	// flag; custom traversal by the renderer is a separate contract.
	os.write_file(group, framework_replace_method(os.read_file(group)!, 'getChildDrawingOrder(II)I', '.method protected getChildDrawingOrder(II)I\n.locals 0\nreturn p2\n.end method\n')!)!
	// Reorder in place: removeView/addView would detach the child, replace its
	// layout parameters and dispatch hierarchy callbacks. Drawing and touch
	// dispatch both read this same list in their respective traversal orders.
	os.write_file(group, framework_replace_method(os.read_file(group)!, 'bringChildToFront(Landroid/view/View;)V', touch_method('public bringChildToFront(Landroid/view/View;)V', '
invoke-virtual {p0, p1}, Landroid/view/ViewGroup;->indexOfChild(Landroid/view/View;)I
move-result v0
if-ltz v0, :done
iget-object v1, p0, Landroid/view/ViewGroup;->children:Ljava/util/ArrayList;
invoke-virtual {v1, v0}, Ljava/util/ArrayList;->remove(I)Ljava/lang/Object;
invoke-virtual {v1, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
iput-object p0, p1, Landroid/view/View;->parent:Landroid/view/ViewParent;
invoke-virtual {p0}, Landroid/view/View;->requestLayout()V
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void'))!)!
}
