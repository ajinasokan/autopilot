import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' show TestGesture;
import 'text_input.dart';

typedef Future<void> Handler(HttpRequest r);

class Autopilot {
  var _textInputDriver = TextInputDriver();

  void init({
    int port = 8080,
    Map<String, Handler> extraHandlers = const {},
  }) async {
    _textInputDriver.init();

    final server = await HttpServer.bind("localhost", port);

    Map<String, Handler> routes = {
      '/widgets': _getWidgets,
      '/keys': _getKeys,
      '/texts': _getTexts,
      '/editables': _getEditables,
      '/type': _doType,
      '/tap': _doTap,
      '/hold': _doHold,
      '/drag': _doDrag,
      '/screenshot': _getScreenshot,
      '/keyboard': _keyboard,
      ...extraHandlers,
    };

    _handle(server, routes);
  }

  void _handle(
    HttpServer server,
    Map<String, Handler> routes,
  ) async {
    await for (var request in server) {
      final handler = routes[request.uri.path];
      try {
        if (handler == null) {
          writeResponse(
            request: request,
            status: 404,
            body: _indentedJson({
              "error": "route not found",
            }),
          );
        } else {
          await routes[request.uri.path](request);
        }
      } catch (error, stackTrace) {
        sendError(request, error, stackTrace);
      }
    }
  }

  String _indentedJson(dynamic payload) {
    return JsonEncoder.withIndent("  ").convert(payload);
  }

  void sendError(HttpRequest r, dynamic e, StackTrace s) async {
    writeResponse(
      request: r,
      status: 500,
      body: _indentedJson({
        "error": e.toString(),
        "stacktrace": s.toString(),
      }),
    );
  }

  void writeResponse({HttpRequest request, int status = 200, String body}) {
    request.response.statusCode = status;
    request.response.headers
        .set("content-type", "application/json; charset=utf-8");
    request.response.write(body);
    request.response.close();
  }

  Future<void> _keyboard(HttpRequest r) async {
    if (r.method == "GET") {
      SystemChannels.textInput.invokeMethod("TextInput.show");
    } else if (r.method == "DELETE") {
      SystemChannels.textInput.invokeMethod("TextInput.hide");
    }
    r.response.close();
  }

  Future<void> _getWidgets(HttpRequest r) async {
    final widgetTree = _serializeTree()["tree"];

    if (widgetTree == null) {
      sendError(r, Exception("Render tree unavailable"), StackTrace.current);
    } else {
      writeResponse(
        request: r,
        body: _indentedJson(widgetTree),
      );
    }
  }

  Future<void> _getKeys(HttpRequest r) async {
    final keys = _serializeTree()["keys"];
    writeResponse(
      request: r,
      body: _indentedJson(keys),
    );
  }

  Future<void> _getTexts(HttpRequest r) async {
    final serialized = _serializeTree();
    final params = r.uri.queryParameters;

    var texts = serialized["texts"] as List<Map<String, dynamic>>;
    if (params.containsKey("text")) {
      final query = params["text"];
      texts = texts.where((item) => item["text"].contains(query)).toList();
    } else if (params.containsKey("key")) {
      final keys = serialized["keys"] as List<Map<String, dynamic>>;
      final widget = keys.firstWhere(
        (info) => info["key"] == params["key"],
        orElse: () => null,
      );
      if (widget != null) {
        texts = texts.where((item) {
          return item["position"]["left"] == widget["position"]["left"] &&
              item["position"]["top"] == widget["position"]["top"];
        }).toList();
      } else {
        texts = [];
      }
    }
    writeResponse(
      request: r,
      body: _indentedJson(texts),
    );
  }

  Future<void> _getEditables(HttpRequest r) async {
    final texts = _serializeTree()["editables"];
    writeResponse(
      request: r,
      body: _indentedJson(texts),
    );
  }

