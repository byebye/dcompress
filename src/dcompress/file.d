module dcompress.file;

import std.stdio : File;

struct FileStat
{
    import core.sys.posix.sys.stat;
    import std.string : fromStringz;

private:

    stat_t _stat;

public:

    @disable this();

    this(string filename)
    {
        import std.string : toStringz;
        this(filename.toStringz);
    }

    this(const(char)* filename)
    {
        lstat(filename, &_stat);
    }

    uint fileType()
    {
        return (_stat.st_mode & S_IFMT);
    }

    /// Number of hard links to the file.
    ulong hardLinksCount() const
    {
        return _stat.st_nlink;
    }

    /// User ID of file.
    uint userId() const
    {
        return _stat.st_uid;
    }

    /// User name of file.
    string userName() const
    {
        import core.sys.posix.pwd : passwd, getpwuid_r;
        //import core.sys.posix.unistd : sysconf, _SC_GETPW_R_SIZE_MAX;
        //immutable size = sysconf(_SC_GETPW_R_SIZE_MAX);
        //assert(size != -1);
        char[1024] buffer = void;
        passwd pwd;
        passwd* result;
        getpwuid_r(groupId(), &pwd, buffer.ptr, buffer.length, &result);
        assert(result != null);
        return fromStringz(result.pw_name).idup;
    }

    /// Group ID of file.
    uint groupId() const
    {
        return _stat.st_gid;
    }

    /// File mode - permissions, setgid, setuid and sticky bit.
    uint mode() const
    {
        //static immutable mask =
        //    (S_ISUID | S_ISGID | S_ISVTX | S_IRWXU | S_IRWXG | S_IRWXO);
        //return _stat.st_mode & mask;
        return _stat.st_mode;
    }

    /// Group name of file.
    string groupName() const
    {
        import core.sys.posix.grp : group, getgrgid_r;
        //import core.sys.posix.unistd : sysconf, _SC_GETGR_R_SIZE_MAX;
        //immutable size = sysconf(_SC_GETGR_R_SIZE_MAX);
        //assert(size != -1);
        char[1024] buffer = void;
        group grp;
        group* result;
        getgrgid_r(groupId(), &grp, buffer.ptr, buffer.length, &result);
        assert(result != null);
        return fromStringz(result.gr_name).idup;
    }

    /// For regular files, the file size in bytes. For symbolic links, the
    /// length in bytes of the pathname contained in the symbolic link.
    ulong size() const
    {
        return _stat.st_size;
    }

    private static immutable(uint) minorBits = 20;
    private static immutable(uint) minorMask = ((1U << minorBits) - 1);

    static uint makeDeviceNumber(uint major, uint minor)
    {
        return (major << minorBits) | minor;
    }

    /// Device ID major number (if file is character or block special).
    uint deviceMajorNumber() const
    {
        return cast(uint) ((_stat.st_rdev) >> minorBits);
    }

    /// Device ID minor number (if file is character or block special).
    uint deviceMinorNumber() const
    {
        return ((_stat.st_rdev) & minorMask);
    }

    /// Time of last access.
    long accessTime() const
    {
        return _stat.st_atime;
    }

    /// Time of last data modification.
    long modificationTime() const
    {
        return _stat.st_mtime;
    }

    /// Time of last status change.
    long statusChangeTime() const
    {
        return _stat.st_ctime;
    }

    /// A file system-specific preferred I/O block size for this object. In some
    /// file system types, this may vary from file to file.
    long blockSize() const
    {
        return _stat.st_blksize;
    }

    /// Number of blocks allocated for this object.
    long blockCount() const
    {
        return _stat.st_blocks;
    }
}
