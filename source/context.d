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
    import snowflake.utility.hashFile : Hash;

    const(int) stateDir;

    int _scratchesDir = -1;
    ulong nextScratchId = 0;

    int _cachedOutputsDir = -1;

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

    /**
     * File descriptor for the directory that stores cached outputs.
     */
    @safe
    int cachedOutputsDir()
    {
        if (_cachedOutputsDir == -1)
            _cachedOutputsDir = ensureDirAt(stateDir, "cached-outputs");
        return _cachedOutputsDir;
    }

    /**
     * Move an existing file to the output cache.
     *
     * If the file already exists in the output cache, nothing happens.
     *
     * The given hash must match the actual hash of the file!
     * The given file must not be modified afterwards!
     */
    @safe
    void storeCachedOutput(Hash hash, int fromDirfd, string fromPath)
    in
    {
        import snowflake.utility.hashFile : hashFileAt;
        assert (hashFileAt(fromDirfd, fromPath) == hash);
    }
    do
    {
        import core.stdc.errno : EEXIST;
        import snowflake.utility.hashFile : toString;
        import std.exception : ErrnoException;
        try
            os.renameat2(
                fromDirfd,        fromPath,
                cachedOutputsDir, hash.toString,
                os.RENAME_NOREPLACE,
            );
        catch (ErrnoException ex)
            if (ex.errno != EEXIST)
                throw ex;
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
