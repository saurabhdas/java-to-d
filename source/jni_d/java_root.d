module jni_d.java_root;

import jni_d.jni;
import jni_d.support;

interface JavaRootInterface
{
    protected jobject _jniObjectPtr();
}

class JavaRootObject : Object, JavaRootInterface
{
    private jobject _jniObjectPtrValue;

    protected final jobject _jniObjectPtr()
    {
        return _jniObjectPtrValue;
    }

    protected this(jobject ptr)
    {
        _jniObjectPtrValue = ptr;
    }

    ~this()
    {
        destroyObject(_jniObjectPtr);
    }
}

class JavaRootThrowable : Throwable, JavaRootInterface
{
    private jobject _jniObjectPtrValue;
    
    protected final jobject _jniObjectPtr()
    {
        return _jniObjectPtrValue;
    }

    protected this(jobject ptr)
    {
        _jniObjectPtrValue = ptr;
    }

    ~this()
    {
        destroyObject(_jniObjectPtr);
    }
}

class JavaArray(T) : JavaRootObject
{
    this(jobject ptr)
    {
        assert(false, "Not implement yet :(");
    }
}
