module integer;

import jni_d.jni_d;

shared static this()
{
    if (!jvmIsRunning)
        jvmInit();
        
    import std.stdio;
    writeln("Creating integer");

    import java.lang.JInteger;
    auto ji1 = new JInteger(42);
    writeln("Created integer 1");
}

shared static ~this()
{
    if (jvmIsRunning)
        jvmDestroy();
}
