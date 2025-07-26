import ../src/graphql_client
import asyncdispatch, json, tables, logging, times

# Пример за напреднала употреба на GraphQL клиента

# Конфигуриране на logging
var logger = newConsoleLogger()
addHandler(logger)

proc advancedExample() {.async.} =
  echo "=== GraphQL Client Advanced Usage Example ==="
  echo ""
  
  # 1. Създаване на клиент с персонализирана конфигурация
  echo "1. Creating client with custom configuration..."
  var headers = initTable[string, string]()
  headers["Authorization"] = "Bearer your-jwt-token"
  headers["X-Request-ID"] = $now().toTime().toUnix()
  
  let client = newGraphQLClient(
    endpoint = "http://localhost:8080/accounting/graphql",
    headers = headers,
    timeout = 60,
    retries = 5,
    cacheEnabled = true
  )
  
  # 2. Изпълнение на персонализирана заявка с променливи
  echo "2. Executing custom query with variables..."
  let customQuery = """
    query GetAccountsWithFilter($filter: AccountFilter!, $pagination: PaginationInput) {
      accounts(filter: $filter, pagination: $pagination) {
        edges {
          node {
            id
            code
            name
            accountType
            balance {
              amount
              currency
            }
            metadata
          }
          cursor
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          totalCount
        }
      }
    }
  """
  
  let variables = %* {
    "filter": {
      "accountTypes": ["ASSET", "LIABILITY"],
      "isActive": true,
      "balanceGreaterThan": "1000.00"
    },
    "pagination": {
      "first": 20,
      "after": nil
    }
  }
  
  let request = newGraphQLRequest(customQuery, variables, some("GetFilteredAccounts"))
  
  try:
    let response = await client.execute(request)
    
    if response.isSuccess():
      echo "Success! Found ", response.data["accounts"]["pageInfo"]["totalCount"], " accounts"
      
      # Обработка на резултатите
      for edge in response.data["accounts"]["edges"]:
        let node = edge["node"]
        echo "  - ", node["code"].getStr(), ": ", node["name"].getStr(), 
             " (", node["balance"]["amount"].getStr(), " ", node["balance"]["currency"].getStr(), ")"
    else:
      echo "Query failed with errors:"
      for error in response.errors:
        echo "  - ", error.message
        if error.extensions != nil:
          echo "    Code: ", error.extensions["code"].getStr()
  except Exception as e:
    echo "Exception: ", e.msg
  
  # 3. Batch заявки
  echo "\n3. Executing batch queries..."
  let batchQueries = @[
    ("account1", buildAccountQuery(code = "1100")),
    ("account2", buildAccountQuery(code = "1200")),
    ("trialBalance", buildTrialBalanceQuery($now().format("yyyy-MM-dd")))
  ]
  
  var batchResults = initTable[string, JsonNode]()
  
  for (name, query) in batchQueries:
    let req = newGraphQLRequest(query)
    let resp = await client.execute(req)
    if resp.isSuccess():
      batchResults[name] = resp.data
  
  echo "Batch results collected: ", batchResults.len, " queries"
  
  # 4. Мутация с обработка на грешки
  echo "\n4. Executing mutation with error handling..."
  let createAccountMutation = """
    mutation CreateAccountWithValidation($input: CreateAccountInput!) {
      createAccount(input: $input) {
        account {
          id
          code
          name
        }
        errors {
          field
          message
        }
      }
    }
  """
  
  let mutationVars = %* {
    "input": {
      "code": "9999",
      "name": "Test Account " & $now().toTime().toUnix(),
      "accountType": "ASSET",
      "currency": "BGN",
      "metadata": {
        "createdBy": "advanced_example",
        "purpose": "testing"
      }
    }
  }
  
  let mutationReq = newGraphQLRequest(createAccountMutation, mutationVars)
  let mutationResp = await client.execute(mutationReq)
  
  if mutationResp.isSuccess():
    let result = mutationResp.data["createAccount"]
    if result.hasKey("errors") and result["errors"].len > 0:
      echo "Validation errors:"
      for error in result["errors"]:
        echo "  - ", error["field"].getStr(), ": ", error["message"].getStr()
    else:
      echo "Account created successfully:"
      echo "  ID: ", result["account"]["id"].getInt()
      echo "  Code: ", result["account"]["code"].getStr()
      echo "  Name: ", result["account"]["name"].getStr()
  
  # 5. Работа с кеша
  echo "\n5. Working with cache..."
  
  # Първо извикване - ще се кешира
  let accountReq = newGraphQLRequest(buildAccountQuery(code = "1100"))
  let firstCall = now()
  discard await client.execute(accountReq)
  let firstDuration = (now() - firstCall).inMilliseconds
  
  # Второ извикване - от кеша
  let secondCall = now()
  discard await client.execute(accountReq)
  let secondDuration = (now() - secondCall).inMilliseconds
  
  echo "First call duration: ", firstDuration, "ms"
  echo "Second call duration: ", secondDuration, "ms (from cache)"
  
  # Изчистване на специфичен кеш запис
  client.removeCacheEntry(accountReq)
  echo "Cache entry removed"
  
  # 6. Паралелни заявки
  echo "\n6. Executing parallel queries..."
  let parallelStart = now()
  
  let futures = @[
    client.getAccount(1),
    client.getAccountByCode("1100"),
    client.getAccounts(first = 5, accountType = "ASSET"),
    client.getTrialBalance($now().format("yyyy-MM-dd"))
  ]
  
  # Изчакваме всички да завършат
  let results = await all(futures)
  let parallelDuration = (now() - parallelStart).inMilliseconds
  
  echo "Executed ", futures.len, " queries in parallel"
  echo "Total duration: ", parallelDuration, "ms"
  
  # 7. Streaming резултати с пагинация
  echo "\n7. Streaming paginated results..."
  var allAccounts: seq[JsonNode] = @[]
  var cursor: string = ""
  var hasMore = true
  var pageCount = 0
  
  while hasMore and pageCount < 5:  # Лимит от 5 страници
    let pageResp = await client.getAccounts(first = 10, after = cursor)
    
    for edge in pageResp["edges"]:
      allAccounts.add(edge["node"])
    
    hasMore = pageResp["pageInfo"]["hasNextPage"].getBool()
    if hasMore:
      cursor = pageResp["edges"][^1]["cursor"].getStr()
    
    pageCount += 1
    echo "  Loaded page ", pageCount, " (", allAccounts.len, " accounts total)"
  
  echo "Total accounts loaded: ", allAccounts.len
  
  # 8. Транзакция с multiple mutations
  echo "\n8. Executing transaction with multiple mutations..."
  let transactionMutation = """
    mutation ExecuteComplexTransaction($entries: [JournalEntryInput!]!) {
      createJournalEntries(entries: $entries) {
        success
        transaction {
          id
          transactionNumber
          totalAmount
          status
        }
        errors {
          message
        }
      }
    }
  """
  
  let transactionVars = %* {
    "entries": [
      {
        "accountCode": "1100",
        "debit": "1000.00",
        "credit": "0.00",
        "description": "Test debit entry"
      },
      {
        "accountCode": "2100", 
        "debit": "0.00",
        "credit": "1000.00",
        "description": "Test credit entry"
      }
    ]
  }
  
  let transactionReq = newGraphQLRequest(transactionMutation, transactionVars)
  let transactionResp = await client.execute(transactionReq)
  
  if transactionResp.isSuccess():
    let result = transactionResp.data["createJournalEntries"]
    if result["success"].getBool():
      echo "Transaction completed successfully:"
      echo "  ID: ", result["transaction"]["id"].getInt()
      echo "  Number: ", result["transaction"]["transactionNumber"].getStr()
    else:
      echo "Transaction failed:"
      for error in result["errors"]:
        echo "  - ", error["message"].getStr()
  
  # Затваряне на клиента
  echo "\n9. Cleaning up..."
  client.clearCache()
  client.close()
  echo "Client closed successfully"

