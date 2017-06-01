/++
 +
 +/
module dcompress.tar;

import dcompress.tar.internal;

debug = tar;

debug(tar)
{
    import std.stdio;
}

/// File types supported by tar format.
enum FileType : char
{
    regular = '0',
    regularCompatibility = '\0',
    // This flag represents a file linked to another file, of any type,
    // previously archived. Such files are identified in Unix by each file
    // having the same device and inode number. The linked-to name is specified
    // in the `TarHeader.linkedToFilename`.
    hardLink = '1',
    // This represents a symbolic link to another file. The linked-to name is
    // specified in the `TarHeader.linkedToFilename`.
    symbolicLink = '2',
    // These represent character special files and block special files
    // respectively. In this case the `TarHeader.deviceMajorNumber` and
    // `TarHeader.deviceMinorNumber` fields will contain the major and minor
    // device numbers respectively. Operating systems may map the device
    // specifications to their own local specification, or may ignore the entry.
    characterSpecial = '3',
    blockSpecial = '4',
    // This flag specifies a directory or sub-directory. The directory name in
    // the `TarHeader.filename` field should end with a slash. On systems where
    // disk allocation is performed on a directory basis, the `TarHeader.size`
    // field will contain the maximum number of bytes (which may be rounded to
    // the nearest disk block allocation unit) which the directory may hold. A
    // size field of zero indicates no such limiting. Systems which do not
    // support limiting in this manner should ignore the size field.
    directory = '5',
    // This specifies a FIFO special file. Note that the archiving of a FIFO
    // file archives the existence of this file and not its contents.
    fifoSpecial = '6',

    //// This specifies a contiguous file, which is the same as a normal file
    //// except that, in operating systems which support it, all its space is
    //// allocated contiguously on the disk. Operating systems which do not allow
    //// contiguous allocation should silently treat this type as a normal file.
    //contiguous = '7',
    //// Extended header referring to the next file in the archive.
    //extendedHeaderNext = 'x',
    //// Global extended header
    //extendedHeaderGlobal = 'g',
}

/// Type of the file.
FileType fileTypeFromStat(uint fileTypeMask)
{
    import core.sys.posix.sys.stat;
    switch (fileTypeMask)
    {
        case S_IFREG: return FileType.regular;
        case S_IFDIR: return FileType.directory;
        case S_IFLNK: return FileType.symbolicLink;
        case S_IFBLK: return FileType.blockSpecial;
        case S_IFCHR: return FileType.characterSpecial;
        case S_IFIFO: return FileType.fifoSpecial;
        default: assert(0, "Unsupported file type.");
    }
}

uint fileTypeToStatMode(FileType fileType)
{
    import core.sys.posix.sys.stat;
    final switch (fileType)
    {
        case FileType.regular: return S_IFREG;
        case FileType.regularCompatibility: return S_IFREG;
        case FileType.hardLink: return S_IFREG;
        case FileType.directory: return S_IFDIR;
        case FileType.symbolicLink: return S_IFLNK;
        case FileType.blockSpecial: return S_IFBLK;
        case FileType.characterSpecial: return S_IFCHR;
        case FileType.fifoSpecial: return S_IFIFO;
    }
}

/// Bits used in the `TarHeader.mode` field, values in octal.
struct FileMode
{
    alias iuint = immutable(uint);
    import std.conv : octal;
    /// set user ID upon execution
    static iuint setUid  = octal!4000;
    /// set group ID upon execution
    static iuint setGid  = octal!2000;
    /// sticky bit
    static iuint restrictedDeletion = octal!1000;

    static iuint ownerRead  = octal!400;
    static iuint ownerWrite = octal!200;
    static iuint ownerExec  = octal!100;

    static iuint groupRead  = octal!40;
    static iuint groupWrite = octal!20;
    static iuint groupExec  = octal!10;

    static iuint otherRead  = octal!4;
    static iuint otherWrite = octal!2;
    static iuint otherExec  = octal!1;
}

