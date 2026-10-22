fs__ProcFSResource* fs__new_procfs_resource(int kind, u32 mode, i64 pid, i64 tid) {
	fs__ProcFSResource* new_resource = (fs__ProcFSResource*)memdup(&(fs__ProcFSResource){.kind = kind, .pid = pid, .tid = tid, .refcount = 1, .box = (resource__Resource*)NULL, .event = (eventstruct__Event){.overflow = NULL}, .text = _str_28, .snapshots = array_new(sizeof(fs__ProcFSSnapshot), 0, 0)}, sizeof(fs__ProcFSResource));
	new_resource->stat.size = 0;
	new_resource->stat.blocks = 0;
	new_resource->stat.blksize = 512;
	new_resource->stat.dev = fs__procfs_dev_id;
	new_resource->stat.ino = fs__procfs_inode_counter++;
	new_resource->stat.mode = mode;
	u64 __if_val_0 = {0};
	if (stat__isdir(mode)) {
		__if_val_0 = (u64)(2);
	} else {
		__if_val_0 = (u64)(1);
	}
	new_resource->stat.nlink = __if_val_0;
	new_resource->stat.atim = time__realtime_clock;
	new_resource->stat.ctim = time__realtime_clock;
	new_resource->stat.mtim = time__realtime_clock;
	new_resource->box = (resource__Resource*)((resource__Resource*)memdup(&(resource__Resource){._typ = 926124183, ._object = new_resource, .stat = (new_resource != NULL ? (*new_resource).stat : (stat__Stat){0}), .refcount = (new_resource != NULL ? (*new_resource).refcount : 0), .l = (new_resource != NULL ? (*new_resource).l : (klock__Lock){0}), .event = (new_resource != NULL ? (*new_resource).event : (eventstruct__Event){.overflow = NULL}), .status = (new_resource != NULL ? (*new_resource).status : 0), .can_mmap = (new_resource != NULL ? (*new_resource).can_mmap : false)}, sizeof(resource__Resource)));
	return new_resource;
}

__v_option fs__ProcFSResource__unref(fs__ProcFSResource* this, void* _handle) {
	if ((_handle != NULL) && (this->snapshots.len > 0)) {
		klock__Lock__acquire(&this->l);
		i64 v_index = fs__ProcFSResource__snapshot_index(this, _handle);
		if (v_index >= 0) {
			{
				string__free(&((*((fs__ProcFSSnapshot*)((this->snapshots).data) + (v_index)))).text);
			}
			array_delete(&this->snapshots, v_index);
		}
		klock__Lock__release(&this->l);
	}
	if (!katomic__dec_T_v_int(&this->refcount)) {
		{
			string__free(&this->text);
			array__free(&this->snapshots);
		}
		fs__free_after_grace((void*)(this->box));
		fs__free_after_grace((void*)(this));
	}
	return (__v_option){.ok = true};
}

