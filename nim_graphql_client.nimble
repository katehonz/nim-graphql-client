# Package

version       = "1.0.0"
author        = "z-prologue team"
description   = "GraphQL client for Nim with Karax integration"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @[]

# Dependencies

requires "nim >= 1.6.0"
requires "karax >= 1.3.0"

# Tasks

task test, "Run tests":
  exec "nim c -r tests/test_graphql_client.nim"

task docs, "Generate documentation":
  exec "nim doc --project --index:on --outdir:docs src/graphql_client.nim"
  exec "nim doc --project --index:on --outdir:docs src/karax_integration.nim"

task example_basic, "Run basic usage example":
  exec "nim c -r examples/basic_usage.nim"

task example_karax, "Compile Karax example for browser":
  exec "nim js -d:release -o:examples/karax_app.js examples/karax_app.nim"

task test_public, "Test with public GraphQL APIs":
  exec "nim c -d:ssl -r test_quick.nim"

task example_public, "Run public API examples":
  exec "nim c -d:ssl -r examples/public_api_example.nim"

task example_advanced, "Run advanced usage examples":
  exec "nim c -d:ssl -r examples/advanced_usage.nim"

task clean, "Clean generated files":
  exec "rm -rf docs/"
  exec "rm -f examples/*.js"
  exec "rm -f tests/test_*"
  exec "rm -f test_quick"
  exec "rm -f examples/public_api_example"
  exec "rm -f examples/advanced_usage"

# Browser compilation settings
when defined(js):
  switch("define", "nodejs")
  switch("define", "ssl")