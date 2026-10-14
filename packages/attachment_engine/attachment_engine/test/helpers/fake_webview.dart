// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Recording [WebViewPlatform] fake: no real WebView is ever created. Every
/// controller/delegate the code under test builds is kept in [controllers] /
/// [delegates] so a test can drive page-finished / error callbacks and
/// inspect what was loaded or evaluated.
class FakeWebViewPlatform extends WebViewPlatform {
  final List<FakeWebViewController> controllers = [];
  final List<FakeNavigationDelegate> delegates = [];

  /// When set, every `runJavaScript` call throws this.
  Object? scriptError;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params, this);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWebViewWidget(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    final delegate = FakeNavigationDelegate(params);
    delegates.add(delegate);
    return delegate;
  }
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params, this._platform) : super.implementation();

  final FakeWebViewPlatform _platform;

  final List<String> loadedAssets = [];
  final List<String> loadedFiles = [];
  final List<Uri> loadedRequests = [];
  final List<String> scripts = [];
  final Map<String, void Function(JavaScriptMessage)> channels = {};
  JavaScriptMode? javaScriptMode;
  FakeNavigationDelegate? navigationDelegate;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    this.javaScriptMode = javaScriptMode;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigationDelegate = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    channels[javaScriptChannelParams.name] =
        javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> loadFlutterAsset(String key) async => loadedAssets.add(key);

  @override
  Future<void> loadFile(String absoluteFilePath) async =>
      loadedFiles.add(absoluteFilePath);

  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      loadedRequests.add(params.uri);

  @override
  Future<void> runJavaScript(String javaScript) async {
    final error = _platform.scriptError;
    if (error != null) throw error;
    scripts.add(javaScript);
  }
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A minimal [WebResourceError] for driving `onWebResourceError`.
WebResourceError fakeWebResourceError() => WebResourceError(
  errorCode: -1,
  description: 'simulated',
  errorType: WebResourceErrorType.unknown,
);
