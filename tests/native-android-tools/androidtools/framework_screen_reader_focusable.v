// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Screen reader grouping is independent of keyboard/input focus. Retain this
// property even without an accessibility service or node event pipeline in WS.
pub fn framework_screen_reader_focusable(smali string) ! {
 path := smali + '/android/view/View.smali'
 mut text := os.read_file(path)!
 if text.contains('vinixScreenReaderFocusable:Z') {
  return error('View screen reader focus is already extended')
 }
 constructor := '<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'
 start := text.index(' ' + constructor + '\n') or { return error('missing View constructor') }
 end := start + (text[start..].index('.end method') or { return error('unterminated View constructor') })
 assert text[start..end].count('return-void') == 1
 text = text[..start] + text[start..end].replace('return-void',
  'invoke-direct {p0, p1, p2, p3, p4}, Landroid/view/View;->vinixInitScreenReaderFocusable(Landroid/content/Context;Landroid/util/AttributeSet;II)V\nreturn-void') + text[end..]
 text += '\n.field private vinixScreenReaderFocusable:Z\n'
 text = framework_replace_method(text, 'isScreenReaderFocusable()Z',
  '.method public isScreenReaderFocusable()Z\n.locals 1\niget-boolean v0, p0, Landroid/view/View;->vinixScreenReaderFocusable:Z\nreturn v0\n.end method')!
 text = framework_replace_method(text, 'setScreenReaderFocusable(Z)V',
  '.method public setScreenReaderFocusable(Z)V\n.locals 0\niput-boolean p1, p0, Landroid/view/View;->vinixScreenReaderFocusable:Z\nreturn-void\n.end method')!
 // All public constructors delegate here. Match Android's virtual setter
 // dispatch for a present attribute, including theme and both default styles.
 text += '.method private vinixInitScreenReaderFocusable(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n.locals 3\n' +
  'const/4 v0, 1\nnew-array v0, v0, [I\nconst/4 v1, 0\nconst v2, 0x01010574\naput v2, v0, v1\n' +
  'invoke-virtual {p1, p2, v0, p3, p4}, Landroid/content/Context;->obtainStyledAttributes(Landroid/util/AttributeSet;[III)Landroid/content/res/TypedArray;\nmove-result-object v0\n' +
  ':try_start\ninvoke-virtual {v0, v1}, Landroid/content/res/TypedArray;->peekValue(I)Landroid/util/TypedValue;\nmove-result-object v2\nif-eqz v2, :try_end\n' +
  'invoke-virtual {v0, v1, v1}, Landroid/content/res/TypedArray;->getBoolean(IZ)Z\nmove-result v1\n' +
  'invoke-virtual {p0, v1}, Landroid/view/View;->setScreenReaderFocusable(Z)V\n:try_end\n' +
  '.catchall {:try_start .. :try_end} :failed\ninvoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V\nreturn-void\n' +
  ':failed\nmove-exception v1\ninvoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V\nthrow v1\n.end method\n'
 attr := smali + '/android/R$attr.smali'
 mut attrs := os.read_file(attr)!
 if !attrs.contains(' screenReaderFocusable:I') {
  attrs += '\n.field public static final screenReaderFocusable:I = 0x01010574\n'
 }
 os.write_file(path, text)!
 os.write_file(attr, attrs)!
}
