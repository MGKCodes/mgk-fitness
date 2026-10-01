import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The run's figures on the lock screen: the app's own channel, since no
    // plugin is involved. See LiveRunChannel.swift.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveRunChannel") {
      LiveRunChannel.register(with: registrar.messenger())
    }
  }
}
