import asyncio, asyncio.log, asyncio.base_events
import collections
import concurrent.futures
import functools
import itertools
import os
import socket
import subprocess
import sys
import threading


cdef aio_CancelledError = asyncio.CancelledError
cdef aio_TimeoutError = asyncio.TimeoutError
cdef aio_Future = asyncio.Future
cdef aio_Task = asyncio.Task
cdef aio_ensure_future = asyncio.ensure_future
cdef aio_gather = asyncio.gather
cdef aio_wait = asyncio.wait
cdef aio_logger = asyncio.log.logger
cdef aio_coroutine = asyncio.coroutine
cdef aio__check_resolved_address = asyncio.base_events._check_resolved_address
cdef aio_iscoroutine = asyncio.iscoroutine
cdef aio_iscoroutinefunction = asyncio.iscoroutinefunction
cdef aio_wrap_future = asyncio.wrap_future
cdef aio_BaseProtocol = asyncio.BaseProtocol
cdef aio_Protocol = asyncio.Protocol

cdef col_deque = collections.deque
cdef col_Iterable = collections.Iterable
cdef col_Counter = collections.Counter

cdef cc_ThreadPoolExecutor = concurrent.futures.ThreadPoolExecutor

cdef ft_partial = functools.partial

cdef iter_chain = itertools.chain

cdef int has_AF_INET6 = hasattr(socket, 'AF_INET6')
cdef int has_SO_REUSEPORT = hasattr(socket, 'SO_REUSEPORT')
cdef int has_IPPROTO_IPV6 = hasattr(socket, 'IPPROTO_IPV6')

cdef socket_gaierror = socket.gaierror
cdef socket_error = socket.error
cdef socket_timeout = socket.timeout
cdef socket_socket = socket.socket
cdef socket_fromfd = socket.fromfd

cdef int socket_EAI_ADDRFAMILY = getattr(socket, 'EAI_ADDRFAMILY', -1)
cdef int socket_EAI_AGAIN      = getattr(socket, 'EAI_AGAIN', -1)
cdef int socket_EAI_BADFLAGS   = getattr(socket, 'EAI_BADFLAGS', -1)
cdef int socket_EAI_BADHINTS   = getattr(socket, 'EAI_BADHINTS', -1)
cdef int socket_EAI_CANCELED   = getattr(socket, 'EAI_CANCELED', -1)
cdef int socket_EAI_FAIL       = getattr(socket, 'EAI_FAIL', -1)
cdef int socket_EAI_FAMILY     = getattr(socket, 'EAI_FAMILY', -1)
cdef int socket_EAI_MEMORY     = getattr(socket, 'EAI_MEMORY', -1)
cdef int socket_EAI_NODATA     = getattr(socket, 'EAI_NODATA', -1)
cdef int socket_EAI_NONAME     = getattr(socket, 'EAI_NONAME', -1)
cdef int socket_EAI_OVERFLOW   = getattr(socket, 'EAI_OVERFLOW', -1)
cdef int socket_EAI_PROTOCOL   = getattr(socket, 'EAI_PROTOCOL', -1)
cdef int socket_EAI_SERVICE    = getattr(socket, 'EAI_SERVICE', -1)
cdef int socket_EAI_SOCKTYPE   = getattr(socket, 'EAI_SOCKTYPE', -1)


cdef str os_name = os.name
cdef os_environ = os.environ
cdef os_dup = os.dup
cdef os_pipe = os.pipe
cdef os_set_inheritable = os.set_inheritable
cdef os_get_inheritable = os.get_inheritable
cdef os_close = os.close
cdef os_open = os.open
cdef os_devnull = os.devnull
cdef os_O_RDWR = os.O_RDWR

cdef str sys_platform = sys.platform
cdef sys_ignore_environment = sys.flags.ignore_environment
cdef sys_exc_info = sys.exc_info

cdef str sys_fs_encoding = sys.getfilesystemencoding()

cdef long MAIN_THREAD_ID = <long>threading.main_thread().ident

cdef int subprocess_PIPE = subprocess.PIPE
cdef int subprocess_STDOUT = subprocess.STDOUT
cdef int subprocess_DEVNULL = subprocess.DEVNULL


# Cython doesn't clean-up imported objects properly in Py3 mode,
# so we delete refs to all modules manually (except sys)
del asyncio, concurrent, collections
del functools, itertools, socket, os, threading, subprocess