  Future<void> _getScreenshot(HttpRequest r) async {
    final renderElement = WidgetsBinding.instance?.renderView;
    OffsetLayer layer = renderElement.layer;
    var pixelRatio = WidgetsBinding.instance.window.devicePixelRatio;
    var pixelSize = renderElement.size * pixelRatio;
    ui.Image image = await layer.toImage(
      layer.offset & pixelSize,
    );

    ByteData byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData.buffer.asUint8List();
    r.response.headers.set("content-type", "image/png");
    r.response.add(pngBytes);
    r.response.close();
  }

  Future<void> _doType(HttpRequest r) async {
    var text = r.uri.queryParameters["text"];
    _textInputDriver.type(text);
    r.response.close();
  }

  Future<void> _doTap(HttpRequest r) async {
    var gesture = TestGesture(
      hitTester: (location) {
        final HitTestResult result = HitTestResult();
        RendererBinding.instance.hitTest(result, location);
        return result;
      },
      dispatcher: (PointerEvent event, HitTestResult result) async {
        RendererBinding.instance.dispatchEvent(event, result);
      },
    );

    var params = r.uri.queryParameters;
    double x, y;

    if (params.containsKey("x") && params.containsKey("y")) {
      x = double.parse(params["x"]);
      y = double.parse(params["y"]);
    } else if (params.containsKey("key")) {
      final keys = _serializeTree()["keys"] as List<Map<String, dynamic>>;
      final widget = keys.firstWhere(
        (info) => info["key"] == params["key"],
        orElse: () => null,
      );
      if (widget == null) {
        sendError(
          r,
          Exception("Given key doesn't exist."),
          StackTrace.current,
        );
        return;
      } else {
        x = widget["position"]["left"];
        y = widget["position"]["top"];
      }
    } else if (params.containsKey("text")) {
      final texts = _serializeTree()["texts"] as List<Map<String, dynamic>>;
      final widget = texts.firstWhere(
        (info) => info["text"] == params["text"],
        orElse: () => null,
      );
      if (widget == null) {
        sendError(
          r,
          Exception("Given text doesn't exist."),
          StackTrace.current,
        );
        return;
      } else {
        x = widget["position"]["left"];
        y = widget["position"]["top"];
      }
    }

    if (x == null || y == null) {
      sendError(
        r,
        Exception("Unable to get x & y points. Validate your params."),
        StackTrace.current,
      );
      return;
    }

    await gesture.down(Offset(x, y));
    await gesture.up();
    r.response.close();
  }

  Future<void> _doHold(HttpRequest r) async {
    var gesture = TestGesture(
      hitTester: (location) {
        final HitTestResult result = HitTestResult();
        RendererBinding.instance.hitTest(result, location);
        return result;
      },
      dispatcher: (PointerEvent event, HitTestResult result) async {
        RendererBinding.instance.dispatchEvent(event, result);
      },
    );

    await gesture.down(Offset(
      double.parse(r.uri.queryParameters["x"]),
      double.parse(r.uri.queryParameters["y"]),
    ));
    await Future.delayed(Duration(milliseconds: 500));
    await gesture.up();
    r.response.close();
  }

