module snowflake.main;

@safe
void main(string[] args)
{
    import core.time : dur;
    import snowflake.actionPhase.runAction : RunAction, performRunAction;
    import snowflake.config : COREUTILS_PATH;
    import snowflake.context : Context;
    import snowflake.utility.error : UserException, formatTerminal;
    import std.stdio : write;

    auto context = new Context(".snowflake");

    const script = `
        set -efuo pipefail
        export PATH=` ~ COREUTILS_PATH ~ `/bin
        echo 'Hello, world!'
        touch /output/main.o
        sleep 1
    `;

    RunAction runAction;
    runAction.program   = "/bin/sh";
    runAction.arguments = ["bash", "-c", script];
    runAction.outputs   = ["main.h", "main.o"];
    runAction.timeout   = 500.dur!"msecs";

    try
        performRunAction(context, runAction);
    catch (UserException ex)
        write(ex.error.formatTerminal);
}