void fs__drop_procfs_directory(fs__VFSNode* parent, fs__VFSNode* child) {
	fs__VFSNode* node = child;
	if (node->removed) {
		return;
	}
	node->removed = true;
	if (node->children != NULL) {
		Array children = array_new(		sizeof(fs__VFSNode*), 0, node->children->data->count);
		for (int __mi_1 = 0; __mi_1 < (		node->children)->data->key_values.len; __mi_1++) {
			if ((		node->children)->data->key_values.all_deleted && (		node->children)->data->key_values.all_deleted[__mi_1]) continue;
			string __for_idx_0 = *(string*)((		node->children)->data->key_values.keys + __mi_1 * (		node->children)->data->key_values.key_bytes);
			fs__VFSNode* entry = *(fs__VFSNode**)((		node->children)->data->key_values.values + __mi_1 * (		node->children)->data->key_values.value_bytes);
			if ((entry != NULL) && !string__eq(entry->name, _str_2) && !string__eq(entry->name, _str_523)) {
				fs__VFSNode* __arr_val_0 = entry;
				array_push(&children, &__arr_val_0);
			}
		}
		{
			i64 __for_idx_1 = 0;
			for (; __for_idx_1 < children.len; __for_idx_1++) {
				fs__VFSNode* entry = *(fs__VFSNode**)(array_get(children, __for_idx_1));
				fs__drop_procfs_directory(node, entry);
			}
		}
		{
			array__free(&children);
		}
	}
	node->magic_target = NULL;
	string __map_key_2 = node->name;
	map__delete(parent->children, &__map_key_2);
	{
		if ((*((parent->resource->_typ == 328305974) && (parent->resource->_object != NULL) ? &((ans__AnsBlock*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1558573649) && (parent->resource->_object != NULL) ? &((ans__AnsDataResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1348651705) && (parent->resource->_object != NULL) ? &((ans__AnsRootResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1839172749) && (parent->resource->_object != NULL) ? &((backlight__Backlight*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1647416149) && (parent->resource->_object != NULL) ? &((console__Console*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1964297217) && (parent->resource->_object != NULL) ? &((drm__DrmNode*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1717139030) && (parent->resource->_object != NULL) ? &((drm__GemPrimeResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 688955889) && (parent->resource->_object != NULL) ? &((drm__SyncFileResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 71091699) && (parent->resource->_object != NULL) ? &((ext2__EXT2Resource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 973160833) && (parent->resource->_object != NULL) ? &((fbdev__FramebufferNode*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1646654611) && (parent->resource->_object != NULL) ? &((file__EpollResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1760574647) && (parent->resource->_object != NULL) ? &((file__EventFD*)(parent->resource->_object))->stat : ((parent->resource->_typ == 879895653) && (parent->resource->_object != NULL) ? &((file__MemoryPressureFile*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1063122174) && (parent->resource->_object != NULL) ? &((file__TimerFD*)(parent->resource->_object))->stat : ((parent->resource->_typ == 388857941) && (parent->resource->_object != NULL) ? &((fs__CGroupPressureFile*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1489822964) && (parent->resource->_object != NULL) ? &((fs__CGroupResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 443374827) && (parent->resource->_object != NULL) ? &((fs__DevTmpFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1683867766) && (parent->resource->_object != NULL) ? &((fs__INotify*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1213279157) && (parent->resource->_object != NULL) ? &((fs__LogicalVolume*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1440549087) && (parent->resource->_object != NULL) ? &((fs__MknodDeviceResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 366843280) && (parent->resource->_object != NULL) ? &((fs__NsFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 926124183) && (parent->resource->_object != NULL) ? &((fs__ProcFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1744180866) && (parent->resource->_object != NULL) ? &((fs__SysFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 17959826) && (parent->resource->_object != NULL) ? &((fs__TmpFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 289892784) && (parent->resource->_object != NULL) ? &((inet__InetSocket*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1680104024) && (parent->resource->_object != NULL) ? &((netlink__NetlinkSocket*)(parent->resource->_object))->stat : ((parent->resource->_typ == 38933743) && (parent->resource->_object != NULL) ? &((oss__OssDevice*)(parent->resource->_object))->stat : ((parent->resource->_typ == 997390160) && (parent->resource->_object != NULL) ? &((oss__OssMixerDevice*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1253457481) && (parent->resource->_object != NULL) ? &((pipe__Pipe*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1875827954) && (parent->resource->_object != NULL) ? &((pointerdev__Pointer*)(parent->resource->_object))->stat : ((parent->resource->_typ == 593652764) && (parent->resource->_object != NULL) ? &((proc__PidFile*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1875215591) && (parent->resource->_object != NULL) ? &((procdev__Processes*)(parent->resource->_object))->stat : ((parent->resource->_typ == 405352379) && (parent->resource->_object != NULL) ? &((pty__Ptmx*)(parent->resource->_object))->stat : ((parent->resource->_typ == 208973019) && (parent->resource->_object != NULL) ? &((pty__PtyMaster*)(parent->resource->_object))->stat : ((parent->resource->_typ == 984027288) && (parent->resource->_object != NULL) ? &((pty__PtySlave*)(parent->resource->_object))->stat : ((parent->resource->_typ == 317745476) && (parent->resource->_object != NULL) ? &((random__URandom*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1470987673) && (parent->resource->_object != NULL) ? &((smc__Battery*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1884290070) && (parent->resource->_object != NULL) ? &((streams__DevFull*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1494344494) && (parent->resource->_object != NULL) ? &((streams__DevNull*)(parent->resource->_object))->stat : ((parent->resource->_typ == 687083101) && (parent->resource->_object != NULL) ? &((streams__DevZero*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1996200836) && (parent->resource->_object != NULL) ? &((tty__DevTty*)(parent->resource->_object))->stat : ((parent->resource->_typ == 403823580) && (parent->resource->_object != NULL) ? &((typec__Controller*)(parent->resource->_object))->stat : ((parent->resource->_typ == 882710816) && (parent->resource->_object != NULL) ? &((unix__UnixSocket*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1031062005) && (parent->resource->_object != NULL) ? &((userland__SignalFD*)(parent->resource->_object))->stat : ((parent->resource->_typ == 502479482) && (parent->resource->_object != NULL) ? &((verity__VerifiedDevice*)(parent->resource->_object))->stat : ((parent->resource->_typ == 397730150) && (parent->resource->_object != NULL) ? &((virtio_blk__VirtioBlockDevice*)(parent->resource->_object))->stat : ((parent->resource->_typ == 280060949) && (parent->resource->_object != NULL) ? &((wifi__WifiDevice*)(parent->resource->_object))->stat : &parent->resource->stat)))))))))))))))))))))))))))))))))))))))))))))))).nlink > 2) {
			(*((parent->resource->_typ == 328305974) && (parent->resource->_object != NULL) ? &((ans__AnsBlock*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1558573649) && (parent->resource->_object != NULL) ? &((ans__AnsDataResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1348651705) && (parent->resource->_object != NULL) ? &((ans__AnsRootResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1839172749) && (parent->resource->_object != NULL) ? &((backlight__Backlight*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1647416149) && (parent->resource->_object != NULL) ? &((console__Console*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1964297217) && (parent->resource->_object != NULL) ? &((drm__DrmNode*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1717139030) && (parent->resource->_object != NULL) ? &((drm__GemPrimeResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 688955889) && (parent->resource->_object != NULL) ? &((drm__SyncFileResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 71091699) && (parent->resource->_object != NULL) ? &((ext2__EXT2Resource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 973160833) && (parent->resource->_object != NULL) ? &((fbdev__FramebufferNode*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1646654611) && (parent->resource->_object != NULL) ? &((file__EpollResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1760574647) && (parent->resource->_object != NULL) ? &((file__EventFD*)(parent->resource->_object))->stat : ((parent->resource->_typ == 879895653) && (parent->resource->_object != NULL) ? &((file__MemoryPressureFile*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1063122174) && (parent->resource->_object != NULL) ? &((file__TimerFD*)(parent->resource->_object))->stat : ((parent->resource->_typ == 388857941) && (parent->resource->_object != NULL) ? &((fs__CGroupPressureFile*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1489822964) && (parent->resource->_object != NULL) ? &((fs__CGroupResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 443374827) && (parent->resource->_object != NULL) ? &((fs__DevTmpFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1683867766) && (parent->resource->_object != NULL) ? &((fs__INotify*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1213279157) && (parent->resource->_object != NULL) ? &((fs__LogicalVolume*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1440549087) && (parent->resource->_object != NULL) ? &((fs__MknodDeviceResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 366843280) && (parent->resource->_object != NULL) ? &((fs__NsFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 926124183) && (parent->resource->_object != NULL) ? &((fs__ProcFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1744180866) && (parent->resource->_object != NULL) ? &((fs__SysFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 17959826) && (parent->resource->_object != NULL) ? &((fs__TmpFSResource*)(parent->resource->_object))->stat : ((parent->resource->_typ == 289892784) && (parent->resource->_object != NULL) ? &((inet__InetSocket*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1680104024) && (parent->resource->_object != NULL) ? &((netlink__NetlinkSocket*)(parent->resource->_object))->stat : ((parent->resource->_typ == 38933743) && (parent->resource->_object != NULL) ? &((oss__OssDevice*)(parent->resource->_object))->stat : ((parent->resource->_typ == 997390160) && (parent->resource->_object != NULL) ? &((oss__OssMixerDevice*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1253457481) && (parent->resource->_object != NULL) ? &((pipe__Pipe*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1875827954) && (parent->resource->_object != NULL) ? &((pointerdev__Pointer*)(parent->resource->_object))->stat : ((parent->resource->_typ == 593652764) && (parent->resource->_object != NULL) ? &((proc__PidFile*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1875215591) && (parent->resource->_object != NULL) ? &((procdev__Processes*)(parent->resource->_object))->stat : ((parent->resource->_typ == 405352379) && (parent->resource->_object != NULL) ? &((pty__Ptmx*)(parent->resource->_object))->stat : ((parent->resource->_typ == 208973019) && (parent->resource->_object != NULL) ? &((pty__PtyMaster*)(parent->resource->_object))->stat : ((parent->resource->_typ == 984027288) && (parent->resource->_object != NULL) ? &((pty__PtySlave*)(parent->resource->_object))->stat : ((parent->resource->_typ == 317745476) && (parent->resource->_object != NULL) ? &((random__URandom*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1470987673) && (parent->resource->_object != NULL) ? &((smc__Battery*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1884290070) && (parent->resource->_object != NULL) ? &((streams__DevFull*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1494344494) && (parent->resource->_object != NULL) ? &((streams__DevNull*)(parent->resource->_object))->stat : ((parent->resource->_typ == 687083101) && (parent->resource->_object != NULL) ? &((streams__DevZero*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1996200836) && (parent->resource->_object != NULL) ? &((tty__DevTty*)(parent->resource->_object))->stat : ((parent->resource->_typ == 403823580) && (parent->resource->_object != NULL) ? &((typec__Controller*)(parent->resource->_object))->stat : ((parent->resource->_typ == 882710816) && (parent->resource->_object != NULL) ? &((unix__UnixSocket*)(parent->resource->_object))->stat : ((parent->resource->_typ == 1031062005) && (parent->resource->_object != NULL) ? &((userland__SignalFD*)(parent->resource->_object))->stat : ((parent->resource->_typ == 502479482) && (parent->resource->_object != NULL) ? &((verity__VerifiedDevice*)(parent->resource->_object))->stat : ((parent->resource->_typ == 397730150) && (parent->resource->_object != NULL) ? &((virtio_blk__VirtioBlockDevice*)(parent->resource->_object))->stat : ((parent->resource->_typ == 280060949) && (parent->resource->_object != NULL) ? &((wifi__WifiDevice*)(parent->resource->_object))->stat : &parent->resource->stat)))))))))))))))))))))))))))))))))))))))))))))))).nlink--;
		}
	}
	resource__Resource* node_resource = node->resource;
	if (node_resource != NULL) {
		(*((node_resource->_typ == 328305974) && (node_resource->_object != NULL) ? &((ans__AnsBlock*)(node_resource->_object))->stat : ((node_resource->_typ == 1558573649) && (node_resource->_object != NULL) ? &((ans__AnsDataResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1348651705) && (node_resource->_object != NULL) ? &((ans__AnsRootResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1839172749) && (node_resource->_object != NULL) ? &((backlight__Backlight*)(node_resource->_object))->stat : ((node_resource->_typ == 1647416149) && (node_resource->_object != NULL) ? &((console__Console*)(node_resource->_object))->stat : ((node_resource->_typ == 1964297217) && (node_resource->_object != NULL) ? &((drm__DrmNode*)(node_resource->_object))->stat : ((node_resource->_typ == 1717139030) && (node_resource->_object != NULL) ? &((drm__GemPrimeResource*)(node_resource->_object))->stat : ((node_resource->_typ == 688955889) && (node_resource->_object != NULL) ? &((drm__SyncFileResource*)(node_resource->_object))->stat : ((node_resource->_typ == 71091699) && (node_resource->_object != NULL) ? &((ext2__EXT2Resource*)(node_resource->_object))->stat : ((node_resource->_typ == 973160833) && (node_resource->_object != NULL) ? &((fbdev__FramebufferNode*)(node_resource->_object))->stat : ((node_resource->_typ == 1646654611) && (node_resource->_object != NULL) ? &((file__EpollResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1760574647) && (node_resource->_object != NULL) ? &((file__EventFD*)(node_resource->_object))->stat : ((node_resource->_typ == 879895653) && (node_resource->_object != NULL) ? &((file__MemoryPressureFile*)(node_resource->_object))->stat : ((node_resource->_typ == 1063122174) && (node_resource->_object != NULL) ? &((file__TimerFD*)(node_resource->_object))->stat : ((node_resource->_typ == 388857941) && (node_resource->_object != NULL) ? &((fs__CGroupPressureFile*)(node_resource->_object))->stat : ((node_resource->_typ == 1489822964) && (node_resource->_object != NULL) ? &((fs__CGroupResource*)(node_resource->_object))->stat : ((node_resource->_typ == 443374827) && (node_resource->_object != NULL) ? &((fs__DevTmpFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1683867766) && (node_resource->_object != NULL) ? &((fs__INotify*)(node_resource->_object))->stat : ((node_resource->_typ == 1213279157) && (node_resource->_object != NULL) ? &((fs__LogicalVolume*)(node_resource->_object))->stat : ((node_resource->_typ == 1440549087) && (node_resource->_object != NULL) ? &((fs__MknodDeviceResource*)(node_resource->_object))->stat : ((node_resource->_typ == 366843280) && (node_resource->_object != NULL) ? &((fs__NsFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 926124183) && (node_resource->_object != NULL) ? &((fs__ProcFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1744180866) && (node_resource->_object != NULL) ? &((fs__SysFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 17959826) && (node_resource->_object != NULL) ? &((fs__TmpFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 289892784) && (node_resource->_object != NULL) ? &((inet__InetSocket*)(node_resource->_object))->stat : ((node_resource->_typ == 1680104024) && (node_resource->_object != NULL) ? &((netlink__NetlinkSocket*)(node_resource->_object))->stat : ((node_resource->_typ == 38933743) && (node_resource->_object != NULL) ? &((oss__OssDevice*)(node_resource->_object))->stat : ((node_resource->_typ == 997390160) && (node_resource->_object != NULL) ? &((oss__OssMixerDevice*)(node_resource->_object))->stat : ((node_resource->_typ == 1253457481) && (node_resource->_object != NULL) ? &((pipe__Pipe*)(node_resource->_object))->stat : ((node_resource->_typ == 1875827954) && (node_resource->_object != NULL) ? &((pointerdev__Pointer*)(node_resource->_object))->stat : ((node_resource->_typ == 593652764) && (node_resource->_object != NULL) ? &((proc__PidFile*)(node_resource->_object))->stat : ((node_resource->_typ == 1875215591) && (node_resource->_object != NULL) ? &((procdev__Processes*)(node_resource->_object))->stat : ((node_resource->_typ == 405352379) && (node_resource->_object != NULL) ? &((pty__Ptmx*)(node_resource->_object))->stat : ((node_resource->_typ == 208973019) && (node_resource->_object != NULL) ? &((pty__PtyMaster*)(node_resource->_object))->stat : ((node_resource->_typ == 984027288) && (node_resource->_object != NULL) ? &((pty__PtySlave*)(node_resource->_object))->stat : ((node_resource->_typ == 317745476) && (node_resource->_object != NULL) ? &((random__URandom*)(node_resource->_object))->stat : ((node_resource->_typ == 1470987673) && (node_resource->_object != NULL) ? &((smc__Battery*)(node_resource->_object))->stat : ((node_resource->_typ == 1884290070) && (node_resource->_object != NULL) ? &((streams__DevFull*)(node_resource->_object))->stat : ((node_resource->_typ == 1494344494) && (node_resource->_object != NULL) ? &((streams__DevNull*)(node_resource->_object))->stat : ((node_resource->_typ == 687083101) && (node_resource->_object != NULL) ? &((streams__DevZero*)(node_resource->_object))->stat : ((node_resource->_typ == 1996200836) && (node_resource->_object != NULL) ? &((tty__DevTty*)(node_resource->_object))->stat : ((node_resource->_typ == 403823580) && (node_resource->_object != NULL) ? &((typec__Controller*)(node_resource->_object))->stat : ((node_resource->_typ == 882710816) && (node_resource->_object != NULL) ? &((unix__UnixSocket*)(node_resource->_object))->stat : ((node_resource->_typ == 1031062005) && (node_resource->_object != NULL) ? &((userland__SignalFD*)(node_resource->_object))->stat : ((node_resource->_typ == 502479482) && (node_resource->_object != NULL) ? &((verity__VerifiedDevice*)(node_resource->_object))->stat : ((node_resource->_typ == 397730150) && (node_resource->_object != NULL) ? &((virtio_blk__VirtioBlockDevice*)(node_resource->_object))->stat : ((node_resource->_typ == 280060949) && (node_resource->_object != NULL) ? &((wifi__WifiDevice*)(node_resource->_object))->stat : &node_resource->stat)))))))))))))))))))))))))))))))))))))))))))))))).nlink = 0;
		node->directory_resource = true;
		fs__orphan_node(node, (*((node_resource->_typ == 328305974) && (node_resource->_object != NULL) ? &((ans__AnsBlock*)(node_resource->_object))->stat : ((node_resource->_typ == 1558573649) && (node_resource->_object != NULL) ? &((ans__AnsDataResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1348651705) && (node_resource->_object != NULL) ? &((ans__AnsRootResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1839172749) && (node_resource->_object != NULL) ? &((backlight__Backlight*)(node_resource->_object))->stat : ((node_resource->_typ == 1647416149) && (node_resource->_object != NULL) ? &((console__Console*)(node_resource->_object))->stat : ((node_resource->_typ == 1964297217) && (node_resource->_object != NULL) ? &((drm__DrmNode*)(node_resource->_object))->stat : ((node_resource->_typ == 1717139030) && (node_resource->_object != NULL) ? &((drm__GemPrimeResource*)(node_resource->_object))->stat : ((node_resource->_typ == 688955889) && (node_resource->_object != NULL) ? &((drm__SyncFileResource*)(node_resource->_object))->stat : ((node_resource->_typ == 71091699) && (node_resource->_object != NULL) ? &((ext2__EXT2Resource*)(node_resource->_object))->stat : ((node_resource->_typ == 973160833) && (node_resource->_object != NULL) ? &((fbdev__FramebufferNode*)(node_resource->_object))->stat : ((node_resource->_typ == 1646654611) && (node_resource->_object != NULL) ? &((file__EpollResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1760574647) && (node_resource->_object != NULL) ? &((file__EventFD*)(node_resource->_object))->stat : ((node_resource->_typ == 879895653) && (node_resource->_object != NULL) ? &((file__MemoryPressureFile*)(node_resource->_object))->stat : ((node_resource->_typ == 1063122174) && (node_resource->_object != NULL) ? &((file__TimerFD*)(node_resource->_object))->stat : ((node_resource->_typ == 388857941) && (node_resource->_object != NULL) ? &((fs__CGroupPressureFile*)(node_resource->_object))->stat : ((node_resource->_typ == 1489822964) && (node_resource->_object != NULL) ? &((fs__CGroupResource*)(node_resource->_object))->stat : ((node_resource->_typ == 443374827) && (node_resource->_object != NULL) ? &((fs__DevTmpFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1683867766) && (node_resource->_object != NULL) ? &((fs__INotify*)(node_resource->_object))->stat : ((node_resource->_typ == 1213279157) && (node_resource->_object != NULL) ? &((fs__LogicalVolume*)(node_resource->_object))->stat : ((node_resource->_typ == 1440549087) && (node_resource->_object != NULL) ? &((fs__MknodDeviceResource*)(node_resource->_object))->stat : ((node_resource->_typ == 366843280) && (node_resource->_object != NULL) ? &((fs__NsFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 926124183) && (node_resource->_object != NULL) ? &((fs__ProcFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 1744180866) && (node_resource->_object != NULL) ? &((fs__SysFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 17959826) && (node_resource->_object != NULL) ? &((fs__TmpFSResource*)(node_resource->_object))->stat : ((node_resource->_typ == 289892784) && (node_resource->_object != NULL) ? &((inet__InetSocket*)(node_resource->_object))->stat : ((node_resource->_typ == 1680104024) && (node_resource->_object != NULL) ? &((netlink__NetlinkSocket*)(node_resource->_object))->stat : ((node_resource->_typ == 38933743) && (node_resource->_object != NULL) ? &((oss__OssDevice*)(node_resource->_object))->stat : ((node_resource->_typ == 997390160) && (node_resource->_object != NULL) ? &((oss__OssMixerDevice*)(node_resource->_object))->stat : ((node_resource->_typ == 1253457481) && (node_resource->_object != NULL) ? &((pipe__Pipe*)(node_resource->_object))->stat : ((node_resource->_typ == 1875827954) && (node_resource->_object != NULL) ? &((pointerdev__Pointer*)(node_resource->_object))->stat : ((node_resource->_typ == 593652764) && (node_resource->_object != NULL) ? &((proc__PidFile*)(node_resource->_object))->stat : ((node_resource->_typ == 1875215591) && (node_resource->_object != NULL) ? &((procdev__Processes*)(node_resource->_object))->stat : ((node_resource->_typ == 405352379) && (node_resource->_object != NULL) ? &((pty__Ptmx*)(node_resource->_object))->stat : ((node_resource->_typ == 208973019) && (node_resource->_object != NULL) ? &((pty__PtyMaster*)(node_resource->_object))->stat : ((node_resource->_typ == 984027288) && (node_resource->_object != NULL) ? &((pty__PtySlave*)(node_resource->_object))->stat : ((node_resource->_typ == 317745476) && (node_resource->_object != NULL) ? &((random__URandom*)(node_resource->_object))->stat : ((node_resource->_typ == 1470987673) && (node_resource->_object != NULL) ? &((smc__Battery*)(node_resource->_object))->stat : ((node_resource->_typ == 1884290070) && (node_resource->_object != NULL) ? &((streams__DevFull*)(node_resource->_object))->stat : ((node_resource->_typ == 1494344494) && (node_resource->_object != NULL) ? &((streams__DevNull*)(node_resource->_object))->stat : ((node_resource->_typ == 687083101) && (node_resource->_object != NULL) ? &((streams__DevZero*)(node_resource->_object))->stat : ((node_resource->_typ == 1996200836) && (node_resource->_object != NULL) ? &((tty__DevTty*)(node_resource->_object))->stat : ((node_resource->_typ == 403823580) && (node_resource->_object != NULL) ? &((typec__Controller*)(node_resource->_object))->stat : ((node_resource->_typ == 882710816) && (node_resource->_object != NULL) ? &((unix__UnixSocket*)(node_resource->_object))->stat : ((node_resource->_typ == 1031062005) && (node_resource->_object != NULL) ? &((userland__SignalFD*)(node_resource->_object))->stat : ((node_resource->_typ == 502479482) && (node_resource->_object != NULL) ? &((verity__VerifiedDevice*)(node_resource->_object))->stat : ((node_resource->_typ == 397730150) && (node_resource->_object != NULL) ? &((virtio_blk__VirtioBlockDevice*)(node_resource->_object))->stat : ((node_resource->_typ == 280060949) && (node_resource->_object != NULL) ? &((wifi__WifiDevice*)(node_resource->_object))->stat : &node_resource->stat)))))))))))))))))))))))))))))))))))))))))))))))).mode);
	}
}

