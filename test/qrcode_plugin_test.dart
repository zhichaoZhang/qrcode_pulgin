import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrcode_plugin/qrcode_plugin.dart';

void main() {
  const MethodChannel channel = MethodChannel('qrcode_plugin');

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await QrcodePlugin.platformVersion, '42');
  });
}
