multi_return_u64_u64 socket__syscall_recvfrom(void* _0, i64 fdnum, void* buf, u64 len, i64 flags, void* src_addr, u32* addrlen) {
	if (!usercopy__user_range((u64)(buf), len) || ((len != 0) && !usercopy__writable((u64)(buf)))) {
		return (multi_return_u64_u64){errno__err, errno__efault};
	}
	bool wants_address = (src_addr != NULL) && (addrlen != NULL);
	u32 capacity = (u32)(0);
	if (wants_address && !usercopy__copy_from_user((void*)(&capacity), (u64)((void*)(addrlen)), sizeof(u32))) {
		return (multi_return_u64_u64){errno__err, errno__efault};
	}
	u8* storage = (u8*)(vinix_stack_alloc(socket__sockaddr_max));
	{
		memset(storage, 0xff, socket__sockaddr_max);
	}
	u32 __if_val_0 = {0};
	if (capacity < socket__sockaddr_max) {
		__if_val_0 = capacity;
	} else {
		__if_val_0 = socket__sockaddr_max;
	}
	u32 offered = __if_val_0;
	u32* length = (u32*)(vinix_stack_alloc(sizeof(u32)));
	{
		*length = offered;
	}
	u64 __if_val_1 = {0};
	if (len < socket__message_max) {
		__if_val_1 = len;
	} else {
		__if_val_1 = socket__message_max;
	}
	u64 size = __if_val_1;
	u8* small = (u8*)(vinix_stack_alloc(socket__small_message));
	{
		memset(small, 0, socket__small_message);
	}
	void* __if_val_2 = {0};
	if (size <= socket__small_message) {
		__if_val_2 = (void*)(&(small)[0]);
	} else {
		__if_val_2 = (void*)(v_malloc(size));
	}
	void* buffer = __if_val_2;
	if (buffer == NULL) {
		return (multi_return_u64_u64){errno__err, errno__enomem};
	}
	void* address_out = NULL;
	u32* length_out = (u32*)(NULL);
	if (wants_address) {
		address_out = (void*)(&(storage)[0]);
		length_out = length;
	}
	multi_return_u64_u64 __multi_ret_3 = socket__receive_to_kernel(fdnum, buffer, size, flags, address_out, length_out);
	u64 received = __multi_ret_3.arg0;
	u64 err = __multi_ret_3.arg1;
	if (err != 0) {
		multi_return_u64_u64 _t1 = (multi_return_u64_u64){		received, 		err};
		{
			if (size > socket__small_message) {
				{
					v_free(buffer);
				}
			}
		}
		return _t1;
	}
	u64 __if_val_4 = {0};
	if (received < size) {
		__if_val_4 = received;
	} else {
		__if_val_4 = size;
	}
	u64 copied = __if_val_4;
	if ((copied != 0) && !usercopy__copy_to_user((u64)(buf), buffer, copied)) {
		multi_return_u64_u64 _t2 = (multi_return_u64_u64){		errno__err, 		errno__efault};
		{
			if (size > socket__small_message) {
				{
					v_free(buffer);
				}
			}
		}
		return _t2;
	}
	if (wants_address && ((*length != offered) || ((storage)[0] != 0xff) || ((storage)[1] != 0xff)) && !socket__address_to_user(src_addr, (u64)((void*)(addrlen)), (void*)(&(storage)[0]), capacity, *length)) {
		multi_return_u64_u64 _t3 = (multi_return_u64_u64){		errno__err, 		errno__efault};
		{
			if (size > socket__small_message) {
				{
					v_free(buffer);
				}
			}
		}
		return _t3;
	}
	multi_return_u64_u64 _t4 = (multi_return_u64_u64){	received, 	0};
	{
		if (size > socket__small_message) {
			{
				v_free(buffer);
			}
		}
	}
	return _t4;
	{
		if (size > socket__small_message) {
			{
				v_free(buffer);
			}
		}
	}
}
