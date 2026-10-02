multi_return_u64_u64 socket__send_with_control(i64 fdnum, void* buffer, u64 total, public__MsgHdr* header, i64 flags) {
	u8* control = v_malloc(header->msg_controllen);
	if (control == NULL) {
		return (multi_return_u64_u64){errno__err, errno__enomem};
	}
	if (!usercopy__copy_from_user((void*)(control), (u64)(header->msg_control), header->msg_controllen)) {
		multi_return_u64_u64 _t1 = (multi_return_u64_u64){		errno__err, 		errno__efault};
		{
			{
				v_free(control);
			}
		}
		return _t1;
	}
	public__MsgHdr* message = (public__MsgHdr*)(vinix_stack_alloc(sizeof(public__MsgHdr)));
	{
		*message = (public__MsgHdr){.msg_control = (void*)(control), .msg_controllen = header->msg_controllen, .msg_iov = NULL};
	}
	__v_option_file__FDptr __or_opt_0 = file__fd_from_fdnum(NULL, fdnum);
	file__FD* __or_val_1 = {0};
	if (__or_opt_0.ok) {
		__or_val_1 = __or_opt_0.value;
	} else {
		multi_return_u64_u64 _t2 = (multi_return_u64_u64){		errno__err, 		errno__get()};
		{
			{
				v_free(control);
			}
		}
		return _t2;
	}
	file__FD* fd = __or_val_1;
	resource__Resource* res = fd->handle->resource;
	if (res->_typ == 882710816) {
		__v_option_Array __or_opt_2 = socket__collect_passed_fds(message);
		Array __or_val_3 = array_new(sizeof(file__FD*), 0, 0);
		if (__or_opt_2.ok) {
			__or_val_3 = __or_opt_2.value;
		} else {
			multi_return_u64_u64 _t3 = (multi_return_u64_u64){			errno__err, 			errno__get()};
			{
				file__FD__unref(fd);
			}
			{
				{
					v_free(control);
				}
			}
			return _t3;
		}
		Array passed_fds = __or_val_3;
		i64 old_flags = fd->handle->flags;
		if ((flags & 0x40) != 0) {
			fd->handle->flags |= resource__o_nonblock;
		}
		__v_option_i64 __or_opt_4 = unix__UnixSocket__write_with_fds((unix__UnixSocket*)(res->_object), (void*)(fd->handle), buffer, total, passed_fds);
		i64 __or_val_5 = {0};
		if (__or_opt_4.ok) {
			__or_val_5 = __or_opt_4.value;
		} else {
			fd->handle->flags = old_flags;
			socket__release_passed_fds(&passed_fds);
			multi_return_u64_u64 _t4 = (multi_return_u64_u64){			errno__err, 			errno__get()};
			{
				file__FD__unref(fd);
			}
			{
				{
					v_free(control);
				}
			}
			return _t4;
		}
		i64 ret = __or_val_5;
		fd->handle->flags = old_flags;
		{
			array__free(&passed_fds);
		}
		multi_return_u64_u64 _t5 = (multi_return_u64_u64){		(u64)(ret), 		0};
		{
			file__FD__unref(fd);
		}
		{
			{
				v_free(control);
			}
		}
		return _t5;
	}
	multi_return_u64_u64 _t6 = (multi_return_u64_u64){	errno__err, 	errno__eopnotsupp};
	{
		file__FD__unref(fd);
	}
	{
		{
			v_free(control);
		}
	}
	return _t6;
	{
		file__FD__unref(fd);
	}
	{
		{
			v_free(control);
		}
	}
}
