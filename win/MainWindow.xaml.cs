using System.Collections.ObjectModel;
using System.Speech.Recognition;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using NAudio.Wave;
using SwftExperiments.Discovery;
using SwftExperiments.Models;

namespace SwftExperiments;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<Speaker> _speakers = [];
    private readonly MdnsDiscovery _discovery = new();
    private WaveInEvent? _waveIn;
    private SpeechRecognitionEngine? _speech;
    private Storyboard? _breathe;

    public MainWindow()
    {
        InitializeComponent();
        SpeakerList.ItemsSource = _speakers;
        Loaded  += OnLoaded;
        Closing += OnClosing;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _breathe = (Storyboard)FindResource("Breathe");
        _breathe.Begin(this, true);

        _discovery.SpeakerFound += OnSpeakerFound;
        _discovery.Start();

        _ = InitMicAsync();
    }

    // ── Discovery ─────────────────────────────────────────────────────────────

    private void OnSpeakerFound(object? sender, Speaker speaker)
        => Dispatcher.Invoke(() => _speakers.Add(speaker));

    // ── Microphone + orb ──────────────────────────────────────────────────────

    private async Task InitMicAsync()
    {
        try
        {
            _waveIn = new WaveInEvent
            {
                DeviceNumber       = 0,
                WaveFormat         = new WaveFormat(16000, 1),
                BufferMilliseconds = 50
            };
            _waveIn.DataAvailable += OnAudioData;
            _waveIn.StartRecording();

            ReleaseBreathing();
            Dispatcher.Invoke(() => MicStatusBlock.Text = "Listening…");

            await Task.Run(InitSpeech);
        }
        catch (Exception ex)
        {
            Dispatcher.Invoke(() => MicStatusBlock.Text = $"Microphone unavailable: {ex.Message}");
        }
    }

    // Releases the Storyboard's hold on OrbScale so we can drive it directly.
    private void ReleaseBreathing()
    {
        _breathe?.Stop(this);
        OrbScale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
        OrbScale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
    }

    private void OnAudioData(object? sender, WaveInEventArgs e)
    {
        // RMS of 16-bit PCM
        int samples = e.BytesRecorded / 2;
        float sum = 0;
        for (int i = 0; i < e.BytesRecorded; i += 2)
        {
            float norm = BitConverter.ToInt16(e.Buffer, i) / 32768f;
            sum += norm * norm;
        }
        float rms = MathF.Sqrt(sum / samples);

        double boost  = Math.Min(rms * 4.0, 0.55);
        double scale  = 1.0 + boost;
        double glow   = 0.15 + boost * 1.5;
        double blur   = 24  + boost * 80;

        Dispatcher.InvokeAsync(() =>
        {
            OrbScale.ScaleX      = scale;
            OrbScale.ScaleY      = scale;
            OrbGlow.Opacity      = glow;
            OrbGlow.BlurRadius   = blur;
        });
    }

    // ── Speech recognition ────────────────────────────────────────────────────

    private void InitSpeech()
    {
        try
        {
            _speech = new SpeechRecognitionEngine();
            _speech.LoadGrammar(new DictationGrammar());
            _speech.SpeechRecognized     += OnSpeechRecognized;
            _speech.SetInputToDefaultAudioDevice();
            _speech.RecognizeAsync(RecognizeMode.Multiple);
        }
        catch { /* speech recognition unavailable on this machine */ }
    }

    private void OnSpeechRecognized(object? sender, SpeechRecognizedEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            TranscriptBlock.Text    = e.Result.Text;
            TranscriptBlock.Opacity = 1;
        });
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    private void OnClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        _waveIn?.StopRecording();
        _waveIn?.Dispose();

        _speech?.RecognizeAsyncStop();
        _speech?.Dispose();

        _discovery.Dispose();

        foreach (var s in _speakers) s.Dispose();
    }
}
