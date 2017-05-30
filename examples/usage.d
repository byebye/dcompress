import std.stdio;
//import dcompress.gzip;
//import dcompress.lzma;
//import dcompress.bz2;
//import dcompress.file;
import dcompress.zlib;

import std_zlib = std.zlib;
import std.algorithm : map, joiner;
import std.array : array, join;
import std.stdio;

void testZlib()
{
    immutable data = ["aaa", "bbb", "ccc", "dafasdfadfaf", "dfadfa", "adfaf" ];
    immutable dataJoined = data.dup.joiner.array;

    {
        auto c = Compressor.create();
        c.compress(dataJoined);
        c.flush();
        c.flush();
        c.flush();
        c.flush();
        c.flush();
    }
    {
        auto policy = CompressionPolicy.defaultPolicy();
        policy.buffer = new ubyte[2];
        auto comp = Compressor.create(policy);
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
        auto c2 = Compressor.create();
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
        writeln(compress(data[]));
        writeln((compress(R(data))));
        writeln(compress(dataJoined));
    }
    {
        writeln(std_zlib.compress(data));
    }
    {
        auto comp = new std_zlib.Compress;
        ubyte[] output = data.map!(chunk => cast(ubyte[]) comp.compress(chunk.dup)).join;
        output ~= cast(ubyte[]) comp.flush();
        writeln(output);
    }
}

void testBz2()
{
    import dcompress.etc.c.bz2;

    //File f = File("examples/test.bz2");
    //auto data = new ubyte[](f.size);
    //f.rawRead(data);
    //writeln(data);

    ubyte[] data = [66, 90, 104, 57, 49, 65, 89, 38, 83, 89, 107, 38, 89, 215,
    0, 0, 5, 85, 128, 0, 16, 64, 5, 0, 4, 46, 167, 222, 0, 32, 0, 80, 166, 19,
    77, 1, 166, 33, 20, 240, 153, 12, 73, 167, 148, 62, 214, 57, 2, 136, 10,
    193, 67, 46, 70, 42, 205, 217, 226, 214, 126, 122, 178, 155, 77, 109, 175,
    1, 149, 2, 136, 131, 113, 209, 68, 254, 46, 228, 138, 112, 161, 32, 214,
    76, 179, 174];

    auto output = new ubyte[](4096);
    bz_stream stream;
    stream.avail_out = cast(uint)output.length;
    stream.next_out = output.ptr;

    int init_error = BZ2_bzDecompressInit(&stream, 0, 0);
    int bzipresult = BZ2_bzDecompress(&stream);

    stream.avail_in = cast(uint)data.length;
    stream.next_in = data.ptr;

    bzipresult = BZ2_bzDecompress(&stream);
    int read = stream.total_out_lo32;
    BZ2_bzDecompressEnd(&stream);
    writeln(cast(string) output[0 .. read]);
}

void bz2()
{
    import dcompress.bz2;
    auto data = "Lorem ipsum dolor sit amet";
    writeln(compress(data));
}

void testTarRead()
{
    import std.file : read;
    import dcompress.tar;
    auto bytes = cast(ubyte[]) read("tests/tar_ex.tar");
    auto reader = tarReader(bytes);
    foreach (mc; reader)
    {
        writeln("------------------");
        writeln(mc.member);
    }
}

void testTarOpen()
{
    import dcompress.tar;
    auto tar = TarFile.open("tests/tar_ex.tar");
    TarMember member;
    member.filename = "lib/lalala.txt";
    //member.linkedToFilename =
    member.fileType = FileType.regular;
    //member.content = cast(void[]) "lalala";
    //member.size = member.content.length;
    member.mode = 420;
    member.userId = 1000;
    member.groupId = 1000;
    member.userName = "byebye";
    member.groupName = "byebye";
    member.deviceMajorNumber = 0;
    member.deviceMinorNumber = 0;
    import std.datetime : SysTime;
    member.modificationTime = SysTime.fromUnixTime(13106354744);
    //tar.add(member);
    auto stat = FileStat("lib");
    writeln("GROUP: ", stat.groupName());
    writeln("USER: ", stat.userName());
    writefln("MODE: %o", stat.mode());
    writefln("Size: %d", stat.size());
}

void testTarAddRecursive()
{
    import dcompress.tar;
    auto tar = TarFile.open("tests/empty.tar");
    tar.add("tests/tar_ex/");
}

void testTarExtract()
{
    import dcompress.tar;
    auto tar = TarFile.open("tests/tar_ex.tar");
    tar.extractAll("out2/");
}

void testTarWrite()
{
    import dcompress.tar;
    import std.array : appender;
    auto app = appender!(ubyte[])();
    auto writer = tarWriter(app);
    writer.add("tests/tar_ex/");
    writer.finish();
    writeln("Archive size: ", app.data.length);
    foreach (mc; tarReader(app.data))
    {
        writeln("------------------");
        writeln(mc.member);
    }
}

void main() {
    //testBz2();
    //bz2();
    //testTarRead();
    //testTarOpen();
    //testTarAddRecursive();
    //testTarExtract();
    testTarWrite();
}
