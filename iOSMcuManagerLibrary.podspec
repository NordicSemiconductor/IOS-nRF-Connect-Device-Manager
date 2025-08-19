Pod::Spec.new do |s|
  s.name = "iOSMcuManagerLibrary"
  s.version = "1.10.2"
  s.license = { :type => "Apache 2.0", :file => "LICENSE" }
  s.summary = "A mobile management library for devices running Apache Mynewt, Zephyr (McuMgr) and SUIT (Software Update for the Internet of Things)."
  s.homepage = "https://github.com/NordicSemiconductor/IOS-nRF-Connect-Device-Manager"
  s.authors = { "Dinesh Harjani" => "dinesh.harjani@nordicsemi.no", "Aleksander Nowakowski" => "aleksander.nowakowski@nordicsemi.no" }
  s.source = { :git => "https://github.com/NordicSemiconductor/IOS-nRF-Connect-Device-Manager.git", :tag => "#{s.version}" }
  s.swift_versions = ["4.2", "5.0", "5.1", "5.2", "5.3", "5.4", "5.5", "5.6", "5.7", "5.8", "5.9", "5.10"]

  s.ios.deployment_target = "12.0"
  s.osx.deployment_target = "10.13"

  s.source_files = "Source/**/*.{swift, h}"
  s.exclude_files = "Source/*.plist"

  s.requires_arc = true

  s.dependency "SwiftCBOR", "0.4.7"
  s.dependency "ZIPFoundation", "0.9.19"
end
