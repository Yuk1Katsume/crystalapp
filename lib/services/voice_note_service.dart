import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'e2ee_service.dart';
import 'supabase_config.dart';

enum RecordingState {
  idle,
  recording,
  paused,
}

/// Singleton service managing Voice Notes recording, amplitude sampling,
/// preview playback, and End-to-End Encryption (E2EE).
class VoiceNoteService {
  static final VoiceNoteService _instance = VoiceNoteService._internal();
  factory VoiceNoteService() => _instance;
  VoiceNoteService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();

  RecordingState _recordingState = RecordingState.idle;
  RecordingState get recordingState => _recordingState;

  String? _currentRecordingPath;
  int _recordingDurationSeconds = 0;
  int get recordingDurationSeconds => _recordingDurationSeconds;

  Timer? _timer;
  Timer? _amplitudeTimer;

  // Real amplitude samples captured during the live recording
  final List<double> _liveRecordedSamples = [];
  static final Map<String, List<double>> messageWaveforms = {};

  final StreamController<int> _durationController = StreamController<int>.broadcast();
  Stream<int> get durationStream => _durationController.stream;

  final StreamController<double> _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  // Single global audio player for chat playback (ensures only 1 voice note plays at once)
  final AudioPlayer globalChatPlayer = AudioPlayer();
  String? currentlyPlayingMessageId;
  final StreamController<String?> playingMessageController = StreamController<String?>.broadcast();

  AudioPlayer get previewPlayer => _previewPlayer;

  /// Start recording audio with AAC encoder
  Future<bool> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return false;

