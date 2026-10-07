// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
@[has_globals]
module hostbase
#include "hostbase_v_contract.h"
struct C.list_head { mut: next &C.list_head prev &C.list_head }
struct C.rb_node { mut: __rb_parent_color usize rb_left &C.rb_node rb_right &C.rb_node }
struct C.rb_root { mut: rb_node &C.rb_node }
@[typedef] struct C.vmh_const_list_p {}
struct Entry { mut: key i32 order i32 link C.list_head tree C.rb_node }
fn C.INIT_LIST_HEAD(&C.list_head)
fn C.list_sort(voidptr,&C.list_head,fn(voidptr,C.vmh_const_list_p,C.vmh_const_list_p) i32)
fn C.list_empty(&C.list_head) bool
fn C.list_add_tail(&C.list_head,&C.list_head)
fn C.list_del_init(&C.list_head)
fn C.__builtin_offsetof(i32,i32) usize
fn C.rb_parent(&C.rb_node) &C.rb_node
fn C.rb_link_node(&C.rb_node,&C.rb_node,&&C.rb_node)
fn C.rb_insert_color(&C.rb_node,&C.rb_root)
fn C.rb_first(&C.rb_root) &C.rb_node
fn C.rb_next(&C.rb_node) &C.rb_node
fn C.rb_erase(&C.rb_node,&C.rb_root)
fn C.RB_EMPTY_ROOT(&C.rb_root) bool
fn C.vmh_compare_list(voidptr,C.vmh_const_list_p,C.vmh_const_list_p) i32
@[c_extern] __global C.vmh_entry i32
@[c_extern] __global C.link i32
@[c_extern] __global C.tree i32
__global entries [4096]Entry
fn entry_from_link(link &C.list_head) &Entry { unsafe { return &Entry(&u8(link)-C.__builtin_offsetof(C.vmh_entry,C.link)) } }
fn entry_from_tree(tree &C.rb_node) &Entry { unsafe { return &Entry(&u8(tree)-C.__builtin_offsetof(C.vmh_entry,C.tree)) } }
@[export:'vmh_compare_list']
pub fn compare_list(priv voidptr,native_a C.vmh_const_list_p,native_b C.vmh_const_list_p) i32 { unsafe {
 mut a:=&C.list_head(nil);mut b:=&C.list_head(nil);C.memcpy(&a,&native_a,sizeof(a));C.memcpy(&b,&native_b,sizeof(b))
 x:=entry_from_link(a);y:=entry_from_link(b);return i32(x.key>y.key)-i32(x.key<y.key)
} }
@[export:'vmh_list_tests']
pub fn list_tests() { unsafe {
 mut head:=C.list_head{};C.INIT_LIST_HEAD(&head);C.list_sort(nil,&head,C.vmh_compare_list);C.assert(C.list_empty(&head))
 for i:=i32(0);i<4096;i++ { entries[i].key=(i*73)%127;entries[i].order=i;C.list_add_tail(&entries[i].link,&head) }
 C.list_sort(nil,&head,C.vmh_compare_list);mut count:=i32(0);mut previous:=&Entry(nil)
 for link:=head.next;usize(link)!=usize(&head);link=link.next {
  entry:=entry_from_link(link);C.assert(usize(entry.link.next.prev)==usize(&entry.link) && usize(entry.link.prev.next)==usize(&entry.link))
  if previous!=nil { C.assert(previous.key<=entry.key);if previous.key==entry.key { C.assert(previous.order<entry.order) } };previous=entry;count++
 }
 C.assert(count==4096);mut link:=head.next
 for usize(link)!=usize(&head) { next:=link.next;C.list_del_init(link);link=next };C.assert(C.list_empty(&head))
} }
fn tree_height(node &C.rb_node) i32 { unsafe {
 if node==nil { return 1 };if node.rb_left!=nil { C.assert(usize(C.rb_parent(node.rb_left))==usize(node)) }
 if node.rb_right!=nil { C.assert(usize(C.rb_parent(node.rb_right))==usize(node)) };black:=node.__rb_parent_color&1!=0
 if !black { C.assert(node.rb_left==nil || node.rb_left.__rb_parent_color&1!=0);C.assert(node.rb_right==nil || node.rb_right.__rb_parent_color&1!=0) }
 left:=tree_height(node.rb_left);right:=tree_height(node.rb_right);C.assert(left==right);return left+i32(black)
} }
@[export:'vmh_tree_tests']
pub fn tree_tests() { unsafe {
 mut root:=C.rb_root{}
 for i:=i32(0);i<4096;i++ {
  entries[i].key=(i*73)%4096;mut link:=&root.rb_node;mut parent:=&C.rb_node(nil)
  for *link!=nil { parent=*link;other:=entry_from_tree(parent);link=if entries[i].key<other.key { &parent.rb_left } else { &parent.rb_right } }
  C.rb_link_node(&entries[i].tree,parent,link);C.rb_insert_color(&entries[i].tree,&root);C.assert(root.rb_node.__rb_parent_color&1!=0);tree_height(root.rb_node)
 }
 mut expected:=i32(0);for p:=C.rb_first(&root);p!=nil;p=C.rb_next(p) { C.assert(entry_from_tree(p).key==expected);expected++ }
 C.assert(expected==4096);for i:=i32(0);i<4096;i++ { C.rb_erase(&entries[(i*61)%4096].tree,&root);tree_height(root.rb_node) };C.assert(C.RB_EMPTY_ROOT(&root))
} }
