// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_accessibility_traversal_resource(output string) ! {
 os.mkdir_all(output + '/res/layout')!
 os.write_file(output + '/res/layout/accessibility_traversal.xml',
  '<View xmlns:android="http://schemas.android.com/apk/res/android" android:layout_width="1dp" android:layout_height="1dp" android:accessibilityTraversalBefore="@+id/traversal_before" android:accessibilityTraversalAfter="@+id/traversal_after"/>')!
}

fn accessibility_traversal_probe() string {
 mut body := ''
 // Constructor delegation must initialize both IDs to NO_ID every time.
 for count in 1 .. 5 {
  args := ['Landroid/content/Context;', 'Landroid/util/AttributeSet;', 'I', 'I'][..count].join('')
  registers := ['v0', 'p0', 'v1', 'v2', 'v2'][..count + 1].join(', ')
  body += 'new-instance v0, Landroid/view/View;\nconst/4 v1, 0\nconst/4 v2, 0\n' +
   'invoke-direct {' + registers + '}, Landroid/view/View;-><init>(' + args + ')V\n' +
   'const/4 v2, -1\n'
  for kind in ['Before', 'After'] {
   body += 'invoke-virtual {v0}, Landroid/view/View;->getAccessibilityTraversal' + kind + '()I\nmove-result v1\nif-ne v1, v2, :bad\n'
  }
 }
 body += 'new-instance v3, Landroid/view/View;\ninvoke-direct {v3, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V\n'
 for kind in ['Before', 'After'] {
  for id in ['0', '0x7f010123', '-2147483648', '-1'] {
   body += 'const v2, ' + id + '\n' +
    'invoke-virtual {v0, v2}, Landroid/view/View;->setAccessibilityTraversal' + kind + '(I)V\n' +
    'invoke-virtual {v0, v2}, Landroid/view/View;->setAccessibilityTraversal' + kind + '(I)V\n' +
    'invoke-virtual {v0}, Landroid/view/View;->getAccessibilityTraversal' + kind + '()I\nmove-result v1\nif-ne v1, v2, :bad\n' +
    'invoke-virtual {v3}, Landroid/view/View;->getAccessibilityTraversal' + kind + '()I\nmove-result v1\nconst/4 v4, -1\nif-ne v1, v4, :bad\n'
  }
 }
 body += 'const v1, 0x7f010124\ninvoke-virtual {v0, v1}, Landroid/view/View;->setAccessibilityTraversalBefore(I)V\n' +
  'const v2, 0x7f010125\ninvoke-virtual {v0, v2}, Landroid/view/View;->setAccessibilityTraversalAfter(I)V\n' +
  'invoke-virtual {v0}, Landroid/view/View;->getAccessibilityTraversalBefore()I\nmove-result v3\nif-ne v1, v3, :bad\n' +
  'invoke-virtual {v0}, Landroid/view/View;->getAccessibilityTraversalAfter()I\nmove-result v3\nif-ne v2, v3, :bad\n' +
  'invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;\nmove-result-object v4\n' +
  'invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;\nmove-result-object v5\n' +
  'const-string v1, "accessibility_traversal"\nconst-string v2, "layout"\ninvoke-virtual {v4, v1, v2, v5}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I\nmove-result v1\nif-eqz v1, :bad\n' +
  'invoke-static {p0}, Landroid/view/LayoutInflater;->from(Landroid/content/Context;)Landroid/view/LayoutInflater;\nmove-result-object v0\nconst/4 v2, 0\n' +
  'invoke-virtual {v0, v1, v2}, Landroid/view/LayoutInflater;->inflate(ILandroid/view/ViewGroup;)Landroid/view/View;\nmove-result-object v0\n'
 for kind in ['Before', 'After'] {
  body += 'const-string v1, "traversal_' + kind.to_lower() + '"\nconst-string v2, "id"\n' +
   'invoke-virtual {v4, v1, v2, v5}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I\nmove-result v1\nif-eqz v1, :bad\n' +
   'invoke-virtual {v0}, Landroid/view/View;->getAccessibilityTraversal' + kind + '()I\nmove-result v2\nif-ne v1, v2, :bad\n'
 }
 body += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-ACCESSIBILITY-TRAVERSAL-PASS constructors default-no-id per-view before-after replacement reset repeated-set unresolved-ids xml-inflation"\n' +
  'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n' +
  ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "accessibility traversal state"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 return method('private static accessibilityTraversal(Landroid/content/Context;)V', body)
}
