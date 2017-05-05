import std.range.primitives : isInputRange;

struct Archive(R)
if (isInputRange!R) 
{

    private R _input;

    public:

    this(R input)
    {
        _input = input;
    }
}

