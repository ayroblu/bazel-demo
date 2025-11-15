import Jotai

@MainActor
public func userDefaultsAtom<T>(state: PersistWithDefaultState<T>, f: (() -> Void)? = nil)
  -> SimpleWritableAtom<T>
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
@MainActor
public func userDefaultsAtom<T>(state: PersistCodableWithDefaultState<T>, f: (() -> Void)? = nil)
  -> SimpleWritableAtom<T>
{
  let dataAtom = PrimitiveAtom(try! state.get())
  return WritableAtom(
    { getter in getter.get(atom: dataAtom) },
    { (setter, value) in
      try? state.set(value)
      setter.set(atom: dataAtom, value: value)
      f?()
    })
}
@MainActor
public func userDefaultsAtom<T>(state: Persist<T>, f: (() -> Void)? = nil) -> SimpleWritableAtom<T?>
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
