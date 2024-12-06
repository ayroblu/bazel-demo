let context = getJsContext()
if let context = context {
  print(context.objectForKeyedSubscript("thing"))
}
