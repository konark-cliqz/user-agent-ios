/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import GCDWebServer
import Shared
import Storage

private let MozDomain = "mozilla"
private let MozErrorDownloadsNotEnabled = 100
private let MessageOpenInSafari = "openInSafari"
private let MessageCertVisitOnce = "certVisitOnce"

// Regardless of cause, NSURLErrorServerCertificateUntrusted is currently returned in all cases.
// Check the other cases in case this gets fixed in the future.
private let CertErrors = [
    NSURLErrorServerCertificateUntrusted,
    NSURLErrorServerCertificateHasBadDate,
    NSURLErrorServerCertificateHasUnknownRoot,
    NSURLErrorServerCertificateNotYetValid,
]

// Error codes copied from Gecko. The ints corresponding to these codes were determined
// by inspecting the NSError in each of these cases.
private let CertErrorCodes = [
    -9813: "SEC_ERROR_UNKNOWN_ISSUER",
    -9814: "SEC_ERROR_EXPIRED_CERTIFICATE",
    -9843: "SSL_ERROR_BAD_CERT_DOMAIN",
]

private func certFromErrorURL(_ url: URL) -> SecCertificate? {
    func getCert(_ url: URL) -> SecCertificate? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let encodedCert = components?.queryItems?.filter({ $0.name == "badcert" }).first?.value,
            let certData = Data(base64Encoded: encodedCert, options: []) {
            return SecCertificateCreateWithData(nil, certData as CFData)
        }

        return nil
    }

    let result = getCert(url)
    if result != nil {
        return result
    }

    // Fallback case when the error url is nested, this happens when restoring an error url, it will be inside a 'sessionrestore' url.
    // TO DO : Investigate if we can restore directly as an error url and avoid the 'sessionrestore?url=' wrapping.
    if let internalUrl = InternalURL(url), let url = internalUrl.extractedUrlParam {
        return getCert(url)
    }
    return nil
}

