#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint attachment_engine_macos.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'attachment_engine_macos'
  s.version          = '0.0.1-dev.1'
  s.summary          = 'macOS implementation of the attachment_engine plugin.'
  s.description      = <<-DESC
Native Swift implementation (paths, share, open-externally, download)
backing the attachment_engine Flutter plugin on macOS. PDF rendering,
video/audio playback, and webview are not yet implemented — see README.
                       DESC
  s.homepage         = 'https://github.com/dhc-tech/flutter-packages/tree/main/packages/attachment_engine/attachment_engine_macos'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'DHC' => 'noreply@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'attachment_engine_macos/Sources/attachment_engine_macos/**/*.swift'
  s.resource_bundles = {'attachment_engine_macos_privacy' => ['attachment_engine_macos/Sources/attachment_engine_macos/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
