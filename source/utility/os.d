// SPDX-License-Identifier: AGPL-3.0-only

/**
 * Provides safe wrappers around system calls.
 *
 * The wrappers retain the original names and behaviors of the system calls,
 * making it easy to look up their behavior in the man pages.
 * However, there are a few trivial differences for ease of use:
 *
 * $(LIST
 *  * Errors are reported as exceptions rather than via `errno`.
 *  * String arguments do not have to be null-terminated.
 *  * `*_CLOEXEC` is passed to file handle creation functions,
 *    as it is not thread-safe to set this flag separately.
 * )
 */
module snowflake.utility.os;

import core.stdc.config : c_long, c_ulong;
import std.exception : errnoEnforce;
import std.string : toStringz;
import std.typecons : Nullable;

import os_dirent = core.sys.posix.dirent;
import os_fcntl = core.sys.posix.fcntl;
import os_poll = core.sys.posix.poll;
import os_sched = core.sys.linux.sched;
import os_signal = core.sys.posix.signal;
import os_sys_stat = core.sys.posix.sys.stat;
import os_sys_wait = core.sys.posix.sys.wait;
import os_unistd = core.sys.posix.unistd;

// Re-export types from druntime.
public import core.sys.posix.poll :
    pollfd;
public import core.sys.posix.signal :
    SIGKILL;
public import core.sys.posix.sys.stat :
    mode_t, stat_t;
public import core.sys.posix.sys.wait :
    pid_t;

// Re-export constants from druntime.
public import core.sys.posix.fcntl :
    AT_FDCWD, AT_SYMLINK_NOFOLLOW;
public import core.sys.posix.poll :
    POLLIN;
public import core.sys.posix.sys.stat :
    S_IFDIR, S_IFLNK, S_IFMT, S_IFREG;

// Re-export functions from druntime.
public import core.sys.posix.unistd :
    getgid, getuid;
public import core.sys.posix.sys.wait :
    WEXITSTATUS, WIFEXITED;

// These are not in druntime yet.
extern (C) nothrow private @nogc
{
    public enum F_DUPFD_CLOEXEC = 1030;

    public enum MS_BIND    = 0x01000;
    public enum MS_NODEV   = 0x00004;
    public enum MS_NOEXEC  = 0x00008;
    public enum MS_NOSUID  = 0x00002;
    public enum MS_PRIVATE = 0x40000;
    public enum MS_RDONLY  = 0x00001;
    public enum MS_REC     = 0x04000;
    public enum MS_REMOUNT = 0x00020;

    public enum O_CLOEXEC   = 0x080000;
    public enum O_CREAT     = 0x000040;
    public enum O_DIRECTORY = 0x010000;
    public enum O_PATH      = 0x200000;
    public enum O_RDONLY    = 0x000000;
    public enum O_RDWR      = 0x000002;
    public enum O_TRUNC     = 0x000200;
    public enum O_WRONLY    = 0x000001;

    public enum RENAME_NOREPLACE = 1;

    pragma (mangle, "fdopendir")
    @trusted os_dirent.DIR* os_dirent_fdopendir(int fd);

    pragma (mangle, "openat")
    @system int os_fcntl_openat(
        int          dirfd,
        const(char)* pathname,
        int          flags,
        mode_t       mode,
    );

    pragma (mangle, "renameat2")
    @system int os_stdio_renameat2(
        int olddirfd, const(char)* oldpath,
        int newdirfd, const(char)* newpath,
        int flags,
    );

    pragma (mangle, "fstatat")
    @system int os_sys_stat_fstatat(
        int          dirfd,
        const(char)* pathname,
        stat_t*      statbuf,
        int          flags,
    );

    pragma (mangle, "mkdirat")
    @system int os_sys_stat_mkdirat(
        int          dirfd,
        const(char)* pathname,
        mode_t       mode,
    );

    pragma (mangle, "pipe2")
    @system int os_unistd_pipe2(int* pipefd, int flags);

    pragma (mangle, "symlinkat")
    @system int os_unistd_symlinkat(
        const(char)* target,
        int          newdirfd,
        const(char)* linkpath,
    );

    pragma (mangle, "readlinkat")
    @system ptrdiff_t os_unistd_readlinkat(
        int          dirfd,
        const(char)* pathname,
        char*        buf,
        size_t       bufsiz,
    );
}

struct DIR
{
private:
    os_dirent.DIR* inner;

    nothrow pure @nogc @system
    this(os_dirent.DIR* inner)
    {
        this.inner = inner;
    }

public:
    @disable this();
    @disable this(this);

    @trusted
    ~this()
    {
        const ok = os_dirent.closedir(inner);
        errnoEnforce(ok != -1, "closedir");
    }
}

struct dirent
{
private:
    os_dirent.dirent inner;

public:
    nothrow pure @nogc @trusted
    inout(char)[] d_name() inout return scope
    {
        import std.string : fromStringz;
        return inner.d_name.ptr.fromStringz;
    }
}

@safe
void close(int fd)
{
    const ok = os_unistd.close(fd);
    errnoEnforce(ok != -1, "close");
}

int dup()(int oldfd)
{
    static assert (
        false,
        "dup cannot set CLOEXEC. " ~
        "Use fcntl_dupfd instead of dup",
    );
}

