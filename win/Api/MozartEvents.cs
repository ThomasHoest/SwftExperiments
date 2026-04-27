using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace SwftExperiments.Api;

public class MozartEventArgs(string eventType, JsonElement eventData) : EventArgs
{
    public string      EventType { get; } = eventType;
    public JsonElement EventData { get; } = eventData;
}

public class MozartEvents : IDisposable
{
    private readonly string _url;
    private ClientWebSocket? _ws;
    private readonly CancellationTokenSource _cts = new();
    private int _retryCount;

    public event EventHandler<MozartEventArgs>? EventReceived;

    public MozartEvents(string host) => _url = $"ws://{host}:9339/";

    public void Connect() => _ = ConnectLoopAsync();

    private async Task ConnectLoopAsync()
    {
        while (!_cts.IsCancellationRequested)
        {
            try
            {
                _ws = new ClientWebSocket();
                await _ws.ConnectAsync(new Uri(_url), _cts.Token);
                _retryCount = 0;
                await ReceiveLoopAsync();
            }
            catch (OperationCanceledException) { break; }
            catch
            {
                _ws?.Dispose();
                _ws = null;
                var delay = Math.Min(1000 * (int)Math.Pow(2, _retryCount), 30_000);
                _retryCount = Math.Min(_retryCount + 1, 5);
                try { await Task.Delay(delay, _cts.Token); } catch { break; }
            }
        }
    }

    private async Task ReceiveLoopAsync()
    {
        var buffer = new byte[8192];
        using var ms = new MemoryStream();

        while (_ws?.State == WebSocketState.Open && !_cts.IsCancellationRequested)
        {
            WebSocketReceiveResult result;
            do
            {
                result = await _ws.ReceiveAsync(buffer, _cts.Token);
                ms.Write(buffer, 0, result.Count);
            }
            while (!result.EndOfMessage);

            if (result.MessageType == WebSocketMessageType.Text)
                ProcessMessage(Encoding.UTF8.GetString(ms.ToArray()));

            ms.SetLength(0);
        }
    }

    private void ProcessMessage(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.TryGetProperty("eventType", out var t) &&
                root.TryGetProperty("eventData", out var d))
                EventReceived?.Invoke(this, new MozartEventArgs(t.GetString()!, d.Clone()));
        }
        catch { }
    }

    public void Dispose()
    {
        _cts.Cancel();
        _ws?.Dispose();
        _cts.Dispose();
    }
}
