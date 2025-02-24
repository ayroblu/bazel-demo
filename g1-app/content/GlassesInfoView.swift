import SwiftUI

struct GlassesInfoView: View {
  @Environment(\.colorScheme) var colorScheme
  @StateObject var mainVm: MainVM

  var body: some View {
    ZStack {
      Image(uiImage: getImage(mainVm: mainVm, isDark: colorScheme == .dark))
        .resizable()
        .aspectRatio(contentMode: .fit)
      VStack {
        if let battery = mainVm.battery {
          HStack {
            Spacer()
            Image(systemName: getBatterySymbol(battery: battery))
            Text("\(battery)%")
          }
        }
        if mainVm.isCaseOpen != nil, let battery = mainVm.caseBattery {
          HStack {
            Spacer()
            Image(systemName: getBatterySymbol(battery: battery))
            Text("\(battery)%")
          }
        }
        Spacer()
      }
    }
    .onTapGesture {
      mainVm.connectionManager.deviceInfo()
    }
  }
}

func getBatterySymbol(battery: Int) -> String {
  return battery > 75
    ? "battery.100percent"
    : battery > 50
      ? "battery.75percent"
      : battery > 25
        ? "battery.25percent"
        : "battery.0percent"
}

func getImage(mainVm: MainVM, isDark: Bool) -> UIImage {
  if isDark {
    if mainVm.isConnected {
      if let isCaseOpen = mainVm.isCaseOpen {
        if isCaseOpen {
          if mainVm.caseBattery != 100 {
            return caseOpenChargingDarkImage
          } else {
            return caseOpenFullDarkImage
          }
        } else {
          if mainVm.caseBattery != 100 {
            return caseCloseChargingDarkImage
          } else {
            return caseOpenFullDarkImage
          }
        }
      } else {
        return foldedDarkImage
      }
    } else {
      return noPairedDarkImage
    }
  } else {
    if mainVm.isConnected {
      if let isCaseOpen = mainVm.isCaseOpen {
        if isCaseOpen {
          if mainVm.caseBattery != 100 {
            return caseOpenChargingImage
          } else {
            return caseOpenFullImage
          }
        } else {
          if mainVm.caseBattery != 100 {
            return caseCloseChargingImage
          } else {
            return caseOpenFullImage
          }
        }
      } else {
        return foldedImage
      }
    } else {
      return noPairedImage
    }
  }
}
let caseOpenChargingImage = UIImage(named: "g1/image_g1_b_brown1_l_case_open_charging.png")!
let caseOpenFullImage = UIImage(named: "g1/image_g1_b_brown1_l_case_open_full.png")!
let foldedImage = UIImage(named: "g1/image_g1_b_brown1_l_folded.png")!
let noPairedImage = UIImage(named: "g1/image_g1_b_brown1_l_no_paired_device.png")!
let caseCloseChargingImage = UIImage(named: "g1/image_g1_l_case_close_charging.png")!
let caseCloseFullImage = UIImage(named: "g1/image_g1_l_case_close_full.png")!

let caseOpenChargingDarkImage = UIImage(
  named: "g1/image_g1_b_brown1_l_case_open_charging_dark.png")!
let caseOpenFullDarkImage = UIImage(named: "g1/image_g1_b_brown1_l_case_open_full_dark.png")!
let foldedDarkImage = UIImage(named: "g1/image_g1_b_brown1_l_folded_dark.png")!
let noPairedDarkImage = UIImage(named: "g1/image_g1_b_brown1_l_no_paired_device_dark.png")!
let caseCloseChargingDarkImage = UIImage(named: "g1/image_g1_l_case_close_charging_dark.png")!
let caseCloseFullDarkImage = UIImage(named: "g1/image_g1_l_case_close_full_dark.png")!