void fs__procfs_lookup_refresh_locked(fs__VFSNode* node, string name) {
	if (fs__procfs_root == 0 || (node == NULL) || node->removed || (node->resource == NULL) || (node->children == NULL) || !fs__is_procfs_resource(node->resource)) {
		return;
	}
	fs__ProcFSResource* directory = (fs__ProcFSResource*)(node->resource->_object);
	if ((directory->pid == 0) && (((void*)(node) == (void*)(fs__procfs_root)) || (directory->view != NULL)) && (name.len > 0) && (string__at(name, 0) >= '0') && (string__at(name, 0) <= '9') && ({string __map_key_0 = name;
	map__exists(node->children, &__map_key_0);})) {
		fs__VFSNode* child = ({string __map_key_1 = name;
		fs__VFSNode* __map_zero_2 = NULL;
		*(fs__VFSNode**)(map__get(node->children, &__map_key_1, &__map_zero_2));});
		if ((child != NULL) && fs__is_procfs_resource(child->resource)) {
			fs__ProcFSResource* process = (fs__ProcFSResource*)(child->resource->_object);
			if ((process->kind == fs__ProcFSKind__directory) && (process->pid > 0) && (process->tid == 0) && !proc__task_attached(process->pid, process->pid)) {
				fs__drop_procfs_directory(node, child);
			}
		}
		return;
	}
	if ((directory->pid != 0) && (directory->tid == 0) && string__eq(node->name, _str_778) && ({string __map_key_3 = name;
	map__exists(node->children, &__map_key_3);})) {
		fs__VFSNode* child = ({string __map_key_4 = name;
		fs__VFSNode* __map_zero_5 = NULL;
		*(fs__VFSNode**)(map__get(node->children, &__map_key_4, &__map_zero_5));});
		if ((child != NULL) && fs__is_procfs_resource(child->resource)) {
			fs__ProcFSResource* task = (fs__ProcFSResource*)(child->resource->_object);
			if ((task->kind == fs__ProcFSKind__directory) && (task->pid == directory->pid) && (task->tid > 0) && !proc__task_attached(task->pid, task->tid)) {
				fs__drop_procfs_directory(node, child);
			}
		}
		return;
	}
	if ((directory->pid != 0) && (string__eq(node->name, _str_558) || string__eq(node->name, _str_779))) {
		fs__procfs_refresh_named_locked(node, _str_28);
		return;
	}
	string __map_key_6 = name;
	if (!map__exists(node->children, &__map_key_6)) {
		fs__procfs_refresh_named_locked(node, name);
	}
	if ((directory->pid != 0) && (string__eq(name, _str_555) || string__eq(name, _str_556) || string__eq(name, _str_557)) && ({string __map_key_7 = name;
	map__exists(node->children, &__map_key_7);})) {
		fs__VFSNode* link = ({string __map_key_8 = name;
		fs__VFSNode* __map_zero_9 = NULL;
		*(fs__VFSNode**)(map__get(node->children, &__map_key_8, &__map_zero_9));});
		if (string__eq(name, _str_555)) {
			link->magic_target = fs__process_exe_node(directory->pid);
			fs__set_link_text(link, fs__exe_link_text(directory->pid, link->magic_target));
		} else if (string__eq(name, _str_556)) {
			link->magic_target = fs__process_cwd_node(directory->pid);
			if (link->magic_target != NULL) {
				fs__set_link_text(link, fs__pathname(link->magic_target));
			}
		} else {
			link->magic_target = fs__process_root_node(directory->pid);
			if (link->magic_target != NULL) {
				fs__set_link_text(link, fs__pathname(link->magic_target));
			}
		}
	}
}

