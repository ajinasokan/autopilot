import 'package:flutter/services.dart';

class TextInputDriver {
  void _handlePlatformMessage(String methodName, List<dynamic> arguments) {
    ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        MethodCall(
          methodName,
          arguments,
        ),
      ),
      (ByteData? data) {},
    );
  }

  void type(String text) {
    final value = TextEditingValue(text: text);
    _handlePlatformMessage(
        'TextInputClient.updateEditingState', <dynamic>[-1, value.toJSON()]);
  }

  void keyboardAction(String type) {
    _handlePlatformMessage('TextInputClient.performAction',
        <dynamic>[-1, submitTypes[type].toString()]);
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
}
