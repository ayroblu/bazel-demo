import SearchUtils
import XCTest

class SearchUtilsTests: XCTestCase {
  let list = [Example(name: "first"), Example(name: "second")]

  func testSearchFilter_noop() {
    let result = SearchFilterCached<Example>().searchFilter(searchQuery: "", list: list) {
      $0.name
    }
    XCTAssertEqual(result, list)
  }

  func testSearchFilter_spaceSeparatedItems() {
    let cache = SearchFilterCached<Example>()
    let result = cache.searchFilter(searchQuery: "fi  st", list: list) {
      $0.name
    }
    XCTAssertEqual(result, [Example(name: "first")])

    var counter = 0
    let second = cache.searchFilter(searchQuery: "fi  st", list: list) {
      item in
      counter += 1
      return item.name
    }
    XCTAssertEqual(second, [Example(name: "first")])
    XCTAssertEqual(counter, 0, "Search is cached and should not be called again")
  }
}

struct Example: Hashable {
  let name: String
}
