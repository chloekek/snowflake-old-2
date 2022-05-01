// SPDX-License-Identifier: AGPL-3.0-only

module snowflake.utility.io;

/**
 * Foreach aggregate that yields up-to-`N`-sized chunks of data from a file.
 * The buffer is allocated on the call stack and reused across chunks.
 */
struct readChunks(size_t N)
{
private:
    int fd;

public:
    @disable this();
    @disable this(this);

    /**
     * Read chunks from the given file descriptor.
     * The file descriptor is borrowed, not owned.
     */
    this(int fd)
    {
        this.fd = fd;
    }

    /**
     * Implements the foreach aggregate interface.
     */
    int opApply(scope int delegate(scope ubyte[]) @safe dg)
    {
        import os = snowflake.utility.os;

        ubyte[4096] buf = void;

        for (;;) {

            auto subbuf = os.read(fd, buf);
            if (subbuf.length == 0)
                return 0;

            const status = dg(subbuf);
            if (status != 0)
                return status;

        }
    }
}
