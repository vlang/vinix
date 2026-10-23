// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

__global ws_object_samples i32

fn ws_object_selected(text &char, selected &char) bool {
 unsafe {
  mut at := 0
  for _ in 0 .. 16 {
   start := at
   for at < 1024 && selected[at]!=0 && selected[at]!=`,` { at++ }
   length := at-start
   if length>0 && C.strncmp(text,selected+start,usize(length))==0 && C.strlen(text)==usize(length) { return true }
   if selected[at]==0 || at==1024 { break }
   at++
  }
  return false
 }
}

// Bounded, read-only instance-field search. Never calls application methods.
fn ws_trace_objects(e voidptr) {
 unsafe {
  selected := C.getenv(c'VINIX_ANDROID_TRACE_OBJECT_CLASS')
  if selected == nil || ws_object_samples >= 3 || pending(e) { return }
  ws_object_samples++
  push_frame(e)
  defer { pop_frame(e) }
  mut values := [1024]voidptr{}
  mut depths := [1024]i32{}
  mut parents := [1024]i32{}
  mut names := [1024][64]char{}
  window := obj(e,ws.activity,c'android/app/Activity',c'getWindow',c'()Landroid/view/Window;',nil)
  decor := obj(e,window,c'android/view/Window',c'getDecorView',c'()Landroid/view/View;',nil)
  find := [Value{i:26}]!
  view := obj(e,decor,c'android/view/View',c'findViewById',c'(I)Landroid/view/View;',&find[0])
  mut root := get_object(e,view,c'android/view/View',c'on_click_listener',c'Landroid/view/View$OnClickListener;')
  path := c'a.@afql.a.b.d.b.c'
  mut cursor := 0
  if path != nil {
   for hop in 0 .. 16 {
    mut name := [128]char{}
    mut length := 0
    for cursor < 1024 && path[cursor] != 0 && path[cursor] != `.` && length < 127 { name[length]=path[cursor]; length++; cursor++ }
    if length==0 || root==nil || cursor==1024 || length==127 { root=nil; break }
    if name[0] == `@` {
     if !instance_of(e,root,c'java/util/Map') { root=nil; break }
     contents := obj(e,root,c'java/util/Map',c'values',c'()Ljava/util/Collection;',nil)
     entries := obj(e,contents,c'java/util/Collection',c'toArray',c'()[Ljava/lang/Object;',nil)
     total := if pending(e) { i32(0) } else { ws_array_len(e,entries) }
     root=nil
     for n := i32(0); n < total && n < 256 && !pending(e); n++ {
      entry := WsArrayGet(slot(e,173))(e,entries,n)
      if entry==nil { continue }
      cls := WsObjectClass(slot(e,31))(e,entry)
      label := obj(e,cls,c'java/lang/Class',c'getName',c'()Ljava/lang/String;',nil)
      if pending(e) { break }
      text := ws_utf(e,label)
      matches := text != nil && !pending(e) && C.strcmp(text,&name[1])==0
      if text != nil { ws_release(e,label,text) }
      if matches { root=entry; break }
      Drop(slot(e,23))(e,entry)
     }
     if root==nil || pending(e) || path[cursor]==0 { break }
     cursor++
     if hop==15 { root=nil }
     continue
    }
    mut owner := WsObjectClass(slot(e,31))(e,root)
    arg := [Value{l:ws_string(e,&name[0])}]!
    mut field := voidptr(nil)
    for _ in 0 .. 16 {
     if owner==nil || pending(e) { break }
     field=obj(e,owner,c'java/lang/Class',c'getDeclaredField',c'(Ljava/lang/String;)Ljava/lang/reflect/Field;',&arg[0])
     if !pending(e) { break }
     ExceptionClear(slot(e,17))(e)
     owner=obj(e,owner,c'java/lang/Class',c'getSuperclass',c'()Ljava/lang/Class;',nil)
    }
    if field==nil || pending(e) { root=nil; break }
    access := [Value{i:1}]!
    call(e,field,c'java/lang/reflect/Field',c'setAccessible',c'(Z)V',&access[0])
    if pending(e) { break }
    arg_value := [Value{l:root}]!
    root=obj(e,field,c'java/lang/reflect/Field',c'get',c'(Ljava/lang/Object;)Ljava/lang/Object;',&arg_value[0])
    if pending(e) || path[cursor]==0 { break }
    cursor++
    if hop==15 { root=nil }
   }
  }
  if root == nil || pending(e) {
   C.puts(c'ANDROID-WS-OBJECT-ROOT unavailable')
   if pending(e) { ExceptionClear(slot(e,17))(e) }
   return
  }
  values[0] = WsRef(slot(e, 21))(e, root)
  mut used := i32(1)
  visited := new_object(e, c'java/util/IdentityHashMap', c'()V', nil)
  root_args := [Value{l: root}, Value{l: root}]!
  obj(e, visited, c'java/util/IdentityHashMap', c'put', c'(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', &root_args[0])
  C.printf(c'ANDROID-WS-OBJECTS-BEGIN sample=%d selected=%s\n', ws_object_samples, selected)
  for at := i32(0); at < used && !pending(e); at++ {
   push_frame(e)
   value := values[at]
   mut owner := WsObjectClass(slot(e, 31))(e, value)
   class_name := obj(e, owner, c'java/lang/Class', c'getName', c'()Ljava/lang/String;', nil)
   if class_name == nil || pending(e) { pop_frame(e); break }
   text := ws_utf(e, class_name)
   leaf := C.getenv(c'VINIX_ANDROID_TRACE_OBJECT_LEAF_CLASS')
   excluded := text == nil || (leaf != nil && ws_object_selected(text,leaf)) || C.strncmp(text,c'java.',5)==0 || C.strncmp(text,c'android.',8)==0 || C.strncmp(text,c'libcore.',8)==0 || text[0]==`[`
   matched := !excluded
   if matched {
    C.printf(c'ANDROID-WS-OBJECT index=%d depth=%d class=%s\n',at,depths[at],text)
    mut node := at
    for _ in 0 .. 10 {
     if node == 0 { break }
     C.printf(c'ANDROID-WS-OBJECT-PATH index=%d parent=%d field=%s\n',node,parents[node],&names[node][0])
     node = parents[node]
    }
   }
   if text != nil { ws_release(e,class_name,text) }
   if instance_of(e,value,c'java/util/Map') && depths[at] < 6 {
    contents := obj(e,value,c'java/util/Map',c'values',c'()Ljava/util/Collection;',nil)
    entries := obj(e,contents,c'java/util/Collection',c'toArray',c'()[Ljava/lang/Object;',nil)
    length := if pending(e) { i32(0) } else { ws_array_len(e,entries) }
    for i := i32(0); i < length && i < 256 && used < 1024 && !pending(e); i++ {
     entry := WsArrayGet(slot(e,173))(e,entries,i)
     if entry==nil { continue }
     key := [Value{l:entry}]!
     if boolean(e,visited,c'java/util/IdentityHashMap',c'containsKey',c'(Ljava/lang/Object;)Z',&key[0])!=0 { continue }
     insert := [Value{l:entry},Value{l:entry}]!
     obj(e,visited,c'java/util/IdentityHashMap',c'put',c'(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;',&insert[0])
     if pending(e) { break }
     values[used]=WsRef(slot(e,21))(e,entry)
     depths[used]=depths[at]+1
     parents[used]=at
     names[used][0]=`*`
     used++
     Drop(slot(e,23))(e,entry)
    }
   }
   if (!excluded || matched) && depths[at] < 6 {
    for _ in 0 .. 16 {
     if owner == nil || pending(e) { break }
     fields := obj(e,owner,c'java/lang/Class',c'getDeclaredFields',c'()[Ljava/lang/reflect/Field;',nil)
     if pending(e) { ExceptionClear(slot(e,17))(e); break }
     length := ws_array_len(e,fields)
     for i := i32(0); i < length && i < 256 && !pending(e); i++ {
      push_frame(e)
      member := WsArrayGet(slot(e,173))(e,fields,i)
      flags := integer(e,member,c'java/lang/reflect/Field',c'getModifiers',c'()I',nil)
      if flags & 8 == 0 && !pending(e) {
       access := [Value{i:1}]!
       call(e,member,c'java/lang/reflect/Field',c'setAccessible',c'(Z)V',&access[0])
       owner_args := [Value{l:value}]!
       field_value := obj(e,member,c'java/lang/reflect/Field',c'get',c'(Ljava/lang/Object;)Ljava/lang/Object;',&owner_args[0])
       field_name := obj(e,member,c'java/lang/reflect/Field',c'getName',c'()Ljava/lang/String;',nil)
       if field_value != nil && !pending(e) {
        if matched {
         simple := instance_of(e,field_value,c'java/lang/Number') || instance_of(e,field_value,c'java/lang/Boolean') || instance_of(e,field_value,c'java/lang/String')
         mut description := voidptr(nil)
         if simple {
          arg := [Value{l:field_value}]!
          description = static_obj(e,c'java/lang/String',c'valueOf',c'(Ljava/lang/Object;)Ljava/lang/String;',&arg[0])
         } else {
          field_class := WsObjectClass(slot(e,31))(e,field_value)
          description = obj(e,field_class,c'java/lang/Class',c'getName',c'()Ljava/lang/String;',nil)
         }
         if !pending(e) {
          label := ws_utf(e,field_name)
          content := ws_utf(e,description)
          if label != nil && content != nil && !pending(e) { C.printf(c'ANDROID-WS-OBJECT-FIELD name=%.128s value=%.512s\n',label,content) }
          if label != nil { ws_release(e,field_name,label) }
          if content != nil { ws_release(e,description,content) }
         }
        }
        if !excluded && used < 1024 && !pending(e) {
         key := [Value{l:field_value}]!
         if boolean(e,visited,c'java/util/IdentityHashMap',c'containsKey',c'(Ljava/lang/Object;)Z',&key[0])==0 && !pending(e) {
          insert := [Value{l:field_value},Value{l:field_value}]!
          obj(e,visited,c'java/util/IdentityHashMap',c'put',c'(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;',&insert[0])
          label := ws_utf(e,field_name)
          if !pending(e) && label != nil {
           for n := 0; n < 63 && label[n] != 0; n++ { names[used][n]=label[n] }
           values[used]=WsRef(slot(e,21))(e,field_value)
           depths[used]=depths[at]+1
           parents[used]=at
           used++
          }
          if label != nil { ws_release(e,field_name,label) }
         }
        }
       } else if matched && !pending(e) {
        label := ws_utf(e,field_name)
        if label != nil && !pending(e) { C.printf(c'ANDROID-WS-OBJECT-FIELD name=%.128s value=null\n',label) }
        if label != nil { ws_release(e,field_name,label) }
       }
      }
      if pending(e) { ExceptionClear(slot(e,17))(e) }
      pop_frame(e)
     }
     owner = obj(e,owner,c'java/lang/Class',c'getSuperclass',c'()Ljava/lang/Class;',nil)
    }
   }
   if pending(e) { ExceptionClear(slot(e,17))(e) }
   pop_frame(e)
  }
  if pending(e) { C.puts(c'ANDROID-WS-OBJECTS unavailable'); ExceptionClear(slot(e,17))(e) }
  for i := i32(0); i < used; i++ { Drop(slot(e,22))(e,values[i]) }
  C.printf(c'ANDROID-WS-OBJECTS-END visited=%d\n',used)
 }
}
