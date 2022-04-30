module snowflake.main;

@safe
void main(string[] args)
{
    import core.time : dur;
    import snowflake.actionPhase.runAction : RunAction, performRunAction;
    import snowflake.config : COREUTILS_PATH;
    import snowflake.context : Context;

    auto context = new Context(".snowflake");

    const script = `
        set -efuo pipefail
        export PATH=` ~ COREUTILS_PATH ~ `/bin
        echo 'Hello, world!'
        touch /output/main.o
    `;

    RunAction runAction;
    runAction.program   = "/bin/sh";
    runAction.arguments = ["bash", "-c", script];
    runAction.outputs   = ["main.o"];
    runAction.timeout   = 5000.dur!"msecs";

    performRunAction(context, runAction);
}
