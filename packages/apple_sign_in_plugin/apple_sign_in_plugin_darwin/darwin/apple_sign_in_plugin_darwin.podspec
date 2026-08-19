#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'apple_sign_in_plugin_darwin'
  s.version          = '0.0.1'
  s.summary          = 'iOS and macOS implementation of the apple_sign_in_plugin package.'
  s.description      = <<-DESC
A native Sign in with Apple implementation for iOS and macOS, built directly on Apple's AuthenticationServices framework.
Downloaded by pub (not CocoaPods).
                       DESC
  s.homepage         = 'https://github.com/dhc-tech/flutter-packages'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'DHC Tech' => 'digvijaysinh2204@gmail.com' }
  s.source           = { :http => 'https://github.com/dhc-tech/flutter-packages/tree/main/packages/apple_sign_in_plugin_darwin' }
  s.documentation_url = 'https://pub.dev/packages/apple_sign_in_plugin_darwin'
  s.source_files = 'apple_sign_in_plugin_darwin/Sources/apple_sign_in_plugin_darwin/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.resource_bundles = {'apple_sign_in_plugin_darwin_privacy' => ['apple_sign_in_plugin_darwin/Sources/apple_sign_in_plugin_darwin/Resources/PrivacyInfo.xcprivacy']}
  s.xcconfig = {
    'LIBRARY_SEARCH_PATHS' => '$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME)/ $(SDKROOT)/usr/lib/swift',
    'LD_RUNPATH_SEARCH_PATHS' => '/usr/lib/swift',
  }
  s.swift_version = '5.0'
end
