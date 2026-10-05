__v_option_i64 unix__UnixSocket__write_with_fds(unix__UnixSocket* this, void* _handle, void* buf, u64 _count, Array fds) {
	u64 count = _count;
	if (this->write_closed) {
		errno__set(errno__epipe);
		return (__v_option_i64){.ok = false};
	}
	if (unix__UnixSocket__is_datagram(this)) {
		unix__UnixSocket* __if_val_0 = {0};
		if (this->dgram_target != NULL) {
			__if_val_0 = this->dgram_target;
		} else {
			__if_val_0 = this->peer;
		}
		unix__UnixSocket* target = __if_val_0;
		if (target == NULL) {
			errno__set(errno__enotconn);
			return (__v_option_i64){.ok = false};
		}
		return unix__UnixSocket__send_datagram(this, target, _handle, buf, count, fds);
	}
	unix__UnixSocket* peer = this->peer;
	if (peer == NULL) {
		errno__set(errno__enotconn);
		return (__v_option_i64){.ok = false};
	}
	if (unix__UnixSocket__is_seqpacket(peer) && (({ u64 _t1 = (u64)(_count); i64 _t2 = (i64)(unix__sock_buf); _t2 < 0 ? 1 : ((u64)(_t1) > (u64)(_t2)); })) && !peer->closed) {
		errno__set(errno__emsgsize);
		return (__v_option_i64){.ok = false};
	}
	klock__Lock__acquire(&peer->l);
	if (peer->read_closed || peer->closed) {
		errno__set(errno__epipe);
		__v_option_i64 _t3 = (__v_option_i64){.ok = false};
		{
			klock__Lock__release(&peer->l);
		}
		return _t3;
	}
	file__Handle* handle = (file__Handle*)(_handle);
	u64 __if_val_1 = {0};
	if (({ u64 _t4 = (u64)(count); i64 _t5 = (i64)(unix__sock_buf); _t5 < 0 ? 0 : ((u64)(_t4) <= (u64)(_t5)); })) {
		__if_val_1 = count;
	} else {
		__if_val_1 = (u64)(1);
	}
	u64 requested_room = __if_val_1;
	u64 deadline = unix__deadline_after(this->send_timeout_ns);
	while ((unix__sock_buf - katomic__load_T_u64(&peer->used)) < requested_room) {
		if ((handle->flags & resource__o_nonblock) != 0) {
			if (({ u64 _t6 = (u64)(peer->used); i64 _t7 = (i64)(unix__sock_buf); _t7 < 0 ? 0 : ((u64)(_t6) == (u64)(_t7)); })) {
				errno__set(errno__ewouldblock);
				__v_option_i64 _t8 = (__v_option_i64){.ok = false};
				{
					klock__Lock__release(&peer->l);
				}
				return _t8;
			}
			break;
		}
		klock__Lock__release(&peer->l);
		if (!unix__wait_on(&peer->event, deadline, false, 0)) {
			klock__Lock__acquire(&peer->l);
			__v_option_i64 _t9 = (__v_option_i64){.ok = false};
			{
				klock__Lock__release(&peer->l);
			}
			return _t9;
		}
		klock__Lock__acquire(&peer->l);
		if (peer->read_closed) {
			errno__set(errno__epipe);
			__v_option_i64 _t10 = (__v_option_i64){.ok = false};
			{
				klock__Lock__release(&peer->l);
			}
			return _t10;
		}
	}
	if (({ u64 _t11 = (u64)(peer->used + count); i64 _t12 = (i64)(unix__sock_buf); _t12 < 0 ? 1 : ((u64)(_t11) > (u64)(_t12)); })) {
		count = unix__sock_buf - peer->used;
	}
	if ((count == 0) && (fds.len != 0)) {
		errno__set(errno__eagain);
		__v_option_i64 _t13 = (__v_option_i64){.ok = false};
		{
			klock__Lock__release(&peer->l);
		}
		return _t13;
	}
	if ((count == 0) && !unix__UnixSocket__is_seqpacket(peer)) {
		__v_option_i64 _t14 = (__v_option_i64){.ok = true, .value = 		0};
		{
			klock__Lock__release(&peer->l);
		}
		return _t14;
	}
	unix__UnixSocket* __order_snapshot_2 = peer;
	u64 __if_val_3 = {0};
	if (count == 0) {
		__if_val_3 = (u64)(1);
	} else {
		__if_val_3 = peer->used + count;
	}
	unix__UnixSocket__ensure_capacity(__order_snapshot_2, __if_val_3);
	u64 fd_offset = peer->used;
	u64 before_wrap = (u64)(0);
	u64 after_wrap = (u64)(0);
	u64 new_ptr_loc = (u64)(0);
	if ((peer->write_ptr + count) > peer->capacity) {
		before_wrap = peer->capacity - peer->write_ptr;
		after_wrap = count - before_wrap;
		new_ptr_loc = after_wrap;
	} else {
		before_wrap = count;
		after_wrap = 0;
		new_ptr_loc = peer->write_ptr + count;
		if (new_ptr_loc == peer->capacity) {
			new_ptr_loc = 0;
		}
	}
	{
		memcpy(&(peer->data)[peer->write_ptr], buf, before_wrap);
	}
	if (after_wrap != 0) {
		{
			memcpy(peer->data, (void*)((u64)(buf) + before_wrap), after_wrap);
		}
	}
	peer->write_ptr = new_ptr_loc;
	peer->used += count;
	if (({ u64 _t15 = (u64)(peer->used); i64 _t16 = (i64)(unix__sock_buf); _t16 < 0 ? 0 : ((u64)(_t15) == (u64)(_t16)); })) {
		this->status &= ~file__pollout;
	}
	if (fds.len != 0) {
		unix__PendingFdGroup group = (unix__PendingFdGroup){.offset = fd_offset, .span = count, .fds = array_new(		sizeof(file__FD*), 0, 0)};
		array__push_many(&group.fds, fds.data, fds.len);
		peer->pending_fd_groups.flags |= 1;
		unix__PendingFdGroup __arr_val_4 = group;
		array_push(&peer->pending_fd_groups, &__arr_val_4);
	}
	if (unix__UnixSocket__is_seqpacket(peer)) {
		peer->packet_lengths.flags |= 1;
		u64 __arr_val_5 = count;
		array_push(&peer->packet_lengths, &__arr_val_5);
	}
	peer->status |= file__pollin;
	event__trigger(&peer->event, false);
	__v_option_i64 _t17 = (__v_option_i64){.ok = true, .value = 	(i64)(count)};
	{
		klock__Lock__release(&peer->l);
	}
	return _t17;
	{
		klock__Lock__release(&peer->l);
	}
	return (__v_option_i64){.ok = true};
}
