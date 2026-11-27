using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;

internal sealed partial class PetWindow
{
    private sealed class Preferences
    {
        public double Opacity { get; set; } = 1;
        public bool Topmost { get; set; } = true;
        public string? Language { get; set; }
        public int Theme { get; set; }
        public double Size { get; set; } = 1;
        public bool ShowName { get; set; }
        public int IdleMin { get; set; } = 8;
        public int IdleMax { get; set; } = 20;
        public bool RememberPosition { get; set; } = true;
        public bool PassThrough { get; set; }
        public bool AvoidFullscreen { get; set; } = true;
        public bool Typing { get; set; }
        public Shortcut? Hotkey { get; set; }
        public Dictionary<string, bool> Plugins { get; set; } = [];
        public Dictionary<string, string> ActionLabels { get; set; } = [];
        public HashSet<string> HiddenActions { get; set; } = [];
        public List<string> ActionOrder { get; set; } = [];
    }

    private sealed record Plugin(string id, string name, string version, bool enabled, string kind, string summary, string triggers, bool typing, SpeechDetails? speech);
    private sealed record SpeechDetails(int count, double minimum, double maximum, double duration);
    private sealed record Character(string name, Plugin[] plugins, Interaction[] actions);
    private Character? character;
    private static readonly int[] IdleOptions = [1, 3, 5, 8, 12, 15, 20, 30, 45, 60, 90, 120];

    private string PreferencesFile => Path.Combine(stateDirectory, "preferences.json");

    private void RestorePreferences()
    {
        try
        {
            var saved = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(PreferencesFile));
            if (saved != null)
                preferences = saved;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { }

        preferences.Opacity = Math.Clamp(preferences.Opacity, .35, 1);
        preferences.Size = Math.Clamp(preferences.Size, .65, 1.75);
        preferences.Theme = Math.Clamp(preferences.Theme, 0, 2);
        if (!IdleOptions.Contains(preferences.IdleMin) || !IdleOptions.Contains(preferences.IdleMax) ||
            preferences.IdleMin > preferences.IdleMax)
        {
            preferences.IdleMin = 8;
            preferences.IdleMax = 20;
        }
        preferences.Plugins ??= [];
        preferences.ActionLabels ??= [];
        preferences.HiddenActions ??= [];
        preferences.ActionOrder ??= [];
    }

    private void SavePreferences()
    {
        string staged = PreferencesFile + "." + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(staged, JsonSerializer.Serialize(preferences));
            File.Move(staged, PreferencesFile, true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            try { File.Delete(staged); }
            catch (Exception cleanup) when (cleanup is IOException or UnauthorizedAccessException) { }
            MessageBox.Show(settings ?? this, error.Message, Title);
        }
    }

    private string ClientLanguage => chinese ? "zh-CN" : "en";

    private void ApplyWindowPreferences()
    {
        Opacity = preferences.Opacity;
        Topmost = preferences.Topmost;
        Width = 260 * preferences.Size;
        Height = 300 * preferences.Size;
        player.ZoomFactor = preferences.Size;
        ApplyPassThrough();
    }

    private async Task<string?> Script(string script)
    {
        if (!ready)
            return null;
        try { return await player.CoreWebView2.ExecuteScriptAsync(script); }
        catch (Exception error) when (error is InvalidOperationException or COMException) { return null; }
    }

    private Task ApplyPlayerPreferences() => Script($$"""
        document.documentElement.lang={{JsonSerializer.Serialize(ClientLanguage)}};
        document.getElementById('label').hidden={{JsonSerializer.Serialize(!preferences.ShowName)}};
        stage.title=ui('轻点抚摸，长按拖动');
        stage.feedback.setIdleInterval({{preferences.IdleMin}},{{preferences.IdleMax}});
        stage.feedback.menuItems=petMenuItems(pet);
        """);

    private async Task RefreshCharacter()
    {
        string? state = await Script("""
            ({name:pet.name,plugins:[...(pet.modules??[]),...rules].map(module=>({
              id:module.id,name:module.name??module.id,version:String(module.version??1),
              enabled:pet.plugins.includes(module.id),kind:module.kind??(module.wasm?'wasm':'rule'),
              summary:typeof module.description==='string'?module.description.slice(0,320):'',
              triggers:Object.keys(module.enter??{}).concat(module.events??[],module.on??[]).filter(Boolean).slice(0,8).join(', '),
              typing:module.kind==='state-machine'&&Object.hasOwn(module.enter??{},'typing.stroke'),
              speech:module.kind==='speech'?{count:module.lines.length,minimum:module.minSeconds,
                maximum:module.maxSeconds,duration:module.durationSeconds}:null
            })),actions:stage.feedback.menuItems})
            """);
        if (state != null)
        {
            try { character = JsonSerializer.Deserialize<Character>(state); }
            catch (JsonException) { character = null; }
        }
        SyncTyping();
        RefreshTray();
    }

