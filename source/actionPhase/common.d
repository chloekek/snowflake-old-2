// SPDX-License-Identifier: AGPL-3.0-only

module snowflake.actionPhase.common;

import snowflake.context : Context;
import snowflake.utility.error : QuickUserError, UserError;
import snowflake.utility.error : UserErrorElaborator, UserException;
import snowflake.utility.hashFile : Hash, hashFileAt;
import std.sumtype : SumType;

import os = snowflake.utility.os;

/// Information that is passed by `performAction` to the action-specific code.
struct ActionContext
{
    /// File descriptor for the scratch directory.
    ///
    /// The action-specific code may freely manipulate
    /// the contents of this directory, as working memory.
    ///
    /// When the action-specific code returns,
    /// each output must exist as a directory entry
    /// of the `outputs` directory in this directory.
    ///
    /// The action-specific code must *not* close this file descriptor!
    int scratchDir;

    /// File descriptor for the log file.
    ///
    /// The action-specific code must write any logs to this file descriptor,
    /// rather than writing it to stdout or stderr of the Snowflake process.
    /// The logs are displayed to the user if the action warns or fails.
    ///
    /// The action-specific code must *not* close this file descriptor!
    int logFile;
}

/// How an action finishes.
alias ActionStatus = SumType!(
    ActionStatusSuccess,
    ActionStatusFailure,
    ActionStatusWarning,
);
struct ActionStatusSuccess { }
struct ActionStatusFailure { string log; const(Exception) cause; }
struct ActionStatusWarning { string log; }

/// Perform an action.
///
/// This constructs the action context and runs the action-specific code.
/// After the action-specific code returns, outputs are moved to the cache.
///
/// The status returned indicates how the action finished.
/// The action failing does not generally cause an exception to be thrown.
/// But a serious failure such as inability to create the scratch directory
/// will cause this function to throw an exception rather than return a status.
@safe
ActionStatus performAction(
    Context context,
    scope const(char[])[] outputs,
    void delegate(ref scope const(ActionContext)) @safe actionSpecificCode,
)
{
    import std.conv : octal;

    // Create scratch directory for this action to use.
    const scratchDir = context.newScratchDir();
    scope (exit) os.close(scratchDir);

    // Create directory for this action to place its outputs in.
    os.mkdirat(scratchDir, "outputs", octal!"755");

    // Create the log file for the action to write logs to.
    const logFlags = os.O_CREAT | os.O_RDWR;
    const logFile = os.openat(scratchDir, "build.log", logFlags, octal!"644");
    scope (exit) os.close(logFile);

    try {

        // Run the action-specific code.
        ActionContext actionContext;
        actionContext.scratchDir = scratchDir;
        actionContext.logFile = logFile;
        actionSpecificCode(actionContext);

        // Verify the outputs and move them to the cache.
        const outputsDir = openOutputsDir(scratchDir);
        scope (exit) os.close(outputsDir);
        const outputHashes = collectOutputHashes(outputsDir, outputs);
        foreach (output, hash; outputHashes)
            context.storeCachedOutput(hash, outputsDir, output);

        // TODO: Scan the log file for warnings.

        return typeof(return)(ActionStatusSuccess());

    } catch (Exception ex) {

        // TODO: Read log file into string.
        string log = "TODO";

        return typeof(return)(ActionStatusFailure(log, ex));

    }
}

/// Open the outputs directory.
///
/// This may fail if the action deleted the outputs directory
/// or otherwise made the outputs directory inaccessible.
/// If this is the case, an exception is thrown.
private @safe
int openOutputsDir(int scratchDir)
{
    try {
        const outputFlags = os.O_DIRECTORY | os.O_PATH;
        return os.openat(scratchDir, "outputs", outputFlags, 0);
    } catch (Exception ex) {
        const error = new OutputsDirectoryInaccessibleError(ex);
        throw new UserException(error);
    }
}

/// Compute the hash of each output.
///
/// This only hashes outputs that are declared by the action.
/// Extraneous files in the outputs directory are ignored.
/// If an output cannot be hashed, this failure is recorded.
/// All these failures are thrown in a single exception.
private @safe
Hash[string] collectOutputHashes(int outputsDir, scope const(char[])[] outputs)
{
    Exception[string] unhashableOutputs;
    Hash     [string] outputHashes;

    foreach (output; outputs)
        try
            outputHashes[output] = hashFileAt(outputsDir, output);
        catch (Exception ex)
            unhashableOutputs[output] = ex;

    if (unhashableOutputs.length != 0) {
        const error = new OutputsInaccessibleError(unhashableOutputs);
        throw new UserException(error);
    }

    return outputHashes;
}

/+ -------------------------------------------------------------------------- +/
/+                               User errors                                  +/
/+ -------------------------------------------------------------------------- +/

alias OutputsDirectoryInaccessibleError = QuickUserError!(
    "The outputs directory was made inaccessible by the action",
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
        "The action failed to produce one or more outputs";

    override pure @safe
    void elaborate(scope UserErrorElaborator elaborator) const
    {
        foreach (output, exception; invalidOutputs)
            elaborator.field(output, exception);
    }
}
