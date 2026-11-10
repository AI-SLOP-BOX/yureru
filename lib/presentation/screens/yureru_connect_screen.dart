import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../../server/yureru_lan_server.dart';
import '../i18n.dart';
import '../widgets/thumb_image.dart';

final yureruLanServerProvider = Provider<YureruLanServer>((ref) {
  final server = YureruLanServer(() => ref.read(libraryProvider));
  ref.onDispose(() => unawaited(server.stop()));
  return server;
});

class YureruConnectScreen extends ConsumerStatefulWidget {
  const YureruConnectScreen({super.key});

  @override
  ConsumerState<YureruConnectScreen> createState() =>
      _YureruConnectScreenState();
}

class _YureruConnectScreenState extends ConsumerState<YureruConnectScreen> {
  static const _accessKeyPreference = 'yureru.server.access_key.v1';
  static const _pairingCodePreference = 'yureru.server.pairing_code.v1';
  static const _lastAddressPreference = 'yureru.client.last_address.v1';
  static const _lastCodePreference = 'yureru.client.last_code.v1';
  final _hostController = TextEditingController(text: '47821');
  final _addressController = TextEditingController();
  final _keyController = TextEditingController();
  final _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  List<MediaItem> _remoteMedia = const [];
  List<YureruDiscoveredServer> _discoveredServers = const [];
  String? _accessKey;
  String? _pairingCode;
  String? _error;
  bool _connecting = false;
  bool _starting = false;
  bool _discovering = false;
  bool _hasDiscovered = false;
  bool _serverRunning = false;

  @override
  void initState() {
    super.initState();
    _serverRunning = ref.read(yureruLanServerProvider).isRunning;
    unawaited(_loadAccessKey());
    unawaited(_loadLastConnection());
    unawaited(_discoverServers());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _addressController.dispose();
    _keyController.dispose();
    _httpClient.close(force: true);
    super.dispose();
  }

  Future<void> _loadAccessKey() async {
    final preferences = await SharedPreferences.getInstance();
    final random = Random.secure();
    var key = preferences.getString(_accessKeyPreference);
    if (key == null || key.length < 24) {
      key = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await preferences.setString(_accessKeyPreference, key);
    }
    var code = preferences.getString(_pairingCodePreference);
    if (code == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
      code = List.generate(6, (_) => random.nextInt(10)).join();
      await preferences.setString(_pairingCodePreference, code);
    }
    if (!mounted) return;
    setState(() {
      _accessKey = key;
      _pairingCode = code;
    });
  }

