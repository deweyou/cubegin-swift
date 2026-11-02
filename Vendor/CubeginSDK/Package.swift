// swift-tools-version: 6.0
import PackageDescription
import Foundation
// Release packaging writes Artifact.json with an immutable URL and checksum.
let artifactURL=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("sdk/swift/Artifact.json")
let binary:Target
if let data=try? Data(contentsOf:artifactURL), let artifact=try? JSONSerialization.jsonObject(with:data) as? [String:String],let url=artifact["url"],let checksum=artifact["checksum"] {
 binary = .binaryTarget(name:"CubeginFFI",url:url,checksum:checksum)
} else {
 binary = .binaryTarget(name:"CubeginFFI",path:"dist/CubeginFFI.xcframework")
}
let package=Package(name:"Cubegin",platforms:[.iOS(.v15),.macOS(.v12)],products:[.library(name:"Cubegin",targets:["Cubegin"])],targets:[
 binary,
 .target(name:"Cubegin",dependencies:["CubeginFFI"],path:"sdk/swift/Generated",exclude:["CubeginFFI.h","CubeginFFI.modulemap"],sources:["Cubegin.swift"]),
 .testTarget(name:"CubeginTests",dependencies:["Cubegin"],path:"sdk/swift/PackageTests")
])