private func cfErrorToName(_ err: CFNetworkErrors) -> String {
    switch err {
    case .cfHostErrorHostNotFound: return "CFHostErrorHostNotFound"
    case .cfHostErrorUnknown: return "CFHostErrorUnknown"
    case .cfsocksErrorUnknownClientVersion: return "CFSOCKSErrorUnknownClientVersion"
    case .cfsocksErrorUnsupportedServerVersion: return "CFSOCKSErrorUnsupportedServerVersion"
    case .cfsocks4ErrorRequestFailed: return "CFSOCKS4ErrorRequestFailed"
    case .cfsocks4ErrorIdentdFailed: return "CFSOCKS4ErrorIdentdFailed"
    case .cfsocks4ErrorIdConflict: return "CFSOCKS4ErrorIdConflict"
    case .cfsocks4ErrorUnknownStatusCode: return "CFSOCKS4ErrorUnknownStatusCode"
    case .cfsocks5ErrorBadState: return "CFSOCKS5ErrorBadState"
    case .cfsocks5ErrorBadResponseAddr: return "CFSOCKS5ErrorBadResponseAddr"
    case .cfsocks5ErrorBadCredentials: return "CFSOCKS5ErrorBadCredentials"
    case .cfsocks5ErrorUnsupportedNegotiationMethod: return "CFSOCKS5ErrorUnsupportedNegotiationMethod"
    case .cfsocks5ErrorNoAcceptableMethod: return "CFSOCKS5ErrorNoAcceptableMethod"
    case .cfftpErrorUnexpectedStatusCode: return "CFFTPErrorUnexpectedStatusCode"
    case .cfErrorHTTPAuthenticationTypeUnsupported: return "CFErrorHTTPAuthenticationTypeUnsupported"
    case .cfErrorHTTPBadCredentials: return "CFErrorHTTPBadCredentials"
    case .cfErrorHTTPConnectionLost: return "CFErrorHTTPConnectionLost"
    case .cfErrorHTTPParseFailure: return "CFErrorHTTPParseFailure"
    case .cfErrorHTTPRedirectionLoopDetected: return "CFErrorHTTPRedirectionLoopDetected"
    case .cfErrorHTTPBadURL: return "CFErrorHTTPBadURL"
    case .cfErrorHTTPProxyConnectionFailure: return "CFErrorHTTPProxyConnectionFailure"
    case .cfErrorHTTPBadProxyCredentials: return "CFErrorHTTPBadProxyCredentials"
    case .cfErrorPACFileError: return "CFErrorPACFileError"
    case .cfErrorPACFileAuth: return "CFErrorPACFileAuth"
    case .cfErrorHTTPSProxyConnectionFailure: return "CFErrorHTTPSProxyConnectionFailure"
    case .cfStreamErrorHTTPSProxyFailureUnexpectedResponseToCONNECTMethod: return "CFStreamErrorHTTPSProxyFailureUnexpectedResponseToCONNECTMethod"

    case .cfurlErrorBackgroundSessionInUseByAnotherProcess: return "CFURLErrorBackgroundSessionInUseByAnotherProcess"
    case .cfurlErrorBackgroundSessionWasDisconnected: return "CFURLErrorBackgroundSessionWasDisconnected"
    case .cfurlErrorUnknown: return "CFURLErrorUnknown"
    case .cfurlErrorCancelled: return "CFURLErrorCancelled"
    case .cfurlErrorBadURL: return "CFURLErrorBadURL"
    case .cfurlErrorTimedOut: return "CFURLErrorTimedOut"
    case .cfurlErrorUnsupportedURL: return "CFURLErrorUnsupportedURL"
    case .cfurlErrorCannotFindHost: return "CFURLErrorCannotFindHost"
    case .cfurlErrorCannotConnectToHost: return "CFURLErrorCannotConnectToHost"
    case .cfurlErrorNetworkConnectionLost: return "CFURLErrorNetworkConnectionLost"
    case .cfurlErrorDNSLookupFailed: return "CFURLErrorDNSLookupFailed"
    case .cfurlErrorHTTPTooManyRedirects: return "CFURLErrorHTTPTooManyRedirects"
    case .cfurlErrorResourceUnavailable: return "CFURLErrorResourceUnavailable"
    case .cfurlErrorNotConnectedToInternet: return "CFURLErrorNotConnectedToInternet"
    case .cfurlErrorRedirectToNonExistentLocation: return "CFURLErrorRedirectToNonExistentLocation"
    case .cfurlErrorBadServerResponse: return "CFURLErrorBadServerResponse"
    case .cfurlErrorUserCancelledAuthentication: return "CFURLErrorUserCancelledAuthentication"
    case .cfurlErrorUserAuthenticationRequired: return "CFURLErrorUserAuthenticationRequired"
    case .cfurlErrorZeroByteResource: return "CFURLErrorZeroByteResource"
    case .cfurlErrorCannotDecodeRawData: return "CFURLErrorCannotDecodeRawData"
    case .cfurlErrorCannotDecodeContentData: return "CFURLErrorCannotDecodeContentData"
    case .cfurlErrorCannotParseResponse: return "CFURLErrorCannotParseResponse"
    case .cfurlErrorInternationalRoamingOff: return "CFURLErrorInternationalRoamingOff"
    case .cfurlErrorCallIsActive: return "CFURLErrorCallIsActive"
    case .cfurlErrorDataNotAllowed: return "CFURLErrorDataNotAllowed"
    case .cfurlErrorRequestBodyStreamExhausted: return "CFURLErrorRequestBodyStreamExhausted"
    case .cfurlErrorFileDoesNotExist: return "CFURLErrorFileDoesNotExist"
    case .cfurlErrorFileIsDirectory: return "CFURLErrorFileIsDirectory"
    case .cfurlErrorNoPermissionsToReadFile: return "CFURLErrorNoPermissionsToReadFile"
    case .cfurlErrorDataLengthExceedsMaximum: return "CFURLErrorDataLengthExceedsMaximum"
    case .cfurlErrorSecureConnectionFailed: return "CFURLErrorSecureConnectionFailed"
    case .cfurlErrorServerCertificateHasBadDate: return "CFURLErrorServerCertificateHasBadDate"
    case .cfurlErrorServerCertificateUntrusted: return "CFURLErrorServerCertificateUntrusted"
    case .cfurlErrorServerCertificateHasUnknownRoot: return "CFURLErrorServerCertificateHasUnknownRoot"
    case .cfurlErrorServerCertificateNotYetValid: return "CFURLErrorServerCertificateNotYetValid"
    case .cfurlErrorClientCertificateRejected: return "CFURLErrorClientCertificateRejected"
    case .cfurlErrorClientCertificateRequired: return "CFURLErrorClientCertificateRequired"
    case .cfurlErrorCannotLoadFromNetwork: return "CFURLErrorCannotLoadFromNetwork"
    case .cfurlErrorCannotCreateFile: return "CFURLErrorCannotCreateFile"
    case .cfurlErrorCannotOpenFile: return "CFURLErrorCannotOpenFile"
    case .cfurlErrorCannotCloseFile: return "CFURLErrorCannotCloseFile"
    case .cfurlErrorCannotWriteToFile: return "CFURLErrorCannotWriteToFile"
    case .cfurlErrorCannotRemoveFile: return "CFURLErrorCannotRemoveFile"
    case .cfurlErrorCannotMoveFile: return "CFURLErrorCannotMoveFile"
    case .cfurlErrorDownloadDecodingFailedMidStream: return "CFURLErrorDownloadDecodingFailedMidStream"
    case .cfurlErrorDownloadDecodingFailedToComplete: return "CFURLErrorDownloadDecodingFailedToComplete"

    case .cfhttpCookieCannotParseCookieFile: return "CFHTTPCookieCannotParseCookieFile"
    case .cfNetServiceErrorUnknown: return "CFNetServiceErrorUnknown"
    case .cfNetServiceErrorCollision: return "CFNetServiceErrorCollision"
    case .cfNetServiceErrorNotFound: return "CFNetServiceErrorNotFound"
    case .cfNetServiceErrorInProgress: return "CFNetServiceErrorInProgress"
    case .cfNetServiceErrorBadArgument: return "CFNetServiceErrorBadArgument"
    case .cfNetServiceErrorCancel: return "CFNetServiceErrorCancel"
    case .cfNetServiceErrorInvalid: return "CFNetServiceErrorInvalid"
    case .cfNetServiceErrorTimeout: return "CFNetServiceErrorTimeout"
    case .cfNetServiceErrorDNSServiceFailure: return "CFNetServiceErrorDNSServiceFailure"
    default: return "Unknown"
    }
}

