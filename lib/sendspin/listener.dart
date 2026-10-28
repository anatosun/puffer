import 'dart:async';
import 'dart:io';

import 'session.dart';

/// The WebSocket endpoint Sendspin servers connect to (server-initiated connections, spec: connection.md). It admits one session for playback at a time: a session that declares playback displaces the previous one.
class SendspinListener {
  SendspinListener({
    required this.config,
    required this.output,
    this.port = 8928,
    this.path = '/sendspin',
    this.onStatus,
  });

  final SendspinConfig config;
  final SendspinAudioOutput output;
  final int port;
  final String path;
  final void Function(SendspinStatus status)? onStatus;

  HttpServer? _server;
  final _sessions = <SendspinSession>{};
  SendspinSession? _admitted;

  int? get boundPort => _server?.port;

  Future<void> start() async {
    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _server!.listen(_onRequest);
  }

  Future<void> _onRequest(HttpRequest request) async {
    // Browsers send an Origin header; Sendspin servers must not (spec: "Server Initiated Connections").
    if (request.uri.path != path ||
        request.headers.value('origin') != null ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = const Duration(seconds: 10);
    late final SendspinSession session;
    session = SendspinSession(
      socket,
      config,
      output,
      // Only the admitted session reports its status.
      onStatus: (status) {
        if (identical(_admitted, session)) onStatus?.call(status);
      },
      onActivated: _onActivated,
    );
    _sessions.add(session);
    await session.run();
    _sessions.remove(session);
    if (identical(_admitted, session)) {
      _admitted = null;
      onStatus?.call(const SendspinStatus());
    }
  }

  void _onActivated(SendspinSession session, List<String> activities) {
    if (!activities.contains('playback') || identical(_admitted, session)) {
      return;
    }
    final previous = _admitted;
    _admitted = session;
    onStatus?.call(session.status);
    if (previous != null) unawaited(previous.goodbye('another_server'));
  }

  Future<void> stop() async {
    for (final s in [..._sessions]) {
      await s.goodbye('shutdown');
    }
    await _server?.close(force: true);
    _server = null;
  }
}
