/// Shared attachment type, extension, MIME, and size rules.
///
/// Mirrors `ui/src/forms/attachmentAccepts.js` and `api/config/settings.py`
/// in `field-log-poc`.
enum AttachmentKind { image, audio, video }

const String defaultAccepts = 'image';

const int _mb = 1024 * 1024;
const int maxImageBytes = 10 * _mb;
const int maxAudioBytes = 50 * _mb;
const int maxVideoBytes = 1024 * _mb;

const Set<String> imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic'};
const Set<String> videoExtensions = {'mp4', 'mov', 'webm'};

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

const Map<String, String> videoMimeByExtension = {
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
};

/// Parse a `form_config` `accepts` string (e.g. `"image"`, `"audio"`,
/// `"video"`, `"image,video"`) into supported kinds, defaulting to
/// `{AttachmentKind.image}` when null, empty, or containing only unknown values.
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
      case 'video':
        kinds.add(AttachmentKind.video);
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
/// Pass [preferredKind] to disambiguate shared containers like `.webm`.
String? mimeForExtension(String ext, {AttachmentKind? preferredKind}) {
  final normalized = ext.trim().toLowerCase();
  if (preferredKind == AttachmentKind.video &&
      videoMimeByExtension.containsKey(normalized)) {
    return videoMimeByExtension[normalized];
  }
  return imageMimeByExtension[normalized] ??
      audioMimeByExtension[normalized] ??
      videoMimeByExtension[normalized];
}

AttachmentKind? kindForContentType(String? contentType) {
  final normalized = contentType?.split(';').first.trim().toLowerCase() ?? '';
  if (normalized.startsWith('image/')) return AttachmentKind.image;
  if (normalized.startsWith('audio/')) return AttachmentKind.audio;
  if (normalized.startsWith('video/')) return AttachmentKind.video;
  return null;
}

final Set<String> _supportedContentTypes = {
  ...imageMimeByExtension.values,
  ...audioMimeByExtension.values,
  ...videoMimeByExtension.values,
};

bool isSupportedContentType(String? contentType) {
  final normalized = contentType?.split(';').first.trim().toLowerCase() ?? '';
  return _supportedContentTypes.contains(normalized);
}

AttachmentKind? kindForExtension(String ext) {
  final normalized = ext.trim().toLowerCase();
  if (imageMimeByExtension.containsKey(normalized)) {
    return AttachmentKind.image;
  }
  if (audioMimeByExtension.containsKey(normalized)) {
    return AttachmentKind.audio;
  }
  if (videoMimeByExtension.containsKey(normalized)) {
    return AttachmentKind.video;
  }
  return null;
}

AttachmentKind kindForAttachment({
  String? contentType,
  required String pathOrName,
}) {
  return kindForContentType(contentType) ??
      kindForExtension(extensionOf(pathOrName)) ??
      AttachmentKind.image;
}

bool isAudioPath(String pathOrName) {
  return kindForExtension(extensionOf(pathOrName)) == AttachmentKind.audio;
}

bool isVideoPath(String pathOrName) {
  return kindForExtension(extensionOf(pathOrName)) == AttachmentKind.video;
}

int maxBytesForKind(AttachmentKind kind) {
  switch (kind) {
    case AttachmentKind.image:
      return maxImageBytes;
    case AttachmentKind.audio:
      return maxAudioBytes;
    case AttachmentKind.video:
      return maxVideoBytes;
  }
}

int maxMbForKind(AttachmentKind kind) => maxBytesForKind(kind) ~/ _mb;

String formatMaxSizeForKind(AttachmentKind kind) {
  final mb = maxMbForKind(kind);
  if (mb >= 1024 && mb % 1024 == 0) return '${mb ~/ 1024} GB';
  return '$mb MB';
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < _mb) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * _mb) return '${(bytes / _mb).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * _mb)).toStringAsFixed(1)} GB';
}
