package com.dhc.attachment_engine

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * AttachmentEnginePlugin: registers one Pigeon-generated `HostApi` (or, for
 * the audio/video/download event streams, one hand-written `EventChannel`
 * — see `attachment_engine_platform_interface/pigeons/messages.dart`) plus
 * one platform-view factory, per capability. Replaces the third-party
 * plugins previously used (pdfx, video_player, just_audio, share_plus,
 * open_filex, dio, path_provider) with hand-written native implementations
 * wired through Pigeon codegen for the method-call surface. Webview
 * embedding is handled by the official `webview_flutter` package instead,
 * at the app-facing layer — not through this plugin.
 */
class AttachmentEnginePlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var legacyChannel: MethodChannel
    private lateinit var messenger: BinaryMessenger

    private lateinit var pathsChannel: PathsChannel
    private lateinit var pdfChannel: PdfChannel
    private lateinit var downloadChannel: DownloadChannel
    private lateinit var shareChannel: ShareChannel
    private lateinit var openChannel: OpenChannel
    private lateinit var audioChannel: AudioChannel
    private lateinit var videoChannel: VideoChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        messenger = flutterPluginBinding.binaryMessenger
        val context = flutterPluginBinding.applicationContext

        legacyChannel = MethodChannel(messenger, "attachment_engine")
        legacyChannel.setMethodCallHandler(this)

        pathsChannel = PathsChannel(context).also { it.register(messenger) }
        pdfChannel = PdfChannel().also { it.register(messenger) }
        downloadChannel = DownloadChannel().also { it.register(messenger) }
        shareChannel = ShareChannel(context).also { it.register(messenger) }
        openChannel = OpenChannel(context).also { it.register(messenger) }
        audioChannel = AudioChannel(messenger).also { it.register() }
        videoChannel = VideoChannel(messenger).also { it.register() }

        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            VideoChannel.VIEW_TYPE,
            VideoPlatformViewFactory(videoChannel),
        )
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        legacyChannel.setMethodCallHandler(null)
        pathsChannel.unregister(messenger)
        pdfChannel.unregister(messenger)
        downloadChannel.unregister(messenger)
        shareChannel.unregister(messenger)
        openChannel.unregister(messenger)
        audioChannel.unregister()
        videoChannel.unregister()
    }
}
