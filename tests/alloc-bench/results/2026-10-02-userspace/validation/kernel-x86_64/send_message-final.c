multi_return_u64_u64 socket__send_message(i64 fdnum, public__MsgHdr* header, i64 flags) {
	if ((header->msg_control == NULL) && (header->msg_controllen != 0)) {
		return (multi_return_u64_u64){errno__err, errno__efault};
	}
	if (header->msg_controllen > socket__control_max) {
		return (multi_return_u64_u64){errno__err, errno__enobufs};
	}
	__v_option_u64 __or_opt_0 = socket__iovec_total(header);
	u64 __or_val_1 = {0};
	if (__or_opt_0.ok) {
		__or_val_1 = __or_opt_0.value;
	} else {
		return (multi_return_u64_u64){errno__err, errno__get()};
	}
	u64 total = __or_val_1;
	if (total > socket__message_max) {
		total = socket__message_max + 1;
	}
	u8* small = (u8*)(vinix_stack_alloc(socket__small_message));
	{
		memset(small, 0, socket__small_message);
	}
	void* __if_val_2 = {0};
	if (total <= socket__small_message) {
		__if_val_2 = (void*)(&(small)[0]);
	} else {
		__if_val_2 = (void*)(v_malloc(total));
	}
	void* buffer = __if_val_2;
	if (buffer == NULL) {
		return (multi_return_u64_u64){errno__err, errno__enomem};
	}
	u64 copied = (u64)(0);
	{
		u64 i = (u64)(0);
		for (; (i < header->msg_iovlen) && (copied < total); i++) {
			__v_option_public__IoVec __or_opt_3 = socket__iovec_from_user((void*)(header->msg_iov), i);
			public__IoVec __or_val_4 = {0};
			if (__or_opt_3.ok) {
				__or_val_4 = __or_opt_3.value;
			} else {
				multi_return_u64_u64 _t1 = (multi_return_u64_u64){				errno__err, 				errno__get()};
				{
					if (total > socket__small_message) {
						{
							v_free(buffer);
						}
					}
				}
				return _t1;
			}
			public__IoVec iov = __or_val_4;
			u64 __if_val_5 = {0};
			if (iov.iov_len < (total - copied)) {
				__if_val_5 = iov.iov_len;
			} else {
				__if_val_5 = total - copied;
			}
			u64 amount = __if_val_5;
			if (amount != 0) {
				if (!usercopy__copy_from_user((void*)((u64)(buffer) + copied), (u64)(iov.iov_base), amount)) {
					multi_return_u64_u64 _t2 = (multi_return_u64_u64){					errno__err, 					errno__efault};
					{
						if (total > socket__small_message) {
							{
								v_free(buffer);
							}
						}
					}
					return _t2;
				}
				copied += amount;
			}
		}
	}
	total = copied;
	u8* storage = (u8*)(vinix_stack_alloc(socket__sockaddr_max));
	{
		memset(storage, 0, socket__sockaddr_max);
	}
	__v_option_voidptr __or_opt_6 = socket__address_from_user(header->msg_name, header->msg_namelen, (void*)(&(storage)[0]));
	void* __or_val_7 = {0};
	if (__or_opt_6.ok) {
		__or_val_7 = __or_opt_6.value;
	} else {
		multi_return_u64_u64 _t3 = (multi_return_u64_u64){		errno__err, 		errno__get()};
		{
			if (total > socket__small_message) {
				{
					v_free(buffer);
				}
			}
		}
		return _t3;
	}
	void* name = __or_val_7;
	if (header->msg_controllen != 0) {
		if (((flags & ~0x4040) != 0) || (header->msg_name != NULL)) {
			multi_return_u64_u64 _t4 = (multi_return_u64_u64){			errno__err, 			errno__eopnotsupp};
			{
				if (total > socket__small_message) {
					{
						v_free(buffer);
					}
				}
			}
			return _t4;
		}
		multi_return_u64_u64 __multi_ret_8 = socket__send_with_control(fdnum, buffer, total, header, flags);
		u64 sent = __multi_ret_8.arg0;
		u64 err = __multi_ret_8.arg1;
		multi_return_u64_u64 _t5 = (multi_return_u64_u64){		sent, 		err};
		{
			if (total > socket__small_message) {
				{
					v_free(buffer);
				}
			}
		}
		return _t5;
	}
	multi_return_u64_u64 __multi_ret_9 = socket__send_from_kernel(fdnum, buffer, total, flags, name, header->msg_namelen);
	u64 sent = __multi_ret_9.arg0;
	u64 err = __multi_ret_9.arg1;
	multi_return_u64_u64 _t6 = (multi_return_u64_u64){	sent, 	err};
	{
		if (total > socket__small_message) {
			{
				v_free(buffer);
			}
		}
	}
	return _t6;
	{
		if (total > socket__small_message) {
			{
				v_free(buffer);
			}
		}
	}
}
