import Flutter
import XCTest
@testable import rtmp_streaming

final class RunnerTests: XCTestCase {
    @MainActor func testNativeCapabilitiesDoNotAdvertiseUnimplementedFeatures() {
        let plugin = HaishinKitPlugin()
        let done = expectation(description: "capabilities")
        plugin.handle(FlutterMethodCall(methodName: "getCapabilities", arguments: nil)) { value in
            let map = value as! [String: Any]
            XCTAssertEqual(map["backend"] as? String, "HaishinKit/2.2.5 (SPM)")
            let features = map["features"] as! [String: Bool]
            XCTAssertEqual(features["recordingPause"], false)
            XCTAssertEqual(features["whipBearerToken"], false)
            XCTAssertEqual(features["screenCapture"], false)
            done.fulfill()
        }
        waitForExpectations(timeout: 5)
    }

    @MainActor func testMalformedEncoderSettingsFail() {
        let plugin = HaishinKitPlugin()
        let done = expectation(description: "invalid settings")
        plugin.handle(FlutterMethodCall(methodName: "setVideoSettings", arguments: ["width": 721])) { value in
            XCTAssertEqual((value as? FlutterError)?.code, "setVideoSettingsError")
            done.fulfill()
        }
        waitForExpectations(timeout: 5)
    }

    @MainActor func testStopAllWithoutRecordingIsIdempotent() {
        let plugin = HaishinKitPlugin()
        let done = expectation(description: "stop idle session")
        plugin.handle(FlutterMethodCall(methodName: "stopRecordingOrStreaming", arguments: nil)) { value in
            XCTAssertNil(value)
            done.fulfill()
        }
        waitForExpectations(timeout: 5)
    }
}
