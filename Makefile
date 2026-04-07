release:
	xcodebuild -project EyeSaver.xcodeproj -scheme EyeSaver -configuration Release build SWIFT_ACTIVE_COMPILATION_CONDITIONS='ENABLE_SCREEN_SHARING'
	open -R "/Users/jason/Library/Developer/Xcode/DerivedData/EyeSaver-gttusnejcimqtcdmahfshixbqwep/Build/Products/Release/EyeSaver.app"

appstore:
	xcodebuild -project EyeSaver.xcodeproj -scheme EyeSaver -configuration Release build
	open -R "/Users/jason/Library/Developer/Xcode/DerivedData/EyeSaver-gttusnejcimqtcdmahfshixbqwep/Build/Products/Release/EyeSaver.app"
