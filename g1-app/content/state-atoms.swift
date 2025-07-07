import Foundation
import g1protocol
import Jotai
import Log

let notifDurationSecondsAtom = userDefaultsAtom(state: notifDurationSecondsState)
let notifDurationSecondsDoubleAtom = DoubleUInt8CastAtom(atom: notifDurationSecondsAtom)
let cronTimeEnabledAtom = cronTimeAtom(state: cronTimeEnabledState)
let cronTimeIntervalMinutesAtom = cronTimeAtom(state: cronTimeIntervalMinutesState)

let notifDirectPushAtom = notifConfigAtom(state: notifDirectPushState)
let notifConfigCalendarAtom = notifAllowlistAtom(state: notifConfigCalendarState)
let notifConfigCallAtom = notifAllowlistAtom(state: notifConfigCallState)
let notifConfigMsgAtom = notifAllowlistAtom(state: notifConfigMsgState)
let notifConfigIosMailAtom = notifAllowlistAtom(state: notifConfigIosMailState)
let notifConfigAppsAtom = notifAllowlistAtom(state: notifConfigAppsState)

func cronTimeAtom<T>(state: PersistWithDefaultState<T>) -> WritableAtom<T, T, Void> {
  return userDefaultsAtom(state: state) {
    cronTimer.update()
  }
}

func notifConfigAtom<T>(state: PersistWithDefaultState<T>) -> WritableAtom<T, T, Void> {
  return userDefaultsAtom(state: state) {
    manager.sendNotifConfig()
  }
}
func notifAllowlistAtom<T>(state: PersistWithDefaultState<T>) -> WritableAtom<T, T, Void> {
  return userDefaultsAtom(state: state) {
    manager.sendAllowNotifs()
  }
}

func userDefaultsAtom<T>(state: PersistWithDefaultState<T>, f: (() -> Void)? = nil)
  -> WritableAtom<T, T, Void>
{
  let dataAtom = PrimitiveAtom(state.get())
  return WritableAtom(
    { getter in getter.get(atom: dataAtom) },
    { (setter, value) in
      state.set(value)
      setter.set(atom: dataAtom, value: value)
      f?()
    })
}

func DoubleUInt8CastAtom(atom: PrimitiveAtom<UInt8>, onSet: ((Setter, UInt8) -> Void)? = nil)
  -> WritableAtom<
    Double, Double, Void
  >
{
  return WritableAtom(
    { getter in Double(getter.get(atom: atom)) },
    { (setter, value) in
      setter.set(atom: atom, value: UInt8(value))
      onSet?(setter, UInt8(value))
    })
}
func DoubleUInt8CastAtom(atom: WritableAtom<UInt8, UInt8, Void>, onSet: ((Setter, UInt8) -> Void)? = nil)
  -> WritableAtom<
    Double, Double, Void
  >
{
  return WritableAtom(
    { getter in Double(getter.get(atom: atom)) },
    { (setter, value) in
      setter.set(atom: atom, value: UInt8(value))
      onSet?(setter, UInt8(value))
    })
}
