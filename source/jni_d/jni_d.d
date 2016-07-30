module jni_d.jni_d;

static import java.lang.JObject;
private import jni_d.jni;
private import std.conv : to;
private import std.string;

// Return value: Was a new JVM init'd or was there an existing one already
bool jvmIsRunning()
{
    return (_jvm !is null);
}

void jvmInit(string classpath)
{
    assert(!jvmIsRunning);

    JavaVMInitArgs vm_args;
    JavaVMOption[] options = new JavaVMOption[1];
    options[0].optionString = cast(char*) toStringz("-Djava.class.path=" ~ classpath);
    
    vm_args.version_ = JNI_VERSION_1_6;
    vm_args.nOptions = 1;
    vm_args.options = options.ptr;
    vm_args.ignoreUnrecognized = false;
    
    auto res = JNI_CreateJavaVM(&_jvm, cast(void**) &_env, &vm_args);
    if (res < 0)
        throw new Exception("Could not create JVM. Got return value '" ~ res.to!string ~ "' JNI_CreateJavaVM");
}

void jvmDestroy()
{
    assert(_jvm !is null);
    assert(_env !is null);

    auto res1 = (*_jvm).DetachCurrentThread(_jvm);
    if (res1 < 0)
        throw new Exception("Could not destroy JVM. Got return value '" ~ res1.to!string ~ "' from DetachCurrentThread");

    auto res2 = (*_jvm).DestroyJavaVM(_jvm);
    if (res2 < 0)
        throw new Exception("Could not destroy JVM. Got return value '" ~ res2.to!string ~ "' from DestroyJavaVM");

    _jvm = null;
    _env = null;
}

class JavaArray(T) : java.lang.JObject.JObject
{
}

struct InternalConstructorInfo
{
    jobject javaPointer;
}

jclass loadClass(string name)
{
    assert(_jvm !is null);
    assert(_env !is null);

    jclass cls = (*_env).FindClass(_env, toStringz(name.replace(".", "/")));
    if (cls is null)
        throw new Exception("Could not load class '" ~ name ~ "'");
    return cls;
}

private:

__gshared JavaVM* _jvm;
__gshared JNIEnv* _env;
