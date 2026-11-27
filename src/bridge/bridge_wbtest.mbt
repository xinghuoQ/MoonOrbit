///|
test "bridge smoke" {
  assert_eq(bridge_status(), "parser: ready | graph: ready | layout: ready")
}