proc errorHandlingExample() {.async.} =
  echo "\n=== Error Handling Example ==="
  
  let client = newGraphQLClient("http://localhost:8080/accounting/graphql")
  
  # Пример с различни типове грешки
  let scenarios = @[
    ("Invalid Query", "INVALID { syntax"),
    ("Non-existent Field", "query { account(id: 1) { nonExistentField } }"),
    ("Type Mismatch", "query { account(id: \"not-a-number\") { id } }")
  ]
  
  for (name, query) in scenarios:
    echo "\nTesting: ", name
    let req = newGraphQLRequest(query)
    
    try:
      let resp = await client.execute(req)
      
      if resp.isSuccess():
        echo "  Unexpected success!"
      else:
        echo "  Errors detected:"
        for error in resp.errors:
          echo "    - ", error.message
          if error.path.len > 0:
            echo "      Path: ", error.path.join(" -> ")
          if error.extensions != nil and error.extensions.hasKey("code"):
            echo "      Code: ", error.extensions["code"].getStr()
    except GraphQLClientError as e:
      echo "  GraphQL Error: ", e.msg
    except Exception as e:
      echo "  General Error: ", e.msg
  
  client.close()

proc performanceExample() {.async.} =
  echo "\n=== Performance Testing Example ==="
  
  let client = newGraphQLClient(
    "http://localhost:8080/accounting/graphql",
    cacheEnabled = true
  )
  
  # Тест производителност със и без кеш
  echo "\n1. Cache performance test..."
  
  proc measureQueryTime(client: GraphQLClient, query: string, useCache: bool): Future[int] {.async.} =
    if not useCache:
      client.clearCache()
    
    let start = now()
    let req = newGraphQLRequest(query)
    discard await client.execute(req)
    result = (now() - start).inMilliseconds
  
  let testQuery = buildAccountsQuery(first = 50)
  
  # Без кеш
  var noCacheTimes: seq[int] = @[]
  for i in 1..5:
    noCacheTimes.add(await measureQueryTime(client, testQuery, false))
  
  # С кеш
  var cacheTimes: seq[int] = @[]
  for i in 1..5:
    cacheTimes.add(await measureQueryTime(client, testQuery, true))
  
  echo "Without cache (ms): ", noCacheTimes
  echo "With cache (ms): ", cacheTimes
  
  let avgNoCache = noCacheTimes.foldl(a + b) div noCacheTimes.len
  let avgCache = cacheTimes.foldl(a + b) div cacheTimes.len
  
  echo "Average without cache: ", avgNoCache, "ms"
  echo "Average with cache: ", avgCache, "ms"
  echo "Cache speedup: ", formatFloat(avgNoCache / avgCache, ffDecimal, 2), "x"
  
  client.close()

# Главна функция
proc main() {.async.} =
  try:
    await advancedExample()
    await errorHandlingExample()
    await performanceExample()
  except Exception as e:
    echo "\nFatal error: ", e.msg
    echo "Make sure the GraphQL server is running on http://localhost:8080"

when isMainModule:
  echo "Starting GraphQL Client Advanced Examples..."
  echo "Make sure your GraphQL server is running!"
  echo ""
  
  waitFor main()
  
  echo "\nAll examples completed!"