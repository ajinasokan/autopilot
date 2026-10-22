part of 'driver.dart';

typedef _Tool = ({
  String description,
  Map<String, Object?> inputSchema,
  Future<Object?> Function(_Params params) run,
});

// Newest first. The first one is offered when the client asks for an
// unknown version.
const _protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"];

const _instructions =
    "Drives a running Flutter app. Find widgets with get_keys or get_texts "
    "before tapping, and prefer tapping by key or text over coordinates. "
    "Positions are logical pixels from the top-left of the screen. Use "
    "screenshot to see the current state of the app.";

/// MCP server over the Streamable HTTP transport. Stateless: every POST
/// carries one JSON-RPC message and gets a plain JSON reply.
class _Mcp {
  _Mcp(this.driver);

  final _Driver driver;

  late final Map<String, _Tool> tools = {
    "get_widgets": (
      description:
          "Returns the full widget tree with types, sizes, positions and "
          "keys. Large; prefer get_keys or get_texts, or narrow it with parent.",
      inputSchema: _schema({"parent": _parent}),
      run: driver.getWidgets,
    ),
    "get_keys": (
      description:
          "Lists widgets that have a ValueKey, with their key, type, size, "
          "position and value (for switches, checkboxes and radios).",
      inputSchema: _schema({"parent": _parent}),
      run: driver.getKeys,
    ),
    "get_texts": (
      description:
          "Lists visible texts with their size, position and style. Filter "
          "by a substring of the text, or by the key of the Text widget.",
      inputSchema: _schema({
        "text": _string("Only return texts containing this substring."),
        "key": _string("Only return the text of the widget with this key."),
        "parent": _parent,
      }),
      run: driver.getTexts,
    ),
    "get_editables": (
      description: "Lists text fields with their size, position and content.",
      inputSchema: _schema({"parent": _parent}),
      run: driver.getEditables,
    ),
    "tap": (
      description:
          "Taps a widget found by key or by exact text, or taps at x, y. "
          "Taps the top-left corner of the widget unless center is true.",
      inputSchema: _schema({
        "key": _string("Key of the widget to tap."),
        "text": _string("Exact text of the widget to tap."),
        "x": _number("X position to tap, used together with y."),
        "y": _number("Y position to tap, used together with x."),
        "center": {
          "type": "boolean",
          "description": "Tap the center of the widget instead of its corner.",
        },
        "parent": _parent,
      }),
      run: driver.tap,
    ),
    "hold": (
      description: "Presses at x, y for 500 ms.",
      inputSchema: _schema(
        {"x": _number("X position."), "y": _number("Y position.")},
        required: ["x", "y"],
      ),
      run: driver.hold,
    ),
    "drag": (
      description: "Drags from x, y by dx, dy.",
      inputSchema: _schema(
        {
          "x": _number("X position to start from."),
          "y": _number("Y position to start from."),
          "dx": _number("Distance to drag along x."),
          "dy": _number("Distance to drag along y."),
        },
        required: ["x", "y", "dx", "dy"],
      ),
      run: driver.drag,
    ),
    "scroll": (
      description:
          "Drags the widget with the given key by dx, dy. Negative dy "
          "scrolls a vertical list down.",
      inputSchema: _schema(
        {
          "key": _string("Key of the scrollable widget."),
          "dx": _number("Distance to drag along x."),
          "dy": _number("Distance to drag along y."),
          "parent": _parent,
        },
        required: ["key", "dx", "dy"],
      ),
      run: driver.scroll,
    ),
    "scroll_into": (
      description:
          "Keeps dragging a scrollable by dx, dy until the widget with the "
          "given key appears, then scrolls it fully into view.",
      inputSchema: _schema(
        {
          "scrollable-key": _string("Key of the scrollable widget."),
          "key": _string("Key of the widget to bring into view."),
          "dx": _number("Distance of each drag along x."),
          "dy": _number("Distance of each drag along y."),
          "timeout": _number("Give up after this many ms. Defaults to 5000."),
          "delay": _number(
            "Wait this many ms after each drag. Defaults to 500.",
          ),
          "parent": _parent,
        },
        required: ["scrollable-key", "key", "dx", "dy"],
      ),
      run: driver.scrollInto,
    ),
    "type": (
      description:
          "Replaces the content of the focused text field. Tap the field "
          "first to focus it.",
      inputSchema: _schema(
        {"text": _string("Text to put in the field.")},
        required: ["text"],
      ),
      run: driver.type,
    ),
    "keyboard": (
      description:
          "Shows or hides the keyboard, or sends an action such as done or "
          "next to the focused text field.",
      inputSchema: _schema(
        {
          "action": {
            "type": "string",
            "enum": ["show", "hide", ...driver.submitTypes.keys],
          },
        },
        required: ["action"],
      ),
      run: (params) => switch (params["action"]) {
        "show" => driver.setKeyboardVisible(true),
        "hide" => driver.setKeyboardVisible(false),
        final action => driver.keyboardAction({"type": "$action"}),
      },
    ),
    "screenshot": (
      description: "Takes a screenshot of the app as a PNG image.",
      inputSchema: _schema({}),
      run: (_) => driver.screenshot(),
    ),
  };

