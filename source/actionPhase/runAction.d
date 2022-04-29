module snowflake.actionPhase.runAction;

import std.conv : octal;
import snowflake.context : Context;

import os = snowflake.utility.os;

/**
 * Execute a run action.
 */
@safe
void executeRunAction(
    Context  context,
    string[] outputs,
)
{
    import snowflake.utility.hashFile : Hash, hashFileAt;

    const scratchDir = context.newScratchDir();
    scope (exit) os.close(scratchDir);

    // Working directory for the command.
    os.mkdirat(scratchDir, "build", octal!"755");

    // Directory in which outputs are to be placed.
    os.mkdirat(scratchDir, "output", octal!"755");

    // TODO: Spawn sandbox command.

    // Open the output directory.
    const outputDir = os.openat(scratchDir, "output",
                                os.O_DIRECTORY | os.O_PATH, 0);
    scope (exit) os.close(outputDir);

    // Compute the hash of each output.
    // This must not be interleaved with moving outputs to the cache,
    // because we don't want to move any outputs to the cache
    // if any output was not present or not hashable.
    Hash[string] outputHashes;
    foreach (output; outputs) {
        const hash = hashFileAt(outputDir, output);
        outputHashes[output] = hash;
    }

    // TODO: Move outputs to cache.
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
    // TODO: Bind mount user-declared inputs.

    // Change root directory to working directory.
    os.chroot(".");

    // Change the working directory to the build directory.
    // Must be absolute as chroot does not change the working directory.
    os.chdir("/build");
}

/**
 * Create a read-only bind mount.
 *
 * This is more involved than simply passing `MS_BIND | MS_RDONLY`.
 * See https://unix.stackexchange.com/a/492462 for more information.
 */
private @safe
void mountBindRdonly(scope const(char)[] source, scope const(char)[] target)
{
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
