import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/utils/attachment_accepts.dart';

void main() {
  group('parseAcceptedKinds', () {
    test('defaults to image when null or empty', () {
      expect(parseAcceptedKinds(null), {AttachmentKind.image});
      expect(parseAcceptedKinds(''), {AttachmentKind.image});
      expect(parseAcceptedKinds('   '), {AttachmentKind.image});
    });

    test('parses single image, audio, or video kind', () {
      expect(parseAcceptedKinds('image'), {AttachmentKind.image});
      expect(parseAcceptedKinds('audio'), {AttachmentKind.audio});
      expect(parseAcceptedKinds(' AUDIO '), {AttachmentKind.audio});
      expect(parseAcceptedKinds('video'), {AttachmentKind.video});
      expect(parseAcceptedKinds(' VIDEO '), {AttachmentKind.video});
    });

    test('parses combined accepts strings', () {
      expect(
        parseAcceptedKinds('image,audio'),
        {AttachmentKind.image, AttachmentKind.audio},
      );
      expect(
        parseAcceptedKinds('audio, image'),
        {AttachmentKind.image, AttachmentKind.audio},
      );
      expect(
        parseAcceptedKinds('image,video'),
        {AttachmentKind.image, AttachmentKind.video},
      );
      expect(
        parseAcceptedKinds('image,audio,video'),
        {AttachmentKind.image, AttachmentKind.audio, AttachmentKind.video},
      );
    });

    test('ignores unknown tokens and falls back to image when none match', () {
      expect(parseAcceptedKinds('pdf,txt'), {AttachmentKind.image});
      expect(parseAcceptedKinds('audio,pdf'), {AttachmentKind.audio});
    });
  });

  group('extensionOf and mimeForExtension', () {
    test('extracts lowercase extension from path or filename', () {
      expect(extensionOf('/tmp/dir/Call.M4A'), 'm4a');
      expect(extensionOf('bird.call.opus'), 'opus');
      expect(extensionOf('no_extension'), '');
      expect(extensionOf('.hidden'), '');
    });

    test('maps supported image, audio, and video extensions to canonical MIME types', () {
      expect(mimeForExtension('jpg'), 'image/jpeg');
      expect(mimeForExtension('jpeg'), 'image/jpeg');
      expect(mimeForExtension('png'), 'image/png');
      expect(mimeForExtension('webp'), 'image/webp');
      expect(mimeForExtension('heic'), 'image/heic');

      expect(mimeForExtension('m4a'), 'audio/mp4');
      expect(mimeForExtension('mp3'), 'audio/mpeg');
      expect(mimeForExtension('wav'), 'audio/wav');
      expect(mimeForExtension('ogg'), 'audio/ogg');
      expect(mimeForExtension('opus'), 'audio/ogg');
      expect(mimeForExtension('webm'), 'audio/webm');
      expect(mimeForExtension('aac'), 'audio/aac');
      expect(mimeForExtension('flac'), 'audio/flac');

      expect(mimeForExtension('mp4'), 'video/mp4');
      expect(mimeForExtension('mov'), 'video/quicktime');
      expect(
        mimeForExtension('webm', preferredKind: AttachmentKind.video),
        'video/webm',
      );

      expect(mimeForExtension('pdf'), isNull);
      expect(mimeForExtension(''), isNull);
    });

    test('identifies audio/video paths, content types, and per-kind size limits', () {
      expect(isAudioPath('/docs/abc.m4a'), isTrue);
      expect(isAudioPath('/docs/abc.MP3'), isTrue);
      expect(isAudioPath('/docs/abc.jpg'), isFalse);
      expect(isVideoPath('/docs/clip.mp4'), isTrue);
      expect(isVideoPath('/docs/clip.MOV'), isTrue);
      expect(isVideoPath('/docs/abc.jpg'), isFalse);
      expect(
        kindForAttachment(contentType: 'video/webm', pathOrName: '/docs/a.webm'),
        AttachmentKind.video,
      );
      expect(
        kindForAttachment(contentType: 'audio/webm', pathOrName: '/docs/a.webm'),
        AttachmentKind.audio,
      );
      expect(maxMbForKind(AttachmentKind.image), 10);
      expect(maxMbForKind(AttachmentKind.audio), 50);
      expect(maxMbForKind(AttachmentKind.video), 1024);
      expect(formatMaxSizeForKind(AttachmentKind.image), '10 MB');
      expect(formatMaxSizeForKind(AttachmentKind.audio), '50 MB');
      expect(formatMaxSizeForKind(AttachmentKind.video), '1 GB');
    });
  });

  group('formatFileSize', () {
    test('formats bytes, KB, MB, and GB cleanly', () {
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2 KB');
      expect(formatFileSize(1572864), '1.5 MB');
      expect(formatFileSize(1024 * 1024 * 1024), '1.0 GB');
    });
  });
}
