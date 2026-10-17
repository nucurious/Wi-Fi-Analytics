Pod::Spec.new do |s|
  s.name             = 'radio_info'
  s.version          = '1.0.0'
  s.summary          = 'Radio access technology info for WiFi Analytics.'
  s.description      = 'Reports the current radio access technology (LTE / 5G) and connection type.'
  s.homepage         = 'https://example.com/wifi_analytics'
  s.license          = { :type => 'MIT' }
  s.author           = { 'WiFi Analytics' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'CoreTelephony', 'Network'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
