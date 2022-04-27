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

import core.stdc.config : c_ulong;
import std.exception : errnoEnforce;
import std.string : toStringz;
import std.typecons : Nullable;

import os_dirent = core.sys.posix.dirent;
import os_fcntl = core.sys.posix.fcntl;
import os_sched = core.sys.linux.sched;
import os_sys_stat = core.sys.posix.sys.stat;
import os_unistd = core.sys.posix.unistd;

// Re-export types from druntime.
public import core.sys.posix.sys.stat :
    mode_t, stat_t;

// Re-export constants from druntime.
public import core.sys.posix.fcntl :
    AT_FDCWD, AT_SYMLINK_NOFOLLOW;
public import core.sys.linux.sched :
    CLONE_NEWCGROUP, CLONE_NEWIPC, CLONE_NEWNET, CLONE_NEWNS,
    CLONE_NEWPID, CLONE_NEWUSER, CLONE_NEWUTS;

// Re-export functions from druntime.
public import core.sys.posix.sys.stat :
    S_IFDIR, S_IFLNK, S_IFMT, S_IFREG;

// These are not in druntime yet.
extern (C) nothrow private @nogc
{
    public enum MS_BIND    = 0x1000;
    public enum MS_RDONLY  = 0x0001;
    public enum MS_REC     = 0x4000;
    public enum MS_REMOUNT = 0x0020;

    public enum O_CLOEXEC   = 0x080000;
    public enum O_DIRECTORY = 0x010000;
    public enum O_PATH      = 0x200000;
    public enum O_RDONLY    = 0x000000;

    pragma (mangle, "fdopendir")
    @trusted os_dirent.DIR* os_dirent_fdopendir(int fd);

    pragma (mangle, "openat")
    @system int os_fcntl_openat(
        int          dirfd,
        const(char)* pathname,
        int          flags,
        mode_t       mode,
    );

    pragma (mangle, "chroot")
    @system int os_unistd_chroot(const(char)* path);

    pragma (mangle, "fstatat")
    @system int os_sys_stat_fstatat(
        int          dirfd,
        const(char)* pathname,
        stat_t*      statbuf,
        int          flags,
    );

    pragma (mangle, "mount")
    @system int os_sys_mount_mount(
        const(char)* source,
        const(char)* target,
        const(char)* filesystemtype,
        c_ulong      mountflags,
        const(void)* data,
    );

    pragma (mangle, "mkdirat")
    @system int os_sys_stat_mkdirat(
        int          dirfd,
        const(char)* pathname,
        mode_t       mode,
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

@trusted
void chdir(scope const(char)[] path)
{
    const ok = os_unistd.chdir(path.toStringz);
    errnoEnforce(ok != -1, "chdir: " ~ path);
}

@trusted
void chroot(scope const(char)[] path)
{
    const ok = os_unistd_chroot(path.toStringz);
    errnoEnforce(ok != -1, "chroot: " ~ path);
}

@safe
void close(int fd)
{
    const ok = os_unistd.close(fd);
    errnoEnforce(ok != -1, "close");
}

@safe
int dup(int oldfd)
{
    const fd = os_unistd.dup(oldfd);
    errnoEnforce(fd != -1, "dup");
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
void mount(
    scope const(char)[] source,
    scope const(char)[] target,
    scope const(char)[] filesystemtype,
    c_ulong             mountflags,
    scope const(char)[] data,
)
{
    const ok = os_sys_mount_mount(
        source.toStringz,
        target.toStringz,
        filesystemtype.toStringz,
        mountflags,
        data.toStringz,
    );
    errnoEnforce(ok != -1, "mount: " ~ target ~ " -> " ~ source);
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
void symlink(scope const(char)[] target, scope const(char)[] linkpath)
{
    const ok = os_unistd.symlink(target.toStringz, linkpath.toStringz);
    errnoEnforce(ok != -1, "symlink: " ~ linkpath ~ " -> " ~ target);
}

@safe
void unshare(int flags)
{
    const ok = os_sched.unshare(flags);
    errnoEnforce(ok != -1, "unshare");
}