      final dir = await getTemporaryDirectory();
      _currentRecordingPath = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _liveRecordedSamples.clear();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _recordingState = RecordingState.recording;
      _recordingDurationSeconds = 0;
      _durationController.add(0);

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_recordingState == RecordingState.recording) {
          _recordingDurationSeconds++;
          _durationController.add(_recordingDurationSeconds);
        }
      });

      _amplitudeTimer?.cancel();
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 50), (t) async {
        if (_recordingState == RecordingState.recording) {
          try {
            final amp = await _recorder.getAmplitude();
            // current db is between -60dB and 0dB. Normalize to 0.08 - 1.0
            final db = amp.current;
            double normalized = 0.08;
            if (db > -55.0) {
              normalized = ((db + 55.0) / 55.0).clamp(0.08, 1.0);
            }
            _liveRecordedSamples.add(normalized);
            _amplitudeController.add(normalized);
          } catch (_) {}
        }
      });

      return true;
    } catch (e) {
      _recordingState = RecordingState.idle;
      return false;
    }
  }

  /// Pause current recording
  Future<void> pauseRecording() async {
    if (_recordingState == RecordingState.recording) {
      await _recorder.pause();
      _recordingState = RecordingState.paused;
    }
  }

  /// Resume paused recording
  Future<void> resumeRecording() async {
    if (_recordingState == RecordingState.paused) {
      await _recorder.resume();
      _recordingState = RecordingState.recording;
    }
  }

  /// Resample raw amplitude stream into a fixed bar count (e.g. 34 bars)
  List<double> _resampleAmplitudes(List<double> raw, int targetCount) {
    if (raw.isEmpty) {
      return List.generate(targetCount, (_) => 0.15);
    }
    if (raw.length <= targetCount) {
      // Interpolate to fill
      final result = <double>[];
      for (int i = 0; i < targetCount; i++) {
        final idx = ((i / targetCount) * raw.length).floor().clamp(0, raw.length - 1);
        result.add(raw[idx].clamp(0.1, 1.0));
      }
      return result;
    }

    // Average into buckets
    final result = <double>[];
    final chunkSize = raw.length / targetCount;
    for (int i = 0; i < targetCount; i++) {
      final start = (i * chunkSize).floor();
      final end = ((i + 1) * chunkSize).ceil().clamp(0, raw.length);
      double maxVal = 0.1;
      double sum = 0.0;
      int count = 0;
      for (int j = start; j < end; j++) {
        sum += raw[j];
        if (raw[j] > maxVal) maxVal = raw[j];
        count++;
      }
      final avg = count > 0 ? (sum / count) : 0.1;
      // Blend average and peak for punchy speech waveform
      final val = (avg * 0.4 + maxVal * 0.6).clamp(0.1, 1.0);
      result.add(val);
    }
    return result;
  }

  /// Extract real waveform samples from an audio file
  static Future<List<double>> extractWaveformFromAudioFile(String filePath, {int barCount = 34}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return List.generate(barCount, (_) => 0.15);
      final bytes = await file.readAsBytes();
      if (bytes.length < 200) return List.generate(barCount, (_) => 0.15);

      final headerOffset = bytes.length > 512 ? 256 : 0;
      final audioBytesLength = bytes.length - headerOffset;
      final chunkSize = (audioBytesLength / barCount).floor();
      if (chunkSize <= 0) return List.generate(barCount, (_) => 0.15);

      final result = <double>[];
      for (int i = 0; i < barCount; i++) {
        final start = headerOffset + (i * chunkSize);
        final end = (start + chunkSize).clamp(0, bytes.length);
        double sumDiff = 0.0;
        int maxVal = 0;
        for (int j = start; j < end - 1; j += 2) {
          final diff = (bytes[j] - bytes[j + 1]).abs();
          sumDiff += diff;
          if (bytes[j] > maxVal) maxVal = bytes[j];
        }
        final avgDiff = (sumDiff / (chunkSize / 2)).clamp(0.0, 255.0);
        final normalized = (avgDiff / 50.0).clamp(0.12, 1.0);
        result.add(normalized);
      }

      // Smooth slightly with neighbors for an organic visual curve
      final smoothed = <double>[];
      for (int i = 0; i < result.length; i++) {
        final prev = i > 0 ? result[i - 1] : result[i];
        final next = i < result.length - 1 ? result[i + 1] : result[i];
        final val = (prev * 0.2 + result[i] * 0.6 + next * 0.2).clamp(0.12, 1.0);
        smoothed.add(val);
      }
      return smoothed;
    } catch (_) {
      return List.generate(barCount, (_) => 0.15);
    }
  }

  /// Stop recording and return local audio file path, duration and real samples
  Future<Map<String, dynamic>?> stopRecording() async {
    _timer?.cancel();
    _amplitudeTimer?.cancel();

    if (_recordingState == RecordingState.idle) return null;

    try {
      final path = await _recorder.stop();
      final totalSeconds = _recordingDurationSeconds;
      final samples = _resampleAmplitudes(_liveRecordedSamples, 34);

      _recordingState = RecordingState.idle;
      _recordingDurationSeconds = 0;
      _liveRecordedSamples.clear();

      if (path != null && File(path).existsSync()) {
        return {
          'path': path,
          'duration': totalSeconds > 0 ? totalSeconds : 1,
          'samples': samples,
        };
      }
    } catch (_) {}

    _recordingState = RecordingState.idle;
    _liveRecordedSamples.clear();
    return null;
  }

  /// Cancel and delete current recording
  Future<void> cancelRecording() async {
    _timer?.cancel();
    _amplitudeTimer?.cancel();

    try {
      final path = await _recorder.stop();
      if (path != null && File(path).existsSync()) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      if (_currentRecordingPath != null && File(_currentRecordingPath!).existsSync()) {
        try {
          File(_currentRecordingPath!).deleteSync();
        } catch (_) {}
      }
    } catch (_) {}

    _recordingState = RecordingState.idle;
    _recordingDurationSeconds = 0;
    _currentRecordingPath = null;
  }

  /// Plays preview of recorded file
  Future<void> startPreview(String filePath) async {
    await _previewPlayer.stop();
    await _previewPlayer.play(DeviceFileSource(filePath));
  }

  /// Stops preview player
  Future<void> stopPreview() async {
    await _previewPlayer.stop();
  }

  /// Encrypts audio file bytes using E2EE shared secret key
  Future<Uint8List> encryptAudioFile(String localPath, String sharedKey) async {
    final rawBytes = await File(localPath).readAsBytes();
    return E2EEService.encryptBytes(rawBytes, sharedKey);
  }

  /// Prepares audio payload for sending:
  /// Embeds encrypted base64 string or uploads to Supabase Storage if larger
  Future<String> prepareEncryptedAudioPayload({
    required String localPath,
    required String sharedKey,
    required String messageId,
  }) async {
    final encryptedBytes = await encryptAudioFile(localPath, sharedKey);

    // If audio is under 1MB, embed directly with E2EE prefix for ultra-fast relay
    if (encryptedBytes.length <= 1000000) {
      final b64 = base64Encode(encryptedBytes);
      return 'AUDENC:$b64';
    } else {
      // Upload encrypted bytes directly to Supabase storage bucket
      try {
        final fileName = 'enc_vn_${messageId}.bin';
        await SupabaseConfig.client.storage
            .from('chat-media')
            .uploadBinary(fileName, encryptedBytes);
        final url = SupabaseConfig.client.storage
            .from('chat-media')
            .getPublicUrl(fileName);
        return 'AUDENC_URL:$url';
      } catch (e) {
        final b64 = base64Encode(encryptedBytes);
        return 'AUDENC:$b64';
      }
    }
  }

  /// Decrypts received audio payload and returns playable local file path
  Future<String?> resolveAndDecryptAudio({
    required String rawMediaUrl,
    required String sharedKey,
    required String messageId,
  }) async {
    try {
      // 1. If it's already a local valid existing file on device (e.g. sender side)
      if (File(rawMediaUrl).existsSync()) {
        return rawMediaUrl;
      }

      final dir = await getTemporaryDirectory();
      final targetFile = File('${dir.path}/dec_audio_$messageId.m4a');
      if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
        return targetFile.path;
      }

      Uint8List? encryptedBytes;

      if (rawMediaUrl.startsWith('AUDENC:')) {
        final b64 = rawMediaUrl.substring(7);
        encryptedBytes = Uint8List.fromList(base64Decode(b64));
      } else if (rawMediaUrl.startsWith('AUDENC_URL:')) {
        final url = rawMediaUrl.substring(11);
        final res = await HttpClient().getUrl(Uri.parse(url));
        final response = await res.close();
        final bytesList = <int>[];
        await for (var chunk in response) {
          bytesList.addAll(chunk);
        }
        encryptedBytes = Uint8List.fromList(bytesList);
      } else if (rawMediaUrl.startsWith('http')) {
        final res = await HttpClient().getUrl(Uri.parse(rawMediaUrl));
        final response = await res.close();
        final bytesList = <int>[];
        await for (var chunk in response) {
          bytesList.addAll(chunk);
        }
        encryptedBytes = Uint8List.fromList(bytesList);
      }

      if (encryptedBytes != null) {
        final decryptedBytes = E2EEService.decryptBytes(encryptedBytes, sharedKey);
        await targetFile.writeAsBytes(decryptedBytes);
        return targetFile.path;
      }
    } catch (_) {}

    return null;
  }

  /// Play voice note for a specific message, stopping any other playing note
  Future<void> playMessageAudio({
    required String messageId,
    required String audioPath,
  }) async {
    if (currentlyPlayingMessageId != messageId) {
      await globalChatPlayer.stop();
      currentlyPlayingMessageId = messageId;
      playingMessageController.add(messageId);
    }
    await globalChatPlayer.play(DeviceFileSource(audioPath));
  }

  /// Pause current chat voice note
  Future<void> pauseMessageAudio() async {
    await globalChatPlayer.pause();
  }

  double _chatPlaybackRate = 1.0;
  double get chatPlaybackRate => _chatPlaybackRate;

  /// Set chat playback speed (0.5x, 1.0x, 1.25x, 1.5x, 2.0x)
  Future<void> setPlaybackRate(double rate) async {
    _chatPlaybackRate = rate;
    await globalChatPlayer.setPlaybackRate(rate);
  }

  /// Stop current chat voice note
  Future<void> stopMessageAudio() async {
    await globalChatPlayer.stop();
    currentlyPlayingMessageId = null;
    playingMessageController.add(null);
  }
}
