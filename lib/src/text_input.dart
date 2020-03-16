import 'package:flutter/services.dart';
import 'dart:ui' as ui;

class TextInputDriver {
  int _clientId = 0;

  void init() {
    SystemChannels.textInput.setMockMethodCallHandler(_handler);
  }

  void type(String text) {
    var value = TextEditingValue(text: text);
    ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        MethodCall(
          'TextInputClient.updateEditingState',
          <dynamic>[_clientId, value.toJSON()],
        ),
      ),
      (ByteData data) {},
    );
  }

  Future<dynamic> _handler(MethodCall methodCall) async {
    ui.window.sendPlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(methodCall),
      (ByteData data) {},
    );

    switch (methodCall.method) {
      case 'TextInput.setClient':
        _clientId = methodCall.arguments[0];
        break;
      case 'TextInput.clearClient':
        _clientId = 0;
        break;
    }
  }
}
