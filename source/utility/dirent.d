module snowflake.utility.dirent;

import os = snowflake.utility.os;

/**
 * List all entries of the given directory, in arbitrary order.
 * The entries `.` and `..` are omitted from the result.
 */
@safe
string[] dirents(int fd)
{
    fd = os.fcntl_dupfd(fd);
    auto dir = os.fdopendir(fd);
    return dirents(dir);
}

/// ditto
@safe
string[] dirents(ref scope os.DIR dir)
{
    import std.array : Appender;

    Appender!(string[]) result;

    for (;;) {

        auto dirent = os.readdir(dir);
        if (dirent.isNull)
            break;

        const name = dirent.get.d_name;
        if (name == "." || name == "..")
            continue;

        result ~= name.idup;

    }

    return result[];
}
