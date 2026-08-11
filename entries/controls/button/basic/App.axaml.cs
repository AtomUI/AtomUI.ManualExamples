using AtomUI;
using AtomUI.Desktop.Controls;
using AtomUI.Fonts.AlibabaSans;
using AtomUI.Theme;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;

namespace AtomUI.ManualExamples.Controls.Button.Basic;

public partial class App : Application
{
    public override void Initialize()
    {
        this.UseAtomUI(builder =>
        {
            builder.WithInitialTheme(IThemeManager.DEFAULT_THEME_ID);
            builder.UseAlibabaSansFont();
            builder.WithDefaultFontFamily("fonts:AlibabaSans#Alibaba Sans, $Default");
            builder.UseDesktopControls();
        });
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is ISingleViewApplicationLifetime singleViewLifetime)
        {
            singleViewLifetime.MainView = new MainView();
        }

        base.OnFrameworkInitializationCompleted();
    }
}
