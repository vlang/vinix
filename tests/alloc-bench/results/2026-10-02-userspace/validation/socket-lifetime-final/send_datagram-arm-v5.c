__v_option_i64 unix__UnixSocket__send_datagram(unix__UnixSocket* this, unix__UnixSocket* target, void* _handle, void* buf, u64 count, Array fds) {
	if (!unix__UnixSocket__is_datagram(target)) {
		errno__set(errno__eprototype);
		return (__v_option_i64){.ok = false};
	}
	if (({ u64 _t1 = (u64)(count); i64 _t2 = (i64)(unix__sock_buf); _t2 < 0 ? 1 : ((u64)(_t1) > (u64)(_t2)); })) {
		errno__set(errno__emsgsize);
		return (__v_option_i64){.ok = false};
	}
	proc__Process* process = (proc__current_thread())->process;
	unix__DatagramSender sender = (unix__DatagramSender){.name = this->name, .name_len = unix__UnixSocket__address_length(this), .pid = process->pid, .uid = process->euid, .gid = process->egid};
	file__Handle* handle = (file__Handle*)(_handle);
	klock__Lock__acquire(&target->l);
	u64 deadline = unix__deadline_after(this->send_timeout_ns);
	for (;;) {
		if (target->closed || target->read_closed) {
			errno__set(errno__econnrefused);
			__v_option_i64 _t3 = (__v_option_i64){.ok = false};
			{
				klock__Lock__release(&target->l);
			}
			return _t3;
		}
		if ((unix__sock_buf - target->used) >= count) {
			break;
		}
		if ((handle->flags & resource__o_nonblock) != 0) {
			errno__set(errno__eagain);
			__v_option_i64 _t4 = (__v_option_i64){.ok = false};
			{
				klock__Lock__release(&target->l);
			}
			return _t4;
		}
		u64 generation = event__generation(&target->event);
		klock__Lock__release(&target->l);
		if (!unix__wait_on(&target->event, deadline, true, generation)) {
			klock__Lock__acquire(&target->l);
			__v_option_i64 _t5 = (__v_option_i64){.ok = false};
			{
				klock__Lock__release(&target->l);
			}
			return _t5;
		}
		klock__Lock__acquire(&target->l);
	}
	unix__UnixSocket* __order_snapshot_0 = target;
	u64 __if_val_1 = {0};
	if (count == 0) {
		__if_val_1 = (u64)(1);
	} else {
		__if_val_1 = target->used + count;
	}
	unix__UnixSocket__ensure_capacity(__order_snapshot_0, __if_val_1);
	if (fds.len != 0) {
		unix__PendingFdGroup group = (unix__PendingFdGroup){.offset = target->used, .span = count, .fds = array_new(		sizeof(file__FD*), 0, 0)};
		array__push_many(&group.fds, fds.data, fds.len);
		target->pending_fd_groups.flags |= 1;
		unix__PendingFdGroup __arr_val_2 = group;
		array_push(&target->pending_fd_groups, &__arr_val_2);
	}
	if (count != 0) {
		u64 before_wrap = count;
		u64 after_wrap = (u64)(0);
		if ((target->write_ptr + count) > target->capacity) {
			before_wrap = target->capacity - target->write_ptr;
			after_wrap = count - before_wrap;
		}
		{
			memcpy(&(target->data)[target->write_ptr], buf, before_wrap);
		}
		if (after_wrap != 0) {
			{
				memcpy(target->data, (void*)((u64)(buf) + before_wrap), after_wrap);
			}
		}
		target->write_ptr = ({ u64 _t6 = (u64)((target->write_ptr + count)); u64 _t7 = (u64)(target->capacity); if (_t7 == 0) v_panic(_S("modulo by zero")); (u64)(_t6 % _t7); });
		target->used += count;
	}
	target->packet_lengths.flags |= 1;
	target->datagrams.flags |= 1;
	u64 __arr_val_3 = count;
	array_push(&target->packet_lengths, &__arr_val_3);
	unix__DatagramSender __arr_val_4 = sender;
	array_push(&target->datagrams, &__arr_val_4);
	target->status |= file__pollin;
	event__trigger(&target->event, false);
	__v_option_i64 _t8 = (__v_option_i64){.ok = true, .value = 	(i64)(count)};
	{
		klock__Lock__release(&target->l);
	}
	return _t8;
	{
		klock__Lock__release(&target->l);
	}
	return (__v_option_i64){.ok = true};
}
