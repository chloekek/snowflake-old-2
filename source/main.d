// SPDX-License-Identifier: AGPL-3.0-only

module snowflake.main;

@safe
void main(string[] args)
{
    import core.time : dur;
    import snowflake.actionPhase.common : performAction;
    import snowflake.actionPhase.runAction : PerformRunAction, performRunAction;
    import snowflake.config : COREUTILS_PATH;
    import snowflake.context : Context;
    import std.stdio : writeln;

    auto context = new Context(".snowflake");

    const script = `
        set -efuo pipefail
        export PATH=` ~ COREUTILS_PATH ~ `/bin
        echo 'foo'
        1>&2 echo 'bar'
        echo 'Hello, world!' > /outputs/main.h
        touch /outputs/main.o
    `;

    PerformRunAction info;
    info.program   = "/bin/sh";
    info.arguments = ["bash", "-c", script];
    info.timeout   = 500.dur!"msecs";

    const status = performAction(
        context,
        ["main.h", "main.o"],
        (ref context) => performRunAction(context, info),
    );
    (() @trusted => writeln(status))();
}
