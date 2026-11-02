import SwiftUI
import UIKit

let busMarkerStyle = BusMarkerStyle.routemaster

enum BusMarkerStyle {
  case routemaster
  case enviro400
  case topDownChevron

  var image: UIImage {
    switch self {
    case .routemaster: routemasterImage
    case .enviro400: enviro400Image
    case .topDownChevron: topDownChevronImage
    }
  }

  func transform(heading: Double) -> CGAffineTransform {
    let radians = heading * .pi / 180
    switch self {
    case .routemaster, .enviro400:
      return sin(radians) >= 0
        ? CGAffineTransform(rotationAngle: radians - .pi / 2)
        : CGAffineTransform(rotationAngle: radians - 3 * .pi / 2).scaledBy(x: -1, y: 1)
    case .topDownChevron:
      return CGAffineTransform(rotationAngle: radians)
    }
  }
}

private let routemasterImage = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 28)).image {
  context in
  let cg = context.cgContext
  fill(cg, corners(CGRect(x: 1, y: 2, width: 34, height: 20.5), tl: 7, tr: 7, br: 2, bl: 2), red)
  fill(cg, CGPath(rect: CGRect(x: 1, y: 11, width: 34, height: 1.6), transform: nil), cream)
  for x in stride(from: 5.0, through: 23, by: 6) {
    fill(cg, rounded(CGRect(x: x, y: 4.5, width: 4.6, height: 5), 1), glass)
  }
  fill(cg, corners(CGRect(x: 29, y: 4.5, width: 4.2, height: 5), tl: 1, tr: 3, br: 1, bl: 1), glass)
  for x in stride(from: 9.0, through: 21, by: 6) {
    fill(cg, rounded(CGRect(x: x, y: 13.8, width: 4.6, height: 5), 1), glass)
  }
  fill(cg, rounded(CGRect(x: 2.5, y: 13.8, width: 4, height: 8), 1), darkGlass)
  fill(cg, rounded(CGRect(x: 28, y: 13.8, width: 5, height: 5), 1), glass)
  wheel(cg, x: 9, y: 22.5, radius: 3.6)
  wheel(cg, x: 27, y: 22.5, radius: 3.6)
}

private let enviro400Image = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 28)).image {
  context in
  let cg = context.cgContext
  fill(cg, corners(CGRect(x: 1, y: 2, width: 34, height: 20.5), tl: 3, tr: 4, br: 1.5, bl: 2), red)
  fill(cg, CGPath(rect: CGRect(x: 1, y: 11.2, width: 34, height: 0.9), transform: nil), cream)
  for x in stride(from: 3.5, through: 21.5, by: 6) {
    fill(cg, rounded(CGRect(x: x, y: 4.5, width: 5.2, height: 5.2), 1), glass)
  }
  fill(
    cg, corners(CGRect(x: 27.5, y: 4.5, width: 7, height: 5.2), tl: 1, tr: 3, br: 1, bl: 1), glass)
  for x in stride(from: 3.5, through: 15.5, by: 6) {
    fill(cg, rounded(CGRect(x: x, y: 13.5, width: 5.2, height: 5), 1), glass)
  }
  fill(cg, rounded(CGRect(x: 23, y: 13.5, width: 4.5, height: 8.5), 0.8), glass)
  fill(cg, CGPath(rect: CGRect(x: 25.1, y: 13.5, width: 0.4, height: 8.5), transform: nil), red)
  fill(cg, corners(CGRect(x: 29, y: 13, width: 6, height: 7), tl: 1, tr: 1.5, br: 1, bl: 1), glass)
  fill(cg, rounded(CGRect(x: 30, y: 2.6, width: 4.5, height: 1.4), 0.5), amber)
  wheel(cg, x: 8.5, y: 22.5, radius: 3.6)
  wheel(cg, x: 29.5, y: 22.5, radius: 3.6)
}

private let topDownChevronImage = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 38))
  .image { context in
    let cg = context.cgContext
    fill(cg, rounded(CGRect(x: 0.5, y: 6, width: 2.5, height: 3), 1), black)
    fill(cg, rounded(CGRect(x: 17, y: 6, width: 2.5, height: 3), 1), black)
    fill(cg, corners(CGRect(x: 2, y: 1, width: 16, height: 36), tl: 5, tr: 5, br: 3, bl: 3), red)
    fill(
      cg, corners(CGRect(x: 3.5, y: 2.5, width: 13, height: 4), tl: 3.5, tr: 3.5, br: 1, bl: 1),
      darkGlass)
    fill(cg, rounded(CGRect(x: 4, y: 9, width: 12, height: 25), 2), roofRed)
    let chevron = CGMutablePath()
    chevron.addLines(between: [
      CGPoint(x: 10, y: 11), CGPoint(x: 15, y: 18), CGPoint(x: 12.5, y: 18),
      CGPoint(x: 10, y: 14.5), CGPoint(x: 7.5, y: 18), CGPoint(x: 5, y: 18),
    ])
    chevron.closeSubpath()
    fill(cg, chevron, UIColor.white.cgColor)
    fill(cg, rounded(CGRect(x: 4, y: 34.5, width: 12, height: 1.5), 0.5), darkRed)
  }

private let red = UIColor(busRed).cgColor
private let roofRed = CGColor(red: 0.72, green: 0.1, blue: 0.09, alpha: 1)
private let darkRed = CGColor(red: 0.5, green: 0.05, blue: 0.05, alpha: 1)
private let glass = CGColor(red: 0.82, green: 0.92, blue: 1, alpha: 1)
private let darkGlass = CGColor(red: 0.13, green: 0.16, blue: 0.2, alpha: 1)
private let amber = CGColor(red: 1, green: 0.72, blue: 0.1, alpha: 1)
private let cream = CGColor(red: 0.98, green: 0.94, blue: 0.82, alpha: 1)
private let black = CGColor(gray: 0.08, alpha: 1)
private let hub = CGColor(gray: 0.62, alpha: 1)

private func fill(_ cg: CGContext, _ path: CGPath, _ color: CGColor) {
  cg.addPath(path)
  cg.setFillColor(color)
  cg.fillPath()
}

private func corners(_ r: CGRect, tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat) -> CGPath {
  let path = CGMutablePath()
  path.move(to: CGPoint(x: r.minX + tl, y: r.minY))
  path.addArc(
    tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY),
    radius: tr)
  path.addArc(
    tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY),
    radius: br)
  path.addArc(
    tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY),
    radius: bl)
  path.addArc(
    tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY),
    radius: tl)
  path.closeSubpath()
  return path
}

private func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func wheel(_ cg: CGContext, x: CGFloat, y: CGFloat, radius: CGFloat) {
  fill(
    cg,
    CGPath(
      ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius),
      transform: nil), black)
  let hubRadius = radius * 0.42
  fill(
    cg,
    CGPath(
      ellipseIn: CGRect(
        x: x - hubRadius, y: y - hubRadius, width: 2 * hubRadius, height: 2 * hubRadius),
      transform: nil), hub)
}