  Future<void> _loadLastConnection() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _addressController.text =
          preferences.getString(_lastAddressPreference) ?? '';
      _keyController.text = preferences.getString(_lastCodePreference) ?? '';
    });
  }

  Future<void> _discoverServers() async {
    if (_discovering) return;
    setState(() => _discovering = true);
    try {
      final servers = await discoverYureruServers();
      if (!mounted) return;
      setState(() {
        _discoveredServers = servers;
        _hasDiscovered = true;
        if (_addressController.text.trim().isEmpty && servers.length == 1) {
          _addressController.text = servers.single.address;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ref.tr('connect_copied'))));
  }

  Future<void> _toggleServer() async {
    final server = ref.read(yureruLanServerProvider);
    if (server.isRunning) {
      await server.stop();
      if (mounted) setState(() => _serverRunning = false);
      return;
    }
    final port = int.tryParse(_hostController.text.trim());
    final key = _accessKey;
    final code = _pairingCode;
    if (port == null ||
        port < 1024 ||
        port > 65535 ||
        key == null ||
        code == null) {
      setState(() => _error = ref.tr('connect_invalid_port'));
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await server.start(port: port, accessKey: key, pairingCode: code);
      if (mounted) setState(() => _serverRunning = true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _connect() async {
    final rawAddress = _addressController.text.trim();
    final code = _keyController.text.trim();
    var address = rawAddress;
    if (address.isNotEmpty && !address.contains('://')) {
      address = 'http://$address';
    }
    final base = Uri.tryParse(address);
    if (base == null ||
        !{'http', 'https'}.contains(base.scheme) ||
        base.host.isEmpty ||
        !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = ref.tr('connect_invalid_address'));
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final uri = base.replace(
        path: '/api/v1/library',
        queryParameters: {'code': code},
      );
      final request = await _httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          response.statusCode == HttpStatus.unauthorized
              ? ref.tr('connect_auth_failed')
              : response.statusCode == HttpStatus.tooManyRequests
              ? ref.tr('connect_rate_limited')
              : ref.tr('connect_server_error'),
        );
      }
      final decoded = jsonDecode(await response.transform(utf8.decoder).join());
      if (decoded is! Map || decoded['media'] is! List) {
        throw const FormatException('Invalid Yureru server response.');
      }
      final media = <MediaItem>[];
      for (final entry in decoded['media'] as List) {
        if (entry is! Map) continue;
        final id = entry['id'];
        final streamUrl = entry['streamUrl'];
        if (id is! String || streamUrl is! String) continue;
        media.add(
          MediaItem(
            id: 'remote:${base.host}:$id',
            title: entry['title'] as String? ?? '(unknown)',
            artist: entry['artist'] as String?,
            album: entry['album'] as String?,
            localPath: streamUrl,
            durationMs: (entry['durationMs'] as num?)?.toInt(),
            artworkPath: entry['artworkUrl'] as String?,
            thumbnailPath: entry['thumbnailUrl'] as String?,
            origin: 'temporary',
          ),
        );
      }
      if (media.isEmpty) throw StateError(ref.tr('connect_empty_library'));
      ref.read(libraryProvider.notifier).addTemporaryMedia(media);
      if (mounted) {
        setState(() {
          _remoteMedia = media;
          _addressController.text = base.toString().replaceFirst(
            RegExp(r'/$'),
            '',
          );
          _keyController.text = code;
        });
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          _lastAddressPreference,
          _addressController.text,
        );
        await preferences.setString(_lastCodePreference, code);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _playRemote(MediaItem item) {
    ref
        .read(queueProvider.notifier)
        .start(_remoteMedia.map((media) => media.id).toList(), shuffle: false);
    final index = _remoteMedia.indexWhere((media) => media.id == item.id);
    if (index >= 0) ref.read(queueProvider.notifier).jumpTo(index);
    showPlayerView(ref);
    unawaited(ref.read(playbackControllerProvider).openCurrent());
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(yureruLanServerProvider);
    final addresses = _serverRunning
        ? yureruLanAddresses()
        : Future.value(const <String>[]);
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('yureru_connect'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            ref.tr('connect_host_title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(ref.tr('connect_host_desc')),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _hostController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: ref.tr('connect_port'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _starting || _accessKey == null
                    ? null
                    : _toggleServer,
                icon: Icon(
                  _serverRunning ? Icons.stop_rounded : Icons.dns_rounded,
                ),
                label: Text(
                  _starting
                      ? ref.tr('loading')
                      : _serverRunning
                      ? ref.tr('connect_stop_host')
                      : ref.tr('connect_start_host'),
                ),
              ),
            ],
          ),
          if (_serverRunning) ...[
            const SizedBox(height: 12),
            FutureBuilder<List<String>>(
              future: addresses,
              builder: (context, snapshot) {
                final found = snapshot.data ?? const <String>[];
                return SelectableText(
                  found.isEmpty
                      ? ref.tr('connect_no_address')
                      : found
                            .map((address) => 'http://$address:${server.port}')
                            .join('\n'),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    '${ref.tr('connect_pairing_code')}: ${_pairingCode ?? ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: ref.tr('connect_pairing_code'),
                  onPressed: _pairingCode == null
                      ? null
                      : () => _copyText(_pairingCode!),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            Text(ref.tr('connect_same_network_hint')),
          ],
          const Divider(height: 36),
          Text(
            ref.tr('connect_client_title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(ref.tr('connect_client_desc')),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _discovering ? null : _discoverServers,
              icon: const Icon(Icons.wifi_find_rounded),
              label: Text(
                _discovering
                    ? ref.tr('connect_searching')
                    : ref.tr('connect_find_servers'),
              ),
            ),
          ),
          if (_discoveredServers.isNotEmpty)
            for (final discovered in _discoveredServers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_outlined),
                title: Text(discovered.name),
                subtitle: Text(discovered.address),
                trailing: const Icon(Icons.arrow_forward_rounded),
                onTap: () {
                  _addressController.text = discovered.address;
                  if (RegExp(r'^\d{6}$').hasMatch(_keyController.text.trim())) {
                    _connect();
                  }
                },
              ),
          if (_hasDiscovered && !_discovering && _discoveredServers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ref.tr('connect_no_servers_found'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_discoveredServers.isNotEmpty &&
              !RegExp(r'^\d{6}$').hasMatch(_keyController.text.trim()))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ref.tr('connect_code_needed'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: ref.tr('connect_server_address'),
              hintText: 'http://192.168.1.20:47821',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyController,
            decoration: InputDecoration(
              labelText: ref.tr('connect_pairing_code'),
              hintText: '123456',
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _connecting ? null : _connect,
              icon: const Icon(Icons.link_rounded),
              label: Text(
                _connecting ? ref.tr('loading') : ref.tr('connect_action'),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_remoteMedia.isNotEmpty) ...[
            const Divider(height: 36),
            Text(
              ref.tr('connect_remote_media'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final item in _remoteMedia)
              ListTile(
                leading: ThumbImage(
                  seed: item.title,
                  mediaId: item.id,
                  localPath: item.localPath,
                  size: 52,
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: item.artist == null ? null : Text(item.artist!),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () => _playRemote(item),
              ),
          ],
        ],
      ),
    );
  }
}
