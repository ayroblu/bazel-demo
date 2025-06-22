import SwiftUI
import g1protocol
import jotai

struct GlassesInfoView: View {
  @Environment(\.colorScheme) var colorScheme
  @AtomState(glassesStateAtom) var glassesState: GlassesState
  @AtomValue(batteryAtom) var battery: Int?
  @AtomState(chargingAtom) var charging: Bool
  @AtomState(caseBatteryAtom) var caseBattery: Int?
  let glasses: GlassesModel

  var body: some View {
    ZStack {
      Image(
        uiImage: getImage(
          store: JotaiStore.shared, glassesState: glassesState, isDark: colorScheme == .dark)
      )
      .resizable()
      .aspectRatio(contentMode: .fit)
      VStack {
        if let battery {
          HStack {
            Spacer()
            Image(
              systemName: charging
                ? "battery.100percent.bolt" : getBatterySymbol(battery: battery))
            Text("\(battery)%")
          }
        }
        switch glassesState {
        case .CaseOpen, .CaseClosed:
          if let battery = caseBattery {
            HStack {
              Spacer()
              Image(
                systemName: charging
                  ? "battery.100percent.bolt" : getBatterySymbol(battery: battery))
              Text("\(battery)%")
            }
          }
        default:
          EmptyView()
        }
        Spacer()
      }
    }
    .onTapGesture {
      bluetoothManager.syncKnown(glasses: (glasses.left, glasses.right))
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

func getImage(store: JotaiStore, glassesState: GlassesState, isDark: Bool) -> UIImage {
  let images = GlassesImages(isDark: isDark)
  if store.get(atom: isConnectedAtom) {
    switch glassesState {
    case .Off:
      return images.folded
    case .Wearing:
      return images.wearing
    case .CaseOpen:
      if store.get(atom: caseBatteryAtom) != 100 {
        return images.caseOpenCharging
      } else {
        return images.caseOpenFull
      }
    case .CaseClosed:
      if store.get(atom: caseBatteryAtom) != 100 {
        return images.caseCloseCharging
      } else {
        return images.caseCloseFull
      }
    }
  } else {
    return images.noPaired
  }
}
struct GlassesImages {
  let isDark: Bool
  var caseOpenCharging: UIImage { isDark ? caseOpenChargingDarkImage : caseOpenChargingImage }
  var caseOpenFull: UIImage { isDark ? caseOpenFullDarkImage : caseOpenFullImage }
  var folded: UIImage { isDark ? foldedDarkImage : foldedImage }
  var noPaired: UIImage { isDark ? noPairedDarkImage : noPairedImage }
  var wearing: UIImage { isDark ? wearingDarkImage : wearingImage }
  var caseCloseCharging: UIImage { isDark ? caseCloseChargingDarkImage : caseCloseChargingImage }
  var caseCloseFull: UIImage { isDark ? caseCloseFullDarkImage : caseCloseFullImage }
}
let caseOpenChargingImage = UIImage(named: "g1/image_g1_b_brown1_l_case_open_charging.png")!
let caseOpenFullImage = UIImage(named: "g1/image_g1_b_brown1_l_case_open_full.png")!
let foldedImage = UIImage(named: "g1/image_g1_b_brown1_l_folded.png")!
let noPairedImage = UIImage(named: "g1/image_g1_b_brown1_l_no_paired_device.png")!
let wearingImage = UIImage(named: "g1/image_g1_b_brown1_l_wearing.png")!
let caseCloseChargingImage = UIImage(named: "g1/image_g1_l_case_close_charging.png")!
let caseCloseFullImage = UIImage(named: "g1/image_g1_l_case_close_full.png")!

let caseOpenChargingDarkImage = UIImage(
  named: "g1/image_g1_b_brown1_l_case_open_charging_dark.png")!
let caseOpenFullDarkImage = UIImage(named: "g1/image_g1_b_brown1_l_case_open_full_dark.png")!
let foldedDarkImage = UIImage(named: "g1/image_g1_b_brown1_l_folded_dark.png")!
let noPairedDarkImage = UIImage(named: "g1/image_g1_b_brown1_l_no_paired_device_dark.png")!
let wearingDarkImage = UIImage(named: "g1/image_g1_b_brown1_l_wearing_dark.png")!
let caseCloseChargingDarkImage = UIImage(named: "g1/image_g1_l_case_close_charging_dark.png")!
let caseCloseFullDarkImage = UIImage(named: "g1/image_g1_l_case_close_full_dark.png")!