unittest
{
    import core.sys.posix.sys.stat;
    //writefln("S: %o %o %o", S_ISUID, S_ISGID, S_ISVTX);
    //writefln("U: %o %o %o %o", S_IRWXU, S_IRUSR, S_IWUSR, S_IXUSR);
    //writefln("G: %o %o %o %o", S_IRWXG, S_IRGRP, S_IWGRP, S_IXGRP);
    //writefln("O: %o %o %o %o", S_IRWXO, S_IROTH, S_IWOTH, S_IXOTH);

    assert(FileMode.setUid == S_ISUID);
    assert(FileMode.setGid == S_ISGID);
    assert(FileMode.restrictedDeletion == S_ISVTX);

    assert(FileMode.ownerRead == S_IRUSR);
    assert(FileMode.ownerWrite == S_IWUSR);
    assert(FileMode.ownerExec == S_IXUSR);

    assert(FileMode.groupRead == S_IRGRP);
    assert(FileMode.groupWrite == S_IWGRP);
    assert(FileMode.groupExec == S_IXGRP);

    assert(FileMode.otherRead == S_IROTH);
    assert(FileMode.otherWrite == S_IWOTH);
    assert(FileMode.otherExec == S_IXOTH);
}


class TarException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

void enforceSuccess(int status)
{
    if (status == 0)
        return;

    import std.string : fromStringz;
    import core.stdc.string : strerror;
    import core.stdc.errno;

    string msg = fromStringz(strerror(errno)).idup;
    throw new TarException(msg);
}

struct TarMember
{
    import std.datetime : SysTime;

    string filename;
    string linkedToFilename;
    size_t size;
    FileType fileType;
    uint mode;
    uint userId;
    uint groupId;
    string userName;
    string groupName;
    uint deviceMajorNumber;
    uint deviceMinorNumber;
    private SysTime _modificationTime;

    @property void modificationTime(long unixTime)
    {
        _modificationTime = SysTime.fromUnixTime(unixTime);
    }

    @property void modificationTime(SysTime time)
    {
        _modificationTime = time;
    }

    @property SysTime modificationTime() const
    {
        return _modificationTime;
    }

    static TarMember fromTarHeader(TarHeader header)
    {
        import std.string : fromStringz;
        import std.path : buildNormalizedPath, isValidPath;

        TarMember member;

        member.filename = buildNormalizedPath(
            fromStringz(header.prefix.ptr), fromStringz(header.filename.ptr));

        assert(member.filename.isValidPath);

        member.linkedToFilename = fromStringz(header.linkedToFilename.ptr).idup;

        import std.conv : to;
        member.fileType = to!FileType(header.fileTypeFlag[0]);

        T octalParse(T)(char[] slice)
        {
            import std.conv : parse;
            return parse!T(slice, 8);
        }

        member.size = octalParse!size_t(header.size);
        member.mode = octalParse!uint(header.mode);
        member.userId = octalParse!uint(header.userId);
        member.groupId = octalParse!uint(header.groupId);

        member.userName = fromStringz(header.userName.ptr).idup;
        member.groupName = fromStringz(header.groupName.ptr).idup;

        member.deviceMajorNumber = octalParse!uint(header.deviceMajorNumber);
        member.deviceMinorNumber = octalParse!uint(header.deviceMinorNumber);

        member.modificationTime = octalParse!long(header.modificationTime);

        return member;
    }

    static TarMember fromFile(string filename)
    {
        import dcompress.file : FileStat;
        auto stat = FileStat(filename);

        TarMember member;
        member.filename = filename;
        member.fileType = fileTypeFromStat(stat.fileType());
        if (member.fileType == FileType.regular ||
            member.fileType == FileType.regularCompatibility ||
            member.fileType == FileType.hardLink)
            member.size = stat.size();
        if (member.fileType == FileType.symbolicLink)
        {
            import std.file : readLink;
            member.linkedToFilename = readLink(filename);
        }
        member.userId = stat.userId();
        member.groupId = stat.groupId();
        member.userName = stat.userName();
        member.groupName = stat.groupName();
        member.mode = stat.mode();
        if (member.fileType == FileType.characterSpecial ||
            member.fileType == FileType.blockSpecial)
        {
            member.deviceMajorNumber = stat.deviceMajorNumber;
            member.deviceMinorNumber = stat.deviceMinorNumber;
        }

        member.modificationTime = stat.modificationTime;

        return member;
    }
}