void fs__procfs_refresh_named_locked(fs__VFSNode* node, string name) {
	if (fs__procfs_root == 0 || (node == NULL)) {
		return;
	}
	fs__VFSNode* target = node;
	if ((target->resource == NULL) || !stat__isdir((*((target->resource->_typ == 328305974) && (target->resource->_object != NULL) ? &((ans__AnsBlock*)(target->resource->_object))->stat : ((target->resource->_typ == 1558573649) && (target->resource->_object != NULL) ? &((ans__AnsDataResource*)(target->resource->_object))->stat : ((target->resource->_typ == 1348651705) && (target->resource->_object != NULL) ? &((ans__AnsRootResource*)(target->resource->_object))->stat : ((target->resource->_typ == 1839172749) && (target->resource->_object != NULL) ? &((backlight__Backlight*)(target->resource->_object))->stat : ((target->resource->_typ == 1647416149) && (target->resource->_object != NULL) ? &((console__Console*)(target->resource->_object))->stat : ((target->resource->_typ == 1964297217) && (target->resource->_object != NULL) ? &((drm__DrmNode*)(target->resource->_object))->stat : ((target->resource->_typ == 1717139030) && (target->resource->_object != NULL) ? &((drm__GemPrimeResource*)(target->resource->_object))->stat : ((target->resource->_typ == 688955889) && (target->resource->_object != NULL) ? &((drm__SyncFileResource*)(target->resource->_object))->stat : ((target->resource->_typ == 71091699) && (target->resource->_object != NULL) ? &((ext2__EXT2Resource*)(target->resource->_object))->stat : ((target->resource->_typ == 973160833) && (target->resource->_object != NULL) ? &((fbdev__FramebufferNode*)(target->resource->_object))->stat : ((target->resource->_typ == 1646654611) && (target->resource->_object != NULL) ? &((file__EpollResource*)(target->resource->_object))->stat : ((target->resource->_typ == 1760574647) && (target->resource->_object != NULL) ? &((file__EventFD*)(target->resource->_object))->stat : ((target->resource->_typ == 879895653) && (target->resource->_object != NULL) ? &((file__MemoryPressureFile*)(target->resource->_object))->stat : ((target->resource->_typ == 1063122174) && (target->resource->_object != NULL) ? &((file__TimerFD*)(target->resource->_object))->stat : ((target->resource->_typ == 388857941) && (target->resource->_object != NULL) ? &((fs__CGroupPressureFile*)(target->resource->_object))->stat : ((target->resource->_typ == 1489822964) && (target->resource->_object != NULL) ? &((fs__CGroupResource*)(target->resource->_object))->stat : ((target->resource->_typ == 443374827) && (target->resource->_object != NULL) ? &((fs__DevTmpFSResource*)(target->resource->_object))->stat : ((target->resource->_typ == 1683867766) && (target->resource->_object != NULL) ? &((fs__INotify*)(target->resource->_object))->stat : ((target->resource->_typ == 1213279157) && (target->resource->_object != NULL) ? &((fs__LogicalVolume*)(target->resource->_object))->stat : ((target->resource->_typ == 1440549087) && (target->resource->_object != NULL) ? &((fs__MknodDeviceResource*)(target->resource->_object))->stat : ((target->resource->_typ == 366843280) && (target->resource->_object != NULL) ? &((fs__NsFSResource*)(target->resource->_object))->stat : ((target->resource->_typ == 926124183) && (target->resource->_object != NULL) ? &((fs__ProcFSResource*)(target->resource->_object))->stat : ((target->resource->_typ == 1744180866) && (target->resource->_object != NULL) ? &((fs__SysFSResource*)(target->resource->_object))->stat : ((target->resource->_typ == 17959826) && (target->resource->_object != NULL) ? &((fs__TmpFSResource*)(target->resource->_object))->stat : ((target->resource->_typ == 289892784) && (target->resource->_object != NULL) ? &((inet__InetSocket*)(target->resource->_object))->stat : ((target->resource->_typ == 1680104024) && (target->resource->_object != NULL) ? &((netlink__NetlinkSocket*)(target->resource->_object))->stat : ((target->resource->_typ == 38933743) && (target->resource->_object != NULL) ? &((oss__OssDevice*)(target->resource->_object))->stat : ((target->resource->_typ == 997390160) && (target->resource->_object != NULL) ? &((oss__OssMixerDevice*)(target->resource->_object))->stat : ((target->resource->_typ == 1253457481) && (target->resource->_object != NULL) ? &((pipe__Pipe*)(target->resource->_object))->stat : ((target->resource->_typ == 1875827954) && (target->resource->_object != NULL) ? &((pointerdev__Pointer*)(target->resource->_object))->stat : ((target->resource->_typ == 593652764) && (target->resource->_object != NULL) ? &((proc__PidFile*)(target->resource->_object))->stat : ((target->resource->_typ == 1875215591) && (target->resource->_object != NULL) ? &((procdev__Processes*)(target->resource->_object))->stat : ((target->resource->_typ == 405352379) && (target->resource->_object != NULL) ? &((pty__Ptmx*)(target->resource->_object))->stat : ((target->resource->_typ == 208973019) && (target->resource->_object != NULL) ? &((pty__PtyMaster*)(target->resource->_object))->stat : ((target->resource->_typ == 984027288) && (target->resource->_object != NULL) ? &((pty__PtySlave*)(target->resource->_object))->stat : ((target->resource->_typ == 317745476) && (target->resource->_object != NULL) ? &((random__URandom*)(target->resource->_object))->stat : ((target->resource->_typ == 1470987673) && (target->resource->_object != NULL) ? &((smc__Battery*)(target->resource->_object))->stat : ((target->resource->_typ == 1884290070) && (target->resource->_object != NULL) ? &((streams__DevFull*)(target->resource->_object))->stat : ((target->resource->_typ == 1494344494) && (target->resource->_object != NULL) ? &((streams__DevNull*)(target->resource->_object))->stat : ((target->resource->_typ == 687083101) && (target->resource->_object != NULL) ? &((streams__DevZero*)(target->resource->_object))->stat : ((target->resource->_typ == 1996200836) && (target->resource->_object != NULL) ? &((tty__DevTty*)(target->resource->_object))->stat : ((target->resource->_typ == 403823580) && (target->resource->_object != NULL) ? &((typec__Controller*)(target->resource->_object))->stat : ((target->resource->_typ == 882710816) && (target->resource->_object != NULL) ? &((unix__UnixSocket*)(target->resource->_object))->stat : ((target->resource->_typ == 1031062005) && (target->resource->_object != NULL) ? &((userland__SignalFD*)(target->resource->_object))->stat : ((target->resource->_typ == 502479482) && (target->resource->_object != NULL) ? &((verity__VerifiedDevice*)(target->resource->_object))->stat : ((target->resource->_typ == 397730150) && (target->resource->_object != NULL) ? &((virtio_blk__VirtioBlockDevice*)(target->resource->_object))->stat : ((target->resource->_typ == 280060949) && (target->resource->_object != NULL) ? &((wifi__WifiDevice*)(target->resource->_object))->stat : &target->resource->stat)))))))))))))))))))))))))))))))))))))))))))))))).mode)) {
		return;
	}
	if (((void*)(target->filesystem) == NULL) || (target->children == NULL)) {
		return;
	}
	if (!fs__is_procfs_resource(target->resource)) {
		return;
	}
	fs__ProcFSResource* directory = (fs__ProcFSResource*)(target->resource->_object);
	if (target->removed) {
		return;
	}
	if (directory->lazy && !directory->populated) {
		if (name.len > 0) {
			fs__add_process_entry(target, directory->pid, name, directory->tid == 0);
			return;
		}
		directory->populated = true;
		if (directory->tid == 0) {
			fs__populate_process_directory(target, directory->pid);
		} else {
			fs__add_process_entries(target, directory->pid);
		}
		return;
	}
	if (((void*)(target) == (void*)(fs__procfs_root)) || ((directory->view != NULL) && (directory->pid == 0))) {
		fs__refresh_process_directories(target, directory->view);
	} else if ((directory->tid == 0) && (directory->pid != 0)) {
		if (string__eq(target->name, _str_778)) {
			fs__refresh_thread_directories(target, directory->pid);
		} else if (string__eq(target->name, _str_558)) {
			fs__refresh_fd_directory(target, directory->pid);
		} else if (string__eq(target->name, _str_779)) {
			fs__refresh_ns_directory(target, directory->pid);
		}
	}
}

