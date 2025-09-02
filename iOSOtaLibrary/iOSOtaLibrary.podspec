Pod::Spec.new do |s|
  s.name = "iOSOtaLibrary"
  s.version = "0.1"
  s.license = { :type => "Apache 2.0", :file => "LICENSE" }
  s.summary = "Complementary library to iOSMcuManager to fetch OTA DFU Images from nRF Cloud powered by Memfault."
  s.homepage = "https://github.com/NordicSemiconductor/IOS-nRF-Connect-Device-Manager"
  s.authors = { "Dinesh Harjani" => "dinesh.harjani@nordicsemi.no" }
  s.source = { :git => "https://github.com/NordicSemiconductor/IOS-nRF-Connect-Device-Manager.git", :tag => "ota-#{s.version}" }
  s.swift_versions = ["5.10"]

  s.ios.deployment_target = "12.0"
  s.osx.deployment_target = "10.13"

  s.source_files = "Source/**/*.{swift, h}"
  s.exclude_files = "Source/*.plist"

  s.requires_arc = true
end

