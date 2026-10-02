multi_return_u64_u64 socket__receive_message(i64 fdnum, public__MsgHdr* header, i64 flags) {
	__v_option_u64 __or_opt_0 = socket__iovec_total(header);
	u64 __or_val_1 = {0};
	if (__or_opt_0.ok) {
		__or_val_1 = __or_opt_0.value;
	} else {
		return (multi_return_u64_u64){errno__err, errno__get()};
	}
	u64 total = __or_val_1;
	u64 __if_val_2 = {0};
	if (total < socket__message_max) {
		__if_val_2 = total;
	} else {
		__if_val_2 = socket__message_max;
	}
	u64 size = __if_val_2;
	if (size != 0) {
		__v_option_public__IoVec __or_opt_3 = socket__iovec_from_user((void*)(header->msg_iov), 0);
		public__IoVec __or_val_4 = {0};
		if (__or_opt_3.ok) {
			__or_val_4 = __or_opt_3.value;
		} else {
			return (multi_return_u64_u64){errno__err, errno__get()};
		}
		public__IoVec first = __or_val_4;
		if ((first.iov_len != 0) && !usercopy__writable((u64)(first.iov_base))) {
			return (multi_return_u64_u64){errno__err, errno__efault};
		}
	}
	u8* small = (u8*)(vinix_stack_alloc(socket__small_message));
	{
		memset(small, 0, socket__small_message);
	}
	void* __if_val_5 = {0};
	if (size <= socket__small_message) {
		__if_val_5 = (void*)(&(small)[0]);
	} else {
		__if_val_5 = (void*)(v_malloc(size));
	}
	void* buffer = __if_val_5;
	if (buffer == NULL) {
		return (multi_return_u64_u64){errno__err, errno__enomem};
	}
	public__IoVec vector = (public__IoVec){.iov_base = buffer, .iov_len = size};
	u64 __if_val_6 = {0};
	if (header->msg_control == NULL) {
		__if_val_6 = (u64)(0);
	} else {
		if (header->msg_controllen < socket__control_max) {
			__if_val_6 = header->msg_controllen;
		} else {
			__if_val_6 = socket__control_max;
		}
	}
	u64 control_size = __if_val_6;
	u8* __if_val_7 = {0};
	if (control_size != 0) {
		__if_val_7 = v_malloc(control_size);
	} else {
		__if_val_7 = NULL;
	}
	u8* control = __if_val_7;
	u8* storage = (u8*)(vinix_stack_alloc(socket__sockaddr_max));
	{
		memset(storage, 0xff, socket__sockaddr_max);
	}
	u32 __if_val_8 = {0};
	if (header->msg_name == NULL) {
		__if_val_8 = (u32)(0);
	} else {
		if (header->msg_namelen < socket__sockaddr_max) {
			__if_val_8 = header->msg_namelen;
		} else {
			__if_val_8 = socket__sockaddr_max;
		}
	}
	u32 offered = __if_val_8;
	void* __if_val_9 = {0};
	if (header->msg_name == NULL) {
		__if_val_9 = NULL;
	} else {
		__if_val_9 = (void*)(&(storage)[0]);
	}
	public__MsgHdr kernel_message = (public__MsgHdr){.msg_name = __if_val_9, .msg_namelen = offered, .msg_iov = &vector, .msg_iovlen = 1, .msg_control = (void*)(control), .msg_controllen = control_size};
	public__MsgHdr* message = &kernel_message;
	multi_return_u64_u64 __multi_ret_10 = socket__receive_into(fdnum, message, flags);
	u64 received = __multi_ret_10.arg0;
	u64 err = __multi_ret_10.arg1;
	if (err != 0) {
		multi_return_u64_u64 _t1 = (multi_return_u64_u64){		received, 		err};
		{
			if (control != NULL) {
				{
					v_free(control);
				}
			}
		}
		{
			if (size > socket__small_message) {
				{
					v_free(buffer);
				}
			}
		}
		return _t1;
	}
	u64 __if_val_11 = {0};
	if (received < size) {
		__if_val_11 = received;
	} else {
		__if_val_11 = size;
	}
	u64 left = __if_val_11;
	u64 copied = (u64)(0);
	{
		u64 i = (u64)(0);
		for (; (i < header->msg_iovlen) && (left != 0); i++) {
			__v_option_public__IoVec __or_opt_12 = socket__iovec_from_user((void*)(header->msg_iov), i);
			public__IoVec __or_val_13 = {0};
			if (__or_opt_12.ok) {
				__or_val_13 = __or_opt_12.value;
			} else {
				multi_return_u64_u64 _t2 = (multi_return_u64_u64){				errno__err, 				errno__get()};
				{
					if (control != NULL) {
						{
							v_free(control);
						}
					}
				}
				{
					if (size > socket__small_message) {
						{
							v_free(buffer);
						}
					}
				}
				return _t2;
			}
			public__IoVec iov = __or_val_13;
			u64 __if_val_14 = {0};
			if (iov.iov_len < left) {
				__if_val_14 = iov.iov_len;
			} else {
				__if_val_14 = left;
			}
			u64 amount = __if_val_14;
			if (amount != 0) {
				if (!usercopy__copy_to_user((u64)(iov.iov_base), (void*)((u64)(buffer) + copied), amount)) {
					multi_return_u64_u64 _t3 = (multi_return_u64_u64){					errno__err, 					errno__efault};
					{
						if (control != NULL) {
							{
								v_free(control);
							}
						}
					}
					{
						if (size > socket__small_message) {
							{
								v_free(buffer);
							}
						}
					}
					return _t3;
				}
				copied += amount;
				left -= amount;
			}
		}
	}
	if (header->msg_control != NULL) {
		u64 __if_val_15 = {0};
		if (message->msg_controllen < control_size) {
			__if_val_15 = message->msg_controllen;
		} else {
			__if_val_15 = control_size;
		}
		u64 used = __if_val_15;
		if ((used != 0) && !usercopy__copy_to_user((u64)(header->msg_control), (void*)(control), used)) {
			multi_return_u64_u64 _t4 = (multi_return_u64_u64){			errno__err, 			errno__efault};
			{
				if (control != NULL) {
					{
						v_free(control);
					}
				}
			}
			{
				if (size > socket__small_message) {
					{
						v_free(buffer);
					}
				}
			}
			return _t4;
		}
	}
	header->msg_controllen = message->msg_controllen;
	if ((header->msg_name != NULL) && ((message->msg_namelen != offered) || ((storage)[0] != 0xff) || ((storage)[1] != 0xff))) {
		u32 __if_val_16 = {0};
		if (message->msg_namelen < offered) {
			__if_val_16 = message->msg_namelen;
		} else {
			__if_val_16 = offered;
		}
		u32 named = __if_val_16;
		if ((named != 0) && !usercopy__copy_to_user((u64)(header->msg_name), (void*)(&(storage)[0]), named)) {
			multi_return_u64_u64 _t5 = (multi_return_u64_u64){			errno__err, 			errno__efault};
			{
				if (control != NULL) {
					{
						v_free(control);
					}
				}
			}
			{
				if (size > socket__small_message) {
					{
						v_free(buffer);
					}
				}
			}
			return _t5;
		}
		header->msg_namelen = message->msg_namelen;
	}
	header->msg_flags = message->msg_flags;
	multi_return_u64_u64 _t6 = (multi_return_u64_u64){	received, 	0};
	{
		if (control != NULL) {
			{
				v_free(control);
			}
		}
	}
	{
		if (size > socket__small_message) {
			{
				v_free(buffer);
			}
		}
	}
	return _t6;
	{
		if (control != NULL) {
			{
				v_free(control);
			}
		}
	}
	{
		if (size > socket__small_message) {
			{
				v_free(buffer);
			}
		}
	}
}