  Future<void> _doDrag(HttpRequest r) async {
    var gesture = TestGesture(
      hitTester: (location) {
        final HitTestResult result = HitTestResult();
        RendererBinding.instance.hitTest(result, location);
        return result;
      },
      dispatcher: (PointerEvent event, HitTestResult result) async {
        RendererBinding.instance.dispatchEvent(event, result);
      },
    );

    await gesture.down(Offset(
      double.parse(r.uri.queryParameters["x"]),
      double.parse(r.uri.queryParameters["y"]),
    ));

    var offset = Offset(
      double.parse(r.uri.queryParameters["dx"]),
      double.parse(r.uri.queryParameters["dy"]),
    );
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
            await gesture
                .moveBy(Offset(offsetX - signedSlopX, offsetY - diffY));
          } else {
            final double diffY2 = signedSlopY - diffY;
            final double diffX2 = inverseOffsetSlope * diffY2;

            // The vector from the edge of the box to the horizontal extension of the horizontal edge.
            await gesture.moveBy(Offset(diffX2, diffY2));
            await gesture.moveBy(
                Offset(offsetX - diffX2 - signedSlopX, offsetY - signedSlopY));
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
            await gesture
                .moveBy(Offset(offsetX - diffX, offsetY - signedSlopY));
          } else {
            final double diffX2 = signedSlopX - diffX;
            final double diffY2 = offsetSlope * diffX2;

            // The vector from the edge of the box to the vertical extension of the vertical edge.
            await gesture.moveBy(Offset(diffX2, diffY2));
            await gesture.moveBy(
                Offset(offsetX - signedSlopX, offsetY - diffY2 - signedSlopY));
          }
        }
      } else {
        // The drag goes through the corner of the box.
        await gesture.moveBy(Offset(signedSlopX, signedSlopY));
        await gesture
            .moveBy(Offset(offsetX - signedSlopX, offsetY - signedSlopY));
      }
    } else {
      // The drag ends inside the box.
      await gesture.moveBy(offset);
    }
    await gesture.up();
    r.response.close();
  }

  Map<String, dynamic> _serializeTree() {
    final renderElement = WidgetsBinding.instance?.renderViewElement;

    List<Map<String, dynamic>> texts = [];
    List<Map<String, dynamic>> editables = [];
    List<Map<String, dynamic>> keys = [];

    Map<String, dynamic> serialize(Element element) {
      if (element == null) return null;
      var node = element.renderObject.toDiagnosticsNode();

      Map<String, Object> out = {
        "widget": element.widget.runtimeType.toString(),
        "render": node.toDescription(),
      };

      if (node.value is TextSpan) {
        out["text"] = (node.value as TextSpan).text;
      }

      if (node.value is RenderParagraph && element.widget is RichText) {
        var n = node.value as RenderParagraph;
        node.getChildren().forEach((subnode) {
          if (subnode.value is TextSpan) {
            var text = (subnode.value as TextSpan).text.toString();
            var textInfo = <String, dynamic>{
              "text": text,
            };
            textInfo["size"] = {
              "height": n.size.height,
              "width": n.size.width,
            };
            var pos = n.localToGlobal(Offset.zero);
            textInfo["position"] = {
              "left": pos.dx,
              "top": pos.dy,
            };
            out["text"] = textInfo;
            texts.add(textInfo);
          }
        });
      }

      if (node.value is RenderEditable) {
        var n = node.value as RenderEditable;
        var pos = n.localToGlobal(Offset.zero);
        editables.add({
          "size": {
            "height": n.size.height,
            "width": n.size.width,
          },
          "position": {
            "left": pos.dx,
            "top": pos.dy,
          }
        });
      }

      if (node.value is RenderBox) {
        var n = node.value as RenderBox;
        out["size"] = {
          "height": n.size.height,
          "width": n.size.width,
        };
        var pos = n.localToGlobal(Offset.zero);
        out["position"] = {
          "left": pos.dx,
          "top": pos.dy,
        };
      }

      List<Map<String, Object>> props = [];
      out["props"] = props;

      node.getProperties().forEach((p) {
        if (p is IterableProperty && p.name == "gestures") {
          props.add({
            "gestures": p.value,
          });
        }
      });

      String key;
      if (element.widget.key is ValueKey) {
        key = (element.widget.key as ValueKey).value.toString();
        out["key"] = key;
        keys.add({...out});
      }

      List<Map<String, Object>> children = [];
      out["children"] = children;

      element.visitChildren((node) {
        children.add(serialize(node));
      });

      return out;
    }

    final tree = serialize(renderElement);

    return {
      "texts": texts,
      "editables": editables,
      "tree": tree,
      "keys": keys,
    };
  }
}
