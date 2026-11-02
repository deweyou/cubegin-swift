import XCTest
import Cubegin
final class EngineTests:XCTestCase {
 func testBinaryPackageConsumer() throws {
  XCTAssertTrue(try evaluate(algorithm:"").solved)
  XCTAssertFalse(try evaluate(algorithm:"R").solved)
  XCTAssertThrowsError(try evaluate(algorithm:"Rw"))
  let s=try scramble(seed:42)
  let solution=try solve(facelets:s.facelets)
  XCTAssertTrue(try evaluate(algorithm:s.algorithm+" "+solution).solved)
 }
 func testExpandedCapabilities() throws {
  XCTAssertTrue(try evaluateEvent(event:"444",algorithm:"Rw U").svg.contains("svg"))
  XCTAssertTrue(try generateTraining(id:"333.pll",seed:42,optionsJson:"{}").contains("333.pll"))
  XCTAssertTrue(try solveAssist(event:"333",methodsJson:"[\"cross\"]",algorithm:"R U F",optionsJson:"{}").contains("solution"))
  XCTAssertTrue(try playerSvg(event:"sq1",algorithm:"(1,0) /",completed:1,progress:0.5).contains("<polygon"))
 }
}
