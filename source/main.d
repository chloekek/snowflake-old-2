module snowflake.main;

@safe
void main()
{
    import snowflake.actionPhase.runAction : enterRunActionSandbox;
    import std.process : spawnShell, wait;

    enterRunActionSandbox();

    auto pid = spawnShell(`
        /nix/store/l0zvs9z152zys4sxa64hkvnxalgkszpi-coreutils-9.0/bin/ls -alh
    `);
    wait(pid);
}
