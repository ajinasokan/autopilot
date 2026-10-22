import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' show TestGesture;

part 'autopilot.dart';
part 'mcp.dart';

typedef Handler = Future<void> Function(AutopilotAction r);

class AutopilotAction {
  final HttpRequest request;

  AutopilotAction(this.request);

  HttpResponse get response => request.response;

  Future<void> sendError(dynamic e, StackTrace s) async {
    await writeResponse(
      status: 500,
      body: {"error": e.toString(), "stacktrace": s.toString()},
    );
  }

  Future<void> sendSuccess() async {
    await writeResponse(body: {"status": "success"});
  }

  Future<void> writeResponse({int status = 200, dynamic body}) async {
    request.response.statusCode = status;
    request.response.headers.set(
      "content-type",
      "application/json; charset=utf-8",
    );
    request.response.write(_indentedJson(body));
    await request.response.close();
  }

  String _indentedJson(dynamic payload) {
    return JsonEncoder.withIndent("  ").convert(payload);
  }
}

typedef _Params = Map<String, String>;
typedef _Action = Future<Object?> Function(_Params params);

const _success = {"status": "success"};

class _Driver {
  _Driver({
    required String host,
    required int port,
    required Map<String, Handler> extraHandlers,
  }) {
    final mcp = _Mcp(this);
    Map<String, Handler> routes = {
      '/widgets': _rest(getWidgets),
      '/keys': _rest(getKeys),
      '/texts': _rest(getTexts),
      '/editables': _rest(getEditables),
      '/type': _rest(type),
      '/tap': _rest(tap),
      '/hold': _rest(hold),
      '/drag': _rest(drag),
      '/scroll': _rest(scroll),
      '/scroll-into': _rest(scrollInto),
      '/screenshot': _restScreenshot,
      '/keyboard': _restKeyboard,
      '/mcp': mcp.handle,
      ...extraHandlers,
    };

    unawaited(_handle(host, port, routes));
  }

  Future<void> _handle(
    String host,
    int port,
    Map<String, Handler> routes,
  ) async {
    final server = await HttpServer.bind(host, port);

    await for (final request in server) {
      final handler = routes[request.uri.path];
      final action = AutopilotAction(request);
      try {
        if (handler == null) {
          await action.writeResponse(
            status: 404,
            body: {"error": "route not found"},
          );
        } else {
          await handler(action);
        }
      } catch (error, stackTrace) {
        await action.sendError(error, stackTrace);
      }
    }
  }

  Handler _rest(_Action run) => (action) async {
    final body = await run(action.request.uri.queryParameters);
    await action.writeResponse(body: body);
  };

  Future<void> _restScreenshot(AutopilotAction action) async {
    final pngBytes = await screenshot();
    action.response.headers.set("content-type", "image/png");
    action.response.add(pngBytes);
    await action.response.close();
  }

  Future<void> _restKeyboard(AutopilotAction action) async {
    final body = switch (action.request.method) {
      "GET" => await setKeyboardVisible(true),
      "DELETE" => await setKeyboardVisible(false),
      "POST" => await keyboardAction(action.request.uri.queryParameters),
      final method => throw Exception("Method $method not allowed"),
    };
    await action.writeResponse(body: body);
  }

  Future<Object?> setKeyboardVisible(bool visible) async {
    await SystemChannels.textInput.invokeMethod(
      visible ? "TextInput.show" : "TextInput.hide",
    );
    return _success;
  }

  Map<String, TextInputAction> get submitTypes =>
      TextInputAction.values.asNameMap();

  String get _acceptableValuesMsg =>
      'Acceptable values are: [${submitTypes.keys.join(', ')}]';

  Future<Object?> keyboardAction(_Params params) async {
    final type = params['type'];
    final inputAction = submitTypes[type];
    if (inputAction == null) {
      throw Exception(
        "Type '$type' is not an available action. $_acceptableValuesMsg",
      );
    }

    _requireFocusedEditable().performAction(inputAction);
    return _success;
  }

  Future<Object?> getWidgets(_Params params) async {
    final widgetTree = _serializeTree(parent: params['parent'])["tree"];
    if (widgetTree == null) throw Exception("Render tree unavailable");
    return widgetTree;
  }

  Future<Object?> getKeys(_Params params) async {
    return _serializeTree(parent: params['parent'])["keys"];
  }

