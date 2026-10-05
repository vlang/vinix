multi_return_u64_u64 socket__syscall_sendto(void* _0, i64 fdnum, void* buf, u64 len, i64 flags, void* dest_addr, u32 addrlen) {
	if (!usercopy__user_range((u64)(buf), len)) {
		return (multi_return_u64_u64){errno__err, errno__efault};
	}
	u8* storage = (u8*)(vinix_stack_alloc(socket__sockaddr_max));
	{
		memset(storage, 0, socket__sockaddr_max);
	}
	__v_option_voidptr __or_opt_0 = socket__address_from_user(dest_addr, addrlen, (void*)(&(storage)[0]));
	void* __or_val_1 = {0};
	if (__or_opt_0.ok) {
		__or_val_1 = __or_opt_0.value;
	} else {
		return (multi_return_u64_u64){errno__err, errno__get()};
	}
	void* address = __or_val_1;
	u64 __if_val_2 = {0};
	if (len <= socket__message_max) {
		__if_val_2 = len;
	} else {
		__if_val_2 = socket__message_max + 1;
	}
	u64 size = __if_val_2;
	u8* small = (u8*)(vinix_stack_alloc(socket__small_message));
	{
		memset(small, 0, socket__small_message);
	}
	void* __if_val_3 = {0};
	if (size <= socket__small_message) {
		__if_val_3 = (void*)(&(small)[0]);
	} else {
		__if_val_3 = (void*)(v_malloc(size));
	}
	void* buffer = __if_val_3;
	if (buffer == NULL) {
		return (multi_return_u64_u64){errno__err, errno__enomem};
	}
	u64 done = (u64)(0);
	for (;;) {
		u64 __if_val_4 = {0};
		if ((len - done) < size) {
			__if_val_4 = len - done;
		} else {
			__if_val_4 = size;
		}
		u64 chunk = __if_val_4;
		if ((chunk != 0) && !usercopy__copy_from_user(buffer, (u64)(buf) + done, chunk)) {
			if (done != 0) {
				multi_return_u64_u64 _t1 = (multi_return_u64_u64){				done, 				0};
				{
					if (size > socket__small_message) {
						{
							v_free(buffer);
						}
					}
				}
				return _t1;
			}
			multi_return_u64_u64 _t2 = (multi_return_u64_u64){			errno__err, 			errno__efault};
			{
				if (size > socket__small_message) {
					{
						v_free(buffer);
					}
				}
			}
			return _t2;
		}
		multi_return_u64_u64 __multi_ret_5 = socket__send_from_kernel(fdnum, buffer, chunk, flags, address, addrlen);
		u64 sent = __multi_ret_5.arg0;
		u64 err = __multi_ret_5.arg1;
		if (err != 0) {
			if (done != 0) {
				multi_return_u64_u64 _t3 = (multi_return_u64_u64){				done, 				0};
				{
					if (size > socket__small_message) {
						{
							v_free(buffer);
						}
					}
				}
				return _t3;
			}
			multi_return_u64_u64 _t4 = (multi_return_u64_u64){			sent, 			err};
			{
				if (size > socket__small_message) {
					{
						v_free(buffer);
					}
				}
			}
			return _t4;
		}
		done += sent;
		if ((sent < chunk) || (done >= len)) {
			break;
		}
	}
	multi_return_u64_u64 _t5 = (multi_return_u64_u64){	done, 	0};
	{
		if (size > socket__small_message) {
			{
				v_free(buffer);
			}
		}
	}
	return _t5;
	{
		if (size > socket__small_message) {
			{
				v_free(buffer);
			}
		}
	}
}
