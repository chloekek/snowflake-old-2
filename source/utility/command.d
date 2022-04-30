module snowflake.utility.command;

import core.time : Duration;
import snowflake.utility.error : QuickUserError, UserException;

public import core.sys.posix.sched : pid_t;

/**
 * Represents a system command that can be spawned as a child process.
 * This is similar to the `std.process` module
 * but supports additional features we need.
 */
struct Command
{
    import std.array : Appender;
    import std.typecons : Tuple;

private:
    ulong clone3Flags;

public:
    string setgroups;
    string uid_map;
    string gid_map;

public:
    int fchdir = -1;

private:
    struct Mount
    {
        immutable(char)* source;
        immutable(char)* target;
        immutable(char)* filesystemtype;
        c_ulong          mountflags;
        immutable(char)* data;
    }
    Appender!(Mount[]) mounts;

private:
    immutable(char)*  chrootz;
    immutable(char)*  chrootChdirz;

private:
    immutable(char)*  execvePathname;
    immutable(char*)* execveArgv;
    immutable(char*)* execveEnvp;

public:
    @disable this();
    @disable this(this);

    /**
     * Create a command with the given path, arguments, and environment.
     */
    nothrow pure @safe
    this(
        scope const(char)[] pathname,
        scope const(char[])[] argv,
        scope const(char[])[] envp,
    )
    {
        import std.string : toStringz;
        execvePathname = pathname.toStringz;
        execveArgv     = argv.toArrayz;
        execveEnvp     = envp.toArrayz;
    }

    mixin(clone3FlagSetter("cloneNewcgroup",  "CLONE_NEWCGROUP"));
    mixin(clone3FlagSetter("cloneNewipc",     "CLONE_NEWIPC"));
    mixin(clone3FlagSetter("cloneNewnet",     "CLONE_NEWNET"));
    mixin(clone3FlagSetter("cloneNewns",      "CLONE_NEWNS"));
    mixin(clone3FlagSetter("cloneNewpid",     "CLONE_NEWPID"));
    mixin(clone3FlagSetter("cloneNewuser",    "CLONE_NEWUSER"));
    mixin(clone3FlagSetter("cloneNewuts",     "CLONE_NEWUTS"));
    mixin(clone3FlagSetter("clonePidfd",      "CLONE_PIDFD"));

    mixin(stringSetter("chroot"));
    mixin(stringSetter("chrootChdir"));

    /**
     * Add a mount call to be performed.
     */
    nothrow pure @safe
    void mount(
        scope const(char)[] source,
        scope const(char)[] target,
        scope const(char)[] filesystemtype,
        ulong               mountflags,
        scope const(char)[] data,
    ) scope
    {
        import std.string : toStringz;
        mounts ~= Mount(
            source         is null ? null : source.toStringz,
            target         is null ? null : target.toStringz,
            filesystemtype is null ? null : filesystemtype.toStringz,
            mountflags,
            data           is null ? null : data.toStringz,
        );
    }

    /**
     * Wrapper around `spawn` that runs the process to completion.
     * Throws an exception if the process was terminated unsuccessfully
     * or if the given timeout expired before the process terminated.
     */
    @safe
    void run(Duration timeout)
    {
        import os = snowflake.utility.os;

        // Spawn the child process.
        const process = spawn();
        scope (exit) os.close(process.pidfd);

        {
            // If polling fails or a timeout occurs,
            // immediately kill the child process.
            scope (failure) {
                os.kill(process.pid, os.SIGKILL);
                int wstatus; os.waitpid(process.pid, wstatus, 0);
            }

            // Once the pidfd is readable, the child process has terminated.
            auto pollfds = [os.pollfd(process.pidfd, os.POLLIN, 0)];
            const npolled = os.poll(pollfds, cast(int) timeout.total!"msecs");

            // If `poll` returns 0, there was a timeout.
            if (npolled == 0)
                throw new UserException(new TimeoutError(timeout));
        }

        // Reap the child process and find its exit status.
        int wstatus;
        os.waitpid(process.pid, wstatus, 0);

        // If the child process terminated unsuccessfully, throw an exception.
        if (!os.WIFEXITED(wstatus) || os.WEXITSTATUS(wstatus) != 0)
            throw new UserException(new TerminationError(wstatus));
    }

