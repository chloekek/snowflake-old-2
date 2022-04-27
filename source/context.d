module snowflake.context;

import os = snowflake.utility.os;

/**
 * Information passed throughout the program.
 *
 * Provides access to the state directory (commonly `.snowflake`).
 */
final
class Context
{
    const(int) stateDir;
    int _scratchesDir = -1;
    ulong nextScratchId = 0;

public:
    /**
     * Ensure the state directory exists and open it.
     */
    @safe
    this(string stateDirPath)
    {
        stateDir = ensureDir(stateDirPath);
        scope (failure) os.close(stateDir);
    }

    @safe
    ~this()
    {
        os.close(stateDir);
        if (_scratchesDir != -1)
            os.close(_scratchesDir);
    }

    /**
     * File descriptor for the directory that stores scratch directories.
     */
    @safe
    int scratchesDir()
    {
        if (_scratchesDir == -1)
            _scratchesDir = ensureDirAt(stateDir, "scratches");
        return _scratchesDir;
    }

    /**
     * Create a new scratch directory and return a file descriptor to it.
     */
    @safe
    int newScratchDir()
    {
        import std.conv : to;
        const scratchId = nextScratchId++;
        const scratchDir = ensureDirAt(scratchesDir, scratchId.to!string);
        return scratchDir;
    }
}

private @safe
int ensureDir(scope const(char)[] path)
{
    return ensureDirAt(os.AT_FDCWD, path);
}

private @safe
int ensureDirAt(int dirfd, scope const(char)[] path)
{
    import core.stdc.errno : EEXIST;
    import std.conv : octal;
    import std.exception : ErrnoException;

    // Create directory if it does not yet exist.
    try
        os.mkdirat(dirfd, path, octal!"755");
    catch (ErrnoException ex)
        if (ex.errno != EEXIST)
            throw ex;

    // Open the directory and make sure it is a directory.
    return os.openat(dirfd, path, os.O_DIRECTORY | os.O_PATH, 0);
}
