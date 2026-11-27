import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VideoThumbnailData {
  final Uint8List? bytes;
  final int? durationMs;

  const VideoThumbnailData({this.bytes, this.durationMs});
}

typedef VideoThumbnailLoader =
    Future<VideoThumbnailData?> Function(String filePath, {int maxWidth});

/// Extracts a lightweight static JPEG preview frame and duration from a local
/// video file using native platform APIs (MediaMetadataRetriever on Android,
/// AVAssetImageGenerator on iOS) without allocating a playback controller.
class VideoThumbnailService {
  static const _channel = MethodChannel('com.fieldlog/media');
  static const _maxCacheEntries = 24;
  static final Map<String, VideoThumbnailData?> _cache = {};

  @visibleForTesting
  static VideoThumbnailLoader? loaderOverride;

  @visibleForTesting
  static void clearCache() => _cache.clear();

  static Future<VideoThumbnailData?> load(
    String filePath, {
    int maxWidth = 640,
  }) async {
    if (filePath.isEmpty) return null;

    if (loaderOverride != null) {
      return loaderOverride!(filePath, maxWidth: maxWidth);
    }

    if (_cache.containsKey(filePath)) {
      return _cache[filePath];
    }

    VideoThumbnailData? data;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getVideoThumbnail',
        {'path': filePath, 'maxWidth': maxWidth},
      );
      if (raw != null) {
        final rawBytes = raw['bytes'];
        final bytes = rawBytes is Uint8List && rawBytes.isNotEmpty
            ? rawBytes
            : null;
        final rawDuration = raw['durationMs'];
        final durationMs = rawDuration is num && rawDuration > 0
            ? rawDuration.toInt()
            : null;
        if (bytes != null || durationMs != null) {
          data = VideoThumbnailData(bytes: bytes, durationMs: durationMs);
        }
      }
    } on MissingPluginException {
      data = null;
    } on PlatformException {
      data = null;
    } catch (_) {
      data = null;
    }

    if (data != null) {
      if (_cache.length >= _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      _cache[filePath] = data;
    }
    return data;
  }
}