void fs__prune_directories(fs__VFSNode* parent, Array live) {
	Array stale = array_new(	sizeof(fs__VFSNode*), 0, 0);
	for (int __mi_1 = 0; __mi_1 < (	parent->children)->data->key_values.len; __mi_1++) {
		if ((	parent->children)->data->key_values.all_deleted && (	parent->children)->data->key_values.all_deleted[__mi_1]) continue;
		string __for_idx_0 = *(string*)((	parent->children)->data->key_values.keys + __mi_1 * (	parent->children)->data->key_values.key_bytes);
		fs__VFSNode* child = *(fs__VFSNode**)((	parent->children)->data->key_values.values + __mi_1 * (	parent->children)->data->key_values.value_bytes);
		if (child == NULL) {
			continue;
		}
		string name = child->name;
		if ((name.len == 0) || (string__at(name, 0) < '0') || (string__at(name, 0) > '9')) {
			continue;
		}
		i64 identifier = 0;
		bool numeric = true;
		{
			i64 __for_idx_0 = 0;
			for (; __for_idx_0 < name.len; __for_idx_0++) {
				u8 digit = string__at(name, __for_idx_0);
				if ((digit < '0') || (digit > '9')) {
					numeric = false;
					break;
				}
				identifier = (identifier * 10) + (i64)(digit - '0');
			}
		}
		if (!numeric) {
			continue;
		}
		bool found = false;
		{
			i64 __for_idx_1 = 0;
			for (; __for_idx_1 < live.len; __for_idx_1++) {
				i64 value = *(i64*)(array_get(live, __for_idx_1));
				if (value == identifier) {
					found = true;
					break;
				}
			}
		}
		if (!found) {
			fs__VFSNode* __arr_val_2 = child;
			array_push(&stale, &__arr_val_2);
		}
	}
	{
		i64 __for_idx_3 = 0;
		for (; __for_idx_3 < stale.len; __for_idx_3++) {
			fs__VFSNode* stale_node = *(fs__VFSNode**)(array_get(stale, __for_idx_3));
			fs__drop_procfs_directory(parent, stale_node);
		}
	}
	{
		{
			array__free(&stale);
		}
	}
}

