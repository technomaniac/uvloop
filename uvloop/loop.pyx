# cython: language_level=3


import collections
import functools
import signal
import time
import types

cimport cython

from . cimport uv

from .async_ cimport Async
from .idle cimport Idle
from .signal cimport Signal
from .timer cimport Timer

from libc.stdint cimport uint64_t

from cpython.mem cimport PyMem_Malloc, PyMem_Free
from cpython.exc cimport PyErr_CheckSignals, PyErr_Occurred
from cpython.pythread cimport PyThread_get_thread_ident


class LibUVError(Exception):
    pass


@cython.no_gc_clear
cdef class Loop:
    def __cinit__(self):
        self.loop = <uv.uv_loop_t*> \
                            PyMem_Malloc(sizeof(uv.uv_loop_t))
        if self.loop is NULL:
            raise MemoryError()

        self.loop.data = <void*> self
        self._closed = 0
        self._debug = 0
        self._thread_id = 0
        self._running = 0

        # Seems that Cython still can't cleanup module state
        # on its finalization (in Python 3 at least).
        # If a ref from *this* module to asyncio isn't cleared,
        # the policy won't be properly destroyed, hence the
        # loop won't be properly destroyed, hence some warnings
        # might not be shown at all.
        self._asyncio = __import__('asyncio')
        self._asyncio_Task = self._asyncio.Task

    def __del__(self):
        self._close()

    def __dealloc__(self):
        PyMem_Free(self.loop)

    def __init__(self):
        cdef int err

        err = uv.uv_loop_init(self.loop)
        if err < 0:
            self._handle_uv_error(err)

        self.handler_async = Async(self, self._on_wake)
        self.handler_idle = Idle(self, self._on_idle)
        self.handler_sigint = Signal(self, self._on_sigint, signal.SIGINT)

        self._last_error = None

        self._ready = collections.deque()
        self._ready_len = 0

        self._timers = set()

    def _on_wake(self):
        if self._ready_len > 0 and not self.handler_idle.running:
            self.handler_idle.start()

    def _on_sigint(self):
        self._last_error = KeyboardInterrupt()
        self._stop()

    def _on_idle(self):
        cdef int i, ntodo
        cdef object popleft = self._ready.popleft

        ntodo = len(self._ready)
        for i from 0 <= i < ntodo:
            handler = <Handle> popleft()
            if handler.cancelled == 0:
                handler._run()

        self._ready_len = len(self._ready)
        if self._ready_len == 0 and self.handler_idle.running:
            self.handler_idle.stop()

    cdef _stop(self):
        uv.uv_stop(self.loop)

    cdef _run(self, uv.uv_run_mode mode):
        cdef int err

        if self._closed == 1:
            raise RuntimeError('unable to start the loop; it was closed')

        if self._running == 1:
            raise RuntimeError('Event loop is running.')

        self._thread_id = PyThread_get_thread_ident()
        self._running = 1

        self.handler_idle.start()
        self.handler_sigint.start()

        err = uv.uv_run(self.loop, mode)
        if err < 0:
            self._handle_uv_error(err)

        self.handler_idle.stop()
        self.handler_sigint.stop()

        self._thread_id = 0
        self._running = 0

        if self._last_error is not None:
            self.close()
            raise self._last_error

    cdef _close(self):
        cdef int err

        if self._running == 1:
            raise RuntimeError("Cannot close a running event loop")

        if self._closed == 1:
            return

        self._closed = 1

        self.handler_idle.close()
        self.handler_sigint.close()
        self.handler_async.close()

        if self._timers:
            lst = tuple(self._timers)
            for timer in lst:
                (<TimerHandle>timer).close_handle()

        # Allow loop to fire "close" callbacks
        err = uv.uv_run(self.loop, uv.UV_RUN_DEFAULT)
        if err < 0:
            self._handle_uv_error(err)

        err = uv.uv_loop_close(self.loop)
        if err < 0:
            self._handle_uv_error(err)

        self._ready.clear()
        self._ready_len = 0
        self._timers = None

    cdef uint64_t _time(self):
        return uv.uv_now(self.loop)

    cdef _call_soon(self, object callback):
        self._check_closed()
        handle = Handle(self, callback)
        self._ready.append(handle)
        self._ready_len += 1;
        if not self.handler_idle.running:
            self.handler_idle.start()
        return handle

    cdef _call_later(self, uint64_t delay, object callback):
        return TimerHandle(self, callback, delay)

    cdef void _handle_uvcb_exception(self, object ex):
        if isinstance(ex, Exception):
            self.call_exception_handler({'exception': ex})
        else:
            # BaseException
            self._last_error = ex
            # Exit ASAP
            self._stop()

    cdef _handle_uv_error(self, int err):
        cdef:
            bytes msg = uv.uv_strerror(err)
            bytes name = uv.uv_err_name(err)

        raise LibUVError('({}) {}'.format(name.decode('latin-1'),
                                          msg.decode('latin-1')))

    cdef _check_closed(self):
        if self._closed == 1:
            raise RuntimeError('Event loop is closed')

    cdef _check_thread(self):
        if self._thread_id == 0:
            return
        cdef long thread_id = PyThread_get_thread_ident()
        if thread_id != self._thread_id:
            raise RuntimeError(
                "Non-thread-safe operation invoked on an event loop other "
                "than the current one")

    # Public API

    def __repr__(self):
        return ('<%s running=%s closed=%s debug=%s>'
                % (self.__class__.__name__, self.is_running(),
                   self.is_closed(), self.get_debug()))

    def call_soon(self, callback, *args):
        if self._debug == 1:
            self._check_thread()
        if len(args):
            _cb = callback
            callback = lambda: _cb(*args)
        return self._call_soon(callback)

    def call_soon_threadsafe(self, callback, *args):
        if len(args):
            _cb = callback
            callback = lambda: _cb(*args)
        handle = self._call_soon(callback)
        self.handler_async.send()
        return handle

    def call_later(self, delay, callback, *args):
        self._check_closed()
        if self._debug == 1:
            self._check_thread()
        cdef uint64_t when = <uint64_t>(delay * 1000)
        if len(args):
            _cb = callback
            callback = lambda: _cb(*args)
        return self._call_later(when, callback)

    def time(self):
        return self._time() / 1000

    def stop(self):
        self._call_soon(lambda: self._stop())

    def run_forever(self):
        self._check_closed()
        self._run(uv.UV_RUN_DEFAULT)

    def close(self):
        self._close()

    def get_debug(self):
        if self._debug == 1:
            return True
        else:
            return False

    def set_debug(self, enabled):
        if enabled:
            self._debug = 1
        else:
            self._debug = 0

    def is_running(self):
        if self._running == 0:
            return False
        else:
            return True

    def is_closed(self):
        if self._closed == 0:
            return False
        else:
            return True

    def create_task(self, coro):
        self._check_closed()

        return self._asyncio_Task(coro, loop=self)

    def run_until_complete(self, future):
        self._check_closed()

        new_task = not isinstance(future, self._asyncio.Future)
        future = self._asyncio.ensure_future(future, loop=self)
        if new_task:
            # An exception is raised if the future didn't complete, so there
            # is no need to log the "destroy pending task" message
            future._log_destroy_pending = False

        done_cb = lambda fut: self.stop()

        future.add_done_callback(done_cb)
        try:
            self.run_forever()
        except:
            if new_task and future.done() and not future.cancelled():
                # The coroutine raised a BaseException. Consume the exception
                # to not log a warning, the caller doesn't have access to the
                # local task.
                future.exception()
            raise
        future.remove_done_callback(done_cb)
        if not future.done():
            raise RuntimeError('Event loop stopped before Future completed.')

        return future.result()

    def call_exception_handler(self, context):
        print("!!! EXCEPTION HANDLER !!!", context, flush=True)


