// SPDX-License-Identifier: AGPL-3.0-only

module snowflake.main;

@safe
void main(string[] args)
{
    import core.time : dur;
    import snowflake.actionPhase.runAction : PerformRunAction, performRunAction;
    import snowflake.config : COREUTILS_PATH;
    import snowflake.context : Context;
    import snowflake.utility.error : UserException, formatTerminal;
    import std.stdio : write;

    auto context = new Context(".snowflake");

    const script = `
        set -efuo pipefail
        export PATH=` ~ COREUTILS_PATH ~ `/bin
        echo 'foo'
        1>&2 echo 'bar'
        echo 'Hello, world!' > /output/main.h
        touch /output/main.o
    `;

    PerformRunAction info;
    info.program   = "/bin/sh";
    info.arguments = ["bash", "-c", script];
    info.outputs   = ["main.h", "main.o"];
    info.timeout   = 500.dur!"msecs";

    try
        performRunAction(context, info);
    catch (UserException ex)
        write(ex.error.formatTerminal);
}
