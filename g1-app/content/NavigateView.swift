import Log
import MapKit
import SwiftUI

struct NavigateView: View {
  @StateObject var vm: MainVM
  @State private var route: MKRoute?
  @State private var cameraPosition: MapCameraPosition = MapCameraPosition.userLocation(
    fallback: .automatic)
  let manager = CLLocationManager()

  var body: some View {
    LazyView {
      ZStack {
        Map(position: $cameraPosition) {
          UserAnnotation()
          if let route {
            MapPolyline(route)
              .stroke(
                .white,
                style: StrokeStyle(
                  lineWidth: 7, lineCap: .round, lineJoin: .round, miterLimit: 10))
            MapPolyline(route)
              .stroke(
                .blue,
                style: StrokeStyle(
                  lineWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 10))
          }
        }
        .mapControls {
          MapUserLocationButton()
          MapCompass()
        }
        .onAppear {
          manager.requestWhenInUseAuthorization()
          Task {
            route = await getDirections()
            if let route {
              var rect = route.polyline.boundingMapRect
              rect.size.width *= 1.2
              rect.size.height *= 1.2
              rect.origin.x -= rect.size.width / 10
              rect.origin.y -= rect.size.height / 10
              cameraPosition = MapCameraPosition.rect(rect)
            }
          }
        }
      }
      .navigationTitle("Navigation")
      // .navigationBarHidden(true)
    }
  }
}

#Preview {
  NavigateView(vm: MainVM())
}
