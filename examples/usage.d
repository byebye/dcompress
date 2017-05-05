import std.stdio;
import dcompress.gzip;
import dcompress.lzma;
import dcompress.bz2;

void main() {
/*  
    auto zipFile = new ZipFile("file.zip");
    auto gzFile = new GzipFile("file.gzip");
    auto bz2File = new Bz2File("file.bz2");
    
    auto tarFile = new TarFile("file.tar");
    auto tarGzFile = new TarFile("file.tar.gz"); // transparent decompression
*/

//    import std.zlib : compress;
    struct X { int a, b, c; string s; }
    auto x = X(1, 2, 3, "aaaa");
    string a = "aaa";
    compress(a);
    import std.stdio;
    import std.file;
    "xxx".compress();
    File("test.txt", "r").byChunk(1024 * 4).compress();
    //pragma(msg, ElementType!(typeof(stdout.lockingBinaryWriter)).stringof);
    //pragma(msg, is(isOutputRange!(typeof(stdout), E) && (is(E == ubyte) || is(E : void[]))));
    File("test.txt", "r").byLine.compress(stdout.lockingTextWriter);
    //auto data = compress(x);

}
