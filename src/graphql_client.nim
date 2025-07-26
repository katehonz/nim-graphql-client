import httpclient, json, asyncdispatch, uri, strutils, tables, options
import std/[logging, base64]
when defined(js):
  import dom, jsffi, jsconsole
  
# GraphQL клиент за Nim с Karax поддръжка
# Поддържа синхронни/асинхронни заявки, subscriptions и кеширане

type
  GraphQLClientError* = object of CatchableError
    extensions*: JsonNode
    path*: seq[string]
    
  GraphQLResponse* = object
    data*: JsonNode
    errors*: seq[GraphQLClientError]
    extensions*: JsonNode
    
  GraphQLRequest* = object
    query*: string
    variables*: JsonNode
    operationName*: Option[string]
    
  GraphQLClientConfig* = object
    endpoint*: string
    headers*: Table[string, string]
    timeout*: int  # в секунди
    retries*: int
    cacheEnabled*: bool
    
  GraphQLClient* = ref object
    config*: GraphQLClientConfig
    httpClient*: HttpClient
    cache*: Table[string, GraphQLResponse]
    subscriptions*: Table[string, proc(data: JsonNode)]
    
  # Типове за subscription клиента (browser-based)
  WebSocketConnection* = object
    url*: string
    protocols*: seq[string]
    
  SubscriptionClient* = ref object
    connection*: WebSocketConnection
    callbacks*: Table[string, proc(data: JsonNode)]

# Конструктори
proc newGraphQLClient*(endpoint: string, headers: Table[string, string] = initTable[string, string](), 
                      timeout: int = 30, retries: int = 3, cacheEnabled: bool = true): GraphQLClient =
  ## Създава нов GraphQL клиент
  result = GraphQLClient(
    config: GraphQLClientConfig(
      endpoint: endpoint,
      headers: headers,
      timeout: timeout,
      retries: retries,
      cacheEnabled: cacheEnabled
    ),
    httpClient: newHttpClient(timeout = timeout * 1000),
    cache: initTable[string, GraphQLResponse](),
    subscriptions: initTable[string, proc(data: JsonNode)]()
  )
  
  # Добавяне на основни headers
  for key, value in result.config.headers:
    result.httpClient.headers[key] = value
  
  result.httpClient.headers["Content-Type"] = "application/json"
  result.httpClient.headers["Accept"] = "application/json"

proc newGraphQLRequest*(query: string, variables: JsonNode = newJObject(), 
                       operationName: Option[string] = none(string)): GraphQLRequest =
  ## Създава нова GraphQL заявка
  result = GraphQLRequest(
    query: query,
    variables: variables,
    operationName: operationName
  )

# Помощни функции
proc generateCacheKey(request: GraphQLRequest): string =
  ## Генерира ключ за кеширане
  result = request.query & "|" & $request.variables & "|" & $request.operationName

proc parseGraphQLResponse(jsonStr: string): GraphQLResponse =
  ## Парсира GraphQL отговор от JSON
  let jsonData = parseJson(jsonStr)
  
  result.data = jsonData{"data"}
  result.extensions = jsonData{"extensions"}
  
  # Парсиране на грешки
  if jsonData.hasKey("errors") and jsonData{"errors"}.kind == JArray:
    for errorJson in jsonData{"errors"}:
      var error = GraphQLClientError(message: errorJson{"message"}.getStr("Unknown error"))
      
      if errorJson.hasKey("extensions"):
        error.extensions = errorJson{"extensions"}
      
      if errorJson.hasKey("path") and errorJson{"path"}.kind == JArray:
        for pathItem in errorJson{"path"}:
          error.path.add(pathItem.getStr())
      
      result.errors.add(error)

proc validateGraphQLQuery*(query: string): bool =
  ## Прост валидатор за GraphQL заявки
  if query.len == 0:
    return false
    
  # Проверява за основни GraphQL ключови думи
  let normalizedQuery = query.toLower().replace(" ", "").replace("\n", "")
  
  return normalizedQuery.contains("query") or 
         normalizedQuery.contains("mutation") or 
         normalizedQuery.contains("subscription")