TarHeader toTarHeader()(const auto ref TarMember member)
{
    TarHeader header;

    assert(member.filename.length < header.filename.sizeof + header.prefix.sizeof);

    string withTrailingSlash(string path)
    {
        if (path.length == 0 || path[$ - 1] == '/')
            return path;
        return path ~= "/";
    }

    if (member.filename.length >= header.filename.sizeof)
    {
        import std.path : dirName, baseName;
        auto dir = withTrailingSlash(member.filename.dirName);
        auto base = member.filename.baseName;
        if (member.fileType == FileType.directory)
            base = withTrailingSlash(base);

        assert (dir.length < header.prefix.sizeof && base.length < header.filename.sizeof);

        header.prefix.assignAndZeroTrailing(dir);
        header.filename.assignAndZeroTrailing(base);
    }
    else
    {
        auto f = (member.fileType == FileType.directory) ?
            withTrailingSlash(member.filename) : member.filename;
        header.filename.assignAndZeroTrailing(f);
    }

    header.linkedToFilename.assignAndZeroTrailing(member.linkedToFilename);

    header.fileTypeFlag[0] = member.fileType;

    void octalFormat(T)(char[] dest, T n)
    {
        import std.format : sformat;
        // Size == 5 is sufficient - 1 or 2 digits only
        char[5] fmt;
        sformat(fmt, "%%0%02do", dest.length - 1);
        sformat(dest, fmt, n);
    }

    octalFormat(header.size[], member.size);
    octalFormat(header.mode[], member.mode);
    octalFormat(header.userId[], member.userId);
    octalFormat(header.groupId[], member.groupId);

    header.userName.assignAndZeroTrailing(member.userName);
    header.groupName.assignAndZeroTrailing(member.groupName);

    if (member.fileType == FileType.characterSpecial ||
        member.fileType == FileType.blockSpecial)
    {
        octalFormat(header.deviceMajorNumber[], member.deviceMajorNumber);
        octalFormat(header.deviceMinorNumber[], member.deviceMinorNumber);
    }

    auto unixTime = member.modificationTime.toUnixTime();
    octalFormat(header.modificationTime[], unixTime);

    octalFormat(header.checksum[0 .. $ - 1], header.calculateChecksum);
    header.checksum[$ - 1] = ' ';

    return header;
}

template isTarInput(R)
{
    import std.traits : Unqual;
    import std.range.primitives : isInputRange, ElementType;

    enum isTarInput = isInputRange!R && is(Unqual!(ElementType!R) == ubyte);
}

auto tarReader(bool withContent = true, TarInput)(TarInput input)
if (isTarInput!TarInput)
{
    return TarReader!(TarInput, withContent)(input);
}

import std.typecons : Tuple;
alias TarMemberWithContent = Tuple!(TarMember, "member", void[], "content");
alias TarMemberWithPosition = Tuple!(TarMember, "member", size_t, "position");

struct TarReader(TarInput, bool withContent = true)
if (isTarInput!TarInput)
{
    import std.traits : isArray;

private:

    TarInput _input;

    static if (withContent)
        TarMemberWithContent _member;
    else
    {
        size_t _position;
        TarMemberWithPosition _member;
    }
    bool _empty;

public:

    @disable this();

    this(TarInput input)
    {
        _input = input;
        popFront;
    }

    static if (withContent)
    {
        @property TarMemberWithContent front()
        {
            return _member;
        }
    }
    else
    {
        @property TarMemberWithPosition front()
        {
            return _member;
        }

        @property size_t position() const
        {
            return _position;
        }
    }

    @property bool empty()
    {
        return _empty;
    }

    @property void popFront()
    in
    {
        assert(!empty);
    }
    body
    {
        import std.range : take, refRange;
        import std.algorithm.mutation : copy;

        TarHeader tarHeader;
        auto headerBytes = cast(ubyte[]) tarHeader.asBytes;
        auto rem = refRange(&_input).take(tarBlockSize).copy(headerBytes);

        if (headerBytes[0] == '\0')
        {
            _empty = true;
            return;
        }
        else if (rem.length > 0)
            throw new TarException("Not enough bytes for tar header.");

        static if (isArray!TarInput)
            _input = _input[tarBlockSize .. $];

        auto member = TarMember.fromTarHeader(tarHeader);

        assert(tarHeader.calculateChecksum() ==
            member.toTarHeader.calculateChecksum());

        static if (withContent)
        {
            ubyte[] content;
            if (member.size > 0)
            {
                content.length = member.size;
                rem = refRange(&_input).take(content.length).copy(content);

                if (rem.length > 0)
                    throw new TarException("Not enough bytes for tar member content.");

                static if (isArray!TarInput)
                    _input = _input[content.length .. $];

                auto mod = member.size % tarBlockSize;
                if (mod > 0)
                {
                    import std.range.primitives : popFrontN;
                    auto popped = _input.popFrontN(tarBlockSize - mod);
                    assert(popped == tarBlockSize - mod);
                }
            }

            _member = TarMemberWithContent(member, content);
        }
        else
        {
            _position += tarBlockSize;
            _member = TarMemberWithPosition(member, _position);
            if (member.size > 0)
            {
                import std.range.primitives : popFrontN;

                auto toDrop = member.size.roundUpToMultiple(tarBlockSize);
                auto popped = _input.popFrontN(toDrop);
                assert(popped == toDrop);
                _position += toDrop;
            }
        }
    }
}

