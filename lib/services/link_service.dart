import 'package:flutter/services.dart';

class LinkService {
  static const MethodChannel _channel = MethodChannel('com.fieldlog/links');
  static const privacyPolicyUrl = 'https://fieldlog.thefieldco.com/privacy';

  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
