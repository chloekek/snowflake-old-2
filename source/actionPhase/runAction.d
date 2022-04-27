module snowflake.actionPhase.runAction;

/**
 * Execute a run action.
 */
@safe
void executeRunAction()
{
}

/**
 * Enter the build sandbox for a run action.
 *
 * This is not called directly by `executeRunAction`.
 * Rather, `executeRunAction` spawns a child process
 * which in turn calls this function (see `main`).
 */
@safe
void enterRunActionSandbox()
{
    import snowflake.config : ENV_PATH, SH_PATH;
    import std.conv : octal;

    import os = snowflake.utility.os;

    // Create root directory structure.
    os.mkdir("bin",       octal!"755");
    os.mkdir("nix",       octal!"755");
    os.mkdir("nix/store", octal!"755");
    os.mkdir("usr",       octal!"755");
    os.mkdir("usr/bin",   octal!"755");

    // Create symbolic links to implicit dependencies.
    os.symlink(SH_PATH,  "bin/sh");
    os.symlink(ENV_PATH, "usr/bin/env");

    // Create new sets of identifies for all these resources.
    os.unshare(
        os.CLONE_NEWCGROUP |  // Create cgroup namespace.
        os.CLONE_NEWIPC    |  // Create IPC namespace.
        os.CLONE_NEWNET    |  // Create network namespace.
        os.CLONE_NEWNS     |  // Create mount namespace.
        os.CLONE_NEWPID    |  // Create PID namespace.
        os.CLONE_NEWUSER   |  // Create user namespace.
        os.CLONE_NEWUTS        // Create UTS namespace.
    );

    // Create bind mounts.
    mountBindRdonly("/nix/store", "nix/store");

    // Change root directory to working directory.
    os.chroot(".");

    // chroot does not adjust working directory,
    // so it is currently most likely dangling.
    os.chdir("/");
}

/**
 * Create a read-only bind mount.
 *
 * This is more involved than simply passing `MS_BIND | MS_RDONLY`.
 * See https://unix.stackexchange.com/a/128388 for more information.
 */
private @safe
void mountBindRdonly(scope const(char)[] source, scope const(char)[] target)
{
    import os = snowflake.utility.os;

    os.mount(
        source,
        target,
        null,  // Ignored with MS_BIND.
        os.MS_BIND,
        null,  // Ignored with MS_BIND.
    );

    os.mount(
        "none",
        target,
        null,  // Ignored with MS_BIND.
        os.MS_BIND | os.MS_RDONLY | os.MS_REMOUNT,
        null,  // Ignored with MS_BIND.
    );
}
