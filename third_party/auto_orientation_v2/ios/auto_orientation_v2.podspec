#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'auto_orientation_v2'
  s.version          = '2.4.5'
  s.summary          = 'Set and control device orientation programmatically for Flutter apps on iOS and Android.'
  s.description      = <<-DESC
Set and control device orientation programmatically for Flutter apps on iOS and Android.
                       DESC
  s.homepage         = 'http://rizkyghofur.my.id'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Rizki Abdul Gofur' => 'rizky.abdulghofur@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'auto_orientation_v2/Sources/auto_orientation_v2/**/*'
  s.dependency 'Flutter'
  s.swift_version    = '5.0'

  s.ios.deployment_target = '13.0'
end