class ErrorPageHandler: InternalSchemeResponse {
    static let path = InternalURL.Path.errorpage.rawValue

    func response(forRequest request: URLRequest) -> (URLResponse, Data)? {
        guard let requestUrl = request.url, let originalUrl = InternalURL(requestUrl)?.originalURLFromErrorPage else {
            return nil
        }

        guard let url = request.url,
            let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code = c.valueForQuery("code"),
            let errCode = Int(code),
            let errDescription = c.valueForQuery("description"),
            let errURLDomain = originalUrl.host,
            var errDomain = c.valueForQuery("domain") else {
                return nil
        }

        var asset = Bundle.main.path(forResource: "NetError", ofType: "html")
        var variables = [
            "error_code": "\(errCode)",
            "error_title": errDescription,
            "short_description": errDomain,
            ]

        let tryAgain = NSLocalizedString("Try again", tableName: "ErrorPages", comment: "Shown in error pages on a button that will try to load the page again")
        var actions = "<button onclick='webkit.messageHandlers.localRequestHelper.postMessage({" +
            "securitytoken: \"\(UserScriptManager.securityToken)\"," +
            "type: \"reload\" })'>\(tryAgain)</button>"

        if errDomain == kCFErrorDomainCFNetwork as String {
            if let code = CFNetworkErrors(rawValue: Int32(errCode)) {
                errDomain = cfErrorToName(code)
            }
        } else if errDomain == MozDomain {
            if errCode == MozErrorDownloadsNotEnabled {
                let downloadInSafari = NSLocalizedString("Open in Safari", tableName: "ErrorPages", comment: "Shown in error pages for files that can't be shown and need to be downloaded.")

                // Overwrite the normal try-again action.
                actions = "<button onclick='webkit.messageHandlers.errorPageHelperMessageManager.postMessage({type: \"\(MessageOpenInSafari)\"})'>\(downloadInSafari)</button>"
            }
            errDomain = ""
        } else if CertErrors.contains(errCode) {
            guard let url = request.url, let comp = URLComponents(url: url, resolvingAgainstBaseURL: false), let certError = comp.valueForQuery("certerror") else {
                assert(false)
                return nil
            }

            asset = Bundle.main.path(forResource: "CertError", ofType: "html")
            actions = "<button onclick='history.back()'>\(Strings.ErrorPagesGoBackButton)</button>"
            variables["error_title"] = Strings.ErrorPagesCertWarningTitle
            variables["cert_error"] = certError
            variables["long_description"] = String(format: Strings.ErrorPagesCertWarningDescription, "<b>\(errURLDomain)</b>", AppInfo.displayName)
            variables["advanced_button"] = Strings.ErrorPagesAdvancedButton
            variables["warning_description"] = Strings.ErrorPagesCertWarningDescription
            variables["warning_advanced1"] = Strings.ErrorPagesAdvancedWarning1
            variables["warning_advanced2"] = Strings.ErrorPagesAdvancedWarning2
            variables["warning_actions"] =
            "<p><a href='javascript:webkit.messageHandlers.errorPageHelperMessageManager.postMessage({type: \"\(MessageCertVisitOnce)\"})'>\(Strings.ErrorPagesVisitOnceButton)</button></p>"
        }

        // If a reload is requested and this much time has expired since the page was shown, try to reload the original url. Alternatively, this could have been a boolean flag to indicate if a page has been shown to the user already (the code for that would be nearly identical).
        // The previous method for this this was to track a list of urls for which errorpage should be shown instead of trying to load the original url.
        // This old method was too fragile to reliably add and insert urls into that list, particularly on page restoration as only native code can modify that list.
        let expiryTimeToTryReloadOriginal_ms = 2000

        variables["reloader"] = """
        let url = new URL(location.href);
        let lastTime = parseInt(url.searchParams.get('timestamp'), 10);
        let originalUrl = url.searchParams.get('url');

        if (isNaN(lastTime) || lastTime < 1) {
            setTimeout(() => {
              url.searchParams.set('timestamp', Date.now());
              location.replace(url.toString());
            })
        } else if (lastTime > 0 && Date.now() - lastTime > \(expiryTimeToTryReloadOriginal_ms)) {
        location.replace(originalUrl);
        }
        """

        variables["actions"] = actions

        let response = InternalSchemeHandler.response(forUrl: originalUrl)
        guard let file = asset, var html = try? String(contentsOfFile: file) else {
            assert(false)
            return nil
        }

        variables.forEach { (arg, value) in
            html = html.replacingOccurrences(of: "%\(arg)%", with: value)
        }

        guard let data = html.data(using: .utf8) else { return nil }
        return (response, data)
    }
}