    private IEnumerable<Interaction> OrderInteractions(Interaction[] items)
    {
        var byId = items.ToDictionary(item => item.@event);
        return preferences.ActionOrder.Distinct().Where(byId.ContainsKey).Select(id => byId[id])
            .Concat(items.Where(item => !preferences.ActionOrder.Contains(item.@event)));
    }

    private string InteractionLabel(Interaction item) =>
        preferences.ActionLabels.GetValueOrDefault(item.@event, item.label);

    private void RefreshTray()
    {
        foreach (var item in menu.Items.Cast<System.Windows.Forms.ToolStripItem>().ToArray())
            item.Dispose();
        menu.Items.Clear();
        var interactions = OrderInteractions(character?.actions ?? []).Where(item => !preferences.HiddenActions.Contains(item.@event)).ToArray();
        if (interactions.Length > 0)
        {
            var group = new System.Windows.Forms.ToolStripMenuItem(Localized("互动", "Interactions"));
            foreach (var item in interactions)
                group.DropDownItems.Add(InteractionLabel(item), null, async (_, _) => await SelectInteraction(item.@event));
            menu.Items.Add(group);
            menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        }
        foreach (var action in ManagementActions())
            menu.Items.Add(action.Label, null, (_, _) => action.Run());
    }

    private void OpenSettings()
    {
        if (settings != null)
        {
            settings.Activate();
            return;
        }
        var window = new Window
        {
            Width = 720, Height = 530, MinWidth = 640, MinHeight = 440,
            WindowStartupLocation = WindowStartupLocation.CenterScreen
        };
        settings = window;
        window.Closed += (_, _) => { settings = null; SavePreferences(); };
        RenderSettings();
        window.Show();
        window.Activate();
    }

    private int settingsPage;

    private void RenderSettings()
    {
        if (settings is not { } window)
            return;
        window.Title = Title + " — " + Localized("设置", "Settings");
        ApplyTheme(window);
        (string Title, string Keywords, Action<StackPanel> Fill)[] pages =
        [
            (Localized("外观","Appearance"), "主题 大小 名字 不透明度 待机 theme size opacity name idle", AppearancePage),
            (Localized("桌宠窗口","Pet Window"), "置顶 全屏 穿透 位置 topmost fullscreen click through position", WindowPage),
            (Localized("输入与权限","Input & Permissions"), "陪打字 授权 键盘 typing input permissions", InputPage),
            (Localized("快捷键","Shortcuts"), "显隐 录入 快捷键 hotkey shortcut show hide", ShortcutsPage),
            (Localized("插件与互动","Plugins & Interactions"), "插件 详情 启停 菜单 排序 plugins actions menu", PluginsPage),
            (Localized("应用与系统","App & System"), "语言 启动 恢复 language login startup restore", SystemPage),
            (Localized("关于","About"), "版本 当前角色 导出 version character export", AboutPage)
        ];
        var root = new Grid { Margin = new Thickness(16) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(176) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var sidebar = new DockPanel { Margin = new Thickness(0, 0, 12, 0) };
        var search = new TextBox { Margin = new Thickness(0, 0, 0, 9), Padding = new Thickness(6) };
        AutomationProperties.SetName(search, Localized("搜索设置", "Search settings"));
        search.ToolTip = Localized("搜索设置", "Search settings");
        DockPanel.SetDock(search, Dock.Top);
        sidebar.Children.Add(search);
        var navigation = new ListBox();
        sidebar.Children.Add(navigation);
        root.Children.Add(sidebar);
        var content = new StackPanel { Margin = new Thickness(14, 4, 14, 12) };
        var scroll = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(scroll, 1);
        root.Children.Add(scroll);

        navigation.SelectionChanged += (_, _) =>
        {
            content.Children.Clear();
            if (navigation.SelectedItem is not ListBoxItem { Tag: int index })
                return;
            settingsPage = index;
            content.Children.Add(new TextBlock { Text = pages[index].Title, FontSize = 23, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 12) });
            pages[index].Fill(content);
            scroll.ScrollToTop();
        };

        void Filter()
        {
            int current = settingsPage;
            navigation.Items.Clear();
            for (int i = 0; i < pages.Length; i++)
            {
                var page = pages[i];
                if (!(page.Title + " " + page.Keywords).Contains(search.Text.Trim(), StringComparison.OrdinalIgnoreCase))
                    continue;
                var row = new ListBoxItem { Content = page.Title, Tag = i, Padding = new Thickness(7) };
                navigation.Items.Add(row);
                if (i == current)
                    navigation.SelectedItem = row;
            }
            if (navigation.SelectedIndex < 0 && navigation.Items.Count > 0)
                navigation.SelectedIndex = 0;
        }

        search.TextChanged += (_, _) => Filter();
        Filter();
        window.Content = root;
    }