import dcompress.primitives : isCompressOutput;

TarWriter!TarOutput tarWriter(TarOutput)(TarOutput output)
if (isCompressOutput!TarOutput)
{
    return TarWriter!TarOutput(output);
}

struct TarWriter(TarOutput)
if (isCompressOutput!TarOutput)
{
private:

    TarOutput _output;
    size_t _writtenBytes;
    size_t _blockingFactor = 20; // number of records per block

public:

    private void padToMultiple(size_t n)
    {
        auto padding = _writtenBytes.roundUpToMultiple(n) - _writtenBytes;
        if (padding == 0)
            return;
        _writtenBytes += padding;
        import std.range : put, repeat, take;
        put(_output, '\0'.repeat.take(padding));
    }

    void finish()
    {
        padToMultiple(_blockingFactor * tarBlockSize);
    }

    void add(alias memberFilter = (TarMember member) => true)(
        string filename, bool recursive = true)
    {
        import dcompress.primitives : isPredicate;
        static if (!isPredicate!(memberFilter, TarMember))
            assert(false, "'filter' should be a predicate taking TarMember as an argument.");

        import std.file : exists;
        if (!exists(filename))
            throw new TarException("File '" ~ filename ~ "' does not exist.");

        import std.file : dirEntries;
        import std.traits : ReturnType;

        ReturnType!dirEntries entries;

        import std.file : isDir;
        if (recursive && isDir(filename))
        {
            import std.file : SpanMode;
            entries = dirEntries(filename, SpanMode.breadth);
        }

        import std.algorithm.iteration : map, filter, each;
        import std.range : only, chain;

        only(filename).chain(entries)
            .map!(name => TarMember.fromFile(name))
            .filter!(member => memberFilter(member))
            .each!(member => addReadContent(member));
    }

    void addReadContent(TarMember member)
    {
        debug(tar)
            writefln("Adding file to tar: %s (size: %d)",
                member.filename, member.size);

        if (member.size > 0)
        {
           auto sourceFile = File(member.filename, "rb");
           assert(member.size == sourceFile.size);
           ubyte[4096] chunk;
           add(member, sourceFile.byChunk(chunk[]));
        }
        else
        {
            add(member);
        }
    }

    void add(TarMember member)
    {
        auto header = member.toTarHeader();

        import std.range.primitives : put;
        put(_output, cast(ubyte[]) header.asBytes);

        _writtenBytes += tarBlockSize;
    }

    import dcompress.primitives : isCompressInput;

    void add(InR)(TarMember member, InR content)
    if (isCompressInput!InR)
    {
        add(member);

        if (member.size > 0)
        {
            import std.range.primitives : put;
            put(_output, content);

            _writtenBytes += member.size;

            padToMultiple(tarBlockSize);
        }
    }
}

import dcompress.primitives : isCompressInput;

