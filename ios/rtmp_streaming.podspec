# HaishinKit >= 2.1 moved to Swift Package Manager. The split RTMP/RTC
# modules used by this plugin do not exist in the final CocoaPods releases.
raise 'rtmp_streaming requires Swift Package Manager. Run flutter config --enable-swift-package-manager, then flutter clean and flutter pub get. Remove this plugin from legacy Podfile overrides.'
