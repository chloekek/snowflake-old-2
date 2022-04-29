module snowflake.main;

@safe
void main()
{
    import snowflake.actionPhase.runAction;
    import snowflake.context : Context;
    import snowflake.utility.hashFile : hashFileAt;
    import std.stdio : writefln;

    import os = snowflake.utility.os;

    const hash = hashFileAt(os.AT_FDCWD, "/home/r/snowflake/source");
    writefln!"%(%02x%)"(hash);

    auto context = new Context(".snowflake");

    executeRunAction(context, ["main.o"]);

    os.chdir(".snowflake/scratches/0");
    enterRunActionSandbox();
}
