///|
/// Placeholder for the JS bridge. It calls every core package so the
/// cross-package wiring is exercised from the first build.
pub fn bridge_status() -> String {
  @parser.parser_status() + " | " + @graph.graph_status() + " | " + @layout.layout_status()
}
