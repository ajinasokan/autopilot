import 'package:flutter/services.dart';
import 'dart:ui' as ui;

class TextInputDriver {
  int _clientId = 0;

  void init() {
    SystemChannels.textInput.setMockMethodCallHandler(_handler);
  }

  void _handlePlatformMessage(String methodName, dynamic arguments) {
    ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        MethodCall(
          methodName,
          arguments,
        ),
      ),
      (ByteData data) {},
    );
  }

  void type(String text) {
    final value = TextEditingValue(text: text);
    _handlePlatformMessage('TextInputClient.updateEditingState',
        <dynamic>[_clientId, value.toJSON()]);
  }

  void submit(String type) {
    _handlePlatformMessage('TextInputClient.performAction',
        <dynamic>[_clientId, submitTypes[type].toString()]);
  }

  Map<String, TextInputAction> get submitTypes => {
        'continueAction': TextInputAction.continueAction,
        'done': TextInputAction.done,
        'emergencyCall': TextInputAction.emergencyCall,
        'go': TextInputAction.go,
        'join': TextInputAction.join,
        'newline': TextInputAction.newline,
        'next': TextInputAction.next,
        'none': TextInputAction.none,
        'previous': TextInputAction.previous,
        'route': TextInputAction.route,
        'search': TextInputAction.search,
        'send': TextInputAction.send,
        'unspecified': TextInputAction.unspecified,
      };

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