# Основни методи за заявки
proc execute*(client: GraphQLClient, request: GraphQLRequest): Future[GraphQLResponse] {.async.} =
  ## Изпълнява GraphQL заявка асинхронно
  let cacheKey = generateCacheKey(request)
  
  # Проверка в кеша
  if client.config.cacheEnabled and client.cache.hasKey(cacheKey):
    return client.cache[cacheKey]
  
  # Валидация на заявката
  if not validateGraphQLQuery(request.query):
    var error = GraphQLClientError(message: "Invalid GraphQL query")
    result.errors.add(error)
    return result
  
  # Подготовка на данните
  var requestData = %* {
    "query": request.query,
    "variables": request.variables
  }
  
  if request.operationName.isSome:
    requestData["operationName"] = %request.operationName.get()
  
  var attempts = 0
  var lastError: ref Exception = nil
  
  # Retry логика
  while attempts <= client.config.retries:
    try:
      let response = await client.httpClient.post(client.config.endpoint, $requestData)
      
      if response.code == Http200:
        result = parseGraphQLResponse(response.body)
        
        # Кеширане на успешни резултати
        if client.config.cacheEnabled and result.errors.len == 0:
          client.cache[cacheKey] = result
        
        return result
      else:
        var error = GraphQLClientError(message: "HTTP Error: " & $response.code & " - " & response.body)
        result.errors.add(error)
        return result
        
    except Exception as e:
      lastError = e
      attempts += 1
      if attempts <= client.config.retries:
        await sleepAsync(1000 * attempts)  # Exponential backoff
  
  # Ако всички опити са неуспешни
  var error = GraphQLClientError(message: "Request failed after " & $client.config.retries & " retries: " & lastError.msg)
  result.errors.add(error)

proc executeSync*(client: GraphQLClient, request: GraphQLRequest): GraphQLResponse =
  ## Изпълнява GraphQL заявка синхронно
  return waitFor client.execute(request)

# Query builders за популярни заявки
proc buildAccountQuery*(id: int = 0, code: string = ""): string =
  ## Създава заявка за получаване на сметка
  var args = ""
  if id > 0:
    args = "id: " & $id
  elif code.len > 0:
    args = "code: \"" & code & "\""
  else:
    return ""
  
  result = """
    query GetAccount {
      account(""" & args & """) {
        id
        code
        name
        accountType
        balance {
          amount
          currency
        }
        isActive
        createdAt
        updatedAt
      }
    }
  """

proc buildAccountsQuery*(first: int = 10, after: string = "", accountType: string = ""): string =
  ## Създава заявка за списък със сметки
  var args = "first: " & $first
  
  if after.len > 0:
    args &= ", after: \"" & after & "\""
  
  if accountType.len > 0:
    args &= ", accountType: " & accountType
  
  result = """
    query GetAccounts {
      accounts(""" & args & """) {
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
            isActive
          }
          cursor
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        totalCount
      }
    }
  """

proc buildCreateAccountMutation*(code: string, name: string, accountType: string): string =
  ## Създава мутация за създаване на сметка
  result = """
    mutation CreateAccount {
      createAccount(input: {
        code: \"""" & code & """\"
        name: \"""" & name & """\"
        accountType: """ & accountType & """
      }) {
        id
        code
        name
        accountType
        balance {
          amount
          currency
        }
        isActive
        createdAt
        updatedAt
      }
    }
  """

proc buildTrialBalanceQuery*(asOfDate: string): string =
  ## Създава заявка за оборотна ведомост
  result = """
    query TrialBalance {
      trialBalance(asOfDate: \"""" & asOfDate & """\") {
        asOfDate
        accounts {
          accountCode
          accountName
          debitBalance {
            amount
            currency
          }
          creditBalance {
            amount
            currency
          }
        }
        totalDebits {
          amount
          currency
        }
        totalCredits {
          amount
          currency
        }
        isBalanced
      }
    }
  """

