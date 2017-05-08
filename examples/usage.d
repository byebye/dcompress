import std.stdio;
//import dcompress.gzip;
//import dcompress.lzma;
//import dcompress.bz2;
//import dcompress.file;
import d_zlib = dcompress.zlib;

import std.zlib : std_compress = compress;
import std.algorithm : joiner;
import std.array : array;

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

    auto comp = d_zlib.Compressor(1024);
    auto data = ["aaa", "bbb", "ccc", "dafasdfadfaf", "dfadfa", "adfaf" ];
    ubyte[] output;

    auto c2 = d_zlib.Compressor(1024);
    auto o = c2.compress(data.joiner.array).dup;
    o ~= c2.flush();
    writeln(o);
    foreach (chunk; data)
    {
        output ~= cast(ubyte[]) comp.compress(chunk);
        while (!comp.needsInput)
            output ~= cast(ubyte[])comp.continueCompress();
    }
    do
        output ~= cast(ubyte[])comp.flush();
    while (comp.outputAvailableFlush);
    writeln(output);

    writeln(std_compress(data.joiner.array));
}
