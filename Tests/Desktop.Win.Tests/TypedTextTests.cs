using Remotely.Desktop.Win.Services;

namespace Remotely.Desktop.Win.Tests;

[TestClass]
public class TypedTextTests
{
    [DataTestMethod]
    [DataRow("abc", "abc")]
    [DataRow("čćđ ČĆĐ žš @€", "čćđ ČĆĐ žš @€")]
    [DataRow("a{+}b{^}c{%}d{~}e{(}f{)}", "a+b^c%d~e(f)")]
    [DataRow("{{}x{}}{[}y{]}", "{x}[y]")]
    [DataRow("{ENTER}", "{ENTER}")]
    [DataRow("a{", "a{")]
    [DataRow("a{b", "a{b")]
    [DataRow("1\r\n2\n3\r4", "1\r2\r3\r4")]
    [DataRow("a\tb", "a\tb")]
    [DataRow("", "")]
    public void ParseTypedText_UnwrapsSendKeysBracesAndTurnsLineBreaksIntoEnter(string sent, string typed)
    {
        Assert.AreEqual(typed, string.Concat(KeyboardMouseInputWin.ParseTypedText(sent)));
    }
}
