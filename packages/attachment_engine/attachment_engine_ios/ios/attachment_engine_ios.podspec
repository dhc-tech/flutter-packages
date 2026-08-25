#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint attachment_engine_ios.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'attachment_engine_ios'
  s.version          = '0.0.1-dev.0'
  s.summary          = 'iOS implementation of the attachment_engine plugin.'
  s.description      = <<-DESC
Native Swift implementation (PDF, video, audio, webview, share, open,
download, paths) backing the attachment_engine Flutter plugin on iOS.
                       DESC
  s.homepage         = 'https://github.com/dhc-tech/flutter-packages/tree/main/packages/attachment_engine/attachment_engine_ios'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'DHC' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'attachment_engine_ios/Sources/attachment_engine_ios/**/*.swift'
  s.resource_bundles = {'attachment_engine_ios_privacy' => ['attachment_engine_ios/Sources/attachment_engine_ios/PrivacyInfo.xcprivacy']}
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
