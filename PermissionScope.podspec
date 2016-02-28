Pod::Spec.new do |s|
  s.name = 'PermissionScope'
  s.version = '1.0.2'
  s.license = 'MIT'
  s.summary = 'A Periscope-inspired way to ask for iOS permissions (Eyez.io revision)'
  s.homepage = 'https://github.com/Eyez-io'
  s.authors = { "Noam Etzion-Rosenberg" => 'noam@eyez.io' }
  s.source = { :git => 'https://github.com/Eyez-io/PermissionScope', :tag => s.version }

  s.ios.deployment_target = '8.0'

  s.source_files = 'PermissionScope/*.swift'

  s.requires_arc = true
end