    /**
     * Spawn a child process with the command.
     * Waits until `execve` succeeds and throws if it doesn't.
     * Returns the process identifier of the child process.
     * If `CLONE_PIDFD` is set, also returns a new pidfd.
     */
    @trusted
    Tuple!(pid_t, "pid", int, "pidfd") spawn()
    {
        import core.sys.posix.signal : SIGCHLD;
        import std.exception : ErrnoException, errnoEnforce;
        import std.string : format, toStringz;
        import std.typecons : tuple;

        import bitmanip = std.bitmanip;
        import os       = snowflake.utility.os;
        import system   = std.system;

        // For unknown reasons, using `fchdir(fd)` in the child process
        // prevents `mount` and `chroot` from working with relative paths.
        // Using `chdir("/proc/self/fd/N")` isn't sufficient either.
        // Dereferencing it and _then_ calling `chdir` works fine.
        // FIXME: Debug and fix this properly.
        immutable(char)* fchdirz;
        if (fchdir != -1) {
            const symlink = format!"/proc/self/fd/%d"(fchdir);
            fchdirz = os.readlinkat(os.AT_FDCWD, symlink).toStringz;
        }

        // Create a pipe for the child to communicate
        // any errors that occur in `childPreExecve`.
        // Does not persist after `spawn` returns.
        int pipeR, pipeW;
        os.pipe2(0, pipeR, pipeW);
        scope (exit) os.close(pipeR);

        // The clone3 system call may generate these output parameters.
        int pidfd = -1;

        // Invoke the clone3 system call to spawn the child process.
        // clone3 is more featureful than fork; it supports flags.
        // But other than that its interface is very similar.
        os_sched_clone_args cl_args;
        cl_args.flags       = clone3Flags;
        cl_args.pidfd       = cast(ulong) &pidfd;
        cl_args.exit_signal = SIGCHLD;
        const pid = cast(pid_t) os_unistd_syscall(
            os_sys_syscall_SYS_clone3,
            &cl_args, cl_args.sizeof,
        );
        {
            scope (failure) os.close(pipeW);
            errnoEnforce(pid != -1, "clone3");
        }

        // If clone3 returns 0, this is the child process.
        if (pid == 0)
            childPreExecve(pipeR, pipeW, fchdirz);

        // If anything below fails, kill and reap the child process.
        scope (failure) {
            os.kill(pid, os.SIGKILL);
            int wstatus; os.waitpid(pid, wstatus, 0);
        }

        // Close write end of the pipe.
        os.close(pipeW);

        // Wait for the `execve` call to complete in the child process.
        // Once it does, `pipeW` will be closed due to `CLOEXEC`,
        // which in turn causes this read to complete at EOF.
        // If this read completes with data, an error was sent.
        ubyte[512] errorBuf = void;
        auto errorSubbuf = os.read(pipeR, errorBuf);
        if (errorSubbuf.length != 0) {
            const errno = bitmanip.read!(int, system.endian)(errorSubbuf);
            const msg   = cast(string) errorSubbuf.idup;
            throw new ErrnoException(msg, errno);
        }

        return typeof(return)(pid, pidfd);
    }

