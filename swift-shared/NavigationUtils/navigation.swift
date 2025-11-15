import MapKit
import SwiftUI

@Observable
public class MapCompleter {
  public var completions = [MKLocalSearchCompletion]()
  private var completer: CompletionDelegate!

  public init(_ options: CompletionOptions) {
    completer = CompletionDelegate(options: options) { [self] results in
      completions = results
    }
  }

  public func update(queryFragment: String, region: MKCoordinateRegion?) {
    completer.update(queryFragment: queryFragment, region: region)
  }
}

extension MKLocalSearchCompletion: @retroactive Identifiable {
  public var id: String {
    return "\(title)-\(subtitle)"
  }
}

class CompletionDelegate: NSObject, MKLocalSearchCompleterDelegate {
  private let completer: MKLocalSearchCompleter = MKLocalSearchCompleter()

  private let onUpdate: ([MKLocalSearchCompletion]) -> Void

  init(
    options: CompletionOptions,
    onUpdate: @escaping ([MKLocalSearchCompletion]) -> Void
  ) {
    self.onUpdate = onUpdate
    super.init()
    completer.delegate = self
    completer.resultTypes = options.resultTypes
    completer.regionPriority = options.regionPriority
    completer.pointOfInterestFilter = options.pointOfInterestFilter
    completer.addressFilter = options.addressFilter
  }

  func update(queryFragment: String, region: MKCoordinateRegion?) {
    if let region {
      completer.region = region
    }
    completer.queryFragment = queryFragment
  }

  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    onUpdate(completer.results)
  }
}

public struct CompletionOptions {
  public let resultTypes: MKLocalSearchCompleter.ResultType
  public let regionPriority: MKLocalSearchRegionPriority
  public let pointOfInterestFilter: MKPointOfInterestFilter?
  public let addressFilter: MKAddressFilter?

  public init(
    resultTypes: MKLocalSearchCompleter.ResultType,
    regionPriority: MKLocalSearchRegionPriority = .default,
    pointOfInterestFilter: MKPointOfInterestFilter? = nil, addressFilter: MKAddressFilter? = nil
  ) {
    self.resultTypes = resultTypes
    self.regionPriority = regionPriority
    self.pointOfInterestFilter = pointOfInterestFilter
    self.addressFilter = addressFilter
  }
}
