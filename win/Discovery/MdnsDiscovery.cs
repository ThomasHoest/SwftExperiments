using Makaretu.Dns;
using SwftExperiments.Models;

namespace SwftExperiments.Discovery;

public class MdnsDiscovery : IDisposable
{
    // B&O Mozart speakers advertise on this service type.
    private const string ServiceType = "_bangolufsen._tcp";

    private MulticastService? _mdns;
    private ServiceDiscovery? _sd;
    private readonly HashSet<string> _found = [];

    public event EventHandler<Speaker>? SpeakerFound;

    public void Start()
    {
        _mdns = new MulticastService();
        _sd   = new ServiceDiscovery(_mdns);

        _sd.ServiceInstanceDiscovered += OnInstanceDiscovered;

        _mdns.Start();
        _sd.QueryServiceInstances(ServiceType);
    }

    private async void OnInstanceDiscovered(object? sender, ServiceInstanceDiscoveryEventArgs e)
    {
        // The response message may include A records in the additional section.
        var ip = e.Message.AdditionalRecords
                          .OfType<ARecord>()
                          .FirstOrDefault()
                          ?.Address.ToString();

        if (string.IsNullOrEmpty(ip) || !_found.Add(ip)) return;

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

    public void Dispose()
    {
        _sd?.Dispose();
        _mdns?.Stop();
        _mdns?.Dispose();
    }
}