  Future<Object?> getTexts(_Params params) async {
    final serialized = _serializeTree(parent: params['parent']);

    var texts = serialized["texts"] as List<Map<String, dynamic>>?;
    if (params.containsKey("text")) {
      final query = params["text"];
      texts = texts!.where((item) => item["text"].contains(query)).toList();
    } else if (params.containsKey("key")) {
      final keys = serialized["keys"] as List<Map<String, dynamic>>;
      final widget = keys.firstWhereOrNull(
        (info) => info["key"] == params["key"],
      );
      if (widget != null) {
        texts = texts!.where((item) {
          return item["position"]["left"] == widget["position"]["left"] &&
              item["position"]["top"] == widget["position"]["top"];
        }).toList();
      } else {
        texts = [];
      }
    }
    return texts;
  }

  Future<Object?> getEditables(_Params params) async {
    return _serializeTree(parent: params['parent'])["editables"];
  }

  Future<Uint8List> screenshot() async {
    final renderView = WidgetsBinding.instance.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = renderView.layer as OffsetLayer;
    final pixelRatio = renderView.configuration.devicePixelRatio;
    final pixelSize = renderView.size * pixelRatio;
    final image = await layer.toImage(layer.offset & pixelSize);

    final byteData = (await image.toByteData(format: .png))!;
    return byteData.buffer.asUint8List();
  }

  EditableTextState? focusedEditable() {
    final rootElement = WidgetsBinding.instance.rootElement;

    EditableTextState? res;
    void visit(Element element) {
      if (element case StatefulElement(
        widget: EditableText(:final focusNode),
        state: final EditableTextState state,
      ) when focusNode.hasFocus) {
        res = state;
        return;
      }

      element.visitChildren(visit);
    }

    if (rootElement != null) visit(rootElement);

    return res;
  }

  EditableTextState _requireFocusedEditable() {
    return focusedEditable() ?? (throw Exception("No text field is in focus"));
  }

  Future<Object?> type(_Params params) async {
    _requireFocusedEditable().updateEditingValue(
      TextEditingValue(text: params["text"]!),
    );
    return _success;
  }

  TestGesture _createGesture() {
    return TestGesture(
      dispatcher: (PointerEvent event) async {
        RendererBinding.instance.handlePointerEvent(event);
      },
    );
  }

  Future<Object?> tap(_Params params) async {
    final gesture = _createGesture();

    double? x, y;

    if (params.containsKey("x") && params.containsKey("y")) {
      x = double.parse(params["x"]!);
      y = double.parse(params["y"]!);
    } else if (params.containsKey("key")) {
      final keys =
          _serializeTree(parent: params["parent"])["keys"]
              as List<Map<String, dynamic>>;
      final widget = keys.firstWhereOrNull(
        (info) => info["key"] == params["key"],
      );
      if (widget == null) throw Exception("Given key doesn't exist.");

      x = widget["position"]["left"];
      y = widget["position"]["top"];

      if (params["center"] == "true") {
        x = widget["position"]["left"] + widget["size"]["width"] / 2;
        y = widget["position"]["top"] + widget["size"]["height"] / 2;
      }
    } else if (params.containsKey("text")) {
      final texts =
          _serializeTree(parent: params["parent"])["texts"]
              as List<Map<String, dynamic>>;
      final widget = texts.firstWhereOrNull(
        (info) => info["text"] == params["text"],
      );
      if (widget == null) throw Exception("Given text doesn't exist.");

      x = widget["position"]["left"];
      y = widget["position"]["top"];

      if (params["center"] == "true") {
        x = widget["position"]["left"] + widget["size"]["width"] / 2;
        y = widget["position"]["top"] + widget["size"]["height"] / 2;
      }
    }

    if (x == null || y == null) {
      throw Exception("Unable to get x & y points. Validate your params.");
    }

    await gesture.down(Offset(x, y));
    await gesture.up();
    return _success;
  }

  Future<Object?> hold(_Params params) async {
    final gesture = _createGesture();

    await gesture.down(
      Offset(double.parse(params["x"]!), double.parse(params["y"]!)),
    );
    await Future.delayed(const Duration(milliseconds: 500));
    await gesture.up();
    return _success;
  }

  Future<Object?> drag(_Params params) async {
    await _drag(
      double.parse(params["x"]!),
      double.parse(params["y"]!),
      double.parse(params["dx"]!),
      double.parse(params["dy"]!),
    );
    return _success;
  }

  Future<Object?> scroll(_Params params) async {
    final keys =
        _serializeTree(parent: params["parent"])["keys"]
            as List<Map<String, dynamic>>;
    final widget = keys.firstWhereOrNull(
      (info) => info["key"] == params["key"],
    );
    if (widget == null) throw Exception("Given key doesn't exist.");

    await _drag(
      widget["position"]["left"],
      widget["position"]["top"],
      double.parse(params["dx"]!),
      double.parse(params["dy"]!),
    );
    return _success;
  }

