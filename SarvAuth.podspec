Pod::Spec.new do |s|
  s.name             = 'SarvAuth'
  s.version          = '0.1.0'
  s.summary          = 'Login with Sarv for iOS — OAuth 2.1 + PKCE in the system sign-in sheet.'
  s.description      = <<-DESC
    Native "Login with Sarv" button and OAuth 2.1 + PKCE client for oauth.sarv.com:
    ASWebAuthenticationSession sign-in, state and nonce checks, Keychain token storage,
    serialised refresh-token rotation, revoke and sign-out. Same protocol as @sarv-in/login.
  DESC
  s.homepage         = 'https://github.com/Sarv/sarv-login-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Sarv' => 'support@sarv.com' }
  s.source           = { :git => 'https://github.com/Sarv/sarv-login-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version    = '5.9'
  s.source_files     = 'Sources/SarvAuth/**/*.swift'
  s.resource_bundles = { 'SarvAuth' => ['Sources/SarvAuth/Resources/**/*'] }
  s.frameworks       = 'AuthenticationServices', 'CryptoKit', 'Security', 'SwiftUI'
end
