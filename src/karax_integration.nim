import karax / [karax, kdom, kajax, vdom]
import asyncjs, json, strutils, tables, options
import graphql_client

# Karax интеграция за GraphQL клиент
# Осигурява реактивни компоненти и state management

type
  # State management типове
  GraphQLState*[T] = ref object
    data*: Option[T]
    loading*: bool
    error*: Option[string]
    lastFetch*: float  # timestamp
    
  # Hook типове за Karax
  GraphQLHookResult*[T] = object
    data*: Option[T]
    loading*: bool
    error*: Option[string]
    refetch*: proc()
    
  # Subscription state
  SubscriptionState*[T] = ref object
    data*: Option[T]
    connected*: bool
    error*: Option[string]
    
  # Кеш за заявки
  QueryCache* = ref object
    cache*: Table[string, JsonNode]
    timestamps*: Table[string, float]
    maxAge*: float  # в секунди
    
  # Глобален GraphQL контекст за Karax
  KaraxGraphQLContext* = ref object
    client*: GraphQLClient
    cache*: QueryCache
    subscriptions*: Table[string, SubscriptionState[JsonNode]]

# Глобални променливи
var globalContext*: KaraxGraphQLContext = nil

# Инициализация на контекста
proc initKaraxGraphQL*(endpoint: string, headers: Table[string, string] = initTable[string, string]()): KaraxGraphQLContext =
  ## Инициализира глобален GraphQL контекст за Karax
  result = KaraxGraphQLContext(
    client: newGraphQLClient(endpoint, headers),
    cache: QueryCache(
      cache: initTable[string, JsonNode](),
      timestamps: initTable[string, float](),
      maxAge: 300.0  # 5 минути default cache
    ),
    subscriptions: initTable[string, SubscriptionState[JsonNode]]()
  )
  globalContext = result

proc getContext*(): KaraxGraphQLContext =
  ## Получава глобалния GraphQL контекст
  if globalContext == nil:
    raise newException(ValueError, "GraphQL context not initialized. Call initKaraxGraphQL first.")
  result = globalContext

# Кеш управление
proc isExpired(cache: QueryCache, key: string): bool =
  ## Проверява дали кеш записът е изтекъл
  if not cache.timestamps.hasKey(key):
    return true
  
  let now = epochTime()
  let timestamp = cache.timestamps[key]
  result = (now - timestamp) > cache.maxAge

proc getCached(cache: QueryCache, key: string): Option[JsonNode] =
  ## Получава данни от кеша ако не са изтекли
  if cache.cache.hasKey(key) and not cache.isExpired(key):
    result = some(cache.cache[key])
  else:
    result = none(JsonNode)

proc setCached(cache: QueryCache, key: string, data: JsonNode) =
  ## Записва данни в кеша
  cache.cache[key] = data
  cache.timestamps[key] = epochTime()

# State management функции
proc newGraphQLState*[T](): GraphQLState[T] =
  ## Създава ново GraphQL state
  result = GraphQLState[T](
    data: none(T),
    loading: false,
    error: none(string),
    lastFetch: 0.0
  )

proc setLoading*[T](state: GraphQLState[T], loading: bool) =
  ## Задава loading състояние
  state.loading = loading
  if loading:
    state.error = none(string)

proc setData*[T](state: GraphQLState[T], data: T) =
  ## Задава данни и приключва loading
  state.data = some(data)
  state.loading = false
  state.error = none(string)
  state.lastFetch = epochTime()

proc setError*[T](state: GraphQLState[T], error: string) =
  ## Задава грешка и приключва loading
  state.error = some(error)
  state.loading = false

# Hook функции за заявки
proc useQuery*(query: string, variables: JsonNode = newJObject(), 
               cacheKey: string = ""): GraphQLHookResult[JsonNode] =
  ## Hook за изпълнение на GraphQL заявка с автоматичен кеш
  let context = getContext()
  let key = if cacheKey.len > 0: cacheKey else: query & $variables
  
  # State за тази заявка
  var state {.global.}: Table[string, GraphQLState[JsonNode]]
  if not state.hasKey(key):
    state[key] = newGraphQLState[JsonNode]()
  
  let queryState = state[key]
  
  # Функция за refetch
  proc refetch() =
    queryState.setLoading(true)
    
    proc onSuccess(response: JsonNode) =
      if response.hasKey("errors") and response["errors"].len > 0:
        queryState.setError(response["errors"][0]["message"].getStr())
      else:
        let data = response.getOrDefault("data")
        queryState.setData(data)
        context.cache.setCached(key, data)
      redraw()
    
    proc onError(error: cstring) =
      queryState.setError($error)
      redraw()
    
    # Използваме kajax за асинхронна заявка
    let requestData = %* {
      "query": query,
      "variables": variables
    }
    
    let headers = newHttpHeaders([
      ("Content-Type", "application/json"),
      ("Accept", "application/json")
    ])
    
    ajaxPost(context.client.config.endpoint, headers, $requestData, onSuccess, onError)
  
  # Проверка в кеша първо
  let cachedData = context.cache.getCached(key)
  if cachedData.isSome and not queryState.loading:
    queryState.setData(cachedData.get())
  elif queryState.data.isNone and not queryState.loading:
    # Стартираме заявката ако няма данни
    refetch()
  
  result = GraphQLHookResult[JsonNode](
    data: queryState.data,
    loading: queryState.loading,
    error: queryState.error,
    refetch: refetch
  )

