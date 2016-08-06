module jni_d;

static import jni_d.jni_d;
static import jni_d.java_root;

alias jvmIsRunning = jni_d.jni_d.jvmIsRunning;
alias jvmInit = jni_d.jni_d.jvmInit;
alias jvmDestroy = jni_d.jni_d.jvmDestroy;

alias JavaArray = jni_d.java_root.JavaArray;
