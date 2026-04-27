using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using SwftExperiments.Api;

namespace SwftExperiments.Models;

public class Speaker : INotifyPropertyChanged, IDisposable
{
    public event PropertyChangedEventHandler? PropertyChanged;

    // ── Identity ──────────────────────────────────────────────────────────────

    public string Host { get; }

    private string _name;
    public string Name
    {
        get => _name;
        set { _name = value; Notify(); }
    }

    // ── Playback ──────────────────────────────────────────────────────────────

    private string _state = "unknown";
    public string State
    {
        get => _state;
        set
        {
            _state = value;
            Notify();
            Notify(nameof(IsPlaying));
            Notify(nameof(StateDisplay));
            Notify(nameof(TrackDisplay));
        }
    }

    public bool IsPlaying => _state is "playing" or "started";

    public string StateDisplay => _state switch
    {
        "playing" or "started" => "Playing",
        "paused"               => "Paused",
        "buffering"            => "Buffering",
        _                      => "Idle"
    };

    private SpeakerMetadata? _metadata;
    public SpeakerMetadata? Metadata
    {
        get => _metadata;
        set { _metadata = value; Notify(); Notify(nameof(TrackDisplay)); }
    }

    public string TrackDisplay
    {
        get
        {
            if (!IsPlaying) return string.Empty;
            var parts = new[] { Metadata?.Artist, Metadata?.Title }
                        .Where(s => !string.IsNullOrWhiteSpace(s)).ToArray();
            if (parts.Length > 0) return string.Join(" – ", parts);
            if (!string.IsNullOrWhiteSpace(Metadata?.Genre)) return Metadata.Genre!;
            if (!string.IsNullOrWhiteSpace(Metadata?.Album)) return Metadata.Album!;
            return Source ?? string.Empty;
        }
    }

    // ── Volume ────────────────────────────────────────────────────────────────

    private int? _volume;
    public int? Volume
    {
        get => _volume;
        set { _volume = value; Notify(); Notify(nameof(VolumeDisplay)); }
    }

    public string VolumeDisplay => _volume.HasValue ? $"Vol {_volume}" : string.Empty;

    // ── Source ────────────────────────────────────────────────────────────────

    private string? _source;
    public string? Source
    {
        get => _source;
        set { _source = value; Notify(); Notify(nameof(TrackDisplay)); }
    }

    // ── Battery ───────────────────────────────────────────────────────────────

    private int? _batteryLevel;
    public int? BatteryLevel
    {
        get => _batteryLevel;
        set { _batteryLevel = value; Notify(); Notify(nameof(BatteryDisplay)); Notify(nameof(HasBattery)); }
    }

    public bool   HasBattery     => _batteryLevel.HasValue;
    public string BatteryDisplay => _batteryLevel.HasValue ? $"{_batteryLevel}%" : string.Empty;

    // ── Internals ─────────────────────────────────────────────────────────────

    private readonly MozartClient _client;
    private readonly MozartEvents _events;

    public Speaker(string host)
    {
        Host    = host;
        _name   = host;
        _client = new MozartClient(host);
        _events = new MozartEvents(host);
    }

    public async Task InitializeAsync()
    {
        await Task.WhenAll(
            LoadIdentityAsync(),
            LoadPlaybackStateAsync(),
            LoadVolumeAsync(),
            LoadBatteryAsync(),
            LoadActiveSourceAsync()
        );

        _events.EventReceived += OnEvent;
        _events.Connect();
    }

    // ── REST loaders ──────────────────────────────────────────────────────────

    private async Task LoadIdentityAsync()
    {
        try
        {
            var data = await _client.GetAsync("/beolink/self");
            if (data?.TryGetProperty("friendlyName", out var v) == true && v.GetString() is { } n)
                Dispatch(() => Name = n);
        }
        catch { }
    }

    private async Task LoadPlaybackStateAsync()
    {
        try
        {
            var data = await _client.GetAsync("/playback/state");
            if (data?.TryGetProperty("state", out var v) == true && v.GetString() is { } s)
                Dispatch(() => State = s);
        }
        catch { }
    }

    private async Task LoadVolumeAsync()
    {
        try
        {
            var data = await _client.GetAsync("/sound/volume");
            if (data?.TryGetProperty("volume", out var vol) == true &&
                vol.TryGetProperty("level", out var lev))
                Dispatch(() => Volume = lev.GetInt32());
        }
        catch { }
    }

    private async Task LoadBatteryAsync()
    {
        try
        {
            var data = await _client.GetAsync("/battery");
            if (data?.TryGetProperty("batteryLevel", out var lev) == true)
            {
                var level = lev.GetInt32();
                var charging = data.Value.TryGetProperty("isCharging", out var c) && c.GetBoolean();
                if (level > 0 || charging)
                    Dispatch(() => BatteryLevel = level);
            }
        }
        catch { }
    }

    private async Task LoadActiveSourceAsync()
    {
        try
        {
            var data = await _client.GetAsync("/playback/sources/active");
            var name = data?.TryGetProperty("friendlyName", out var fn) == true ? fn.GetString()
                     : data?.TryGetProperty("id",           out var id) == true ? id.GetString()
                     : null;
            if (name != null) Dispatch(() => Source = name);
        }
        catch { }
    }

    // ── WebSocket event handler ───────────────────────────────────────────────

    private void OnEvent(object? sender, MozartEventArgs e)
    {
        switch (e.EventType)
        {
            case "WebSocketEventPlaybackState":
                if (e.EventData.TryGetProperty("value", out var sv))
                    Dispatch(() => State = sv.GetString() ?? State);
                break;

            case "WebSocketEventPlaybackMetadata":
                Dispatch(() => Metadata = new SpeakerMetadata
                {
                    Title  = Str(e.EventData, "title"),
                    Artist = Str(e.EventData, "artistName"),
                    Album  = Str(e.EventData, "albumName"),
                });
                break;

            case "WebSocketEventVolume":
                if (e.EventData.TryGetProperty("volume", out var vol) &&
                    vol.TryGetProperty("level", out var lev))
                    Dispatch(() => Volume = lev.GetInt32());
                break;

            case "WebSocketEventBattery":
                if (e.EventData.TryGetProperty("batteryLevel", out var bl))
                {
                    var level    = bl.GetInt32();
                    var charging = e.EventData.TryGetProperty("isCharging", out var c) && c.GetBoolean();
                    if (level > 0 || charging) Dispatch(() => BatteryLevel = level);
                }
                break;

            case "WebSocketEventPlaybackSource":
                var src = Str(e.EventData, "friendlyName") ?? Str(e.EventData, "id");
                if (src != null) Dispatch(() => Source = src);
                break;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static string? Str(JsonElement el, string key)
        => el.TryGetProperty(key, out var v) ? v.GetString() : null;

    private static void Dispatch(Action a)
        => Application.Current?.Dispatcher.Invoke(a);

    private void Notify([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public void Dispose() => _events.Dispose();
}
