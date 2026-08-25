import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import 'renderer.dart';

/// Renders local/remote/cached HTML (also used by SCORM/H5P entry points)
/// via the official `webview_flutter` package (`flutter.dev`-published) —
/// this is the one capability where a battle-tested official plugin
/// covers Android/iOS/macOS uniformly, so there's no hand-written native
/// webview channel in this engine at all.
class HtmlAttachmentRenderer extends AttachmentRenderer {
  const HtmlAttachmentRenderer();

  @override
  AttachmentType get type => AttachmentType.html;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return _HtmlView(attachment: attachment);
  }
}

class _HtmlView extends StatefulWidget {
  const _HtmlView({required this.attachment});
  final Attachment attachment;

  @override
  State<_HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<_HtmlView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final path = widget.attachment.localPath;
    final url = widget.attachment.remoteUrl;
    if (path != null) {
      _controller.loadFile(path);
    } else if (url != null) {
      _controller.loadRequest(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
