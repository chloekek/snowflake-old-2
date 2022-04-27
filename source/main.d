module snowflake.main;

@safe
void main()
{
    import snowflake.actionPhase.runAction;
    import snowflake.context : Context;

    import os = snowflake.utility.os;

    auto context = new Context(".snowflake");

    executeRunAction(context);

    os.chdir(".snowflake/scratches/0");
    enterRunActionSandbox();
}
