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
 * )
 */
module snowflake.utility.os;

import core.stdc.config : c_ulong;
import std.exception : errnoEnforce;
import std.string : toStringz;

import os_sched = core.sys.linux.sched;
import os_sys_stat = core.sys.posix.sys.stat;
import os_unistd = core.sys.posix.unistd;

// Re-export types from druntime.
public import core.sys.posix.sys.stat : mode_t;

// Re-export constants from druntime.
public import core.sys.linux.sched :
    CLONE_NEWCGROUP, CLONE_NEWIPC, CLONE_NEWNET, CLONE_NEWNS,
    CLONE_NEWPID, CLONE_NEWUSER, CLONE_NEWUTS;

// These are not in druntime yet.
extern (C) nothrow private @nogc
{
    public enum MS_BIND    = 0x1000;
    public enum MS_RDONLY  = 0x0001;
    public enum MS_REC     = 0x4000;
    public enum MS_REMOUNT = 0x0020;

    pragma (mangle, "chroot")
    @system int os_unistd_chroot(const(char)* path);

    pragma (mangle, "mount")
    @system int os_sys_mount_mount(
        const(char)* source,
        const(char)* target,
        const(char)* filesystemtype,
        c_ulong      mountflags,
        const(void)* data,
    );
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

@trusted
void mkdir(scope const(char)[] path, mode_t mode)
{
    const ok = os_sys_stat.mkdir(path.toStringz, mode);
    errnoEnforce(ok != -1, "mkdir: " ~ path);
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
