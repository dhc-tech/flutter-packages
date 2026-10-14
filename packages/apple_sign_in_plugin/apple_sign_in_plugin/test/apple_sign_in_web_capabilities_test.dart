// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

@TestOn('browser')
library;

import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capabilities on web advertise Apple JS and wasm only', () async {
    final AppleSignInCapabilities caps = await AppleSignIn.instance.capabilities();
    expect(caps.platformName, 'Web');
    expect(caps.webAppleJs, isTrue);
    expect(caps.wasmWeb, isTrue);
    expect(caps.nativeCredentialState, isFalse);
    expect(caps.revocationEvents, isFalse);
    expect(caps.browserAuthorization, isFalse);
  });

  test('disconnect on web requires a backend adapter', () async {
    final AppleDisconnectResult result = await AppleSignIn.instance.disconnect(userIdentifier: 'u');
    expect(result.status, AppleDisconnectStatus.backendRequired);
  });
}
