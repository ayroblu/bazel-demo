import Foundation
import StringUtils

public class SearchFilterCached<T: Hashable> {
  private var map = [[T]: [String: [T]]]()

  public init() {}

  public func searchFilter(searchQuery: String, list: [T], getter: (T) -> String) -> [T] {
    let subDict = map[list]
    if let item = subDict?[searchQuery] {
      return item
    }

    let result = filter(searchQuery: searchQuery, list: list, getter: getter)

    if var subDict {
      subDict[searchQuery] = result
    } else {
      map[list] = [searchQuery: result]
    }
    return result
  }
}

func filter<T>(searchQuery: String, list: [T], getter: (T) -> String) -> [T] {
  let searchItems = searchQuery.split(separator: " ").filter { $0.trim().count > 0 }
  if searchItems.count == 0 { return list }
  return list.filter { item in
    searchItems.allSatisfy { searchItem in
      getter(item).range(of: searchItem, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }
}
