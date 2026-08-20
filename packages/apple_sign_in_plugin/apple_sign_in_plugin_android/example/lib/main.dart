// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

/// The example app's root widget.
class MyApp extends StatelessWidget {
  /// Creates the example app.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apple Sign In Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
      ),
      home: const SignInPage(),
    );
  }
}

/// Page demonstrating the Apple Sign-In flow.
///
/// This app does not perform its own token exchange or storage — those are
/// backend responsibilities (see the package README's "Backend Boundary"
/// section). It only demonstrates requesting a credential from Apple and
/// displaying what was returned.
class SignInPage extends StatefulWidget {
  /// Creates the sign-in page.
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  AppleCredential? _credential;
  bool _isLoading = false;
  String? _errorText;

  /// Initiates the Apple Sign-In flow and displays the returned
  /// [AppleCredential].
  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final AppleCredential credential = await AppleSignInPlatform.instance.signIn(
        scopes: {
          AppleAuthorizationScope.email,
          AppleAuthorizationScope.fullName,
        },
      );
      setState(() => _credential = credential);
    } on AppleSignInException catch (e) {
      if (e.code == AppleSignInErrorCode.canceled) {
        // The user dismissed the sheet; nothing to report.
        return;
      }
      if (kDebugMode) {
        debugPrint('Sign in failed: $e');
      }
      setState(() => _errorText = e.message);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Clears the locally displayed credential.
  ///
  /// This only resets this screen's UI state — it does not sign the user
  /// out of their Apple ID, and it does not revoke anything with Apple.
  /// A real app's backend owns its own session/sign-out.
  void _clear() {
    setState(() => _credential = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apple Sign In Plugin'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child:
                    _credential != null ? _buildCredentialView(_credential!) : _buildLoginButton(),
              ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.apple, size: 80),
        const SizedBox(height: 20),
        const Text(
          'Sign in to access your account',
          style: TextStyle(fontSize: 18),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 16),
          Text(_errorText!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.apple),
            label: const Text('Sign in with Apple'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialView(AppleCredential credential) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: Icon(Icons.account_circle, size: 80)),
          const SizedBox(height: 30),
          const Text(
            'Apple Credential:',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          _infoRow('User ID', _truncated(credential.userIdentifier)),
          _infoRow('Email', credential.email ?? 'Not shared this time'),
          _infoRow(
            'Name',
            credential.name == null
                ? 'Not shared this time'
                : '${credential.name!.givenName ?? ''} '
                        '${credential.name!.familyName ?? ''}'
                    .trim(),
          ),
          _infoRow(
            'Authorized scopes',
            credential.authorizedScopes.map((s) => s.name).join(', '),
          ),
          _infoRow('Real user status', credential.realUserStatus.name),
          const Divider(),
          const Text(
            'Send to your backend:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _secretRow('Identity token', credential.identityToken),
          _secretRow('Authorization code', credential.authorizationCode),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.clear),
              label: const Text('Clear (local UI only)'),
            ),
          ),
        ],
      ),
    );
  }

  String _truncated(String value) => value.length > 12 ? '${value.substring(0, 12)}…' : value;

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _secretRow(String label, String? secret) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              // Never display the full secret — this app is not the
              // consumer of these values, the backend is.
              secret != null
                  ? '${_maskedPreview(secret)} [sent to backend, not shown]'
                  : 'Not available',
              style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns a short, fixed-length preview of [secret] that never reveals the
/// full value, regardless of how short it is.
String _maskedPreview(String secret) {
  if (secret.isEmpty) {
    return '';
  }
  if (secret.length <= 4) {
    return '${secret[0]}…';
  }
  final String start = secret.substring(0, 4);
  return secret.length > 8 ? '$start…${secret.substring(secret.length - 4)}' : '$start…';
}
