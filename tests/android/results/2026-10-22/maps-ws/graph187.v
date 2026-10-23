// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

__global ws_object_samples i32

// Bounded, read-only instance-field search. Never calls application methods.
fn ws_trace_objects(e voidptr) {
 unsafe {
  selected := C.getenv(c'VINIX_ANDROID_TRACE_OBJECT_CLASS')
  if selected == nil || ws_object_samples >= 6 || pending(e) { return }
  ws_object_samples++
  push_frame(e)
  defer { pop_frame(e) }
  mut values := [4096]voidptr{}
  mut depths := [4096]i32{}
  mut parents := [4096]i32{}
  mut names := [4096][64]char{}
  values[0] = WsRef(slot(e, 21))(e, ws.activity)
  mut used := i32(1)
  visited := new_object(e, c'java/util/IdentityHashMap', c'()V', nil)
  root_args := [Value{l: ws.activity}, Value{l: ws.activity}]!
  obj(e, visited, c'java/util/IdentityHashMap', c'put', c'(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', &root_args[0])
  C.printf(c'ANDROID-WS-OBJECTS-BEGIN sample=%d selected=%s\n', ws_object_samples, selected)
  for at := i32(0); at < used && !pending(e); at++ {
   push_frame(e)
   value := values[at]
   mut owner := WsObjectClass(slot(e, 31))(e, value)
   class_name := obj(e, owner, c'java/lang/Class', c'getName', c'()Ljava/lang/String;', nil)
   if class_name == nil || pending(e) { pop_frame(e); break }
   text := ws_utf(e, class_name)
   matched := text != nil && !pending(e) && C.strcmp(text, selected) == 0
   excluded := text == nil || C.strncmp(text,c'java.',5)==0 || C.strncmp(text,c'android.',8)==0 || C.strncmp(text,c'libcore.',8)==0 || text[0]==`[`
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
   if !excluded && depths[at] < 9 {
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
        if used < 4096 && !pending(e) {
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