@cython.internal
@cython.freelist(100)
cdef class Handle:
    cdef:
        object callback
        int cancelled
        object __weakref__

    def __cinit__(self, Loop loop, object callback):
        self.callback = callback
        self.cancelled = 0

    cdef _run(self):
        self.callback()

    # Public API

    cpdef cancel(self):
        self.cancelled = 1


@cython.internal
@cython.freelist(100)
cdef class TimerHandle:
    cdef:
        object callback
        int cancelled
        int closed
        Timer timer
        Loop loop
        object __weakref__

    def __cinit__(self, Loop loop, object callback, uint64_t delay):
        self.loop = loop
        self.callback = callback
        self.cancelled = 0
        self.closed = 0

        self.timer = Timer(loop, self._run, delay)
        self.timer.start()

        loop._timers.add(self)

    def __del__(self):
        self.close()

    def _remove_self(self):
        try:
            self.loop._timers.remove(self)
        except KeyError:
            pass

    cdef close_handle(self):
        if self.closed == 1:
            return

        self.timer.close()
        self.closed = 1

    cdef close(self):
        if self.closed == 1:
            return

        self.close_handle()

        if self.loop._closed == 0:
            # If loop._closed == 1 the loop is already closing, and
            # will handle loop._timers itself.
            self.loop._call_soon(self._remove_self)

    def _run(self):
        if self.cancelled == 0:
            self.close()
            self.callback()

    # Public API

    cpdef cancel(self):
        if self.cancelled == 0:
            self.cancelled = 1
            self.close()