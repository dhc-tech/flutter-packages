// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/material.dart';

void main() {
  // Real platform packages (apple_sign_in_plugin_darwin,
  // apple_sign_in_plugin_android, ...) register their own implementation
  // here. This example stands in a fake one so the app runs standalone,
  // without a native platform behind it.
  AppleSignInPlatform.instance = _FakeAppleSignIn();
  runApp(const MyApp());
}

/// A minimal [AppleSignInPlatform] implementation.
///
/// Platform packages extend this class rather than implement it, so that
/// new methods added to [AppleSignInPlatform] don't break existing
/// implementations at compile time.
class _FakeAppleSignIn extends AppleSignInPlatform {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AppleCredential> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) async {
    return AppleCredential(
      userIdentifier: 'fake-user-identifier',
      state: state ?? '',
      authorizedScopes: scopes,
      realUserStatus: AppleRealUserStatus.unsupported,
      identityToken: 'fake-identity-token',
      authorizationCode: 'fake-authorization-code',
    );
  }
}

/// The example app's root widget.
class MyApp extends StatelessWidget {
  /// Creates the example app.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apple Sign In Platform Interface Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
      ),
      home: const SignInPage(),
    );
  }
}

/// Page demonstrating [AppleSignInPlatform.instance] directly, the way a
/// platform package's own tests or example app would.
class SignInPage extends StatefulWidget {
  /// Creates the sign-in page.
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  AppleCredential? _credential;
  bool _isLoading = false;

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final AppleCredential credential = await AppleSignInPlatform.instance
          .signIn(scopes: <AppleAuthorizationScope>{
        AppleAuthorizationScope.email,
        AppleAuthorizationScope.fullName,
      });
      setState(() => _credential = credential);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apple Sign In Platform Interface')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ElevatedButton(
              onPressed: _isLoading ? null : _signIn,
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in with Apple'),
            ),
            if (_credential != null) ...<Widget>[
              const SizedBox(height: 16),
              Text('User identifier: ${_credential!.userIdentifier}'),
            ],
          ],
        ),
      ),
    );
  }
}
