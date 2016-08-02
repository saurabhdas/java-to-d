module integer;

import jni_d.jni_d;

shared static this()
{
    if (!jvmIsRunning)
        jvmInit();
        
    import std.stdio;

    import java.lang.JString;
    auto s1 = JString.valueOf(true);

    import java.lang.JSystem;
//    JSystem.jout.print(s1);
}

shared static ~this()
{
    if (jvmIsRunning)
        jvmDestroy();
}
