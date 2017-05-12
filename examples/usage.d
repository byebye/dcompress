import std.stdio;
//import dcompress.gzip;
//import dcompress.lzma;
//import dcompress.bz2;
//import dcompress.file;
import d_zlib = dcompress.zlib;

import std_zlib = std.zlib;
import std.algorithm : map, joiner;
import std.array : array, join;

void main() {
/+
    auto zipFile = new ZipFile("file.zip");
    auto gzFile = new GzipFile("file.gzip");
    auto bz2File = new Bz2File("file.bz2");
+/
/+
    auto tarFile = new TarFile("file.tar");
    auto tarGzFile = new TarFile("file.tar.gz"); // transparent decompression
+/

    //struct X { int a, b, c; string s; }
    //auto x = X(1, 2, 3, "aaaa");
    //string a = "aaa";
    //compress(a);
    //import std.stdio;
    //import std.file;
    //"xxx".compress();
    //File("test.txt", "r").byChunk(1024 * 4).compress();
    //File("test.txt", "r").byLine.compress(stdout.lockingTextWriter);
    ////auto data = compress(x);
    //
    //auto gzipFile = CompressedFile!Gzip("test.gz", "rw", 1024);
    //
    //auto bz2File = CompressedFile!Bz2("test.bz2");


    immutable data = ["aaa", "bbb", "ccc", "dafasdfadfaf", "dfadfa", "adfaf" ];
    immutable dataJoined = data.dup.joiner.array;
    {
        auto policy = d_zlib.CompressionPolicy.defaultPolicy();
        policy.buffer = new ubyte[2];
        auto comp = d_zlib.Compressor.create(policy);
        ubyte[] output;
        foreach (chunk; data)
        {
            output ~= cast(ubyte[]) comp.compress(chunk);
            while (comp.outputPending)
                output ~= cast(ubyte[])comp.compressPending();
        }
        do
        {
            output ~= cast(ubyte[])comp.flush();
        }
        while (comp.outputPending);
        writeln(output);
    }
    {
        auto c2 = d_zlib.Compressor.create();
        auto o = cast(ubyte[]) c2.compress(dataJoined).dup;
        o ~= cast(ubyte[]) c2.flush();
        writeln(o);
    }
    {
        struct R
        {
            immutable(string)[] s;
            @property string front() { return s[0]; }
            @property void popFront() { s = s[1 .. $]; }
            @property bool empty() { return s.length == 0; }
        }
        writeln(d_zlib.compress(data[]));
        writeln(d_zlib.compress!(typeof(data[]))(data[]));
        writeln((d_zlib.compress(R(data))));
        writeln(d_zlib.compress(dataJoined));
    }
    {
        writeln(std_zlib.compress(data));
    }
    {
        auto comp = new std_zlib.Compress;
        ubyte[] output = data.map!(chunk => cast(ubyte[])comp.compress(chunk.dup)).join;
        output ~= cast(ubyte[]) comp.flush();
        writeln(output);
    }
}
