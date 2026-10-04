multi_return_u64_u64 socket__syscall_bind(void* _0, i64 fdnum, void* _addr, u32 addrlen) {
	proc__Thread* current_thread = proc__current_thread();
	proc__Process* process = current_thread->process;
	printf("\n\e[32m%s\e[m: bind(%d, 0x%llx, 0x%llx)\n", process->name.str, (int)(fdnum), _addr, addrlen);
	__v_option_file__FDptr __or_opt_0 = file__fd_from_fdnum(NULL, fdnum);
	file__FD* __or_val_1 = {0};
	if (__or_opt_0.ok) {
		__or_val_1 = __or_opt_0.value;
	} else {
		multi_return_u64_u64 _t1 = (multi_return_u64_u64){		errno__err, 		errno__get()};
		{
			printf("\e[32m%s\e[m: returning\n", process->name.str);
		}
		return _t1;
	}
	file__FD* fd = __or_val_1;
	resource__Resource* res = fd->handle->resource;
	public__Socket* sock = (public__Socket*)NULL;
	if (res->_typ == 882710816) {
		public__Socket __iface_cast_2 = (public__Socket){._typ = 0, ._object = res->_object, .stat = res->stat, .refcount = res->refcount, .l = res->l, .event = res->event, .status = res->status, .can_mmap = res->can_mmap};
		if (res->_typ == 289892784) {
			__iface_cast_2._typ = 289892784;
		}
		if (res->_typ == 1680104024) {
			__iface_cast_2._typ = 1680104024;
		}
		if (res->_typ == 882710816) {
			__iface_cast_2._typ = 882710816;
		}
		if (res->_typ == 421142939) {
			__iface_cast_2._typ = 421142939;
		}
		public__Socket __iface_box_3 = __iface_cast_2;
		sock = (public__Socket*)(memdup(&__iface_box_3, sizeof(public__Socket)));
	} else if (res->_typ == 289892784) {
		public__Socket __iface_cast_4 = (public__Socket){._typ = 0, ._object = res->_object, .stat = res->stat, .refcount = res->refcount, .l = res->l, .event = res->event, .status = res->status, .can_mmap = res->can_mmap};
		if (res->_typ == 289892784) {
			__iface_cast_4._typ = 289892784;
		}
		if (res->_typ == 1680104024) {
			__iface_cast_4._typ = 1680104024;
		}
		if (res->_typ == 882710816) {
			__iface_cast_4._typ = 882710816;
		}
		if (res->_typ == 421142939) {
			__iface_cast_4._typ = 421142939;
		}
		public__Socket __iface_box_5 = __iface_cast_4;
		sock = (public__Socket*)(memdup(&__iface_box_5, sizeof(public__Socket)));
	} else if (res->_typ == 1680104024) {
		public__Socket __iface_cast_6 = (public__Socket){._typ = 0, ._object = res->_object, .stat = res->stat, .refcount = res->refcount, .l = res->l, .event = res->event, .status = res->status, .can_mmap = res->can_mmap};
		if (res->_typ == 289892784) {
			__iface_cast_6._typ = 289892784;
		}
		if (res->_typ == 1680104024) {
			__iface_cast_6._typ = 1680104024;
		}
		if (res->_typ == 882710816) {
			__iface_cast_6._typ = 882710816;
		}
		if (res->_typ == 421142939) {
			__iface_cast_6._typ = 421142939;
		}
		public__Socket __iface_box_7 = __iface_cast_6;
		sock = (public__Socket*)(memdup(&__iface_box_7, sizeof(public__Socket)));
	} else {
		multi_return_u64_u64 _t2 = (multi_return_u64_u64){		errno__err, 		errno__einval};
		{
			file__FD__unref(fd);
		}
		{
			printf("\e[32m%s\e[m: returning\n", process->name.str);
		}
		return _t2;
	}
	if (_addr == NULL) {
		u64 __if_val_8 = {0};
		if (addrlen == 0) {
			__if_val_8 = errno__einval;
		} else {
			__if_val_8 = errno__efault;
		}
		multi_return_u64_u64 _t3 = (multi_return_u64_u64){		errno__err, 		__if_val_8};
		{
			{
				v_free(sock);
			}
		}
		{
			file__FD__unref(fd);
		}
		{
			printf("\e[32m%s\e[m: returning\n", process->name.str);
		}
		return _t3;
	}
	u8* storage = (u8*)(vinix_stack_alloc(socket__sockaddr_max));
	{
		memset(storage, 0, socket__sockaddr_max);
	}
	__v_option_voidptr __or_opt_9 = socket__address_from_user(_addr, addrlen, (void*)(&(storage)[0]));
	void* __or_val_10 = {0};
	if (__or_opt_9.ok) {
		__or_val_10 = __or_opt_9.value;
	} else {
		multi_return_u64_u64 _t4 = (multi_return_u64_u64){		errno__err, 		errno__get()};
		{
			{
				v_free(sock);
			}
		}
		{
			file__FD__unref(fd);
		}
		{
			printf("\e[32m%s\e[m: returning\n", process->name.str);
		}
		return _t4;
	}
	void* address = __or_val_10;
	__v_option __or_opt_11 = public__Socket__bind((sock), (void*)(fd->handle), address, addrlen);
	if (!__or_opt_11.ok) {
		multi_return_u64_u64 _t5 = (multi_return_u64_u64){		errno__err, 		errno__get()};
		{
			{
				v_free(sock);
			}
		}
		{
			file__FD__unref(fd);
		}
		{
			printf("\e[32m%s\e[m: returning\n", process->name.str);
		}
		return _t5;
	}
	multi_return_u64_u64 _t6 = (multi_return_u64_u64){	0, 	0};
	{
		{
			v_free(sock);
		}
	}
	{
		file__FD__unref(fd);
	}
	{
		printf("\e[32m%s\e[m: returning\n", process->name.str);
	}
	return _t6;
	{
		{
			v_free(sock);
		}
	}
	{
		file__FD__unref(fd);
	}
	{
		printf("\e[32m%s\e[m: returning\n", process->name.str);
	}
}
