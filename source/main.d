module snowflake.main;

@safe
void main(string[] args)
{
    import core.time : dur;
    import snowflake.actionPhase.runAction : performRunAction;
    import snowflake.context : Context;

    auto context = new Context(".snowflake");

    performRunAction(context, 5000.dur!"msecs", ["main.o"]);
}