# Удобни методи за често използвани операции
proc getAccount*(client: GraphQLClient, id: int): Future[JsonNode] {.async.} =
  ## Получава сметка по ID
  let query = buildAccountQuery(id = id)
  let request = newGraphQLRequest(query)
  let response = await client.execute(request)
  
  if response.errors.len > 0:
    raise newException(GraphQLClientError, response.errors[0].message)
  
  result = response.data{"account"}

proc getAccountByCode*(client: GraphQLClient, code: string): Future[JsonNode] {.async.} =
  ## Получава сметка по код
  let query = buildAccountQuery(code = code)
  let request = newGraphQLRequest(query)
  let response = await client.execute(request)
  
  if response.errors.len > 0:
    raise newException(GraphQLClientError, response.errors[0].message)
  
  result = response.data{"account"}

proc getAccounts*(client: GraphQLClient, first: int = 10, after: string = "", 
                 accountType: string = ""): Future[JsonNode] {.async.} =
  ## Получава списък със сметки
  let query = buildAccountsQuery(first, after, accountType)
  let request = newGraphQLRequest(query)
  let response = await client.execute(request)
  
  if response.errors.len > 0:
    raise newException(GraphQLClientError, response.errors[0].message)
  
  result = response.data{"accounts"}

proc createAccount*(client: GraphQLClient, code: string, name: string, 
                   accountType: string): Future[JsonNode] {.async.} =
  ## Създава нова сметка
  let query = buildCreateAccountMutation(code, name, accountType)
  let request = newGraphQLRequest(query)
  let response = await client.execute(request)
  
  if response.errors.len > 0:
    raise newException(GraphQLClientError, response.errors[0].message)
  
  result = response.data{"createAccount"}

proc getTrialBalance*(client: GraphQLClient, asOfDate: string): Future[JsonNode] {.async.} =
  ## Получава оборотна ведомост
  let query = buildTrialBalanceQuery(asOfDate)
  let request = newGraphQLRequest(query)
  let response = await client.execute(request)
  
  if response.errors.len > 0:
    raise newException(GraphQLClientError, response.errors[0].message)
  
  result = response.data{"trialBalance"}

# Кеш управление
proc clearCache*(client: GraphQLClient) =
  ## Изчиства кеша на клиента
  client.cache.clear()

proc removeCacheEntry*(client: GraphQLClient, request: GraphQLRequest) =
  ## Премахва конкретен запис от кеша
  let cacheKey = generateCacheKey(request)
  client.cache.del(cacheKey)

# Затваряне на ресурси
proc close*(client: GraphQLClient) =
  ## Затваря HTTP клиента и освобождава ресурси
  client.httpClient.close()

# Браузърни subscription функции (само за JS target)
when defined(js):
  proc createWebSocketConnection*(url: string): WebSocketConnection =
    ## Създава WebSocket връзка за subscriptions
    result = WebSocketConnection(
      url: url,
      protocols: @["graphql-ws"]
    )
  
  proc subscribe*(client: GraphQLClient, query: string, 
                 callback: proc(data: JsonNode), variables: JsonNode = newJObject()) =
    ## Започва subscription за real-time обновления
    let subscriptionId = query & "|" & $variables
    client.subscriptions[subscriptionId] = callback
    
    # WebSocket логика ще бъде имплементирана отделно
    console.log("Subscription started: ", subscriptionId)
  
  proc unsubscribe*(client: GraphQLClient, query: string, variables: JsonNode = newJObject()) =
    ## Спира subscription
    let subscriptionId = query & "|" & $variables
    client.subscriptions.del(subscriptionId)
    console.log("Subscription stopped: ", subscriptionId)

# Debug функции
proc printResponse*(response: GraphQLResponse) =
  ## Принтира GraphQL отговор за debug
  echo "GraphQL Response:"
  echo "  Data: ", if response.data != nil: $response.data else: "null"
  
  if response.errors.len > 0:
    echo "  Errors:"
    for error in response.errors:
      echo "    - ", error.message
      if error.path.len > 0:
        echo "      Path: ", error.path.join(" -> ")
  
  if response.extensions != nil:
    echo "  Extensions: ", $response.extensions

proc isSuccess*(response: GraphQLResponse): bool =
  ## Проверява дали отговорът е успешен
  result = response.errors.len == 0 and response.data != nil