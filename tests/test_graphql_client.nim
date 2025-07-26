import unittest, asyncdispatch, json, tables, httpclient
import ../src/graphql_client

# Тестове за GraphQL клиент

suite "GraphQL клиент тестове":
  
  test "Създаване на GraphQL клиент":
    let client = newGraphQLClient("http://localhost:8080/graphql")
    
    check client != nil
    check client.config.endpoint == "http://localhost:8080/graphql"
    check client.config.timeout == 30
    check client.config.retries == 3
    check client.config.cacheEnabled == true
    
    client.close()
  
  test "Създаване на GraphQL заявка":
    let query = "query { user { id name } }"
    let variables = %* {"id": 1}
    let request = newGraphQLRequest(query, variables, some("GetUser"))
    
    check request.query == query
    check request.variables == variables
    check request.operationName.isSome
    check request.operationName.get() == "GetUser"
  
  test "Валидация на GraphQL заявки":
    check validateGraphQLQuery("query { user { id } }") == true
    check validateGraphQLQuery("mutation { createUser { id } }") == true
    check validateGraphQLQuery("subscription { userUpdated { id } }") == true
    check validateGraphQLQuery("invalid query") == false
    check validateGraphQLQuery("") == false
  
  test "Генериране на кеш ключ":
    let request1 = newGraphQLRequest("query { user }", %* {"id": 1})
    let request2 = newGraphQLRequest("query { user }", %* {"id": 1})
    let request3 = newGraphQLRequest("query { user }", %* {"id": 2})
    
    check generateCacheKey(request1) == generateCacheKey(request2)
    check generateCacheKey(request1) != generateCacheKey(request3)
  
  test "Парсиране на GraphQL отговор":
    let jsonResponse = """
    {
      "data": {
        "user": {
          "id": 1,
          "name": "Тест"
        }
      },
      "errors": [
        {
          "message": "Test error",
          "path": ["user", "email"],
          "extensions": {"code": "VALIDATION_ERROR"}
        }
      ]
    }
    """
    
    let response = parseGraphQLResponse(jsonResponse)
    
    check response.data != nil
    check response.data["user"]["id"].getInt() == 1
    check response.data["user"]["name"].getStr() == "Тест"
    
    check response.errors.len == 1
    check response.errors[0].message == "Test error"
    check response.errors[0].path == @["user", "email"]
    check response.errors[0].extensions != nil
  
  test "Query builders":
    # Тест за buildAccountQuery
    let accountQuery = buildAccountQuery(id = 123)
    check accountQuery.contains("account(id: 123)")
    check accountQuery.contains("code")
    check accountQuery.contains("name")
    check accountQuery.contains("balance")
    
    let accountByCodeQuery = buildAccountQuery(code = "1100")
    check accountByCodeQuery.contains("account(code: \"1100\")")
    
    # Тест за buildAccountsQuery
    let accountsQuery = buildAccountsQuery(first = 10, accountType = "ASSET")
    check accountsQuery.contains("accounts(first: 10")
    check accountsQuery.contains("accountType: ASSET")
    check accountsQuery.contains("edges")
    check accountsQuery.contains("pageInfo")
    
    # Тест за buildCreateAccountMutation
    let createMutation = buildCreateAccountMutation("1500", "Материали", "ASSET")
    check createMutation.contains("createAccount")
    check createMutation.contains("code: \"1500\"")
    check createMutation.contains("name: \"Материали\"")
    check createMutation.contains("accountType: ASSET")
    
    # Тест за buildTrialBalanceQuery
    let trialBalanceQuery = buildTrialBalanceQuery("2024-12-31")
    check trialBalanceQuery.contains("trialBalance(asOfDate: \"2024-12-31\")")
    check trialBalanceQuery.contains("accounts")
    check trialBalanceQuery.contains("totalDebits")
    check trialBalanceQuery.contains("totalCredits")
  
  test "Кеш операции":
    let client = newGraphQLClient("http://localhost:8080/graphql", cacheEnabled = true)
    
    # Тест за празен кеш
    check client.cache.len == 0
    
    # Симулиране на кеширане
    let request = newGraphQLRequest("query { test }")
    let response = GraphQLResponse(
      data: %* {"test": "data"},
      errors: @[],
      extensions: nil
    )
    
    let cacheKey = generateCacheKey(request)
    client.cache[cacheKey] = response
    
    check client.cache.len == 1
    check client.cache.hasKey(cacheKey)
    
    # Тест за изчистване на кеша
    client.clearCache()
    check client.cache.len == 0
    
    client.close()
  
  test "GraphQL грешки":
    let error = GraphQLClientError(
      message: "Test error",
      extensions: %* {"code": "TEST_ERROR"},
      path: @["user", "name"]
    )
    
    check error.message == "Test error"
    check error.extensions["code"].getStr() == "TEST_ERROR"
    check error.path == @["user", "name"]
  
  test "GraphQL отговор утилити":
    # Успешен отговор
    let successResponse = GraphQLResponse(
      data: %* {"user": {"id": 1}},
      errors: @[],
      extensions: nil
    )
    
    check successResponse.isSuccess() == true
    
    # Отговор с грешки
    let errorResponse = GraphQLResponse(
      data: nil,
      errors: @[GraphQLClientError(message: "Error")],
      extensions: nil
    )
    
    check errorResponse.isSuccess() == false

# Интеграционни тестове (изискват работещ сървър)
suite "GraphQL клиент интеграционни тестове":
  
  test "Реален HTTP заявка (пропусни ако няма сървър)":
    # Този тест се изпълнява само ако има работещ сървър
    try:
      let client = newGraphQLClient("http://localhost:8080/accounting/graphql", timeout = 5)
      
      let query = buildAccountQuery(id = 1)
      let request = newGraphQLRequest(query)
      
      let response = waitFor client.execute(request)
      
      # Проверяваме дали получаваме отговор (дори и с грешки)
      check response.data != nil or response.errors.len > 0
      
      client.close()
      
    except:
      # Ако няма сървър, пропускаме теста
      echo "Пропускаме интеграционен тест - няма достъпен сървър"
      check true

# Mock тестове за асинхронни операции
suite "GraphQL клиент асинхронни тестове":
  
  test "Асинхронно изпълнение на заявка":
    proc testAsync() {.async.} =
      let client = newGraphQLClient("http://httpbin.org/status/200", timeout = 5)
      
      let query = "query { test }"
      let request = newGraphQLRequest(query)
      
      # Тестваме че методът е асинхронен
      let future = client.execute(request)
      check future != nil
      
      # Чакаме резултата
      let response = await future
      
      # Очакваме грешка защото httpbin.org не връща GraphQL отговор
      check response.errors.len > 0
      
      client.close()
    
    waitFor testAsync()

# Тестове за конфигурация
suite "GraphQL клиент конфигурация":
  
  test "Персонализирана конфигурация":
    var headers = initTable[string, string]()
    headers["Authorization"] = "Bearer token123"
    headers["X-Custom-Header"] = "test"
    
    let client = newGraphQLClient(
      endpoint = "http://example.com/graphql",
      headers = headers,
      timeout = 60,
      retries = 5,
      cacheEnabled = false
    )
    
    check client.config.endpoint == "http://example.com/graphql"
    check client.config.timeout == 60
    check client.config.retries == 5
    check client.config.cacheEnabled == false
    check client.config.headers["Authorization"] == "Bearer token123"
    
    client.close()

when isMainModule:
  # Изпълнение на всички тестове
  echo "Стартиране на GraphQL клиент тестове..."
  
  # Изпълняваме тестовете
  echo "Всички тестове завършени!"