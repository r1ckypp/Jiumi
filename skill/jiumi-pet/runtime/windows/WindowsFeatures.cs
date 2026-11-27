using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

internal sealed partial class PetWindow
{
    private const int WmHotkey = 0x0312;
    private const int WmInput = 0x00ff;
    private const int WmPowerBroadcast = 0x0218;
    private const int WmDisplayChange = 0x007e;
    private const int ExtendedStyle = -20;
    private const int TransparentStyle = 0x20;
    private readonly DispatcherTimer fullscreen = new() { Interval = TimeSpan.FromMilliseconds(350) };
    private HwndSource? windowSource;
    private int activeHotkey;
    private Shortcut? registeredShortcut;
    private bool typingRegistered;
    private bool manuallyHidden;
    private bool fullscreenHidden;
    private bool sleeping;

    private sealed record Shortcut(ModifierKeys Modifiers, int Key)
    {
        public override string ToString() => string.Join("+",
            new[] { ModifierKeys.Control, ModifierKeys.Alt, ModifierKeys.Shift, ModifierKeys.Windows }
                .Where(part => Modifiers.HasFlag(part)).Select(part => part.ToString()).Append(KeyInterop.KeyFromVirtualKey(Key).ToString()));
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RawInputDevice
    {
        public ushort UsagePage;
        public ushort Usage;
        public uint Flags;
        public IntPtr Target;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RawInputHeader
    {
        public uint Type;
        public uint Size;
        public IntPtr Device;
        public IntPtr Parameters;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RawKeyboardInput
    {
        public RawInputHeader Header;
        public ushort MakeCode;
        public ushort Flags;
        public ushort Reserved;
        public ushort VirtualKey;
        public uint Message;
        public uint ExtraInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left, Top, Right, Bottom;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr window, int id);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterRawInputDevices(ref RawInputDevice device, uint count, uint size);

    [DllImport("user32.dll")]
    private static extern uint GetRawInputData(IntPtr input, uint command, ref RawKeyboardInput data, ref uint size, uint headerSize);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int ReadWindowStyle(IntPtr window, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]
    private static extern int WriteWindowStyle(IntPtr window, int index, int style);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out NativeRect rect);

    [DllImport("user32.dll")]
    private static extern bool IsZoomed(IntPtr window);

    private void InitializeSystem(object? sender, EventArgs args)
    {
        windowSource = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
        windowSource?.AddHook(SystemMessage);
        ApplyPassThrough();
        ReplaceHotkey(preferences.Hotkey);
        fullscreen.Tick += (_, _) => CheckFullscreen();
        fullscreen.Start();
    }

    private void DisposeSystem()
    {
        fullscreen.Stop();
        ReplaceHotkey(null);
        RegisterTyping(false);
        if (windowSource is { IsDisposed: false } source) source.RemoveHook(SystemMessage);
    }

    private IntPtr SystemMessage(IntPtr handle, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == WmHotkey && wParam.ToInt32() == activeHotkey)
        {
            Toggle();
            handled = true;
        }
        if (message == WmPowerBroadcast)
        {
            if (wParam.ToInt32() == 4)
            {
                sleeping = true;
                SyncTyping();
                _ = Script("stage.feedback.setVisible(false);");
            }
            else if (wParam.ToInt32() is 7 or 18)
            {
                sleeping = false;
                CheckFullscreen();
                SyncTyping();
                _ = Script($"stage.feedback.setVisible({(IsVisible ? "true" : "false")});");
            }
        }
        if (message == WmDisplayChange)
            Dispatcher.BeginInvoke(EnsureVisiblePosition);
        if (message == WmInput && typingRegistered && preferences.Typing && IsVisible && !sleeping)
        {
            // Inspect the keyboard transition flag only. Key values never leave this callback.
            var input = new RawKeyboardInput();
            uint size = (uint)Marshal.SizeOf<RawKeyboardInput>();
            uint headerSize = (uint)Marshal.SizeOf<RawInputHeader>();
            if (GetRawInputData(lParam, 0x10000003, ref input, ref size, headerSize) == size &&
                input.Header.Type == 1 && (input.Flags & 1) == 0)
            {
                _ = Script("""
                    stage.feedback.dispatch({v:1,id:crypto.randomUUID(),source:'typing',type:'typing.stroke',at:Date.now()});
                    """);
            }
        }
        return IntPtr.Zero;
    }

