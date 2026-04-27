using Zeroconf;
using SwftExperiments.Models;

namespace SwftExperiments.Discovery;

public class MdnsDiscovery : IDisposable
{
    private const string Protocol = "_bangolufsen._tcp.local.";

    private readonly CancellationTokenSource _cts = new();
    private readonly HashSet<string> _found = [];

    public event EventHandler<Speaker>? SpeakerFound;

    public void Start() => _ = ScanLoopAsync();

    private async Task ScanLoopAsync()
    {
        while (!_cts.IsCancellationRequested)
        {
            try
            {
                var hosts = await ZeroconfResolver.ResolveAsync(
                    Protocol,
                    scanTime: TimeSpan.FromSeconds(3),
                    cancellationToken: _cts.Token);

                foreach (var host in hosts)
                {
                    var ip = host.IPAddress;
                    if (string.IsNullOrEmpty(ip) || !_found.Add(ip)) continue;
                    _ = TryAddSpeakerAsync(ip);
                }
            }
            catch (OperationCanceledException) { break; }
            catch { }

            try { await Task.Delay(TimeSpan.FromSeconds(15), _cts.Token); }
            catch { break; }
        }
    }

    private async Task TryAddSpeakerAsync(string ip)
    {
        var speaker = new Speaker(ip);
        try
        {
            await speaker.InitializeAsync();
            SpeakerFound?.Invoke(this, speaker);
        }
        catch
        {
            _found.Remove(ip);
            speaker.Dispose();
        }
    }

    public void Dispose() => _cts.Cancel();
}
