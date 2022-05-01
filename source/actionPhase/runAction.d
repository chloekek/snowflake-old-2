// SPDX-License-Identifier: AGPL-3.0-only

module snowflake.actionPhase.runAction;

import snowflake.actionPhase.common : ActionContext;
import snowflake.utility.command : Command;
import snowflake.utility.error : QuickUserError, UserException;

import os = snowflake.utility.os;

/**
 * Arguments to `performRunAction`.
 */
struct PerformRunAction
{
    import core.time : Duration;

    /**
     * The program to run.
     */
    string program;

    /**
     * Arguments to pass to the program.
     * The first argument is generally equal to `program`.
     */
    string[] arguments;

    /**
     * Environment entries to pass to the program.
     */
    string[] environment;

    /**
     * The maximum time the program may spend.
     * If exceeded, the program is killed.
     */
    Duration timeout;
}

/**
 * Perform a run action.
 */
@safe
void performRunAction(
    ref scope const(ActionContext) context,
    ref scope const(PerformRunAction) info,
)
{
    import snowflake.config : BASH_PATH, COREUTILS_PATH;
    import std.conv : octal;

    // Create root directory structure.
    os.mkdirat(context.scratchDir, "bin",       octal!"755");
    os.mkdirat(context.scratchDir, "nix",       octal!"755");
    os.mkdirat(context.scratchDir, "nix/store", octal!"755");
    os.mkdirat(context.scratchDir, "proc",      octal!"555");
    os.mkdirat(context.scratchDir, "usr",       octal!"755");
    os.mkdirat(context.scratchDir, "usr/bin",   octal!"755");

    // Create working directory for the command.
    os.mkdirat(context.scratchDir, "build", octal!"755");

    // These executables are expected to exist by many programs.
    // Consider scripts with `#!/usr/bin/env` or programs calling `system(3)`.
    // So we always make these available even if not declared as inputs.
    os.symlinkat(BASH_PATH      ~ "/bin/bash", context.scratchDir, "bin/sh");
    os.symlinkat(COREUTILS_PATH ~ "/bin/env",  context.scratchDir, "usr/bin/env");
    // NOTE: When adding an entry here, add it to the hash of the run action.

    // Run the command of the run action.
    try
        runCommand(context, info);
    catch (UserException ex)
        throw ex;
    catch (Exception ex)
        throw new UserException(new CommandSetupError(ex));
}

/**
 * Run the command of a run action.
 */
private @safe
void runCommand(
    ref scope const(ActionContext) context,
    ref scope const(PerformRunAction) info,
)
{
    import std.string : format;

    // Configure the command to run.
    auto command = Command(info.program, info.arguments, info.environment);

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
    command.fchdir = context.scratchDir;

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

    // Open the log file and redirect stdio.
    command.stdin  = Command.Close();
    command.stdout = Command.Dup2(context.logFile);
    command.stderr = Command.Dup2(context.logFile);

    // Run the command.
    command.run(info.timeout);
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

/+ -------------------------------------------------------------------------- +/
/+                               User errors                                  +/
/+ -------------------------------------------------------------------------- +/

alias CommandSetupError = QuickUserError!(
    "Could not set up the environment for a run action",
    const(Exception), "cause",
);