class ErrorPageHelper {

    fileprivate weak var certStore: CertStore?

    init(certStore: CertStore?) {
        self.certStore = certStore
    }

    func loadPage(_ error: NSError, forUrl url: URL, inWebView webView: WKWebView) {
        guard var components = URLComponents(string: "\(InternalURL.baseUrl)/\(ErrorPageHandler.path)"), let webViewUrl = webView.url else {
            return
        }

        // When an error page is reloaded, the js on the page checks if >2s have passed since the error page was initially loaded, and if so, it reloads the original url for the page. If that original page immediately errors out again, we don't want to push another error page on history stack. This will detect this case, and clear the timestamp to ensure the error page doesn't try to reload.
        if let internalUrl = InternalURL(webViewUrl), internalUrl.originalURLFromErrorPage == url {
            webView.evaluateJavaScript("""
                (function () {
                   let url = new URL(location.href);
                   url.searchParams.remove('timestamp');
                   location.replace(url.toString());
                })();
            """)
            return
        }

        var queryItems = [
            URLQueryItem(name: InternalURL.Param.url.rawValue, value: url.absoluteString),
            URLQueryItem(name: "code", value: String(error.code)),
            URLQueryItem(name: "domain", value: error.domain),
            URLQueryItem(name: "description", value: error.localizedDescription),
            // 'timestamp' is used for the js reload logic
            URLQueryItem(name: "timestamp", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]

        // If this is an invalid certificate, show a certificate error allowing the
        // user to go back or continue. The certificate itself is encoded and added as
        // a query parameter to the error page URL; we then read the certificate from
        // the URL if the user wants to continue.
        if CertErrors.contains(error.code),
            let certChain = error.userInfo["NSErrorPeerCertificateChainKey"] as? [SecCertificate],
            let cert = certChain.first,
            let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
            let certErrorCode = underlyingError.userInfo["_kCFStreamErrorCodeKey"] as? Int {
            let encodedCert = (SecCertificateCopyData(cert) as Data).base64EncodedString
            queryItems.append(URLQueryItem(name: "badcert", value: encodedCert))

            let certError = CertErrorCodes[certErrorCode] ?? ""
            queryItems.append(URLQueryItem(name: "certerror", value: String(certError)))
        }

        components.queryItems = queryItems
        if let urlWithQuery = components.url {
            if let internalUrl = InternalURL(webViewUrl), internalUrl.isSessionRestore, let page = InternalURL.authorize(url: urlWithQuery) {
                // A session restore page is already on the history stack, so don't load another page on the history stack.
                webView.replaceLocation(with: page)
            } else {
                // A new page needs to be added to the history stack (i.e. the simple case of trying to navigate to an url for the first time and it fails, without pushing a page on the history stack, the webview will just show the current page).
                webView.load(PrivilegedRequest(url: urlWithQuery) as URLRequest)
            }
        }
    }
}

extension ErrorPageHelper: TabContentScript {
    static func name() -> String {
        return "ErrorPageHelper"
    }

    func scriptMessageHandlerName() -> String? {
        return "errorPageHelperMessageManager"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        guard let errorURL = message.frameInfo.request.url,
            let internalUrl = InternalURL(errorURL),
            internalUrl.isErrorPage,
            let originalURL = internalUrl.originalURLFromErrorPage,
            let res = message.body as? [String: String],
            let type = res["type"] else { return }

        switch type {
        case MessageOpenInSafari:
            UIApplication.shared.open(originalURL, options: [:])
        case MessageCertVisitOnce:
            if let cert = certFromErrorURL(errorURL),
                let host = originalURL.host {
                let origin = "\(host):\(originalURL.port ?? 443)"
                certStore?.addCertificate(cert, forOrigin: origin)
                message.webView?.replaceLocation(with: originalURL)
                // webview.reload will not change the error URL back to the original URL
            }
        default:
            assertionFailure("Unknown error message")
        }
    }
}