@trusted
int fcntl_dupfd(int oldfd)
{
    const fd = os_fcntl.fcntl(oldfd, F_DUPFD_CLOEXEC, 0);
    errnoEnforce(fd != -1, "fcntl: F_DUPFD_CLOEXEC");
    return fd;
}

@trusted
stat_t fstatat(int dirfd, scope const(char)[] pathname, int flags)
{
    stat_t statbuf = void;
    const ok = os_sys_stat_fstatat(dirfd, pathname.toStringz, &statbuf, flags);
    errnoEnforce(ok != -1, "fstatat: " ~ pathname);
    return statbuf;
}

@trusted
void kill(pid_t pid, int sig)
{
    const ok = os_signal.kill(pid, sig);
    errnoEnforce(ok != -1, "kill");
}

@trusted
void mkdir(scope const(char)[] path, mode_t mode)
{
    const ok = os_sys_stat.mkdir(path.toStringz, mode);
    errnoEnforce(ok != -1, "mkdir: " ~ path);
}

@trusted
void mkdirat(int dirfd, scope const(char)[] path, mode_t mode)
{
    const ok = os_sys_stat_mkdirat(dirfd, path.toStringz, mode);
    errnoEnforce(ok != -1, "mkdirat: " ~ path);
}

@trusted
int openat(int dirfd, scope const(char)[] pathname, int flags, mode_t mode)
{
    flags |= O_CLOEXEC;
    const fd = os_fcntl_openat(dirfd, pathname.toStringz, flags, mode);
    errnoEnforce(fd != -1, "openat: " ~ pathname);
    return fd;
}

@trusted
DIR fdopendir(int fd)
{
    auto dir = os_dirent_fdopendir(fd);

    // fdopendir takes ownership of the file descriptor (closedir closes it).
    // So if construction fails, we should close the file descriptor.
    if (dir is null)
        close(fd);

    errnoEnforce(dir !is null, "fdopendir");
    return DIR(dir);
}

@trusted
void pipe2(int flags, out int pipeR, out int pipeW)
{
    flags |= O_CLOEXEC;
    int[2] pipefd;
    const ok = os_unistd_pipe2(pipefd.ptr, flags);
    errnoEnforce(ok != -1, "pipe");
    pipeR = pipefd[0];
    pipeW = pipefd[1];
}

@trusted
int poll(scope pollfd[] fds, int timeout)
{
    const n = os_poll.poll(fds.ptr, fds.length, timeout);
    errnoEnforce(n != -1, "poll");
    return n;
}

@trusted
ubyte[] read(int fd, return scope ubyte[] buf)
{
    const length = os_unistd.read(fd, buf.ptr, buf.length);
    errnoEnforce(length != -1, "read");
    return buf[0 .. length];
}

@trusted
Nullable!dirent readdir(ref scope DIR dirp)
{
    import core.stdc.errno : errno;

    // readdir returns null both on error and on end of directory.
    // To distinguish, first set errno to zero, then check afterwards.
    errno = 0;
    const result = os_dirent.readdir(dirp.inner);
    if (result is null && errno == 0)
        return typeof(return).init;

    errnoEnforce(result !is null, "readdir");

    // POSIX says this cannot be used as an lvalue.
    // However, we only use Linux, and on Linux it can.
    return typeof(return)(dirent(*result));
}

@safe
char[] readlinkat(int dirfd, scope const(char)[] pathname)
{
    // FIXME: Retry with bigger buffer if it doesn't fit.
    import std.array : uninitializedArray;
    auto buf = uninitializedArray!(char[])(256);
    return readlinkat(dirfd, pathname, buf);
}

@trusted
char[] readlinkat(
                 int           dirfd,
    scope        const(char)[] pathname,
    return scope char[]        buf,
)
{
    const length = os_unistd_readlinkat(
        dirfd,
        pathname.toStringz,
        buf.ptr,
        buf.length,
    );
    errnoEnforce(length != -1, "readlinkat: " ~ pathname);
    return buf[0 .. length];
}

@trusted
void renameat2(
    int olddirfd, scope const(char)[] oldpath,
    int newdirfd, scope const(char)[] newpath,
    int flags,
)
{
    const ok = os_stdio_renameat2(
        olddirfd, oldpath.toStringz,
        newdirfd, newpath.toStringz,
        flags,
    );
    errnoEnforce(ok != -1, "renameat2");
}

@trusted
void symlinkat(
    scope const(char)[] target,
    int newdirfd,
    scope const(char)[] linkpath,
)
{
    const ok = os_unistd_symlinkat(
        target.toStringz,
        newdirfd,
        linkpath.toStringz,
    );
    errnoEnforce(ok != -1, "symlinkat: " ~ linkpath ~ " -> " ~ target);
}

@trusted
pid_t waitpid(pid_t pid, out int wstatus, int options)
{
    const result = os_sys_wait.waitpid(pid, &wstatus, options);
    errnoEnforce(result != -1, "waitpid");
    return result;
}

@trusted
size_t write(int fd, scope const(ubyte)[] buf)
{
    const length = os_unistd.write(fd, buf.ptr, buf.length);
    errnoEnforce(length != -1, "write");
    return length;
}
