import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_auth/one_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecurityService Real-time Threat Stream Verification', () {
    test('SecurityService is a singleton across multiple accesses', () {
      final s1 = SecurityService();
      final s2 = SecurityService();
      expect(identical(s1, s2), isTrue);
    });

    test('threatStream emits threat events in real-time to broadcast listeners', () async {
      final service = SecurityService();
      final eventsReceivedListener1 = <SecurityThreatEvent>[];
      final eventsReceivedListener2 = <SecurityThreatEvent>[];

      // Multiple simultaneous subscribers anywhere in the app
      final sub1 = service.threatStream.listen((event) {
        eventsReceivedListener1.add(event);
      });

      final sub2 = service.threatStream.listen((event) {
        eventsReceivedListener2.add(event);
      });

      // Simulate VPN Active threat
      service.emitThreatForTesting('VPN Active', 'Active VPN connection detected.');
      await Future.delayed(Duration.zero);

      // Verify both listeners received the exact threat in real-time
      expect(eventsReceivedListener1.length, equals(1));
      expect(eventsReceivedListener1.first.threatType, equals('VPN Active'));
      expect(eventsReceivedListener1.first.message, equals('Active VPN connection detected.'));

      expect(eventsReceivedListener2.length, equals(1));
      expect(eventsReceivedListener2.first.threatType, equals('VPN Active'));

      // Verify snapshot state updated
      expect(service.state.isVpnActive, isTrue);
      expect(service.latestThreat?.threatType, equals('VPN Active'));

      // Simulate Root threat
      service.emitThreatForTesting('Root/Jailbreak', 'Privileged access detected on device.');
      await Future.delayed(Duration.zero);

      expect(eventsReceivedListener1.length, equals(2));
      expect(eventsReceivedListener1.last.threatType, equals('Root/Jailbreak'));
      expect(service.state.isRooted, isTrue);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('ChangeNotifier notifies UI listeners when a threat occurs', () async {
      final service = SecurityService();
      bool wasNotified = false;

      void listener() {
        wasNotified = true;
      }

      service.addListener(listener);
      service.emitThreatForTesting('Hooking Framework', 'Frida detected.');
      await Future.delayed(Duration.zero);

      expect(wasNotified, isTrue);
      expect(service.state.isHooked, isTrue);

      service.removeListener(listener);
    });
  });
}
