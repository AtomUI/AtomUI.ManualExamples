using System.Runtime.Versioning;
using Avalonia;
using Avalonia.Browser;

[assembly: SupportedOSPlatform("browser")]

namespace AtomUI.ManualExamples.Controls.Button.Basic;

internal static class Program
{
    public static async Task Main(string[] args)
    {
        await AppBuilder.Configure<App>()
            .LogToTrace()
            .StartBrowserAppAsync("out");
    }
}