proc useMutation*(mutation: string): proc(variables: JsonNode): Future[JsonNode] =
  ## Hook за изпълнение на GraphQL мутация
  let context = getContext()
  
  result = proc(variables: JsonNode): Future[JsonNode] =
    let request = newGraphQLRequest(mutation, variables)
    
    # Създаваме Promise wrapper за async операцията
    let promise = newPromise(proc(resolve: proc(val: JsonNode), reject: proc(reason: string)) =
      proc onSuccess(response: JsonNode) =
        if response.hasKey("errors") and response["errors"].len > 0:
          reject(response["errors"][0]["message"].getStr())
        else:
          resolve(response.getOrDefault("data"))
      
      proc onError(error: cstring) =
        reject($error)
      
      let requestData = %* {
        "query": mutation,
        "variables": variables
      }
      
      let headers = newHttpHeaders([
        ("Content-Type", "application/json"),
        ("Accept", "application/json")
      ])
      
      ajaxPost(context.client.config.endpoint, headers, $requestData, onSuccess, onError)
    )
    
    return promise

# Subscription hooks (WebSocket based)
proc useSubscription*(subscription: string, variables: JsonNode = newJObject()): SubscriptionState[JsonNode] =
  ## Hook за GraphQL subscription
  let context = getContext()
  let key = subscription & $variables
  
  if not context.subscriptions.hasKey(key):
    context.subscriptions[key] = SubscriptionState[JsonNode](
      data: none(JsonNode),
      connected: false,
      error: none(string)
    )
    
    # TODO: Имплементиране на WebSocket логика за real-time subscriptions
    console.log("Starting subscription: ", key)
  
  result = context.subscriptions[key]

# Компонент хелпъри
proc renderLoading*(): VNode =
  ## Стандартен loading компонент
  result = buildHtml(tdiv(class = "graphql-loading")):
    text "Зареждане..."

proc renderError*(error: string): VNode =
  ## Стандартен error компонент  
  result = buildHtml(tdiv(class = "graphql-error")):
    text "Грешка: " & error

proc renderData*[T](data: Option[T], loading: bool, error: Option[string], 
                   dataRenderer: proc(data: T): VNode): VNode =
  ## Универсален рендериращ хелпър
  if loading:
    result = renderLoading()
  elif error.isSome:
    result = renderError(error.get())
  elif data.isSome:
    result = dataRenderer(data.get())
  else:
    result = buildHtml(tdiv()):
      text "Няма данни"

# Специализирани hooks за счетоводната система
proc useAccount*(id: int): GraphQLHookResult[JsonNode] =
  ## Hook за получаване на сметка по ID
  let query = buildAccountQuery(id = id)
  result = useQuery(query, newJObject(), "account_" & $id)

proc useAccountByCode*(code: string): GraphQLHookResult[JsonNode] =
  ## Hook за получаване на сметка по код
  let query = buildAccountQuery(code = code)
  result = useQuery(query, newJObject(), "account_code_" & code)

proc useAccounts*(first: int = 10, accountType: string = ""): GraphQLHookResult[JsonNode] =
  ## Hook за списък със сметки
  let query = buildAccountsQuery(first, "", accountType)
  let variables = %* {"first": first, "accountType": accountType}
  result = useQuery(query, variables, "accounts_" & $first & "_" & accountType)

proc useTrialBalance*(asOfDate: string): GraphQLHookResult[JsonNode] =
  ## Hook за оборотна ведомост
  let query = buildTrialBalanceQuery(asOfDate)
  result = useQuery(query, newJObject(), "trial_balance_" & asOfDate)

