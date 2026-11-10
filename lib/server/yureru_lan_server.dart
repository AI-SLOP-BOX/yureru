import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import '../library/library_notifier.dart';

/// Small LAN API hosted by Yureru itself. Clients remain regular Yureru apps;
/// media is streamed directly from the host with byte-range seeking support.
class YureruLanServer {
  static const discoveryPort = 47822;
  static const _serviceName = 'yureru-v1';
  final LibraryState Function() _library;
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  String? _pairingCode;
  final Map<String, List<DateTime>> _failedAuthorizations = {};

  YureruLanServer(this._library);

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<void> start({
    required int port,
    required String accessKey,
    required String pairingCode,
  }) async {
    if (_server != null) return;
    if (accessKey.length < 24) {
      throw ArgumentError('The Yureru access key is too short.');
    }
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((request) => unawaited(_handle(request, accessKey)));
    _pairingCode = pairingCode;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null || !_isPrivateLanAddress(datagram.address)) return;
        try {
          final message = jsonDecode(utf8.decode(datagram.data));
          if (message is! Map || message['discover'] != _serviceName) return;
          final reply = utf8.encode(
            jsonEncode({
              'service': _serviceName,
              'name': 'Yureru — ${Platform.localHostname}',
              'port': server.port,
            }),
          );
          socket.send(reply, datagram.address, datagram.port);
        } catch (_) {}
      });
    } catch (_) {
      // Manual address entry remains available if UDP discovery is blocked.
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    _pairingCode = null;
    _failedAuthorizations.clear();
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request, String accessKey) async {
    try {
      if (!_isPrivateLanAddress(request.connectionInfo?.remoteAddress)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      final remoteAddress = request.connectionInfo?.remoteAddress.address;
      if (remoteAddress != null && _isRateLimited(remoteAddress)) {
        request.response.statusCode = HttpStatus.tooManyRequests;
        request.response.headers.set(HttpHeaders.retryAfterHeader, '60');
        await request.response.close();
        return;
      }
      final path = request.uri.pathSegments;
      if (request.method != 'GET' ||
          path.length < 3 ||
          path[0] != 'api' ||
          path[1] != 'v1') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (!_authorized(request, accessKey, _pairingCode)) {
        if (remoteAddress != null) _recordFailedAuthorization(remoteAddress);
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        await request.response.close();
        return;
      }

      if (path[2] == 'info' && path.length == 3) {
        await _json(request, {'name': 'Yureru', 'apiVersion': 1});
        return;
      }
      if (path[2] == 'library' && path.length == 3) {
        final library = _library();
        await _json(request, {
          'media': [
            for (final item in library.savedMedia)
              _mediaJson(item, request.uri),
          ],
          'playlists': [
            for (final playlist in library.playlists)
              {
                'id': playlist.id,
                'name': playlist.name,
                'mediaIds': playlist.mediaIds,
              },
          ],
        });
        return;
      }
      if (path[2] == 'media' && path.length >= 4) {
        final item = _library().byId(path[3]);
        if (item == null || item.isTemporary) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        if (path.length == 4) {
          await _streamFile(request, item.localPath);
          return;
        }
        if (path.length == 5 && path[4] == 'image') {
          final type = request.uri.queryParameters['type'];
          final imagePath = type == 'artwork'
              ? item.artworkPath ?? item.thumbnailPath
              : item.thumbnailPath ?? item.artworkPath;
          if (imagePath == null) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          await _streamFile(request, imagePath);
          return;
        }
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Map<String, Object?> _mediaJson(MediaItem item, Uri requestUri) {
    final base = Uri(
      scheme: requestUri.scheme,
      host: requestUri.host,
      port: requestUri.hasPort ? requestUri.port : null,
    );
    final authParameter = requestUri.queryParameters.containsKey('code')
        ? 'code'
        : 'key';
    final authValue = requestUri.queryParameters[authParameter]!;
    Uri endpoint(String path, [Map<String, String>? query]) => base.replace(
      path: path,
      queryParameters: {authParameter: authValue, ...?query},
    );
    return {
      'id': item.id,
      'title': item.title,
      'artist': item.artist,
      'album': item.album,
      'durationMs': item.durationMs,
      'streamUrl': endpoint(
        '/api/v1/media/${Uri.encodeComponent(item.id)}',
      ).toString(),
      'artworkUrl': item.artworkPath == null && item.thumbnailPath == null
          ? null
          : endpoint('/api/v1/media/${Uri.encodeComponent(item.id)}/image', {
              'type': 'artwork',
            }).toString(),
      'thumbnailUrl': item.thumbnailPath == null && item.artworkPath == null
          ? null
          : endpoint('/api/v1/media/${Uri.encodeComponent(item.id)}/image', {
              'type': 'thumbnail',
            }).toString(),
    };
  }

  bool _authorized(HttpRequest request, String key, String? pairingCode) {
    final supplied =
        request.uri.queryParameters['code'] ??
        request.uri.queryParameters['key'] ??
        request.headers
            .value(HttpHeaders.authorizationHeader)
            ?.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    if (supplied == null) return false;
    if (pairingCode != null && _constantTimeEquals(supplied, pairingCode)) {
      return true;
    }
    return _constantTimeEquals(supplied, key);
  }

  bool _constantTimeEquals(String supplied, String expected) {
    if (supplied.length != expected.length) return false;
    var mismatch = 0;
    for (var i = 0; i < expected.length; i++) {
      mismatch |= supplied.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return mismatch == 0;
  }

  bool _isRateLimited(String address) {
    final attempts = _failedAuthorizations[address];
    if (attempts == null) return false;
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    attempts.removeWhere((attempt) => attempt.isBefore(cutoff));
    if (attempts.isEmpty) _failedAuthorizations.remove(address);
    return attempts.length >= 10;
  }

  void _recordFailedAuthorization(String address) {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    final attempts = _failedAuthorizations.putIfAbsent(address, () => []);
    attempts.removeWhere((attempt) => attempt.isBefore(cutoff));
    attempts.add(DateTime.now());
  }

  bool _isPrivateLanAddress(InternetAddress? address) {
    if (address == null || address.type != InternetAddressType.IPv4) {
      return false;
    }
    final octets = address.rawAddress;
    return address.isLoopback ||
        octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168) ||
        (octets[0] == 169 && octets[1] == 254) ||
        (octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127);
  }

  Future<void> _json(HttpRequest request, Object value) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.write(jsonEncode(value));
    await request.response.close();
  }

  Future<void> _streamFile(HttpRequest request, String path) async {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final length = await file.length();
    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = length - 1;
    if (range != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$length',
        );
        await request.response.close();
        return;
      }
      if (match[1]!.isEmpty) {
        final suffixLength = int.tryParse(match[2]!) ?? 0;
        start = (length - suffixLength).clamp(0, length);
      } else {
        start = int.tryParse(match[1]!) ?? 0;
        if (match[2]!.isNotEmpty) end = int.tryParse(match[2]!) ?? end;
      }
      if (start >= length || end < start) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$length',
        );
        await request.response.close();
        return;
      }
      end = end.clamp(start, length - 1);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
    }
    request.response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentLengthHeader, end - start + 1)
      ..set(HttpHeaders.cacheControlHeader, 'private, no-store')
      ..contentType = _contentType(path);
    await request.response.addStream(file.openRead(start, end + 1));
    await request.response.close();
  }

  ContentType _contentType(String path) {
    final extension = path.toLowerCase().split('.').last;
    return switch (extension) {
      'mp4' || 'm4v' => ContentType('video', 'mp4'),
      'mov' => ContentType('video', 'quicktime'),
      'webm' => ContentType('video', 'webm'),
      'mkv' => ContentType('video', 'x-matroska'),
      'mp3' => ContentType('audio', 'mpeg'),
      'm4a' || 'aac' => ContentType('audio', 'mp4'),
      'flac' => ContentType('audio', 'flac'),
      'ogg' || 'opus' => ContentType('audio', 'ogg'),
      'wav' => ContentType('audio', 'wav'),
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'webp' => ContentType('image', 'webp'),
      _ => ContentType.binary,
    };
  }
}

