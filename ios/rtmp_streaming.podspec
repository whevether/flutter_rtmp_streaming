#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rtmp_streaming.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rtmp_streaming'
  s.version          = '1.0.7'
  s.summary          = 'A Flutter plugin for Camera and Microphone streaming library via RTMP.'
  s.description      = <<-DESC
A Flutter plugin for Camera and Microphone streaming library via RTMP for HaishinKit.
This plugin provides easy-to-use API for RTMP streaming functionality in Flutter applications.
                       DESC
  s.homepage         = 'https://github.com/whevether/flutter_rtmp_broadcaster'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'keep_wan' => 'whevether@outlook.com' }
  
  s.source           = { :path => '.' }
  s.source_files     = 'rtmp_streaming/Sources/**/*'
  s.dependency 'Flutter'
  s.dependency 'HaishinKit', '2.0.9'
  
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