    /**
     * The code that runs in the child process before it calls `execve`.
     * The `nothrow` and `@nogc` attributes are very important:
     * the code within this function must be async-signal-safe.
     */
    nothrow private @nogc @system
    noreturn childPreExecve(int pipeR, int pipeW, const(char)* fchdirz)
    {
        import os_errno  = core.stdc.errno;
        import os_fcntl  = core.sys.posix.fcntl;
        import os_unistd = core.sys.posix.unistd;

        // Like `errnoEnforce`, but send error to pipe and exit.
        // This does not allocate memory and does not throw exceptions.
        void errnoEnforcePipe(bool condition, scope const(char)[] msg)
        {
            if (!condition) {
                const errno = os_errno.errno;
                os_unistd.write(pipeW, &errno, errno.sizeof);
                os_unistd.write(pipeW, msg.ptr, msg.length);
                os_unistd._exit(1);
            }
        }

        // Write to a given file with a single write call.
        // Path is taken as a template argument to avoid allocations.
        void writeFile(string path)(string data)
        {
            const flags = os_fcntl.O_TRUNC | os_fcntl.O_WRONLY;
            const fd = os_fcntl.open(path, flags, 0);
            errnoEnforcePipe(fd != -1, "open: " ~ path);

            const nwritten = os_unistd.write(fd, data.ptr, data.length);
            errnoEnforcePipe(nwritten == data.length, "write: " ~ path);

            const ok = os_unistd.close(fd);
            errnoEnforcePipe(ok != -1, "close: " ~ path);
        }

        // Clone read end of the pipe.
        const ok = os_unistd.close(pipeR);
        errnoEnforcePipe(ok != -1, "close");

        // Write to these files as requested.
        if (setgroups !is null) writeFile!"/proc/self/setgroups"(setgroups);
        if (uid_map   !is null) writeFile!"/proc/self/uid_map"  (uid_map);
        if (gid_map   !is null) writeFile!"/proc/self/gid_map"  (gid_map);

        // Set working directory as requested.
        if (fchdirz !is null) {
            const good = os_unistd.chdir(fchdirz);
            errnoEnforcePipe(good != -1, "chdir");
        }

        // Perform each mount as requested.
        foreach (mount; mounts) {
            const good = os_sys_mount_mount(mount.tupleof);
            errnoEnforcePipe(good != -1, "mount");
        }

        // Set root directory as requested.
        if (chrootz !is null) {
            const good = os_unistd_chroot(chrootz);
            errnoEnforcePipe(good != -1, "chroot");
        }

        // Set working directory as requested.
        if (chrootChdirz !is null) {
            const good = os_unistd.chdir(chrootChdirz);
            errnoEnforcePipe(good != -1, "chdir");
        }

        // Replace the process with the requested program.
        os_unistd.execve(execvePathname, execveArgv, execveEnvp);
        errnoEnforcePipe(false, "execve");
    }
}

/+ -------------------------------------------------------------------------- +/
/+                            Utility functions                               +/
/+ -------------------------------------------------------------------------- +/

/**
 * Create a setter for a `clone3` flag.
 */
nothrow private pure @safe
string clone3FlagSetter(string property, string flag)
{
    return `
        nothrow pure @nogc @property @safe
        void ` ~ property ~ `(bool value) scope
        {
            import core.sys.linux.sched;
            enum CLONE_PIDFD = 0x1000;
            if (value)
                clone3Flags |= ` ~ flag ~ `;
            else
                clone3Flags &= ~` ~ flag ~ `;
        }
    `;
}

/**
 * Create a setter for a string option.
 */
nothrow private pure @safe
string stringSetter(string property)
{
    return `
        nothrow pure @property @safe
        void ` ~ property ~ `(scope const(char)[] value) scope
        {
            import std.string : toStringz;
            ` ~ property ~ `z = value is null ? null : value.toStringz;
        }
    `;
}

/**
 * Create a null-terminated array of null-terminated strings.
 * This is useful for creating the `argv` and `envp` arguments to `execve`.
 */
nothrow private pure @trusted
immutable(char*)* toArrayz(scope const(char[])[] self)
{
    import std.algorithm.iteration : map;
    import std.array : array;
    import std.range : chain, only;
    import std.string : toStringz;
    return chain(self.map!toStringz, only(null)).array.ptr;
}

/+ -------------------------------------------------------------------------- +/
/+                               User errors                                  +/
/+ -------------------------------------------------------------------------- +/

alias TimeoutError = QuickUserError!(
    "Command exceeded the configured timeout",
    Duration, "timeout",
);

alias TerminationError = QuickUserError!(
    "Command terminated with non-zero exit status",
    int, "wstatus",
);

/+ -------------------------------------------------------------------------- +/
/+                             FFI declarations                               +/
/+ -------------------------------------------------------------------------- +/

// These are not in druntime yet.
extern (C) nothrow private @nogc
{
    import core.stdc.config : c_long, c_ulong;

    version (X86_64) enum os_sys_syscall_SYS_clone3 = 435;

    struct os_sched_clone_args
    {
        ulong flags, pidfd, child_tid, parent_tid, exit_signal, stack;
        ulong stack_size, tls, set_tid, set_tid_size, cgroup;
    }

    pragma (mangle, "mount")
    @system int os_sys_mount_mount(
        const(char)* source,
        const(char)* target,
        const(char)* filesystemtype,
        c_ulong      mountflags,
        const(void)* data,
    );

    pragma (mangle, "chroot")
    @system int os_unistd_chroot(const(char)* path);

    pragma (mangle, "syscall")
    @system c_long os_unistd_syscall(c_long number, ...);
}