class YureruDiscoveredServer {
  final String name;
  final String host;
  final int port;

  const YureruDiscoveredServer({
    required this.name,
    required this.host,
    required this.port,
  });

  String get address => 'http://$host:$port';
}

Future<List<YureruDiscoveredServer>> discoverYureruServers({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final found = <String, YureruDiscoveredServer>{};
  try {
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final decoded = jsonDecode(utf8.decode(datagram.data));
        if (decoded is! Map || decoded['service'] != 'yureru-v1') return;
        final port = decoded['port'];
        if (port is! num || port.toInt() < 1 || port.toInt() > 65535) return;
        final server = YureruDiscoveredServer(
          name: decoded['name'] as String? ?? 'Yureru',
          host: datagram.address.address,
          port: port.toInt(),
        );
        found[server.address] = server;
      } catch (_) {}
    });
    final query = utf8.encode(jsonEncode({'discover': 'yureru-v1'}));
    final destinations = <InternetAddress>{
      InternetAddress('255.255.255.255'),
      for (final interface in await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      ))
        for (final address in interface.addresses)
          if (!address.isLoopback)
            InternetAddress(
              '${address.address.split('.').take(3).join('.')}.255',
            ),
    };
    for (final destination in destinations) {
      socket.send(query, destination, YureruLanServer.discoveryPort);
    }
    await Future<void>.delayed(timeout);
  } finally {
    socket.close();
  }
  return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

Future<List<String>> yureruLanAddresses() async {
  final addresses = <String>{};
  for (final interface in await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  )) {
    for (final address in interface.addresses) {
      if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
        addresses.add(address.address);
      }
    }
  }
  return addresses.toList()..sort();
}