  Future<void> handle(AutopilotAction action) async {
    final request = action.request;

    // Browsers send Origin; MCP clients don't. Blocks web pages from
    // reaching the server through DNS rebinding.
    final origin = request.headers.value("origin");
    if (origin != null && !_isLocalOrigin(origin)) {
      return action.writeResponse(
        status: 403,
        body: {"error": "origin not allowed"},
      );
    }

    if (request.method != "POST") {
      request.response.headers.set("allow", "POST");
      return action.writeResponse(
        status: 405,
        body: {"error": "method not allowed"},
      );
    }

    final Object? message;
    try {
      message = jsonDecode(await utf8.decoder.bind(request).join());
    } on FormatException {
      return action.writeResponse(body: _error(null, -32700, "Parse error"));
    }

    if (message is! Map<String, Object?>) {
      return action.writeResponse(
        body: _error(null, -32600, "Invalid request"),
      );
    }

    // Notifications and responses don't get a reply.
    final id = message["id"];
    final method = message["method"];
    if (id == null || method is! String) {
      request.response.statusCode = 202;
      return request.response.close();
    }

    final params = message["params"] as Map<String, Object?>? ?? const {};
    final reply = switch (method) {
      "initialize" => _result(id, _initialize(params)),
      "ping" => _result(id, {}),
      "tools/list" => _result(id, {
        "tools": [
          for (final MapEntry(:key, :value) in tools.entries)
            {
              "name": key,
              "description": value.description,
              "inputSchema": value.inputSchema,
            },
        ],
      }),
      "tools/call" => await _callTool(id, params),
      _ => _error(id, -32601, "Method not found: $method"),
    };
    await action.writeResponse(body: reply);
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    final requested = params["protocolVersion"];
    return {
      "protocolVersion": _protocolVersions.contains(requested)
          ? requested
          : _protocolVersions.first,
      "capabilities": {"tools": {}},
      "serverInfo": {"name": "autopilot", "version": "0.4.0"},
      "instructions": _instructions,
    };
  }

  Future<Map<String, Object?>> _callTool(
    Object id,
    Map<String, Object?> params,
  ) async {
    final name = params["name"];
    final tool = tools[name];
    if (tool == null) return _error(id, -32602, "Unknown tool: $name");

    // The actions take the same string params as the REST API.
    final args = params["arguments"] as Map<String, Object?>? ?? const {};
    try {
      final result = await tool.run({
        for (final MapEntry(:key, :value) in args.entries)
          if (value != null) key: "$value",
      });
      final content = result is Uint8List
          ? {
              "type": "image",
              "data": base64Encode(result),
              "mimeType": "image/png",
            }
          : {"type": "text", "text": jsonEncode(result)};
      return _result(id, {
        "content": [content],
      });
    } catch (error) {
      // Tool failures go back as results so the model can read them.
      return _result(id, {
        "content": [
          {"type": "text", "text": "$error"},
        ],
        "isError": true,
      });
    }
  }

  static bool _isLocalOrigin(String origin) {
    final host = Uri.tryParse(origin)?.host;
    return host == "localhost" || host == "127.0.0.1" || host == "::1";
  }

  static Map<String, Object?> _result(Object id, Object? result) {
    return {"jsonrpc": "2.0", "id": id, "result": result};
  }

  static Map<String, Object?> _error(Object? id, int code, String message) {
    return {
      "jsonrpc": "2.0",
      "id": id,
      "error": {"code": code, "message": message},
    };
  }

  static Map<String, Object?> _schema(
    Map<String, Object?> properties, {
    List<String> required = const [],
  }) {
    return {
      "type": "object",
      "properties": properties,
      if (required.isNotEmpty) "required": required,
    };
  }

  static Map<String, Object?> _string(String description) {
    return {"type": "string", "description": description};
  }

  static Map<String, Object?> _number(String description) {
    return {"type": "number", "description": description};
  }

  static const _parent = {
    "type": "string",
    "description":
        "Only look inside the first widget of this type, e.g. AlertDialog.",
  };
}
