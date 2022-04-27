module snowflake.utility.hashFile;

import std.bitmanip : append;
import std.conv : octal;

import os = snowflake.utility.os;

/**
 * Compute the hash of a file.
 *
 * The file may be a regular file, a symbolic link,
 * or (recursively) a directory of eligible files.
 * Symbolic links are not followed; their target paths are hashed.
 * The file contents and mode are used as input to the hash function;
 * other attributes such as file path and modification date are not.
 */
@safe
ubyte[32] hashFileAt(int dirfd, scope const(char)[] path)
{
    import snowflake.utility.blake3 : Blake3;
    auto digest = Blake3(null);
    hashFileAt(digest, dirfd, path);
    return digest.finish();
}

/// ditto
@safe
void hashFileAt(D)(ref D digest, int dirfd, const(char)[] path)
{
    const statbuf = os.fstatat(dirfd, path, os.AT_SYMLINK_NOFOLLOW);
    switch (statbuf.st_mode & os.S_IFMT) {
        case os.S_IFREG: return hashFileAtReg(digest, dirfd, path, statbuf);
        case os.S_IFDIR: return hashFileAtDir(digest, dirfd, path, statbuf);
        case os.S_IFLNK: return hashFileAtLnk(digest, dirfd, path);
        default:  assert(false); // TODO: Throw exception
    }
}

private @safe
void hashFileAtReg(D)(
    ref D                digest,
        int              dirfd,
        const(char)[]    path,
    ref const(os.stat_t) statbuf,
)
{
    import snowflake.utility.io : readChunks;

    // Hash file type.
    append!ubyte(&digest, 0);

    // Hash file permissions.
    append!ushort(&digest, statbuf.st_mode & octal!"777");

    // Hash file size.
    append!ulong(&digest, statbuf.st_size);

    // Hash file contents.
    const fd = os.openat(dirfd, path, os.O_RDONLY, 0);
    scope (exit) os.close(fd);
    foreach (chunk; readChunks!4096(fd))
        digest.put(chunk);
}

private @safe
void hashFileAtDir(D)(
    ref D                digest,
        int              dirfd,
        const(char)[]    path,
    ref const(os.stat_t) statbuf,
)
{
    import snowflake.utility.dirent : dirents;
    import std.algorithm.sorting : sort;

    // Hash file type.
    append!ubyte(&digest, 1);

    // Hash file permissions.
    append!ushort(&digest, statbuf.st_mode & octal!"777");

    // Hash directory entries.
    const fd = os.openat(dirfd, path, os.O_DIRECTORY | os.O_RDONLY, 0);
    scope (exit) os.close(fd);
    foreach (dirent; dirents(fd).sort) {
        digest.put(cast(immutable(ubyte)[]) dirent);
        append!ubyte(&digest, 0);
        hashFileAt(digest, fd, dirent);
    }

    // Mark end of directory entries.
    append!ubyte(&digest, 0);
}

private @safe
void hashFileAtLnk(D)(ref D digest, int dirfd, const(char)[] path)
{
    // Hash file type.
    append!ubyte(&digest, 2);

    // Symbolic links don't have permission bits.
    { }

    // Hash link target.
    const target = os.readlinkat(dirfd, path);
    digest.put(cast(const(ubyte)[]) target);

    // Mark end of link target.
    append!ubyte(&digest, 0);
}

@safe
unittest
{
    import snowflake.utility.blake3 : Blake3;
    import std.algorithm.iteration : map;
    import std.array : Appender;
    import std.string : format;

    Appender!(ubyte[]) appender;
    hashFileAt(appender, os.AT_FDCWD, "testdata/hashFile");
    const buffer = appender[];

    ubyte[] expected = [
        1, 1, 237,
            'b', 'r', 'o', 'k', 'e', 'n', '.', 'l', 'n', 'k', 0,
                2, 'e', 'n', 'o', 'e', 'n', 't', '.', 't', 'x', 't', 0,
            'd', 'i', 'r', 'e', 'c', 't', 'o', 'r', 'y', 0,
                1, 1, 237,
                    'b', 'a', 'r', '.', 't', 'x', 't', 0,
                        0, 1, 164,
                            0, 0, 0, 0, 0, 0, 0, 4,
                            'b', 'a', 'r', '\n',
                    'f', 'o', 'o', '.', 't', 'x', 't', 0,
                        0, 1, 164,
                            0, 0, 0, 0, 0, 0, 0, 4,
                            'f', 'o', 'o', '\n',
                    0,
            'r', 'e', 'g', 'u', 'l', 'a', 'r', '.', 't', 'x', 't', 0,
                0, 1, 164,
                    0, 0, 0, 0, 0, 0, 0, 14,
                    'H', 'e', 'l', 'l', 'o', ',', ' ',
                    'w', 'o', 'r', 'l', 'd', '!', '\n',
            's', 'y', 'm', 'l', 'i', 'n', 'k', '.', 'l', 'n', 'k', 0,
                2, 'r', 'e', 'g', 'u', 'l', 'a', 'r', '.', 't', 'x', 't', 0,
            0,
    ];

    alias message = () => format!"[%(%s, %)]"(buffer.map!`cast(char) a`);
    assert (buffer == expected, message());

    const b3hash = hashFileAt(os.AT_FDCWD, "testdata/hashFile");
    assert (b3hash == Blake3(expected).finish());
}
