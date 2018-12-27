Pod::Spec.new do |s|
  s.name = 'McuManager'
  s.version = '0.6.2'
  s.license = { :type => "Apache 2.0", :file => 'LICENSE' }
  s.summary = 'A mobile management library for devices running Apache Mynewt or Zephyr'
  s.homepage = 'https://github.com/JuulLabs-OSS/mcumgr-ios'
  s.authors = { 'Brian Giori' => 'brian.giori@juul.com' }
  s.source = { :git => 'https://github.com/JuulLabs-OSS/mcumgr-ios.git', :tag => "v#{s.version}" }
  s.swift_version = '4.0'

  s.ios.deployment_target = '9.0'

  s.source_files = 'Source/**/*'

  s.requires_arc = true
end