    private void ApplyPassThrough()
    {
        if (windowSource is not { } source)
            return;
        int style = ReadWindowStyle(source.Handle, ExtendedStyle);
        WriteWindowStyle(source.Handle, ExtendedStyle,
            preferences.PassThrough ? style | TransparentStyle : style & ~TransparentStyle);
    }

    private bool ReplaceHotkey(Shortcut? shortcut)
    {
        if (windowSource is not { } source)
            return shortcut == null;
        if (shortcut == registeredShortcut)
            return true;
        int next = activeHotkey == 1 ? 2 : 1;
        if (shortcut != null &&
            !RegisterHotKey(source.Handle, next, (uint)shortcut.Modifiers | 0x4000, (uint)shortcut.Key))
            return false;
        if (activeHotkey != 0)
            UnregisterHotKey(source.Handle, activeHotkey);
        activeHotkey = shortcut == null ? 0 : next;
        registeredShortcut = shortcut;
        return true;
    }

    private void RegisterTyping(bool enabled)
    {
        if (windowSource is not { } source || enabled == typingRegistered)
            return;
        var device = new RawInputDevice
        {
            UsagePage = 1, Usage = 6, Flags = enabled ? 0x100u : 1u,
            Target = enabled ? source.Handle : IntPtr.Zero
        };
        if (RegisterRawInputDevices(ref device, 1, (uint)Marshal.SizeOf<RawInputDevice>()))
            typingRegistered = enabled;
    }

    private void SyncTyping() => RegisterTyping(ready && IsVisible && !sleeping && preferences.Typing &&
        character?.plugins.Any(plugin => plugin.typing && plugin.enabled) == true);

    private void EnsureVisiblePosition()
    {
        if (windowSource is not { } source || !GetWindowRect(source.Handle, out var rect))
            return;
        var point = new System.Drawing.Point((rect.Left + rect.Right) / 2, (rect.Top + rect.Bottom) / 2);
        if (Forms.Screen.AllScreens.Any(screen => screen.WorkingArea.Contains(point)))
            return;
        ResetPosition();
        SavePosition();
    }

    private void CheckFullscreen()
    {
        if (!ready || windowSource is not { } source)
            return;
        var foreground = GetForegroundWindow();
        if (preferences.AvoidFullscreen &&
            (foreground == source.Handle || (settings is { } window && foreground == new WindowInteropHelper(window).Handle)))
            return;
        bool covered = false;
        if (preferences.AvoidFullscreen && foreground != IntPtr.Zero &&
            GetWindowRect(foreground, out var rect) && !(IsZoomed(foreground) && (ReadWindowStyle(foreground, -16) & 0x00c00000) != 0))
        {
            // The pet HWND retains its screen when hidden.
            var monitor = Forms.Screen.FromHandle(source.Handle).Bounds;
            var active = Forms.Screen.FromHandle(foreground).Bounds;
            covered = monitor == active && rect.Left <= monitor.Left + 2 && rect.Top <= monitor.Top + 2 &&
                      rect.Right >= monitor.Right - 2 && rect.Bottom >= monitor.Bottom - 2;
        }
        if (covered == fullscreenHidden)
            return;
        fullscreenHidden = covered;
        UpdateVisibility();
    }

    private void UpdateVisibility()
    {
        bool visible = !manuallyHidden && !fullscreenHidden;
        if (IsVisible == visible)
            return;
        if (visible)
            Show();
        else
        {
            StopDrag();
            Hide();
        }
        _ = Script($"stage.feedback.setVisible({(visible ? "true" : "false")});");
        SyncTyping();
    }

    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private string LoginItemName => "Jiumi." + petId.ToString("N");

    private bool CanRegisterLogin =>
        File.Exists(Path.Combine(AppContext.BaseDirectory, "pet-id.txt")) &&
        File.Exists(Path.Combine(AppContext.BaseDirectory, "pet.html"));

    private bool IsLoginEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(LoginItemName) is string;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return false;
        }
    }

    private void SetLoginEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (enabled)
                key.SetValue(LoginItemName, "\"" + Environment.ProcessPath + "\"", RegistryValueKind.String);
            else
                key.DeleteValue(LoginItemName, false);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            MessageBox.Show(settings ?? this, error.Message, Title);
        }
    }
}
