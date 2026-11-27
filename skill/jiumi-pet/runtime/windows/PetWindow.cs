using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Forms = System.Windows.Forms;

internal sealed partial class PetWindow : Window
{
    private readonly WebView2CompositionControl player = new()
    {
        DefaultBackgroundColor = System.Drawing.Color.Transparent
    };
    private readonly System.Drawing.Icon trayIcon =
        System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? System.Drawing.SystemIcons.Application;
    private readonly Forms.NotifyIcon tray;
    private readonly Forms.ContextMenuStrip menu = new();
    private readonly DispatcherTimer drag = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private readonly string stateDirectory;
    private readonly Uri page;
    private System.Drawing.Point origin;
    private readonly Guid petId;
    private readonly string initialLanguage;
    private Preferences preferences = new();
    private bool chinese => (preferences.Language ?? initialLanguage) == "zh-CN";
    private Window? settings;
    private ContextMenu? petMenu;
    private bool ready;

    private sealed record Interaction(string @event, string label);

    private sealed record Position(double Left, double Top);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string html = Path.GetFullPath(args.Length > 0 ? args[0] : Path.Combine(AppContext.BaseDirectory, "pet.html"));
            string identity = args.Length > 1 ? args[1] : File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "pet-id.txt")).Trim();
            string language = args.Length > 2 ? args[2] : File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "language.txt")).Trim();
            string name = args.Length > 3 ? args[3] : File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "client-name.txt")).Trim();
            if (!File.Exists(html))
                throw new FileNotFoundException("Pet HTML was not found.", html);
            var app = new Application();
            return app.Run(new PetWindow(html, Guid.Parse(identity), language, name));
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Jiumi", MessageBoxButton.OK, MessageBoxImage.Error);
            return 1;
        }
    }

    private PetWindow(string html, Guid id, string language, string name)
    {
        page = new Uri(html);
        petId = id;
        initialLanguage = language;
        stateDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Jiumi", "pets", id.ToString());
        Directory.CreateDirectory(stateDirectory);
        Title = name;
        Width = 260;
        Height = 300;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        Content = player;
        RestorePreferences();
        ApplyWindowPreferences();
        RefreshTray();
        tray = new Forms.NotifyIcon
        {
            Text = name.Length > 63 ? name[..63] : name,
            Icon = trayIcon,
            ContextMenuStrip = menu,
            Visible = true
        };
        tray.DoubleClick += (_, _) => Toggle();
        drag.Tick += (_, _) => MoveWithPointer();
        SourceInitialized += InitializeSystem;
        Loaded += InitializePlayer;
        Closed += (_, _) =>
        {
            drag.Stop();
            DisposeSystem();
            if (petMenu != null)
                petMenu.IsOpen = false;
            settings?.Close();
            SavePosition();
            tray.Dispose();
            trayIcon.Dispose();
            menu.Dispose();
            player.Dispose();
        };
        if (preferences.RememberPosition) RestorePosition();
        else ResetPosition();
    }

    private async void InitializePlayer(object sender, RoutedEventArgs args)
    {
        Loaded -= InitializePlayer;
        try
        {
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: Path.Combine(stateDirectory, "WebView2"));
            if (!IsLoaded)
                return;
            await player.EnsureCoreWebView2Async(environment);
            var core = player.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled = false;
            await core.AddScriptToExecuteOnDocumentCreatedAsync(
                "window.petPluginOverrides=" + JsonSerializer.Serialize(preferences.Plugins) + ";");
            await core.AddScriptToExecuteOnDocumentCreatedAsync("""
                window.jiumiWindowsHost = true;
                document.addEventListener('contextmenu', event => {
                    event.preventDefault();
                    window.chrome.webview.postMessage('jiumi:menu');
                });
                """);
            core.Settings.AreDevToolsEnabled = false;
            core.NavigationStarting += (_, navigation) => navigation.Cancel = navigation.Uri != page.AbsoluteUri;
            core.NewWindowRequested += (_, request) => request.Handled = true;
            core.WebMessageReceived += async (_, message) =>
            {
                if (message.Source != page.AbsoluteUri)
                    return;
                switch (message.WebMessageAsJson)
                {
                    case "\"jiumi:grab:begin\"":
                        origin = Forms.Cursor.Position;
                        drag.Start();
                        break;
                    case "\"jiumi:menu\"":
                        await OpenPetMenu();
                        break;
                    case "\"jiumi:grab:end\"":
                        StopDrag();
                        break;
                }
            };
            core.NavigationCompleted += async (_, navigation) =>
            {
                if (!navigation.IsSuccess)
                {
                    MessageBox.Show(navigation.WebErrorStatus.ToString(), Title);
                    Application.Current.Shutdown(1);
                    return;
                }
                ready = true;
                EnsureVisiblePosition();
                await ApplyPlayerPreferences();
                await RefreshCharacter();
                RenderSettings();
            };
            core.Navigate(page.AbsoluteUri);
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, Title);
            Application.Current.Shutdown(1);
        }
    }

    private string Localized(string zh, string en) => chinese ? zh : en;

    private (string Label, Action Run)[] ManagementActions() =>
    [
        (Localized("显示 / 隐藏", "Show / Hide"), Toggle),
        (Localized("设置", "Settings"), OpenSettings),
        (Localized("重置位置", "Reset Position"), () => { ResetPosition(); SavePosition(); }),
        (Localized("退出", "Quit"), Close)
    ];

    private async System.Threading.Tasks.Task OpenPetMenu()
    {
        if (!ready || !IsVisible)
            return;
        var context = new ContextMenu { Placement = PlacementMode.MousePoint, PlacementTarget = player };
        try
        {
            string json = await player.CoreWebView2.ExecuteScriptAsync("document.querySelector('#stage')?.feedback?.menuItems ?? []");
            foreach (var item in OrderInteractions(JsonSerializer.Deserialize<Interaction[]>(json) ?? []).Where(item => !preferences.HiddenActions.Contains(item.@event)))
            {
                var entry = new MenuItem { Header = InteractionLabel(item) };
                entry.Click += async (_, _) => await SelectInteraction(item.@event);
                context.Items.Add(entry);
            }
        }
        catch (Exception error) when (error is InvalidOperationException or JsonException or COMException) { }

        if (!IsVisible)
            return;
        if (context.Items.Count > 0)
            context.Items.Add(new Separator());
        foreach (var action in ManagementActions())
        {
            var entry = new MenuItem { Header = action.Label };
            entry.Click += (_, _) => action.Run();
            context.Items.Add(entry);
        }
        if (petMenu != null)
            petMenu.IsOpen = false;
        petMenu = context;
        context.IsOpen = true;
    }

    private async System.Threading.Tasks.Task SelectInteraction(string action)
    {
        try
        {
            string encoded = JsonSerializer.Serialize(action);
            await player.CoreWebView2.ExecuteScriptAsync($"document.querySelector('#stage')?.feedback?.selectMenu({encoded})");
        }
        catch (Exception error) when (error is InvalidOperationException or COMException) { }
    }

    private void MoveWithPointer()
    {
        if ((GetAsyncKeyState(1) & 0x8000) == 0 || !IsVisible)
        {
            StopDrag();
            return;
        }

        var p = Forms.Cursor.Position;
        var scale = VisualTreeHelper.GetDpi(this);
        Left += (p.X - origin.X) / scale.DpiScaleX;
        Top += (p.Y - origin.Y) / scale.DpiScaleY;
        origin = p;
    }

    private void StopDrag()
    {
        if (!drag.IsEnabled)
            return;
        drag.Stop();
        SavePosition();
    }

    private void Toggle()
    {
        if (!ready)
            return;
        manuallyHidden = !manuallyHidden;
        UpdateVisibility();
    }

    private void ResetPosition()
    {
        var screen = Forms.Screen.FromPoint(Forms.Cursor.Position).WorkingArea;
        var scale = VisualTreeHelper.GetDpi(this);
        Left = screen.Right / scale.DpiScaleX - Width - 24;
        Top = screen.Bottom / scale.DpiScaleY - Height - 24;
    }

    private string PositionFile => Path.Combine(stateDirectory, "position.json");

    private void RestorePosition()
    {
        ResetPosition();
        try
        {
            if (JsonSerializer.Deserialize<Position>(File.ReadAllText(PositionFile)) is { } position &&
                double.IsFinite(position.Left) && double.IsFinite(position.Top))
            {
                var desktop = new Rect(SystemParameters.VirtualScreenLeft, SystemParameters.VirtualScreenTop,
                    SystemParameters.VirtualScreenWidth, SystemParameters.VirtualScreenHeight);
                if (desktop.Contains(new Point(position.Left + Width / 2, position.Top + Height - 70)))
                {
                    Left = position.Left;
                    Top = position.Top;
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { }
    }

    private void SavePosition()
    {
        if (!preferences.RememberPosition) return;
        try
        {
            File.WriteAllText(PositionFile, JsonSerializer.Serialize(new Position(Left, Top)));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}
