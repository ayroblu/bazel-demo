import jotai

let headsUpDashInternalAtom = PrimitiveAtom(true)
let headsUpDashAtom = WritableAtom<Bool, Bool, Void>(
    { getter in getter.get(atom: headsUpDashInternalAtom) },
    { (setter, value) in
      setter.set(atom: headsUpDashInternalAtom, value: value)
      manager.headsUpConfig(value ? .dashboard : .none)
    })
