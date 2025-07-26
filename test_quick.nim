import src/graphql_client
import asyncdispatch, json

# Бърз тест с публично GraphQL API

proc quickTest() {.async.} =
  echo "Quick GraphQL Client Test"
  echo "========================"
  
  # Използваме Countries API - винаги е достъпно и безплатно
  let client = newGraphQLClient("https://countries.trevorblades.com/graphql")
  
  # Проста заявка
  let query = """
    query {
      country(code: "BG") {
        name
        capital
        emoji
        currency
      }
    }
  """
  
  echo "\nSending query to Countries API..."
  let request = newGraphQLRequest(query)
  let response = await client.execute(request)
  
  if response.isSuccess():
    echo "\n✓ Success!"
    echo "Response data:"
    echo pretty(response.data)
  else:
    echo "\n✗ Failed!"
    echo "Errors:"
    for error in response.errors:
      echo "  - ", error.msg
  
  client.close()
  echo "\nTest completed!"

when isMainModule:
  waitFor quickTest()