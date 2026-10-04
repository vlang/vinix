multi_return_u64_u64 socket__syscall_getpeername(void* _0, i64 fdnum, void* _addr, u32* addrlen) {
	__v_option_multi_return_file__FDptr_public__Socket __or_opt_1 = socket__socket_from_fdnum(fdnum);
	multi_return_file__FDptr_public__Socket __or_val_2 = {0};
	if (__or_opt_1.ok) {
		__or_val_2 = __or_opt_1.value;
	} else {
		return (multi_return_u64_u64){errno__err, errno__get()};
	}
	multi_return_file__FDptr_public__Socket __multi_ret_0 = __or_val_2;
	file__FD* fd = __multi_ret_0.arg0;
	public__Socket sock = __multi_ret_0.arg1;
	u32 capacity = (u32)(0);
	if (!usercopy__copy_from_user((void*)(&capacity), (u64)((void*)(addrlen)), sizeof(u32))) {
		multi_return_u64_u64 _t1 = (multi_return_u64_u64){		errno__err, 		errno__efault};
		{
			file__FD__unref(fd);
		}
		return _t1;
	}
	u8* storage = (u8*)(vinix_stack_alloc(socket__sockaddr_max));
	{
		memset(storage, 0, socket__sockaddr_max);
	}
	u32 __if_val_3 = {0};
	if (capacity < socket__sockaddr_max) {
		__if_val_3 = capacity;
	} else {
		__if_val_3 = socket__sockaddr_max;
	}
	u32 length = __if_val_3;
	__v_option __or_opt_4 = public__Socket__peername(&(sock), (void*)(fd->handle), (void*)(&(storage)[0]), &length);
	if (!__or_opt_4.ok) {
		multi_return_u64_u64 _t2 = (multi_return_u64_u64){		errno__err, 		errno__get()};
		{
			file__FD__unref(fd);
		}
		return _t2;
	}
	if (!socket__address_to_user(_addr, (u64)((void*)(addrlen)), (void*)(&(storage)[0]), capacity, length)) {
		multi_return_u64_u64 _t3 = (multi_return_u64_u64){		errno__err, 		errno__efault};
		{
			file__FD__unref(fd);
		}
		return _t3;
	}
	multi_return_u64_u64 _t4 = (multi_return_u64_u64){	0, 	0};
	{
		file__FD__unref(fd);
	}
	return _t4;
	{
		file__FD__unref(fd);
	}
}
