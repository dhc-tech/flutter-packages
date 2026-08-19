import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';
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

/// Page demonstrating the Apple Sign-In flow via [AppleSignIn.instance].
///
/// This app does not perform its own token exchange or true revocation —
/// those are backend responsibilities (see the package README's
/// "Do I Need a Backend?" section and `docs/backend/`). It only
/// demonstrates requesting a session from Apple, displaying what was
/// returned, and the local sign-out / disconnect lifecycle.
class SignInPage extends StatefulWidget {
  /// Creates the sign-in page.
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  AppleAuthSession? _session;
  bool _isLoading = false;
  String? _errorText;
  String? _statusText;

  /// Initiates the Apple Sign-In flow and displays the returned
  /// [AppleAuthSession].
  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
      _statusText = null;
    });
    try {
      final AppleAuthSession session = await AppleSignIn.instance.signIn(
        scopes: {
          AppleAuthorizationScope.email,
          AppleAuthorizationScope.fullName,
        },
      );
      setState(() => _session = session);
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

  /// Signs out of the local application session and attempts a full
  /// disconnect (revocation) if a backend adapter is configured.
  Future<void> _disconnect() async {
    final String? userIdentifier = _session?.identity.userIdentifier;
    setState(() => _isLoading = true);
    try {
      final AppleDisconnectResult result =
          await AppleSignIn.instance.disconnect(userIdentifier: userIdentifier);
      setState(() {
        _session = null;
        _statusText = '${result.status.name}: ${result.message ?? ''}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                child: _session != null
                    ? _buildSessionView(_session!)
                    : _buildLoginButton(),
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
        if (_statusText != null) ...[
          const SizedBox(height: 16),
          Text(_statusText!, style: const TextStyle(color: Colors.grey)),
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

  Widget _buildSessionView(AppleAuthSession session) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: Icon(Icons.account_circle, size: 80)),
          const SizedBox(height: 30),
          const Text(
            'Apple Auth Session:',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          _infoRow('User ID', _truncated(session.identity.userIdentifier)),
          _infoRow('Email', session.identity.email ?? 'Not shared this time'),
          _infoRow(
            'Name',
            session.identity.formattedName ?? 'Not shared this time',
          ),
          _infoRow(
            'Authorized scopes',
            session.authorization.scopes.map((s) => s.name).join(', '),
          ),
          _infoRow(
            'Real user status',
            session.authorization.realUserStatus.name,
          ),
          _infoRow(
            'First authorization',
            session.lifecycle.isFirstAuthorization.toString(),
          ),
          const Divider(),
          const Text(
            'Send to your backend:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _secretRow('Identity token', session.authentication.identityToken),
          _secretRow(
            'Authorization code',
            session.authentication.authorizationCode,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out / Disconnect'),
            ),
          ),
        ],
      ),
    );
  }

  String _truncated(String value) =>
      value.length > 12 ? '${value.substring(0, 12)}…' : value;

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
                  ? '${secret.substring(0, secret.length.clamp(0, 12))}…[sent to backend, not shown]'
                  : 'Not available',
              style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