void fs__orphan_node(fs__VFSNode* node, u32 mode) {
	if (!(stat__isdir(mode) || stat__isreg(mode) || stat__islnk(mode) || stat__issock(mode) || stat__ischr(mode) || stat__isblk(mode) || stat__isifo(mode))) {
		return;
	}
	if (stat__isdir(mode)) {
		fs__overlay_detach_work(node);
	}
	fs__hold_parent(node);
	if (fs__pinned(node)) {
		return;
	}
	if (stat__isdir(mode) && fs__is_cgroup_resource(node->resource)) {
		return;
	}
	node->orphan = true;
	if (katomic__load_T_v_int(&node->handles) == 0) {
		fs__retire_node(node);
	}
}

void fs__hold_parent(fs__VFSNode* node) {
	if ((node->parent != NULL) && ((void*)(node->parent) != (void*)(node)) && katomic__cas_T_u32(&node->parent_held, (u32)(0), (u32)(1))) {
		fs__VFSNode* parent = node->parent;
		katomic__inc_T_v_int(&parent->parent_refs);
	}
}

void fs__free_node(fs__VFSNode* node) {
	if (node->directory_resource || ((node->overlay != NULL) && node->removed)) {
		if (node->children != NULL) {
			for (int __mi_1 = 0; __mi_1 < (			node->children)->data->key_values.len; __mi_1++) {
				if ((			node->children)->data->key_values.all_deleted && (			node->children)->data->key_values.all_deleted[__mi_1]) continue;
				string __for_idx_0 = *(string*)((			node->children)->data->key_values.keys + __mi_1 * (			node->children)->data->key_values.key_bytes);
				fs__VFSNode* dot = *(fs__VFSNode**)((			node->children)->data->key_values.values + __mi_1 * (			node->children)->data->key_values.value_bytes);
				{
					v_free(dot);
				}
			}
			{
				map__free(node->children);
				v_free(node->children);
			}
		}
		if (node->directory_resource) {
			resource__Resource* res = node->resource;
			resource__release_resource(res);
		}
	}
	kbudget__release(node->kernel_charge);
	fs__inotify_forget(node);
	if (node->overlay != NULL) {
		fs__overlay_release_entry(node->overlay);
		{
			array__free(&node->overlay->lowers);
			array__free(&node->overlay->lower_resources);
			v_free(node->overlay);
		}
	}
	{
		string__free(&node->name);
		string__free(&node->symlink_target);
		if (node->parent_held != 0) {
			fs__VFSNode* parent = node->parent;
			katomic__dec_T_v_int(&parent->parent_refs);
		}
		v_free(node);
	}
}