proc useCreateAccount*(): proc(code: string, name: string, accountType: string): Future[JsonNode] =
  ## Hook за създаване на сметка
  let mutation = useMutation(buildCreateAccountMutation("", "", ""))
  
  result = proc(code: string, name: string, accountType: string): Future[JsonNode] =
    let variables = %* {
      "input": {
        "code": code,
        "name": name,
        "accountType": accountType
      }
    }
    return mutation(variables)

# Предефинирани компоненти
proc AccountCard*(account: JsonNode): VNode =
  ## Компонент за показване на сметка
  let code = account["code"].getStr()
  let name = account["name"].getStr()
  let balance = account["balance"]["amount"].getStr() & " " & account["balance"]["currency"].getStr()
  let accountType = account["accountType"].getStr()
  
  result = buildHtml(tdiv(class = "account-card")):
    h3: text code & " - " & name
    p: text "Тип: " & accountType
    p: text "Баланс: " & balance

proc AccountsList*(first: int = 10, accountType: string = ""): VNode =
  ## Компонент за списък със сметки
  let accountsResult = useAccounts(first, accountType)
  
  result = renderData(accountsResult.data, accountsResult.loading, accountsResult.error,
    proc(data: JsonNode): VNode =
      let edges = data["accounts"]["edges"]
      
      buildHtml(tdiv(class = "accounts-list")):
        h2: text "Сметки"
        for edge in edges:
          AccountCard(edge["node"])
        
        button(onclick = accountsResult.refetch):
          text "Обнови"
  )

proc TrialBalanceReport*(asOfDate: string): VNode =
  ## Компонент за оборотна ведомост
  let balanceResult = useTrialBalance(asOfDate)
  
  result = renderData(balanceResult.data, balanceResult.loading, balanceResult.error,
    proc(data: JsonNode): VNode =
      let trialBalance = data["trialBalance"]
      let accounts = trialBalance["accounts"]
      let totalDebits = trialBalance["totalDebits"]["amount"].getStr()
      let totalCredits = trialBalance["totalCredits"]["amount"].getStr()
      
      buildHtml(tdiv(class = "trial-balance")):
        h2: text "Оборотна ведомост на " & asOfDate
        
        table(class = "trial-balance-table"):
          thead:
            tr:
              th: text "Код"
              th: text "Име на сметката"
              th: text "Дебит"
              th: text "Кредит"
          tbody:
            for account in accounts:
              tr:
                td: text account["accountCode"].getStr()
                td: text account["accountName"].getStr()
                td: text account["debitBalance"]["amount"].getStr()
                td: text account["creditBalance"]["amount"].getStr()
          tfoot:
            tr:
              td(colspan = "2"): text "Общо:"
              td: text totalDebits
              td: text totalCredits
        
        button(onclick = balanceResult.refetch):
          text "Обнови"
  )

# CSS стилове за компонентите
const graphqlStyles* = """
.graphql-loading {
  text-align: center;
  padding: 20px;
  color: #666;
}

.graphql-error {
  background-color: #fee;
  border: 1px solid #fcc;
  color: #c00;
  padding: 10px;
  border-radius: 4px;
  margin: 10px 0;
}

.account-card {
  border: 1px solid #ddd;
  border-radius: 8px;
  padding: 15px;
  margin: 10px 0;
  background: #f9f9f9;
}

.account-card h3 {
  margin: 0 0 10px 0;
  color: #333;
}

.account-card p {
  margin: 5px 0;
  color: #666;
}

.accounts-list {
  max-width: 800px;
  margin: 0 auto;
}

.trial-balance {
  max-width: 1000px;
  margin: 0 auto;
}

.trial-balance-table {
  width: 100%;
  border-collapse: collapse;
  margin: 20px 0;
}

.trial-balance-table th,
.trial-balance-table td {
  border: 1px solid #ddd;
  padding: 8px;
  text-align: left;
}

.trial-balance-table th {
  background-color: #f2f2f2;
  font-weight: bold;
}

.trial-balance-table tfoot td {
  font-weight: bold;
  background-color: #f9f9f9;
}

button {
  background-color: #007bff;
  color: white;
  border: none;
  padding: 8px 16px;
  border-radius: 4px;
  cursor: pointer;
  margin: 5px;
}

button:hover {
  background-color: #0056b3;
}

button:disabled {
  background-color: #ccc;
  cursor: not-allowed;
}
"""

# Utility функция за добавяне на стиловете
proc injectGraphQLStyles*() =
  ## Добавя CSS стилове за GraphQL компонентите
  when defined(js):
    let style = document.createElement("style")
    style.innerHTML = graphqlStyles
    discard document.head.appendChild(style)