  Future<Object?> scrollInto(_Params params) async {
    // check if scrollable-key exists
    final keys =
        _serializeTree(parent: params["parent"])["keys"]
            as List<Map<String, dynamic>>;
    final widget = keys.firstWhereOrNull(
      (info) => info["key"] == params["scrollable-key"],
    );
    if (widget == null) throw Exception("Given container-key doesn't exist.");

    // timeout params
    int start = DateTime.now().millisecondsSinceEpoch;
    int timeout = int.tryParse("${params["timeout"]}") ?? 5000;
    int delay = int.tryParse("${params["delay"]}") ?? 500;

    while (true) {
      // drag by (dx,dy)
      await _drag(
        widget["position"]["left"],
        widget["position"]["top"],
        double.parse(params["dx"]!),
        double.parse(params["dy"]!),
      );

      // wait for delay
      await Future.delayed(Duration(milliseconds: delay));

      // check if key exists
      final newKeys =
          _serializeTree(includeElement: true)["keys"]
              as List<Map<String, dynamic>>;
      final keyWidget = newKeys.firstWhereOrNull(
        (info) => info["key"] == params["key"],
      );
      if (keyWidget != null) {
        // ensure the widget is visible
        await Scrollable.ensureVisible(keyWidget["element"] as BuildContext);
        await WidgetsBinding.instance.endOfFrame;
        return _success;
      }

      // check if we are out of time
      if (DateTime.now().millisecondsSinceEpoch >= start + timeout) {
        throw Exception("Operation timed out.");
      }
    }
  }

  Future<void> _drag(double x, double y, double dx, double dy) async {
    final gesture = _createGesture();

    await gesture.down(Offset(x, y));

    var offset = Offset(dx, dy);
    final double touchSlopX = 20.0;
    final double touchSlopY = 20.0;

    final double xSign = offset.dx.sign;
    final double ySign = offset.dy.sign;

    final double offsetX = offset.dx;
    final double offsetY = offset.dy;

    final bool separateX = offset.dx.abs() > touchSlopX && touchSlopX > 0;
    final bool separateY = offset.dy.abs() > touchSlopY && touchSlopY > 0;

    if (separateY || separateX) {
      final double offsetSlope = offsetY / offsetX;
      final double inverseOffsetSlope = offsetX / offsetY;
      final double slopSlope = touchSlopY / touchSlopX;
      final double absoluteOffsetSlope = offsetSlope.abs();
      final double signedSlopX = touchSlopX * xSign;
      final double signedSlopY = touchSlopY * ySign;
      if (absoluteOffsetSlope != slopSlope) {
        // The drag goes through one or both of the extents of the edges of the box.
        if (absoluteOffsetSlope < slopSlope) {
          assert(offsetX.abs() > touchSlopX);
          // The drag goes through the vertical edge of the box.
          // It is guaranteed that the |offsetX| > touchSlopX.
          final double diffY = offsetSlope.abs() * touchSlopX * ySign;

          // The vector from the origin to the vertical edge.
          await gesture.moveBy(Offset(signedSlopX, diffY));
          if (offsetY.abs() <= touchSlopY) {
            // The drag ends on or before getting to the horizontal extension of the horizontal edge.
            await gesture.moveBy(
              Offset(offsetX - signedSlopX, offsetY - diffY),
            );
          } else {
            final double diffY2 = signedSlopY - diffY;
            final double diffX2 = inverseOffsetSlope * diffY2;

            // The vector from the edge of the box to the horizontal extension of the horizontal edge.
            await gesture.moveBy(Offset(diffX2, diffY2));
            await gesture.moveBy(
              Offset(offsetX - diffX2 - signedSlopX, offsetY - signedSlopY),
            );
          }
        } else {
          assert(offsetY.abs() > touchSlopY);
          // The drag goes through the horizontal edge of the box.
          // It is guaranteed that the |offsetY| > touchSlopY.
          final double diffX = inverseOffsetSlope.abs() * touchSlopY * xSign;

          // The vector from the origin to the vertical edge.
          await gesture.moveBy(Offset(diffX, signedSlopY));
          if (offsetX.abs() <= touchSlopX) {
            // The drag ends on or before getting to the vertical extension of the vertical edge.
            await gesture.moveBy(
              Offset(offsetX - diffX, offsetY - signedSlopY),
            );
          } else {
            final double diffX2 = signedSlopX - diffX;
            final double diffY2 = offsetSlope * diffX2;

            // The vector from the edge of the box to the vertical extension of the vertical edge.
            await gesture.moveBy(Offset(diffX2, diffY2));
            await gesture.moveBy(
              Offset(offsetX - signedSlopX, offsetY - diffY2 - signedSlopY),
            );
          }
        }
      } else {
        // The drag goes through the corner of the box.
        await gesture.moveBy(Offset(signedSlopX, signedSlopY));
        await gesture.moveBy(
          Offset(offsetX - signedSlopX, offsetY - signedSlopY),
        );
      }
    } else {
      // The drag ends inside the box.
      await gesture.moveBy(offset);
    }
    await gesture.up();
  }

