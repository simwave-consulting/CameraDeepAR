import Flutter
import UIKit
import DeepAR

public class SwiftCameraDeepArPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        //let channel = FlutterMethodChannel(name: "camera_deep_ar", binaryMessenger: registrar.messenger())
        //let instance = SwiftCameraDeepArPlugin()
        //registrar.addMethodCallDelegate(instance, channel: channel)
        let viewFactory = DeepArCameraViewFactory(messenger: registrar.messenger(), registrar: registrar)
        registrar.register(viewFactory, withId: "plugins.flutter.io/deep_ar_camera")
    }
    //public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //  result("iOS " + UIDevice.current.systemVersion)
    //}
}


enum Mode: String, CaseIterable {
    case masks
    case effects
    case filters
}

enum RecordingMode : String, CaseIterable {
    case photo
    case video
    case lowQualityVideo
}

enum Masks: String, CaseIterable {
    case none
    case aviators
    case bigmouth
    case dalmatian
    case bcgSeg
    case look2
    case fatify
    case flowers
    case grumpycat
    case koala
    case lion
    case mudMask
    case obama
    case pug
    case slash
    case sleepingmask
    case smallface
    case teddycigar
    case tripleface
    case twistedFace
}

enum Effects: String, CaseIterable {
    case none
    case fire
    case heart
    case blizzard
    case rain
}

enum Filters: String, CaseIterable {
    case none
    case tv80
    case drawingmanga
    case sepia
    case bleachbypass
    case realvhs
    case filmcolorperfection
}

//Factory view for camera ar
public class DeepArCameraViewFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    let registrar: FlutterPluginRegistrar
    
    init(messenger: FlutterBinaryMessenger, registrar: FlutterPluginRegistrar) {
        self.messenger = messenger
        self.registrar = registrar
    }
    public func create(withFrame frame: CGRect,
                       viewIdentifier viewId: Int64,
                       arguments args: Any?) -> FlutterPlatformView {
        return DeepArCameraView(messenger: messenger, registrar: registrar,
                                frame: frame, viewId: viewId,
                                args: args)
    }
    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}



//The main view for DeepAr Camera
public class DeepArCameraView : NSObject, FlutterPlatformView, DeepARDelegate {
    
    let messenger: FlutterBinaryMessenger
    let frame: CGRect
    let viewId: Int64
    let registrar: FlutterPluginRegistrar
    let channel: FlutterMethodChannel
    var licenceKey: String
    var modeValue: String
    var directionValue: String
    var mode: String
    
    // MARK: - IBOutlets -
    
    @IBOutlet weak var switchCameraButton: UIButton!
    
    @IBOutlet weak var masksButton: UIButton!
    @IBOutlet weak var effectsButton: UIButton!
    @IBOutlet weak var filtersButton: UIButton!
    
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var recordActionButton: UIButton!
    
    @IBOutlet weak var lowQVideoButton: UIButton!
    @IBOutlet weak var videoButton: UIButton!
    @IBOutlet weak var photoButton: UIButton!
    private var arViewContainer: UIView!
    
    private var deepAR: DeepAR!
    private var arView: ARView!
    private var searchingForFace = false
    
    private let numOfChannels: Int = 4
    private let bytesPerChannel: Int = 4;
    private var currentBufferSampleHash : Int = 0;

    
    private var imageFrame: CGRect!
    
    // This class handles camera interaction. Start/stop feed, check permissions etc. You can use it or you
    // can provide your own implementation
    private var cameraController: CameraController!
    
    @objc init(messenger: FlutterBinaryMessenger,  registrar: FlutterPluginRegistrar, frame: CGRect, viewId: Int64, args: Any?){
        self.messenger=messenger
        self.frame=frame
        self.viewId=viewId
        self.registrar=registrar
        deepAR = DeepAR()
        cameraController = CameraController()
        licenceKey=""
        mode=""
        modeValue=""
        directionValue=""
        channel = FlutterMethodChannel(name: "plugins.flutter.io/deep_ar_camera/\(viewId)", binaryMessenger: messenger)
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(orientationDidChange), name:  Notification.Name("UIDeviceOrientationDidChangeNotification"), object: nil)
        