    private void ApplyTheme(Window window)
    {
        // Apply the same Fluent palette to the window and its native control templates.
#pragma warning disable WPF0001
        window.ThemeMode = preferences.Theme switch
        {
            1 => ThemeMode.Light,
            2 => ThemeMode.Dark,
            _ => ThemeMode.System
        };
#pragma warning restore WPF0001
    }

    private static void Note(Panel parent, string text) => parent.Children.Add(new TextBlock
    {
        Text = text, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 10)
    });

    private static Button ButtonFor(Panel parent, string label, Action action)
    {
        var button = new Button { Content = label, Padding = new Thickness(9, 4, 9, 4),
                                  Margin = new Thickness(0, 3, 6, 4), HorizontalAlignment = HorizontalAlignment.Left };
        button.Click += (_, _) => action();
        parent.Children.Add(button);
        return button;
    }

    private static CheckBox ToggleFor(Panel parent, string label, bool value, Action<bool> update)
    {
        var toggle = new CheckBox { Content = label, IsChecked = value, Margin = new Thickness(0, 6, 0, 7) };
        toggle.Click += (_, _) => update(toggle.IsChecked == true);
        parent.Children.Add(toggle);
        return toggle;
    }

    private static ComboBox Choice(Panel parent, string label, IEnumerable<string> options, int index, Action<int> update)
    {
        Note(parent, label);
        var combo = new ComboBox { ItemsSource = options, SelectedIndex = index,
            MinWidth = 145, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 10) };
        AutomationProperties.SetName(combo, label);
        combo.SelectionChanged += (_, _) => { if (combo.SelectedIndex >= 0) update(combo.SelectedIndex); };
        parent.Children.Add(combo);
        return combo;
    }

    private void Percent(Panel parent, string label, int minimum, int maximum, double value, Action<double> update)
    {
        var readout = new TextBlock { Text = $"{label}  {value * 100:0}%" };
        var slider = new Slider { Minimum = minimum, Maximum = maximum, Value = Math.Round(value * 100),
            IsSnapToTickEnabled = true, TickFrequency = 1, Margin = new Thickness(0, 3, 0, 12) };
        AutomationProperties.SetName(slider, label);
        slider.ValueChanged += (_, _) =>
        {
            readout.Text = $"{label}  {slider.Value:0}%";
            update(slider.Value / 100);
        };
        slider.LostMouseCapture += (_, _) => SavePreferences();
        slider.PreviewKeyUp += (_, _) => SavePreferences();
        parent.Children.Add(readout);
        parent.Children.Add(slider);
    }

    private void AppearancePage(StackPanel panel)
    {
        Choice(panel, Localized("设置窗口主题", "Settings theme"),
            [Localized("跟随系统","System"), Localized("浅色","Light"), Localized("深色","Dark")], preferences.Theme, value =>
            {
                preferences.Theme = value;
                SavePreferences();
                if (settings != null) ApplyTheme(settings);
            });
        Percent(panel, Localized("角色大小","Pet size"), 65, 175, preferences.Size, value =>
        {
            preferences.Size = value;
            ApplyWindowPreferences();
        });
        Percent(panel, Localized("窗口不透明度","Opacity"), 35, 100, preferences.Opacity, value =>
        {
            preferences.Opacity = value;
            Opacity = value;
        });
        ToggleFor(panel, Localized("显示角色名字","Show pet name"), preferences.ShowName, async value =>
        {
            preferences.ShowName = value;
            SavePreferences();
            await ApplyPlayerPreferences();
        });
        var seconds = IdleOptions.Select(i => i + Localized(" 秒", " s")).ToArray();
        ComboBox? minimum = null, maximum = null;
        minimum = Choice(panel, Localized("最短待机间隔","Minimum idle interval"), seconds,
            Array.IndexOf(IdleOptions, preferences.IdleMin), value => UpdateIdle(IdleOptions[value], null));
        maximum = Choice(panel, Localized("最长待机间隔","Maximum idle interval"), seconds,
            Array.IndexOf(IdleOptions, preferences.IdleMax), value => UpdateIdle(null, IdleOptions[value]));
        void UpdateIdle(int? min, int? max)
        {
            if (min.HasValue)
            {
                preferences.IdleMin = min.Value;
                if (preferences.IdleMax < min.Value) maximum!.SelectedIndex = Array.IndexOf(IdleOptions, min.Value);
            }
            if (max.HasValue)
            {
                preferences.IdleMax = max.Value;
                if (preferences.IdleMin > max.Value) minimum!.SelectedIndex = Array.IndexOf(IdleOptions, max.Value);
            }
            SavePreferences();
            _ = ApplyPlayerPreferences();
        }
    }

    private void WindowPage(StackPanel panel)
    {
        ToggleFor(panel, Localized("保持桌宠置顶","Always on top"), preferences.Topmost, value =>
        {
            preferences.Topmost = Topmost = value;
            SavePreferences();
        });
        ToggleFor(panel, Localized("全屏时避让","Avoid full-screen apps"), preferences.AvoidFullscreen, value =>
        {
            preferences.AvoidFullscreen = value;
            SavePreferences();
            CheckFullscreen();
        });
        ToggleFor(panel, Localized("鼠标穿透","Click through"), preferences.PassThrough, value =>
        {
            preferences.PassThrough = value;
            ApplyPassThrough();
            SavePreferences();
        });
        Note(panel, Localized("可从托盘菜单打开设置并关闭鼠标穿透。", "Open Settings from the notification area to turn off click-through."));
        ToggleFor(panel, Localized("记住窗口位置","Remember position"), preferences.RememberPosition, value =>
        {
            preferences.RememberPosition = value;
            SavePreferences();
            SavePosition();
        });
        ButtonFor(panel, Localized("移回当前屏幕","Move to current screen"), () => { ResetPosition(); SavePosition(); });
    }

    private void InputPage(StackPanel panel)
    {
        bool hasPlugin = character?.plugins.Any(plugin => plugin.typing && plugin.enabled) == true;
        var status = new TextBlock();
        CheckBox? toggle = null;
        toggle = ToggleFor(panel, Localized("跨应用陪打字","Typing companion across apps"), preferences.Typing, value =>
        {
            preferences.Typing = value;
            SyncTyping();
            if (value && !typingRegistered && IsVisible)
            {
                preferences.Typing = false;
                MessageBox.Show(settings ?? this, Localized("无法启用键盘节奏监听。","Could not register for keyboard timing."), Title);
            }
            SavePreferences();
            UpdateStatus();
        });
        toggle.IsEnabled = hasPlugin;
        Note(panel, Localized("开启后只向桌宠发送敲击节奏，不记录文字或按键。", "When enabled, the pet receives timing only. Key values and typed text are discarded."));
        panel.Children.Add(status);
        UpdateStatus();
        void UpdateStatus()
        {
            if (toggle != null) toggle.IsChecked = preferences.Typing;
            status.Text = !hasPlugin ? Localized("请先启用陪打字插件。", "Enable a typing companion plugin first.") :
                typingRegistered ? Localized("键盘节奏监听已启用。", "Keyboard timing is active.") :
                Localized("键盘节奏监听未启用。", "Keyboard timing is inactive.");
        }
    }

    private void ShortcutsPage(StackPanel panel)
    {
        Note(panel, Localized("全局显隐快捷键", "Global show / hide shortcut"));
        Shortcut? pending = preferences.Hotkey;
        var field = new TextBox { IsReadOnly = true, Text = pending?.ToString() ?? Localized("未绑定","Unassigned"), Padding = new Thickness(5) };
        panel.Children.Add(field);
        var feedback = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Text = pending != null && registeredShortcut != pending
                ? Localized("保存的组合键当前不可用。", "The saved shortcut is currently unavailable.") : ""
        };
        bool recording = false;
        field.PreviewKeyDown += (_, e) =>
        {
            if (!recording) return;
            e.Handled = true;
            Key key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key == Key.Escape)
            {
                recording = false;
                field.Text = pending?.ToString() ?? Localized("未绑定","Unassigned");
                return;
            }
            var modifiers = Keyboard.Modifiers;
            if ((modifiers & (ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Windows)) == 0 ||
                key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin)
                return;
            pending = new Shortcut(modifiers, KeyInterop.VirtualKeyFromKey(key));
            field.Text = pending.ToString();
            recording = false;
        };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 4) };
        panel.Children.Add(buttons);
        ButtonFor(buttons, Localized("录入","Record"), () =>
        {
            recording = true;
            field.Text = Localized("按下组合键…","Press a key combination…");
            field.Focus();
        });
        ButtonFor(buttons, Localized("应用","Apply"), () =>
        {
            if (pending == null || !ReplaceHotkey(pending))
            {
                feedback.Text = Localized("组合键不可用。","Shortcut unavailable.");
                return;
            }
            preferences.Hotkey = pending;
            SavePreferences();
            feedback.Text = Localized("快捷键已保存。","Shortcut saved.");
        });
        ButtonFor(buttons, Localized("清除","Clear"), () =>
        {
            ReplaceHotkey(null);
            pending = preferences.Hotkey = null;
            field.Text = Localized("未绑定","Unassigned");
            SavePreferences();
            feedback.Text = Localized("快捷键已清除。","Shortcut cleared.");
        });
        panel.Children.Add(feedback);
    }

    private void PluginsPage(StackPanel panel)
    {
        Note(panel, Localized("已安装插件","Installed plugins"));
        foreach (var plugin in character?.plugins ?? [])
        {
            var row = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 2, 0, 2) };
            var info = new Button { Content = Localized("详情","Details"), Margin = new Thickness(8, 0, 0, 0), Padding = new Thickness(8, 4, 8, 4) };
            void Details()
            {
                var speech = plugin.speech;
                string speechLine = speech == null ? "" :
                    Localized($"{speech.count} 句台词，每隔 {speech.minimum}–{speech.maximum} 秒显示一条，停留 {speech.duration} 秒。",
                              $"{speech.count} lines, every {speech.minimum}–{speech.maximum} seconds, shown for {speech.duration} seconds.");
                MessageBox.Show(settings ?? this,
                    string.Join(Environment.NewLine, new[] { plugin.name + " " + plugin.version, plugin.kind, plugin.summary, plugin.triggers, speechLine }.Where(value => value.Length > 0)),
                    Localized("插件详情","Plugin details"));
            }
            AutomationProperties.SetName(info, Localized("插件详情 ", "Plugin details ") + plugin.name);
            info.Click += (_, _) => Details();
            DockPanel.SetDock(info, Dock.Right);
            row.Children.Add(info);
            var enabled = new CheckBox { IsChecked = plugin.enabled, VerticalAlignment = VerticalAlignment.Center };
            AutomationProperties.SetName(enabled, Localized("启用 ", "Enable ") + plugin.name);
            enabled.Click += async (_, _) =>
            {
                enabled.IsEnabled = false;
                bool value = enabled.IsChecked == true;
                var result = await Script($"stage.feedback.setPlugin({JsonSerializer.Serialize(plugin.id)},{JsonSerializer.Serialize(value)})");
                if (result == "true")
                {
                    preferences.Plugins[plugin.id] = value;
                    SavePreferences();
                    await RefreshCharacter();
                    RenderSettings();
                }
                else
                {
                    enabled.IsChecked = plugin.enabled;
                    enabled.IsEnabled = true;
                    MessageBox.Show(settings ?? this, Localized("无法更改插件状态。","Unable to change plugin state."), Title);
                }
            };
            DockPanel.SetDock(enabled, Dock.Right);
            row.Children.Add(enabled);
            var label = new TextBlock { Text = plugin.name + "  " + plugin.version, VerticalAlignment = VerticalAlignment.Center };
            label.MouseLeftButtonDown += (_, e) => { if (e.ClickCount == 2) Details(); };
            row.Children.Add(label);
            panel.Children.Add(row);
        }

        Note(panel, Localized("互动菜单","Interaction menu"));
        var actions = OrderInteractions(character?.actions ?? []).ToArray();
        if (actions.Length == 0)
            Note(panel, Localized("当前没有可配置的互动。","There are no configurable interactions."));
        for (int index = 0; index < actions.Length; index++)
        {
            int position = index;
            var action = actions[index];
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(row);
            var name = new TextBox { Text = InteractionLabel(action), Width = 145, Margin = new Thickness(0, 3, 8, 4) };
            AutomationProperties.SetName(name, action.label);
            row.Children.Add(name);
            ButtonFor(row, Localized("应用名称","Apply name"), () =>
            {
                var label = name.Text.Trim();
                if (label.Length == 0 || label == action.label) preferences.ActionLabels.Remove(action.@event);
                else preferences.ActionLabels[action.@event] = label;
                SavePreferences();
                RefreshTray();
                RenderSettings();
            });
            ToggleFor(row, Localized("显示","Show"), !preferences.HiddenActions.Contains(action.@event), value =>
            {
                if (value) preferences.HiddenActions.Remove(action.@event);
                else preferences.HiddenActions.Add(action.@event);
                SavePreferences();
                RefreshTray();
            });
            ButtonFor(row, "↑", () => Reorder(position, position - 1)).IsEnabled = position > 0;
            ButtonFor(row, "↓", () => Reorder(position, position + 1)).IsEnabled = position < actions.Length - 1;
        }

        if (actions.Length > 0 || preferences.ActionOrder.Count > 0 || preferences.HiddenActions.Count > 0 || preferences.ActionLabels.Count > 0)
            ButtonFor(panel, Localized("恢复默认菜单", "Restore default menu"), () =>
            {
                preferences.ActionLabels.Clear();
                preferences.HiddenActions.Clear();
                preferences.ActionOrder.Clear();
                SavePreferences();
                RefreshTray();
                RenderSettings();
            });

        void Reorder(int from, int to)
        {
            var order = actions.Select(item => item.@event).ToList();
            (order[from], order[to]) = (order[to], order[from]);
            order.AddRange(preferences.ActionOrder.Where(id => !order.Contains(id)).ToArray());
            preferences.ActionOrder = order;
            SavePreferences();
            RefreshTray();
            RenderSettings();
        }
    }

    private void SystemPage(StackPanel panel)
    {
        Choice(panel, Localized("界面语言","Language"), ["简体中文","English"], chinese ? 0 : 1, async value =>
        {
            preferences.Language = value == 0 ? "zh-CN" : "en";
            SavePreferences();
            await ApplyPlayerPreferences();
            await RefreshCharacter();
            RenderSettings();
        });
        var login = ToggleFor(panel, Localized("登录时启动","Open at login"), IsLoginEnabled(), value =>
        {
            SetLoginEnabled(value);
            RenderSettings();
        });
        login.IsEnabled = CanRegisterLogin;
        if (!CanRegisterLogin)
            Note(panel, Localized("请从打包后的 Jiumi.exe 设置登录启动。", "Open the packaged Jiumi.exe to configure startup."));
        ButtonFor(panel, Localized("恢复桌面设置…","Restore desktop settings…"), async () =>
        {
            if (MessageBox.Show(settings ?? this, Localized("恢复窗口、外观和快捷键的默认值？", "Restore the default window, appearance and shortcut settings?"),
                Title, MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK)
                return;
            var defaults = new Preferences
            {
                Language = preferences.Language, Plugins = preferences.Plugins,
                ActionLabels = preferences.ActionLabels, HiddenActions = preferences.HiddenActions, ActionOrder = preferences.ActionOrder,
                Typing = preferences.Typing
            };
            preferences = defaults;
            ReplaceHotkey(null);
            ApplyWindowPreferences();
            ResetPosition();
            SavePosition();
            SavePreferences();
            CheckFullscreen();
            await ApplyPlayerPreferences();
            RenderSettings();
        });
    }

    private void AboutPage(StackPanel panel)
    {
        Note(panel, Localized("客户端版本  ", "Client version  ") + Title + " " +
            (typeof(PetWindow).Assembly.GetName().Version?.ToString(3) ?? "1.0.0"));
        Note(panel, Localized("当前角色  ", "Current pet  ") + (character?.name ?? ""));
        ButtonFor(panel, Localized("导出角色包…","Export pet…"), async () =>
        {
            string? json = await Script("JSON.stringify(pet)");
            if (json == null || JsonSerializer.Deserialize<string>(json) is not { } package)
                return;
            var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "pet.json", Filter = "JSON (*.json)|*.json", AddExtension = true };
            if (dialog.ShowDialog(settings ?? this) != true)
                return;
            try { File.WriteAllText(dialog.FileName, package); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { MessageBox.Show(settings ?? this, error.Message, Title); }
        }).IsEnabled = character != null;
    }
}
