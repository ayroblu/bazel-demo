import Foundation
import Log

func image1() -> Data? {
  if let url = Bundle.main.url(forResource: "image_1", withExtension: "bmp"),
    let data = try? Data(contentsOf: url)
  {
    return data
  } else {
    log("Failed to load image, bundle:", Bundle.main.bundlePath)
  }
  return nil
}
