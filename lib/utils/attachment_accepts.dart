/// Shared attachment type, extension, MIME, and size rules.
///
/// Mirrors `ui/src/forms/attachmentAccepts.js` and `api/config/settings.py`
/// in `field-log-poc`.
enum AttachmentKind { image, audio }

const String defaultAccepts = 'image';

const int _mb = 1024 * 1024;
const int maxImageBytes = 10 * _mb;
const int maxAudioBytes = 50 * _mb;

const Set<String> imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic'};

const Map<String, String> imageMimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
};

const Map<String, String> audioMimeByExtension = {
  'm4a': 'audio/mp4',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/ogg',
  'webm': 'audio/webm',
  'aac': 'audio/aac',
  'flac': 'audio/flac',
};

/// Parse a `form_config` `accepts` string (e.g. `"image"`, `"audio"`,
/// `"image,audio"`) into supported kinds, defaulting to `{AttachmentKind.image}`
/// when null, empty, or containing only unknown values.
Set<AttachmentKind> parseAcceptedKinds(String? accepts) {
  final raw = (accepts == null || accepts.trim().isEmpty)
      ? defaultAccepts
      : accepts;

  final kinds = <AttachmentKind>{};
  for (final token in raw.split(',')) {
    switch (token.trim().toLowerCase()) {
      case 'image':
        kinds.add(AttachmentKind.image);
      case 'audio':
        kinds.add(AttachmentKind.audio);
    }
  }
  return kinds.isEmpty ? {AttachmentKind.image} : kinds;
}

/// Returns the lowercase file extension without a leading dot, or `''`.
String extensionOf(String pathOrName) {
  final fileName = pathOrName.split(RegExp(r'[/\\]')).last;
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

/// Returns the canonical backend MIME type for [ext], or `null` if unsupported.
String? mimeForExtension(String ext) {
  final normalized = ext.trim().toLowerCase();
  return imageMimeByExtension[normalized] ?? audioMimeByExtension[normalized];
}

AttachmentKind? kindForExtension(String ext) {
  final normalized = ext.trim().toLowerCase();
  if (imageMimeByExtension.containsKey(normalized)) {
    return AttachmentKind.image;
  }
  if (audioMimeByExtension.containsKey(normalized)) {
    return AttachmentKind.audio;
  }
  return null;
}

bool isAudioPath(String pathOrName) {
  return kindForExtension(extensionOf(pathOrName)) == AttachmentKind.audio;
}

int maxBytesForKind(AttachmentKind kind) {
  switch (kind) {
    case AttachmentKind.image:
      return maxImageBytes;
    case AttachmentKind.audio:
      return maxAudioBytes;
  }
}

int maxMbForKind(AttachmentKind kind) => maxBytesForKind(kind) ~/ _mb;

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < _mb) return '${(bytes / 1024).round()} KB';
  return '${(bytes / _mb).toStringAsFixed(1)} MB';
}
