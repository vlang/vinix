multi_return_u64_u64 socket__syscall_sendmsg(void* _0, i64 fdnum, public__MsgHdr* msg, i64 flags) {
	public__MsgHdr* header = (public__MsgHdr*)(vinix_stack_alloc(sizeof(public__MsgHdr)));
	{
		*header = (public__MsgHdr){.msg_iov = NULL};
	}
	if (!usercopy__copy_from_user((void*)(header), (u64)((void*)(msg)), sizeof(public__MsgHdr))) {
		return (multi_return_u64_u64){errno__err, errno__efault};
	}
	return socket__send_message(fdnum, header, flags);
}
