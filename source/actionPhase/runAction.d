// SPDX-License-Identifier: AGPL-3.0-only

module snowflake.actionPhase.runAction;

import snowflake.context : Context;
import snowflake.utility.command : Command;
import snowflake.utility.error : QuickUserError, UserError;
import snowflake.utility.error : UserErrorElaborator, UserException;

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
     * Outputs that the program must generate.
     */
    string[] outputs;

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
void performRunAction(Context context, ref scope const(PerformRunAction) info)
{
    import snowflake.config : BASH_PATH, COREUTILS_PATH;
    import snowflake.utility.hashFile : Hash, hashFileAt;
    import std.conv : octal;

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

    // These executables are expected to exist by many programs.
    // Consider scripts with `#!/usr/bin/env` or programs calling `system(3)`.
    // So we always make these available even if not declared as inputs.
    os.symlinkat(BASH_PATH      ~ "/bin/bash", scratchDir, "bin/sh");
    os.symlinkat(COREUTILS_PATH ~ "/bin/env",  scratchDir, "usr/bin/env");
    // NOTE: When adding an entry here, add it to the hash of the run action.

    // Open the log file.
    const logFlags = os.O_CREAT | os.O_RDWR;
    const logFile = os.openat(scratchDir, "build.log", logFlags, octal!"644");
    scope (exit) os.close(logFile);

    // Run the command of the run action.
    try
        runCommand(info, scratchDir, logFile);
    catch (UserException ex)
        throw ex;
    catch (Exception ex)
        throw new UserException(new CommandSetupError(ex));

    // Open the output directory that the command wrote into.
    // If the output directory cannot be opened,
    // then the command did something horribly wrong.
    int outputDir;
    try {
        const outputFlags = os.O_DIRECTORY | os.O_PATH;
        outputDir = os.openat(scratchDir, "output", outputFlags, 0);
    } catch (Exception ex) {
        const error = new OutputDirectoryInaccessibleError(ex);
        throw new UserException(error);
    }
    scope (exit) os.close(outputDir);

    // Compute the hash of each expected output.
    // Outputs that were not expected are simply ignored.
    // Expected outputs that cannot be hashed cause a failure.
    // Collect those errors into a single exception for superior UX.
    Exception[string] unhashableOutputs;
    Hash[string] outputHashes;
    foreach (output; info.outputs)
        try
            outputHashes[output] = hashFileAt(outputDir, output);
        catch (Exception ex)
            unhashableOutputs[output] = ex;
    if (unhashableOutputs.length != 0) {
        const error = new OutputsInaccessibleError(unhashableOutputs);
        throw new UserException(error);
    }

    foreach (output, hash; outputHashes)
        context.storeCachedOutput(hash, outputDir, output);
}

/**
 * Run the command of a run action.
 */
private @safe
void runCommand(
    ref scope const(PerformRunAction) info,
              int                     scratchDir,
              int                     logFile,
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

    // Open the log file and redirect stdio.
    command.stdin  = Command.Close();
    command.stdout = Command.Dup2(logFile);
    command.stderr = Command.Dup2(logFile);

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

alias OutputDirectoryInaccessibleError = QuickUserError!(
    "The output directory was made inaccessible by the command",
    const(Exception), "cause",
);

final
class OutputsInaccessibleError
    : UserError
{
    const(Exception[string]) invalidOutputs;

    nothrow pure @nogc @safe
    this(const(Exception[string]) invalidOutputs)
    {
        this.invalidOutputs = invalidOutputs;
    }

    nothrow pure @nogc @safe
    string message() const scope =>
        "The command failed to produce one or more outputs";

    override pure @safe
    void elaborate(scope UserErrorElaborator elaborator) const
    {
        foreach (output, exception; invalidOutputs)
            elaborator.field(output, exception);
    }
}