  Map<String, dynamic> _serializeTree({
    bool includeElement = false,
    String? parent,
  }) {
    final renderElement = WidgetsBinding.instance.rootElement;

    List<Map<String, dynamic>> texts = [];
    List<Map<String, dynamic>> editables = [];
    List<Map<String, dynamic>> keys = [];

    // If parent is specified, find the first element with matching widget type
    Element? startElement = renderElement;
    if (parent != null) {
      Element? foundElement;

      void findParentElement(Element element) {
        if (element.widget.runtimeType.toString() == parent) {
          foundElement ??= element; // Only set if not already found
          return;
        }
        element.visitChildren(findParentElement);
      }

      findParentElement(renderElement!);
      if (foundElement != null) {
        startElement = foundElement;
      } else {
        // If no matching parent is found, return an empty tree
        return {
          "texts": texts,
          "editables": editables,
          "tree": {},
          "keys": keys,
        };
      }
    }

    Map<String, dynamic>? serialize(Element? element) {
      if (element == null) return null;
      var node = element.renderObject!.toDiagnosticsNode();

      // tree sometimes has elements are not visible
      // their positions are NaN and not usable for testing. ignoring them.
      if (node.value is RenderBox &&
          !(node.value as RenderBox).localToGlobal(Offset.zero).isFinite) {
        return null;
      }

      Map<String, Object?> out = {
        "widget": element.widget.runtimeType.toString(),
        "render": node.toDescription(),
      };

      switch (element.widget) {
        case CupertinoSwitch(:final value):
          out["value"] = value;
        case Switch(:final value):
          out["value"] = value;
        case Checkbox(:final value):
          out["value"] = value;
        case Radio(:final value):
          out["value"] = value;
      }

      if (includeElement) {
        out["element"] = element;
      }

      if (node.value case TextSpan(:final text)) {
        out["text"] = text;
      }

      if (node.value case final RenderParagraph n
          when element.widget is RichText) {
        for (final subnode in node.getChildren()) {
          if (subnode.value case final TextSpan textNode) {
            final pos = n.localToGlobal(Offset.zero);
            final textInfo = <String, dynamic>{
              "text": textNode.toPlainText(),
              "size": {"height": n.size.height, "width": n.size.width},
              "position": {"left": pos.dx, "top": pos.dy},
              "style": {
                "color": textNode.style?.color?.toARGB32().toRadixString(16),
                "fontSize": textNode.style?.fontSize,
              },
            };
            out["text"] = textInfo;
            texts.add(textInfo);
          }
        }
      }

      if (node.value case final RenderEditable n) {
        final pos = n.localToGlobal(Offset.zero);
        final text = switch (n.text) {
          TextSpan(:final text) => text,
          _ => "",
        };
        editables.add({
          "size": {"height": n.size.height, "width": n.size.width},
          "position": {"left": pos.dx, "top": pos.dy},
          "text": text,
          "plain_text": n.plainText,
        });
      }

      if (node.value case final RenderBox n) {
        out["size"] = {"height": n.size.height, "width": n.size.width};
        final pos = n.localToGlobal(Offset.zero);
        out["position"] = {"left": pos.dx, "top": pos.dy};
      }

      out["props"] = [
        for (final p in node.getProperties())
          if (p is IterableProperty && p.name == "gestures")
            {"gestures": p.value},
      ];

      if (element.widget.key case ValueKey(:final value)) {
        out["key"] = value.toString();
        keys.add({...out});
      }

      final children = <Map<String, Object?>?>[];
      out["children"] = children;

      element.visitChildren((child) => children.add(serialize(child)));

      return out;
    }

    final tree = serialize(startElement);

    return {"texts": texts, "editables": editables, "tree": tree, "keys": keys};
  }
}
