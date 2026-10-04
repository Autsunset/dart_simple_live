import Flutter
import UIKit

public class AutoOrientationPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "auto_orientation", binaryMessenger: registrar.messenger())
        let instance = AutoOrientationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if #available(iOS 16.0, *) {
            setOrientation(call)
        } else {
            setLegacyOrientation(call)
        }

        UIViewController.attemptRotationToDeviceOrientation()

        // Fix: Always return success unless it's genuinely not implemented
        if (call.method == "setLandscapeRight" || 
            call.method == "setLandscapeLeft" || 
            call.method == "setPortraitUp" || 
            call.method == "setPortraitDown" || 
            call.method == "setPortraitAuto" || 
            call.method == "setLandscapeAuto" || 
            call.method == "setAuto" || 
            call.method == "setScreenOrientationUser") {
            result(nil)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    @available(iOS 16.0, *)
    func setOrientation(_ call: FlutterMethodCall) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            else { return }
        
        let resolvedMask: UIInterfaceOrientationMask
        switch call.method {
        case "setLandscapeRight", "setLandscapeAuto":
            resolvedMask = .landscapeRight
        case "setLandscapeLeft":
            resolvedMask = .landscapeLeft
        case "setPortraitUp", "setPortraitAuto":
            resolvedMask = .portrait
        case "setPortraitDown":
            resolvedMask = .portraitUpsideDown
        case "setAuto", "setScreenOrientationUser":
            resolvedMask = .all
        default:
            resolvedMask = .all
        }
        
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: resolvedMask)) { error in
            // Optional: Log error if needed
        }
    }
    
    func setLegacyOrientation(_ call: FlutterMethodCall) {
        let resolvedOrientation: UIInterfaceOrientation
        switch call.method {
        case "setLandscapeRight", "setLandscapeAuto":
            resolvedOrientation = .landscapeRight
        case "setLandscapeLeft":
            resolvedOrientation = .landscapeLeft
        case "setPortraitUp", "setPortraitAuto":
            resolvedOrientation = .portrait
        case "setPortraitDown":
            resolvedOrientation = .portraitUpsideDown
        case "setAuto", "setScreenOrientationUser":
            resolvedOrientation = .unknown
        default:
            resolvedOrientation = .unknown
        }
        
        if resolvedOrientation != .unknown {
            UIDevice.current.setValue(resolvedOrientation.rawValue, forKey: "orientation")
        } else {
            // For 'auto' or 'user' on legacy, we might just trigger a rotation attempt
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
