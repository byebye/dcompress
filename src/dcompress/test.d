module dcompress.test;

struct InputRange(T, string opt = "noLength")
if (opt == "noLength" || opt == "withLength")
{
    T[] buffer;
    @property T front() { return buffer[0]; }
    @property void popFront() { buffer = buffer[1 .. $]; }
    @property bool empty() { return buffer.length == 0; }
    static if (opt == "withLength")
    {
        @property size_t length() { return buffer.length; }
    }
}

InputRange!(T, opt) inputRange(string opt = "noLength", T)(T[] buffer)
{
    return InputRange!(T, opt)(buffer);
}

struct OutputRange(T)
{
    T[] buffer;
    @property void put(T elem) { buffer ~= elem; }
}