void extract(InR)(TarMember member, InR content, string destPath = ".")
if (isCompressInput!InR)
{
    if (destPath.length == 0)
        destPath = ".";

    import std.path : isValidPath, exists, isDir, buildPath;
    if (!isValidPath(destPath) || (exists(destPath) && !isDir(destPath)))
        throw new TarException("Invalid destination path: '" ~ destPath ~ "'");

    import std.path : dirName, baseName;
    import std.file : write, mkdirRecurse;

    immutable fullPath = buildPath(destPath, member.filename);
    destPath = buildPath(destPath, dirName(member.filename));

    // Do not overwrite existing filess
    if (exists(fullPath))
        return;

    mkdirRecurse(destPath);

    debug(tar) writeln("Destination: ", fullPath);

    import dcompress.file : FileStat;
    import std.string : toStringz;
    immutable fullPathC = fullPath.toStringz;

    if (member.fileType == FileType.directory)
    {
        import core.sys.posix.sys.stat : mkdir;
        mkdir(fullPathC, member.mode).enforceSuccess;
    }
    else if (member.fileType == FileType.symbolicLink)
    {
        import core.sys.posix.unistd : symlink;
        symlink(member.linkedToFilename.toStringz, fullPathC).enforceSuccess;
    }
    else
    {
        immutable mode = (member.mode | fileTypeToStatMode(member.fileType));
        immutable devNumber = FileStat.makeDeviceNumber(
            member.deviceMajorNumber, member.deviceMinorNumber);

        import core.sys.posix.sys.stat : mknod;
        mknod(fullPathC, mode, devNumber).enforceSuccess;
    }

    if (member.size > 0)
    {
        import std.stdio : File;
        import std.algorithm.mutation : copy;

        auto file = File(fullPath, "ab");
        content.copy(file.lockingBinaryWriter);
    }

    import core.sys.posix.unistd : lchown;
    lchown(fullPathC, member.userId, member.groupId).enforceSuccess;

    auto stat = FileStat(fullPath);

    import core.sys.posix.sys.time;
    import core.sys.posix.sys.stat : utimensat;

    timespec[2] newTime;
    newTime[0].tv_sec = stat.accessTime();
    newTime[1].tv_sec = member.modificationTime.toUnixTime();

    import core.sys.posix.fcntl : AT_FDCWD, AT_SYMLINK_NOFOLLOW;

    utimensat(AT_FDCWD, fullPathC, newTime, AT_SYMLINK_NOFOLLOW).enforceSuccess;
}

struct TarFile
{
    import std.stdio : File;

private:

    TarMemberWithPosition[string] _members;

    File _file;
    TarWriter!(File.BinaryWriterImpl!true) _tarWriter;
    size_t _blockingFactor = 20; // number of records per block

public:

    static TarFile open(string path)
    {
        TarFile tarFile;
        tarFile._file = File(path, "rb+");

        import std.algorithm.iteration : joiner;

        ubyte[4096] chunk;
        auto fileInput = tarFile._file.byChunk(chunk).joiner;
        auto reader = tarReader!false(fileInput);

        import std.range : refRange;
        foreach (mp; refRange(&reader))
        {
            tarFile._members[mp.member.filename] = mp;
            debug(tar)
            {
                writeln("------------------");
                writeln(mp.member);
            }
        }

        debug(tar)
            writefln("Position: %d, Size: %d", reader.position, tarFile._file.size);
        tarFile._file.seek(reader.position);
        tarFile._tarWriter = tarWriter(tarFile._file.lockingBinaryWriter);

        return tarFile;
    }

    ~this()
    {
        close();
    }

    void close()
    {
        if (_file.isOpen)
        {
            _tarWriter.finish();
            _file.close();
        }
    }

    @property size_t size()
    {
        return _file.size();
    }

    private ubyte[] readContentAt(size_t pos, size_t size)
    {
        if (size == 0)
            return [];

        ubyte[] buf = new ubyte[size];

        immutable prevPos = _file.tell();
        _file.seek(pos);
        _file.rawRead(buf);
        _file.seek(prevPos);

        return buf;
    }

    void[] readMemberContent(string filename)
    {
        auto mp = (filename in _members);
        assert(mp !is null);

        if (mp.member.size == 0)
            return null;

        return readContentAt(mp.position, mp.member.size);
    }

    void add(alias memberFilter = (TarMember member) => true)(
        string filename, bool recursive = true)
    {
        _tarWriter.add!memberFilter(filename, recursive);
    }

    void addReadContent(TarMember member)
    {
        _tarWriter.addReadContent(member);
    }

    import dcompress.primitives : isCompressInput;

    void add(InR)(TarMember member, InR content)
    if (isCompressInput!InR)
    {
        _tarWriter.add(member, content);
    }

    void extract(string memberFilename, string destPath = ".")
    {
        auto mp = (memberFilename in _members);
        assert(mp !is null);

        ubyte[] content = readContentAt(mp.position, mp.member.size);

        .extract(mp.member, content, destPath);
    }

    void extractAll(string destPath = ".")
    {
        import std.algorithm.iteration : each;
        _members.byKey.each!(filename => extract(filename, destPath));
    }
}

