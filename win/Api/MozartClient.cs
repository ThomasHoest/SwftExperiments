using System.Net.Http;
using System.Text.Json;

namespace SwftExperiments.Api;

public class MozartClient
{
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(5) };
    private readonly string _base;

    public MozartClient(string host) => _base = $"http://{host}/api/v1";

    public async Task<JsonElement?> GetAsync(string path)
    {
        try
        {
            var json = await _http.GetStringAsync($"{_base}{path}");
            return JsonSerializer.Deserialize<JsonElement>(json);
        }
        catch { return null; }
    }

    public async Task PostAsync(string path)
    {
        try { await _http.PostAsync($"{_base}{path}", null); }
        catch { }
    }

    public async Task PutAsync(string path, object body)
    {
        try
        {
            var content = new StringContent(
                JsonSerializer.Serialize(body),
                System.Text.Encoding.UTF8,
                "application/json");
            await _http.PutAsync($"{_base}{path}", content);
        }
        catch { }
    }
}
