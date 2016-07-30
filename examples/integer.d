module integer;

import jni_d.jni_d;

shared static this()
{
    if (!jvmIsRunning)
        jvmInit();
}

shared static ~this()
{
    if (isjvmRunning)
        jvmDestroy();
}
