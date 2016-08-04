module detail.dmodule_writer;

import detail.ast_resolver;

@safe:

@trusted:
uint writeAll(in SymbolTable st, string outputDirectory = ".")
{
    uint num;

    assert(outputDirectory !is null);
    foreach(item; st.table.byKeyValue)
    {
        auto app1 = appender!string;
        auto app2 = appender!(DName[]);
        
        auto proceed = st.table.get(item.key, null).serializeFull(app1, app2, 0);
        if (!proceed)
            continue;

        auto modStringName = convModuleName(item.key).extract;
        auto mText = chain(["module ", modStringName, ";\n", "\n"],
            ["static import jni_d.jni;\n", "static import jni_d.jni_d;\n", "static import jni_d.jni_interface;\n", "static import jni_d.jni_array;\n", "\n"],
            sort(app2.data.filter!(a => a != DName.init).map!(a => a.extract).filter!(a => a != modStringName).array).uniq.map!(a => "static import " ~ a ~ ";\n").array,
            ["\n", app1.data, "\n"]).join;

        auto mPath = convModuleName(item.key).extract.replace(".", "/") ~ ".d";

        logInfo("Writing '", convModuleName(item.key).extract, "'");
        ++num;

        import std.file, std.path;
        mkdirRecurse(outputDirectory ~ "/" ~ dirName(mPath));
        write(outputDirectory ~ "/" ~ mPath, mText);
    }

    return num;
}

