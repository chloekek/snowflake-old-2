module snowflake.actionPhase.runAction;

import core.time : Duration;
import snowflake.context : Context;
import snowflake.utility.command : Command;

import os = snowflake.utility.os;

/**
 * Perform a run action.
 */
@safe
void performRunAction(Context context, Duration timeout, string[] outputs)
{
    import snowflake.config : ENV_PATH, SH_PATH;
    import snowflake.utility.hashFile : Hash, hashFileAt;
    import std.conv : octal;
    import std.string : format;

    const scratchDir = context.newScratchDir();
    scope (exit) os.close(scratchDir);

    // Create root directory structure.
    os.mkdirat(scratchDir, "bin",       octal!"755");
    os.mkdirat(scratchDir, "nix",       octal!"755");
    os.mkdirat(scratchDir, "nix/store", octal!"755");
    os.mkdirat(scratchDir, "proc",      octal!"555");
    os.mkdirat(scratchDir, "usr",       octal!"755");
    os.mkdirat(scratchDir, "usr/bin",   octal!"755");
    os.mkdirat(scratchDir, "build",     octal!"755");  // Working directory.
    os.mkdirat(scratchDir, "output",    octal!"755");  // Outputs placed here.

    // Create symbolic links to implicit dependencies.
    os.symlinkat(SH_PATH,  scratchDir, "bin/sh");
    os.symlinkat(ENV_PATH, scratchDir, "usr/bin/env");

    // Configure the command to run.
    auto command = Command(
        /* pathname */ "/bin/sh",
        /* argv     */ ["bash", "-c", `
            export PATH=/nix/store/l0zvs9z152zys4sxa64hkvnxalgkszpi-coreutils-9.0/bin
            touch /output/main.o
            exit 1
        `],
        /* envp     */ ["USER=root"],
    );

    // Create namespaces to form a container.
    command.cloneNewcgroup = true;  // New cgroup namespace.
    command.cloneNewipc    = true;  // New IPC namespace.
    command.cloneNewnet    = true;  // New network namespace.
    command.cloneNewns     = true;  // New mount namespace.
    command.cloneNewpid    = true;  // New PID namespace.
    command.cloneNewuser   = true;  // New user namespace.
    command.cloneNewuts    = true;  // New UTS namespace.

    // Generate a pidfd for the process.
    command.clonePidfd = true;

    // Map root inside container to actual user outside container.
    command.setgroups = "deny\n";
    command.uid_map   = format!"0 %d 1\n"(os.getuid);
    command.gid_map   = format!"0 %d 1\n"(os.getgid);

    // Set the working directory to the scratch directory.
    command.fchdir = scratchDir;

    // systemd mounts `/` as `MS_SHARED`, but `MS_PRIVATE` is more isolated.
    command.mount("none", "/", null, os.MS_PRIVATE | os.MS_REC, null);

    // Mount `/proc` which is required for some programs to function properly.
    const procMountFlags = os.MS_NODEV | os.MS_NOEXEC | os.MS_NOSUID;
    command.mount("proc", "proc", "proc", procMountFlags, null);

    // Create bind mounts so the container can access outside files.
    mountBindRdonly(command, "/nix/store", "nix/store");

    // Set the root directory of the container to the working directory.
    // Then set the working directory to the build directory.
    command.chroot      = ".";
    command.chrootChdir = "/build";

    // Run the command.
    command.run(timeout);

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
 * Create a read-only bind mount.
 *
 * This is more involved than simply passing `MS_BIND | MS_RDONLY`.
 * See https://unix.stackexchange.com/a/492462 for more information.
 */
private pure @safe
void mountBindRdonly(
    ref scope Command       command,
    scope     const(char)[] source,
    scope     const(char)[] target,
)
{
    const flags1 = os.MS_BIND | os.MS_REC;
    const flags2 = flags1 | os.MS_RDONLY | os.MS_REMOUNT;
    command.mount(source, target, null, flags1, null);
    command.mount("none", target, null, flags2, null);
}
