import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/network_diagnostics.dart';

void main() {
  group('classifyNetType', () {
    test('无网卡视为无网络', () {
      expect(classifyNetType(const []), NetType.none);
    });

    test('wlan 视为 Wi-Fi', () {
      expect(classifyNetType(const ['wlan0', 'lo']), NetType.wifi);
    });

    test('Wi-Fi 命名视为 Wi-Fi', () {
      expect(classifyNetType(const ['wi-fi']), NetType.wifi);
      expect(classifyNetType(const ['WLAN']), NetType.wifi);
    });

    test('rmnet/蜂窝网卡视为移动网络', () {
      expect(classifyNetType(const ['rmnet_data0']), NetType.cellular);
      expect(classifyNetType(const ['ccmni0']), NetType.cellular);
      expect(classifyNetType(const ['pdp_ip0']), NetType.cellular);
    });

    test('有线网卡视为有线网络', () {
      expect(classifyNetType(const ['eth0']), NetType.ethernet);
      expect(classifyNetType(const ['Ethernet']), NetType.ethernet);
    });

    test('VPN 隧道识别', () {
      expect(classifyNetType(const ['tun0']), NetType.vpn);
    });

    test('未知网卡视为其他网络', () {
      expect(classifyNetType(const ['dummy0']), NetType.other);
    });

    test('优先级：wlan 优先于 tun', () {
      expect(
        classifyNetType(const ['tun0', 'wlan0']),
        NetType.wifi,
      );
    });
  });

  group('formatDuration', () {
    test('不足 1 秒用毫秒', () {
      expect(formatDuration(const Duration(milliseconds: 42)), '42 ms');
    });

    test('超过 1 秒保留一位小数', () {
      expect(formatDuration(const Duration(milliseconds: 1500)), '1.5 s');
    });
  });
}
