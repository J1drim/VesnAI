import 'dart:async';
import 'dart:convert';

import 'package:nsd/nsd.dart' as nsd;

/// A VesnAI server found on the LAN via mDNS.
class DiscoveredServer {
  final String name;
  final Uri baseUrl;
  const DiscoveredServer({required this.name, required this.baseUrl});
}

/// Discovers VesnAI servers advertising `_vesnai._tcp`. Behind an interface so
/// tests use a fake without touching the network.
abstract class ServerDiscovery {
  /// Emits the current list of discovered servers as it changes.
  Stream<List<DiscoveredServer>> watch();
}

class NsdServerDiscovery implements ServerDiscovery {
  static const _serviceType = '_vesnai._tcp';

  @override
  Stream<List<DiscoveredServer>> watch() {
    final controller = StreamController<List<DiscoveredServer>>();
    final found = <String, DiscoveredServer>{};
    nsd.Discovery? discovery;

    Future<void> start() async {
      discovery = await nsd.startDiscovery(_serviceType, ipLookupType: nsd.IpLookupType.v4);
      discovery!.addServiceListener((service, status) {
        final server = _toServer(service);
        if (server == null) return;
        if (status == nsd.ServiceStatus.found) {
          found[server.name] = server;
        } else if (status == nsd.ServiceStatus.lost) {
          found.remove(server.name);
        }
        if (!controller.isClosed) controller.add(found.values.toList());
      });
    }

    controller.onListen = start;
    controller.onCancel = () async {
      final d = discovery;
      if (d != null) await nsd.stopDiscovery(d);
    };
    return controller.stream;
  }

  DiscoveredServer? _toServer(nsd.Service service) {
    final host = service.host;
    final port = service.port;
    if (host == null || port == null) return null;
    final txt = service.txt ?? const {};
    String txtValue(String key, String fallback) {
      final bytes = txt[key];
      return bytes == null ? fallback : utf8.decode(bytes);
    }

    final scheme = txtValue('scheme', 'https');
    final cleanHost = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    return DiscoveredServer(
      name: service.name ?? cleanHost,
      baseUrl: Uri.parse('$scheme://$cleanHost:$port'),
    );
  }
}

/// In-memory discovery for tests/onboarding previews.
class FakeServerDiscovery implements ServerDiscovery {
  final List<DiscoveredServer> servers;
  const FakeServerDiscovery(this.servers);

  @override
  Stream<List<DiscoveredServer>> watch() => Stream.value(servers);
}