void fs__retire_node(fs__VFSNode* node) {
	if (!katomic__cas_T_u32(&node->retired, (u32)(0), (u32)(1))) {
		return;
	}
	fs__hold_parent(node);
	fs__retire((fs__RetiredItem){.node = node, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
}

void fs__reap_removed(void) {
	u64 now = time__monotonic_ns();
	klock__Lock__acquire(&fs__removed_lock);
	if (((now - fs__removed_last_reap) < fs__removed_reap_interval_ns) || (fs__removed_items.len == 0)) {
		klock__Lock__release(&fs__removed_lock);
		return;
	}
	fs__removed_last_reap = now;
	i64 due = 0;
	while ((due < fs__removed_items.len) && ((now - ((*(fs__RetiredItem*)array_get(fs__removed_items, due))).at) >= fs__removed_grace_ns)) {
		due++;
	}
	if (due == 0) {
		klock__Lock__release(&fs__removed_lock);
		return;
	}
	Array __arr_init_0 = array_new(	sizeof(fs__RetiredItem), due, 0);
	{
		i64 __arr_idx_1 = 0;
		for (; __arr_idx_1 < __arr_init_0.len; __arr_idx_1++) {
			i64 v_index = __arr_idx_1;
			{ Array* _a0 = &__arr_init_0; int _i0 = __arr_idx_1; array__set(_a0, _i0, &(fs__RetiredItem[]){(fs__RetiredItem){.resource = (resource__Resource*)NULL, .node = NULL, .overlay_backing = NULL, .bytes = NULL, .text = (string){.str = 0}, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0), .charge = (kbudget__Charge){.kind = kbudget__Kind__file}}}); }
		}
	}
	Array items = __arr_init_0;
	{
		memcpy(items.data, fs__removed_items.data, (size_t)(due) * sizeof(fs__RetiredItem));
	}
	array__delete_many(&fs__removed_items, 0, due);
	klock__Lock__release(&fs__removed_lock);
	Array nodes = array_new(	sizeof(void*), 0, due);
	{
		i64 __for_idx_2 = 0;
		for (; __for_idx_2 < items.len; __for_idx_2++) {
			fs__RetiredItem item = *(fs__RetiredItem*)(array_get(items, __for_idx_2));
			if (item.node != NULL) {
				void* __arr_val_3 = (void*)(item.node);
				array_push(&nodes, &__arr_val_3);
			}
		}
	}
	Array running = __new_array_noscan(nodes.len, 0, sizeof(bool));
	proc__mark_programs_in_use(nodes, &running);
	i64 v_index = 0;
	{
		i64 __for_idx_4 = 0;
		for (; __for_idx_4 < items.len; __for_idx_4++) {
			fs__RetiredItem item = *(fs__RetiredItem*)(array_get(items, __for_idx_4));
			if (item.node == NULL) {
				if (item.overlay_backing != NULL) {
					fs__overlay_release_node(item.overlay_backing);
				}
				{
					v_free(item.bytes);
				}
				{
					string__free(&item.text);
				}
				Array lower_nodes = item.lower_nodes;
				Array lower_resources = item.lower_resources;
				{
					array__free(&lower_nodes);
					array__free(&lower_resources);
				}
				if (item.resource != NULL) {
					resource__Resource* res = item.resource;
					resource__release_resource(res);
				}
				kbudget__release(item.charge);
				continue;
			}
			fs__VFSNode* node = item.node;
			bool in_use = (*(bool*)array_get(running, v_index));
			v_index++;
			if (fs__pinned(node)) {
				continue;
			}
			if (katomic__load_T_v_int(&node->overlay_refs) != 0) {
				katomic__store_T_u32(&node->retired, (u32)(0));
				if (katomic__load_T_v_int(&node->overlay_refs) == 0) {
					fs__retire_node(node);
				}
				continue;
			}
			if (katomic__load_T_v_int(&node->handles) != 0) {
				katomic__store_T_u32(&node->retired, (u32)(0));
				if (katomic__load_T_v_int(&node->handles) == 0) {
					fs__retire_node(node);
				}
				continue;
			}
			if (in_use || (katomic__load_T_v_int(&node->parent_refs) != 0)) {
				fs__retire((fs__RetiredItem){.node = node, .directory_busy = item.directory_busy, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
				continue;
			}
			bool directory_busy = node->removed && proc__directory_in_use((void*)(node));
			if (directory_busy) {
				fs__retire((fs__RetiredItem){.node = node, .directory_busy = directory_busy, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
				continue;
			}
			if (item.directory_busy) {
				fs__retire((fs__RetiredItem){.node = node, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
				continue;
			}
			u64 released = katomic__load_T_u64(&node->directory_released);
			u64 checked_at = time__monotonic_ns();
			if (node->removed && ((checked_at < released) || ((checked_at - released) < fs__removed_grace_ns))) {
				fs__retire((fs__RetiredItem){.node = node, .resource = (resource__Resource*)NULL, .overlay_backing = NULL, .bytes = NULL, .charge = (kbudget__Charge){.kind = kbudget__Kind__file}, .text = _str_28, .lower_nodes = array_new(sizeof(fs__VFSNode*), 0, 0), .lower_resources = array_new(sizeof(resource__Resource*), 0, 0)});
				continue;
			}
			fs__free_node(node);
		}
	}
	{
		array__free(&items);
		array__free(&nodes);
		array__free(&running);
	}
}

void file__Handle__unref(file__Handle* this) {
	if (katomic__dec_T_v_int(&this->refcount)) {
		i64 watches = katomic__load_T_v_int(&this->epoll_refs);
		if ((watches != 0) && (katomic__load_T_v_int(&this->refcount) == watches)) {
			file__epoll_forget(this);
		}
		return;
	}
	kbudget__release(this->kernel_charge);
	file__release_description_locks(this, false);
	resource__Resource* res = this->resource;
	__v_option __or_opt_0 = resource__Resource__unref((res), (void*)(this));
	if (!__or_opt_0.ok) {
	}
	if (this->origin_resource != NULL) {
		resource__Resource* origin = this->origin_resource;
		resource__release_resource(origin);
	}
	if ((this->mount_writer != NULL) && (file__mount_writer_released != NULL)) {
		file__mount_writer_released(this->mount_writer);
	}
	if ((this->node != NULL) && (file__handle_released != NULL)) {
		file__handle_released(this->node);
	}
	if ((this->mount_description != NULL) && (file__mount_description_released != NULL)) {
		file__mount_description_released(this->mount_description);
	}
	{
		array__free(&this->dirlist);
		v_free((void*)(this));
	}
}

void resource__retain_resource(resource__Resource* res) {
	katomic__inc_T_v_int(((res->_typ == 328305974) && (res->_object != NULL) ? &((ans__AnsBlock*)(res->_object))->refcount : ((res->_typ == 1558573649) && (res->_object != NULL) ? &((ans__AnsDataResource*)(res->_object))->refcount : ((res->_typ == 1348651705) && (res->_object != NULL) ? &((ans__AnsRootResource*)(res->_object))->refcount : ((res->_typ == 1839172749) && (res->_object != NULL) ? &((backlight__Backlight*)(res->_object))->refcount : ((res->_typ == 1647416149) && (res->_object != NULL) ? &((console__Console*)(res->_object))->refcount : ((res->_typ == 1964297217) && (res->_object != NULL) ? &((drm__DrmNode*)(res->_object))->refcount : ((res->_typ == 1717139030) && (res->_object != NULL) ? &((drm__GemPrimeResource*)(res->_object))->refcount : ((res->_typ == 688955889) && (res->_object != NULL) ? &((drm__SyncFileResource*)(res->_object))->refcount : ((res->_typ == 71091699) && (res->_object != NULL) ? &((ext2__EXT2Resource*)(res->_object))->refcount : ((res->_typ == 973160833) && (res->_object != NULL) ? &((fbdev__FramebufferNode*)(res->_object))->refcount : ((res->_typ == 1646654611) && (res->_object != NULL) ? &((file__EpollResource*)(res->_object))->refcount : ((res->_typ == 1760574647) && (res->_object != NULL) ? &((file__EventFD*)(res->_object))->refcount : ((res->_typ == 879895653) && (res->_object != NULL) ? &((file__MemoryPressureFile*)(res->_object))->refcount : ((res->_typ == 1063122174) && (res->_object != NULL) ? &((file__TimerFD*)(res->_object))->refcount : ((res->_typ == 388857941) && (res->_object != NULL) ? &((fs__CGroupPressureFile*)(res->_object))->refcount : ((res->_typ == 1489822964) && (res->_object != NULL) ? &((fs__CGroupResource*)(res->_object))->refcount : ((res->_typ == 443374827) && (res->_object != NULL) ? &((fs__DevTmpFSResource*)(res->_object))->refcount : ((res->_typ == 1683867766) && (res->_object != NULL) ? &((fs__INotify*)(res->_object))->refcount : ((res->_typ == 1213279157) && (res->_object != NULL) ? &((fs__LogicalVolume*)(res->_object))->refcount : ((res->_typ == 1440549087) && (res->_object != NULL) ? &((fs__MknodDeviceResource*)(res->_object))->refcount : ((res->_typ == 366843280) && (res->_object != NULL) ? &((fs__NsFSResource*)(res->_object))->refcount : ((res->_typ == 926124183) && (res->_object != NULL) ? &((fs__ProcFSResource*)(res->_object))->refcount : ((res->_typ == 1744180866) && (res->_object != NULL) ? &((fs__SysFSResource*)(res->_object))->refcount : ((res->_typ == 17959826) && (res->_object != NULL) ? &((fs__TmpFSResource*)(res->_object))->refcount : ((res->_typ == 289892784) && (res->_object != NULL) ? &((inet__InetSocket*)(res->_object))->refcount : ((res->_typ == 1680104024) && (res->_object != NULL) ? &((netlink__NetlinkSocket*)(res->_object))->refcount : ((res->_typ == 38933743) && (res->_object != NULL) ? &((oss__OssDevice*)(res->_object))->refcount : ((res->_typ == 997390160) && (res->_object != NULL) ? &((oss__OssMixerDevice*)(res->_object))->refcount : ((res->_typ == 1253457481) && (res->_object != NULL) ? &((pipe__Pipe*)(res->_object))->refcount : ((res->_typ == 1875827954) && (res->_object != NULL) ? &((pointerdev__Pointer*)(res->_object))->refcount : ((res->_typ == 593652764) && (res->_object != NULL) ? &((proc__PidFile*)(res->_object))->refcount : ((res->_typ == 1875215591) && (res->_object != NULL) ? &((procdev__Processes*)(res->_object))->refcount : ((res->_typ == 405352379) && (res->_object != NULL) ? &((pty__Ptmx*)(res->_object))->refcount : ((res->_typ == 208973019) && (res->_object != NULL) ? &((pty__PtyMaster*)(res->_object))->refcount : ((res->_typ == 984027288) && (res->_object != NULL) ? &((pty__PtySlave*)(res->_object))->refcount : ((res->_typ == 317745476) && (res->_object != NULL) ? &((random__URandom*)(res->_object))->refcount : ((res->_typ == 1470987673) && (res->_object != NULL) ? &((smc__Battery*)(res->_object))->refcount : ((res->_typ == 1884290070) && (res->_object != NULL) ? &((streams__DevFull*)(res->_object))->refcount : ((res->_typ == 1494344494) && (res->_object != NULL) ? &((streams__DevNull*)(res->_object))->refcount : ((res->_typ == 687083101) && (res->_object != NULL) ? &((streams__DevZero*)(res->_object))->refcount : ((res->_typ == 1996200836) && (res->_object != NULL) ? &((tty__DevTty*)(res->_object))->refcount : ((res->_typ == 403823580) && (res->_object != NULL) ? &((typec__Controller*)(res->_object))->refcount : ((res->_typ == 882710816) && (res->_object != NULL) ? &((unix__UnixSocket*)(res->_object))->refcount : ((res->_typ == 1031062005) && (res->_object != NULL) ? &((userland__SignalFD*)(res->_object))->refcount : ((res->_typ == 502479482) && (res->_object != NULL) ? &((verity__VerifiedDevice*)(res->_object))->refcount : ((res->_typ == 397730150) && (res->_object != NULL) ? &((virtio_blk__VirtioBlockDevice*)(res->_object))->refcount : ((res->_typ == 280060949) && (res->_object != NULL) ? &((wifi__WifiDevice*)(res->_object))->refcount : &res->refcount))))))))))))))))))))))))))))))))))))))))))))))));
}
