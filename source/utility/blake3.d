module snowflake.utility.blake3;

// See `c/blake.h` in the BLAKE3 repository.
extern (C) nothrow private pure @nogc
{
    enum BLAKE3_BLOCK_LEN = 64;
    enum BLAKE3_MAX_DEPTH = 54;
    enum BLAKE3_OUT_LEN   = 32;

    struct blake3_chunk_state {
        uint[8] cv;
        ulong chunk_counter;
        ubyte[BLAKE3_BLOCK_LEN] buf;
        ubyte buf_len;
        ubyte blocks_compressed;
        ubyte flags;
    }

    struct blake3_hasher
    {
        uint[8] key;
        blake3_chunk_state chunk;
        ubyte cv_stack_len;
        ubyte[(BLAKE3_MAX_DEPTH + 1) * BLAKE3_OUT_LEN] cv_stack;
    }

    @system
    const(char)* blake3_version();

    @system
    void blake3_hasher_init(scope blake3_hasher* self);

    @system
    void blake3_hasher_update(
        scope blake3_hasher* self,
        scope const(void)*   input,
        size_t               input_len,
    );

    @system
    void blake3_hasher_finalize(
        scope blake3_hasher* self,
        scope ubyte*         out_,
        size_t               out_len,
    );
}

// Check that BLAKE3 is still ABI-compatible.
static this()
{
    import std.string : fromStringz;
    const b3version = blake3_version().fromStringz;
    assert (
        b3version == "1.3.1",
        "BLAKE3 is of unexpected version " ~ b3version ~ ". " ~
        "Please check that the D signatures still match the C interface, " ~
        "and change the version number in this failed assertion."
    );
}

/**
 * BLAKE3 hasher state.
 */
struct Blake3
{
private:
    blake3_hasher inner = void;

public:
    @disable this();      // Hasher requires non-trivial initialization.
    @disable this(this);  // Copying a hasher is most likely an accident.

    /**
     * Initialize the hasher and feed it the given input.
     *
     * You can leave the input `null` and call `put` instead if desired.
     * `Blake3(input).finish()` is just a convenient way to use this.
     */
    nothrow pure @nogc @trusted
    this(scope const(ubyte)[] input) scope
    {
        blake3_hasher_init(&inner);
        if (input.length != 0)
            put(input);
    }

    /**
     * Feed data into the hasher.
     */
    nothrow pure @nogc @trusted
    void put(scope const(ubyte)[] input) scope
    {
        blake3_hasher_update(&inner, input.ptr, input.length);
    }

    /**
     * Extract the hash from the hasher.
     */
    nothrow pure @nogc @trusted
    ubyte[32] finish() scope
    {
        ubyte[32] out_;
        blake3_hasher_finalize(&inner, out_.ptr, out_.length);
        return out_;
    }
}