        currentMode = .masks
        if let dict = args as? [String: Any] {
            let licence: String = (dict["iosLicenceKey"] as? String ?? "")
            let recordingMode: Int = (dict["recordingMode"] as? Int ?? 0)
            let direction: Int = (dict["direction"] as? Int ?? 0)
            let cameraMode: Int = (dict["cameraMode"] as? Int ?? 0)
            let mode: String = (dict["mode"] as? String ?? "")
            
            print(direction)
            self.licenceKey = licence
            self.currentMode = Mode.allCases[cameraMode];
            self.currentRecordingMode = RecordingMode.allCases[recordingMode]
            self.cameraController.position = direction == 0 ? .back : .front
            self.mode = mode;
            //currentRecordingMode = .photo
        }
        
        channel.setMethodCallHandler { [self] call, result in
            if call.method == "isCameraReady" {
                var dict: [String: Bool] = [String:Bool]()
                dict["isReady"] = true
                self.channel.invokeMethod("onCameraReady", arguments: dict)
                result("iOS is ready")
            }
            else if call.method == "setCameraMode" {
                if let dict = call.arguments as? [String: Any] {
                    if let cameraMode = (dict["cameraMode"] as? Int) {
                        //let index = Int(direction) ?? 0
                        self.currentMode = cameraMode == 0 ? .masks : cameraMode == 1 ? .effects  : .filters
                    }
                }
                result("Camera  Changed")
            }
            else if call.method == "switchCameraDirection" {
                if let dict = call.arguments as? [String: Any] {
                    if let direction = (dict["direction"] as? Int) {
                        //let index = Int(direction) ?? 0
                        self.cameraController.position = direction == 0 ? .back : .front
                    }
                }
                result("Camera  Changed")
            }
            else if call.method == "changeMask" {
                if let dict = call.arguments as? [String: Any] {
                    if let mask = (dict["mask"] as? Int) {
                        //let index = Int(mask) ?? 0
                        self.currentMode = .masks
                        self.switchMode(self.maskPaths[mask])
                    }
                }
                result("Mask  Changed")
            } else if call.method == "changeEffect" {
                if let dict = call.arguments as? [String: Any] {
                    if let effect = (dict["effect"] as? Int) {
                        //let index = Int(effect) ?? 0
                        self.currentMode = .effects
                        self.switchMode(self.effectPaths[effect])
                    }
                }
                result("Effects  Changed")
            } else if call.method == "changeFilter" {
                if let dict = call.arguments as? [String: Any] {
                    if let filter = (dict["filter"] as? Int) {
                        //let index = Int(filter) ?? 0
                        self.currentMode = .filters
                        self.switchMode(self.filterPaths[filter])
                    }
                }
                result("Filter  Changed")
            } else if call.method == "startVideoRecording" {
                let width: Int32 = Int32(self.deepAR.renderingResolution.width)
                let height: Int32 =  Int32(self.deepAR.renderingResolution.height)
                self.deepAR.startVideoRecording(withOutputWidth: width, outputHeight: height)
                self.isRecordingInProcess = true
                result("You Tapped on startVideoRecording")
            } else if call.method == "stopVideoRecording" {
                self.deepAR.finishVideoRecording()
                self.isRecordingInProcess = false
                result("You Tapped on stopVideoRecording")
            } else if call.method == "snapPhoto" {
                //self.deepAR.takeScreenshot()
                self.snapPhoto();
                result("You Tapped on SnapPhoto")
            } else if call.method == "dispose" {
                dispose();
                result("View was disposed!")
            } else if call.method == "switchEffect" {
                if let dict = call.arguments as? [String: Any] {
                    if let mode = (dict["mode"] as? String) {
                        if let path = (dict["path"] as? String){
                            let key = self.registrar.lookupKey(forAsset: path);
                            let pathSwift = Bundle.main.path(forResource: key, ofType: nil)
                            self.deepAR.switchEffect(withSlot: mode, path: pathSwift)
                        }
                    }
                }
                NSLog("Custom Effect Changed")
                result("Custom Effect Changed")
            } else if call.method == "changeParameterFloat" {
                if let dict = call.arguments as? [String: Any] {
                    if let changeParameter = (dict["changeParameter"] as? String) {
                        if let component = (dict["component"] as? String){
                            if let parameter = (dict["parameter"] as? String){
                                if let floatValue = (dict["floatValue"] as? Double){
                                    let f = Float(floatValue);
                                    self.deepAR.changeParameter(changeParameter,component:component,parameter:parameter,floatValue: f);
                                }
                            }
                        }
                    }
                }
                result("Param Changed")
            }
            else if call.method == "changeParameterVec4" {
                if let dict = call.arguments as? [String: Any] {
                    if let changeParameter = (dict["changeParameter"] as? String) {
                        if let component = (dict["component"] as? String){
                            if let parameter = (dict["parameter"] as? String){
                                if let valX = (dict["valX"] as? Double){
                                    if let valY = (dict["valY"] as? Double){
                                        if let valZ = (dict["valZ"] as? Double){
                                            if let valW = (dict["valW"] as? Double){
                                                let x = Float(valX);
                                                let y = Float(valY);
                                                let z = Float(valZ);
                                                let w = Float(valW);
                                                let vec4 = Vector4(x: x, y: y, z: z, w: w);
                                                self.deepAR.changeParameter(changeParameter,component:component,parameter:parameter, vectorValue: vec4);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                result("Param Changed")
            }
            else if call.method == "changeParameterTexture" {
                if let dict = call.arguments as? [String: Any] {
                    if let changeParameter = (dict["changeParameter"] as? String) {
                        if let component = (dict["component"] as? String){
                            if let parameter = (dict["parameter"] as? String){
                                if let texturePath = (dict["texturePath"] as? String){
                                    //let f = Float(floatValue);
                                    let key = self.registrar.lookupKey(forAsset: texturePath);
                                    //NSLog(key);
                                    let pathSwift = Bundle.main.path(forResource: key, ofType: nil);
                                    //NSLog(pathSwift!);
                                    let image = UIImage(named: pathSwift!);
                                    self.deepAR.changeParameter(changeParameter,component:component,parameter:parameter,image: image);
                                }
                            }
                        }
                    }
                }
                result("Param Changed")
            } else if call.method == "changeImagePath" {
                if let dict = call.arguments as? [String: Any] {
                    if let filePath = (dict["filePath"] as? String) {
                        changeImagePath(to: filePath)
                    }
                }
                result("Param Changed")
            } else if call.method == "changeImage" {
                if let dict = call.arguments as? [String: Any] {
                    let imageBytes = dict["imageBytes"] as! FlutterStandardTypedData;
                    let width = dict["width"] as! Int;
                    let height = dict["height"] as! Int;

                    var mutableData = imageBytes.data;
                    mutableData.withUnsafeMutableBytes { (bytesRawPointer : UnsafeMutableRawBufferPointer) in
                        let bytes = bytesRawPointer.baseAddress!.assumingMemoryBound(to: UInt8.self);
                        let image: UIImage? = ImageHelper.convertBitmapRGBA8(toUIImage: bytes, withWidth: Int32(width), withHeight: Int32(height));
                        changeImage(to: image!);
                    }
                }
                result("Param Changed")
            }
            
        }
        if #available(iOS 9.0, *) {
            self.initCameraDeepAR()
            
        } else {
            // Fallback on earlier versions
        }
    }
    
    func changeImagePath(to filePath: String) {
        guard let image = UIImage(contentsOfFile: filePath) else {
            return
        }
        
        changeImage(to: image);
    }
    
    func changeImage(to image: UIImage) -> Void {
        let byteWidth = CGFloat(numOfChannels * bytesPerChannel);
        let scaledWidth = image.size.width * UIScreen.main.scale;
        let scaledHeight = image.size.height * UIScreen.main.scale;
        
        let adjustedWidth = round(scaledWidth / byteWidth) * byteWidth;
        let ratio = adjustedWidth / scaledWidth;
        let adjustedHeight = round(ratio * scaledHeight);
        
        let size = CGSize(width: adjustedWidth, height: adjustedHeight);
        let resized = resizedImage(with: image, for: size)!;
        
        searchingForFace = true;
        enqueueFrame(buffer(from: resized));
    }
    
    // Technique #1 - https://nshipster.com/image-resizing/
    func resizedImage(at path: String, for size: CGSize) -> UIImage? {
        guard let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        
        return resizedImage(with: image, for: size);
    }
    
    func resizedImage(with image: UIImage, for size: CGSize) -> UIImage? {
        let relativeRatio = CGSize(width: size.width / image.size.width, height: size.height / image.size.height)
        let scalerRatio = max(relativeRatio.width, relativeRatio.height);
        
 
        //let scaler = max(relativeRatio.width, relativeRatio.height);
        var newSize = CGSize(width: image.size.width * scalerRatio, height: image.size.height * scalerRatio);
        if (!Int(newSize.width).isMultiple(of: 2)) {
            newSize.width = CGFloat(Int(newSize.width) + 1);
        }
        if (!Int(newSize.height).isMultiple(of: 2)) {
            newSize.height = CGFloat(Int(newSize.height) + 1);
        }
        
        //let newSize = CGSize(width: size.height * scaleX_Y, height: size.height);
        let newOrigin = CGPoint(x: (size.width - newSize.width) / 2, y: (size.height - newSize.height) / 2);
        
        //NSLog("Original size: (w: \(image.size.width), h: \(image.size.height)) -> To size: (w: \(size.width), h: \(size.height))");

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { (context) in
            image.draw(in: CGRect(origin: newOrigin, size: newSize))
        }
    }
    
    func enqueueFrame(_ sampleBuffer: CVPixelBuffer?) {
        currentBufferSampleHash = sampleBuffer.hashValue;
        enqueueFrame(sampleBuffer, sensitivity: 1);
    }
    
    func enqueueFrame(_ sampleBuffer: CVPixelBuffer?, sensitivity: Int) {
        if !searchingForFace || currentBufferSampleHash != sampleBuffer.hashValue {
            return
        }
        
        let newSensitivity = min(max(sensitivity, 1), 3);
        
        self.deepAR.setFaceDetectionSensitivity(newSensitivity);
        self.deepAR.processFrame(sampleBuffer, mirror: false);
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(0.5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: { [self] in
            enqueueFrame(sampleBuffer, sensitivity: newSensitivity + 1)
        })
    }
    
    func buffer(from image: UIImage) -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        //kCVPixelFormatType_32RGBA
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: 4 * Int(image.size.width), space: rgbColorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        // CVPixelBufferGetBytesPerRow(pixelBuffer!)
        context?.translateBy(x: 0, y: image.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context!)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    
    //    @objc
    //    private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
    //        guard sessionSetupSucceeds,  let device = activeCamera else { return }
    //
    //        switch pinch.state {
    //        case .began:
    //            initialScale = device.videoZoomFactor
    //        case .changed:
    //            let minAvailableZoomScale = device.minAvailableVideoZoomFactor
    //            let maxAvailableZoomScale = device.maxAvailableVideoZoomFactor
    //            let availableZoomScaleRange = minAvailableZoomScale...maxAvailableZoomScale
    //            let resolvedZoomScaleRange = zoomScaleRange.clamped(to: availableZoomScaleRange)
    //
    //            let resolvedScale = max(resolvedZoomScaleRange.lowerBound, min(pinch.scale * initialScale, resolvedZoomScaleRange.upperBound))
    //
    //            configCamera(device) { device in
    //                device.videoZoomFactor = resolvedScale
    //            }
    //        default:
    //            return
    //        }
    //    }
    
    @objc func orientationDidChange() {
        //        @available(iOS 13.0, *)
        if #available(iOS 13.0, *) {
            guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else { return }
            switch orientation {
            case .landscapeLeft:
                cameraController.videoOrientation = .landscapeLeft
                break
            case .landscapeRight:
                cameraController.videoOrientation = .landscapeRight
                break
            case .portrait:
                cameraController.videoOrientation = .portrait
                break
            case .portraitUpsideDown:
                cameraController.videoOrientation = .portraitUpsideDown
            default:
                break
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    @objc public func frameAvailable(_ sampleBuffer: CMSampleBuffer!){
        
    }
    
    public func view() -> UIView {
        return arView;
    }
    
    // MARK: - Private properties -
    
    private var maskIndex: Int = 0
    private var maskPaths: [String?] {
        return Masks.allCases.map { $0.rawValue.path }
    }
    //
    private var effectIndex: Int = 0
    private var effectPaths: [String?] {
        return Effects.allCases.map { $0.rawValue.path }
    }
    //
    private var filterIndex: Int = 0
    private var filterPaths: [String?] {
        print("Filter val "+String(describing: Filters.self))
        return Filters.allCases.map { $0.rawValue.path }
    }
    //
    private var buttonModePairs: [(UIButton, Mode)] = []
    private var currentMode: Mode! {
        didSet {
            updateModeAppearance()
        }
    }
    //
    private var buttonRecordingModePairs: [(UIButton, RecordingMode)] = []
    private var currentRecordingMode: RecordingMode! {
        didSet {
            updateRecordingModeAppearance()
        }
    }
    
    private func updateModeAppearance() {
        buttonModePairs.forEach { (button, mode) in
            button.isSelected = mode == currentMode
        }
    }
    
    private func updateRecordingModeAppearance() {
        buttonRecordingModePairs.forEach { (button, recordingMode) in
            button.isSelected = recordingMode == currentRecordingMode
        }
    }
    
    private func switchMode(_ path: String?) {
        self.modeValue="\(currentMode.rawValue) -- \(path ?? "nothing")"
        print(self.modeValue)
        deepAR.switchEffect(withSlot: currentMode.rawValue, path: path)
    }
    
    private var isRecordingInProcess: Bool = false
    
    func statusBarHeight() -> CGFloat {
        let statusBarSize = UIApplication.shared.statusBarFrame.size
        return min(statusBarSize.width, statusBarSize.height)
    }
    
    @available(iOS 9.0, *)
    @objc func  initCameraDeepAR(){
        self.deepAR.delegate = self
        self.deepAR.setLicenseKey(self.licenceKey)
        cameraController.deepAR = self.deepAR
        if (self.arView != nil) {
            self.arView.removeFromSuperview();
        }
        
        self.arView = self.deepAR.createARView(withFrame: self.frame) as? ARView
        self.arView.translatesAutoresizingMaskIntoConstraints = false
        
        if (mode.elementsEqual("camera")) {
            cameraController.startCamera()
        }
    }
    
    @objc
    private func didTapRecordActionButton() {
        //
        
        if (currentRecordingMode == RecordingMode.photo) {
            deepAR.takeScreenshot()
            return
        }
        
        if (isRecordingInProcess) {
            deepAR.finishVideoRecording()
            isRecordingInProcess = false
            return
        }
        
        let width: Int32 = Int32(deepAR.renderingResolution.width)
        let height: Int32 =  Int32(deepAR.renderingResolution.height)
        
        if (currentRecordingMode == RecordingMode.video) {
            deepAR.startVideoRecording(withOutputWidth: width, outputHeight: height)
            isRecordingInProcess = true
            return
        }
        
        if (currentRecordingMode == RecordingMode.lowQualityVideo) {
            let videoQuality = 0.1
            let bitrate =  1250000
            let videoSettings:[AnyHashable : AnyObject] = [
                AVVideoQualityKey : (videoQuality as AnyObject),
                AVVideoAverageBitRateKey : (bitrate as AnyObject)
            ]
            
            let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            
            deepAR.startVideoRecording(withOutputWidth: width, outputHeight: height, subframe: frame, videoCompressionProperties: videoSettings, recordAudio: true)
            isRecordingInProcess = true
        }
    }
    
    @objc
    private func didTapPreviousButton() {
        var path: String?
        
        switch currentMode! {
        case .effects:
            effectIndex = (effectIndex - 1 < 0) ? (effectPaths.count - 1) : (effectIndex - 1)
            path = effectPaths[effectIndex]
        case .masks:
            maskIndex = (maskIndex - 1 < 0) ? (maskPaths.count - 1) : (maskIndex - 1)
            path = maskPaths[maskIndex]
        case .filters:
            filterIndex = (filterIndex - 1 < 0) ? (filterPaths.count - 1) : (filterIndex - 1)
            path = filterPaths[filterIndex]
        }
        
        switchMode(path)
    }
    
    @objc
    private func didTapNextButton() {
        var path: String?
        
        switch currentMode! {
        case .effects:
            effectIndex = (effectIndex + 1 > effectPaths.count - 1) ? 0 : (effectIndex + 1)
            path = effectPaths[effectIndex]
        case .masks:
            maskIndex = (maskIndex + 1 > maskPaths.count - 1) ? 0 : (maskIndex + 1)
            path = maskPaths[maskIndex]
        case .filters:
            filterIndex = (filterIndex + 1 > filterPaths.count - 1) ? 0 : (filterIndex + 1)
            path = filterPaths[filterIndex]
        }
        
        switchMode(path)
    }
    
    @objc
    private func didTapMasksButton() {
        currentMode = .masks
    }
    
    @objc
    private func didTapEffectsButton() {
        currentMode = .effects
    }
    
    @objc
    private func didTapFiltersButton() {
        currentMode = .filters
    }
    
    @objc
    private func didTapPhotoButton() {
        currentRecordingMode = .photo
    }
    
    @objc
    private func didTapVideoButton() {
        currentRecordingMode = .video
    }
    
    @objc
    private func didTapLowQVideoButton() {
        currentRecordingMode = .lowQualityVideo
    }
    
    public func didFinishPreparingForVideoRecording() { }
    
    public func didStartVideoRecording() { }
    
    public func didFinishVideoRecording(_ videoFilePath: String!) {
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let components = videoFilePath.components(separatedBy: "/")
        guard let last = components.last else { return }
        let destination = URL(fileURLWithPath: String(format: "%@/%@", documentsDirectory, last))
        var dict: [String: String] = [String:String]()
        dict["path"] = destination.absoluteString
        channel.invokeMethod("onVideoRecordingComplete", arguments: dict)
    }
    
    public func recordingFailedWithError(_ error: Error!) {}
    
    public func didTakeScreenshot(_ screenshot: UIImage!) {
        if let data = screenshot.pngData() {
            let flutterData: FlutterStandardTypedData = FlutterStandardTypedData.init(bytes: data);
            
            var dict: [String: Any] = [String:Any]()
            dict["imageBytes"] = flutterData;
            dict["width"] = Int(screenshot.size.width);
            dict["height"] = Int(screenshot.size.height);
            channel.invokeMethod("onSnapPhotoCompleted", arguments: dict)
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    public func didInitialize() {
    }
    
    public func dispose() {
        searchingForFace = false;
        NotificationCenter.default.removeObserver(self);
        channel.setMethodCallHandler(nil);
        
        if (self.arView != nil)
        {
            self.arView.shutdown();
        }
    }
    
    public func faceVisiblityDidChange(_ faceVisible: Bool) {
        searchingForFace = false;
        NSLog("Found Face!")
    }
    
    public func snapPhoto() {
        self.deepAR.takeScreenshot();
    }
    
}
    
extension String {
    var path: String? {
        let filePath = Bundle.main.resourcePath!+"/Frameworks/camera_deep_ar.framework/\(self)"
        
        print("Path-find \(self) >>>> \(String(describing: filePath)) >>> ")
        return filePath
        //return Bundle.main.path(forResource: self, ofType: nil)
    }
}
