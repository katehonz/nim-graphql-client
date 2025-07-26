# GraphQL клиент за Nim с Karax интеграция

Мощен и лесен за използване GraphQL клиент за Nim, специално създаден за работа със z-prologue и счетоводни системи. Поддържа пълна интеграция с Karax за frontend разработка.

## 🌟 Функционалности

- ✅ **Пълен GraphQL клиент** - queries, mutations, subscriptions
- ✅ **Karax интеграция** - React-подобни hooks и компоненти
- ✅ **Автоматично кеширане** - интелигентно кеширане на заявки
- ✅ **Async/Sync поддръжка** - работи в сървър и браузър
- ✅ **Обработка на грешки** - детайлна обработка и retry логика
- ✅ **TypeScript-подобни типове** - силна типизация за GraphQL операции
- ✅ **Ready-made компоненти** - готови компоненти за счетоводни операции

## 📦 Инсталация

```bash
# Клониране на проекта
git clone <repository-url>
cd nim-graphql-client

# Инсталиране на зависимости
nimble install

# Тестване
nimble test
```

## 🚀 Бърз старт

### Основно използване

```nim
import graphql_client
import asyncdispatch, json

proc main() {.async.} =
  # Създаване на клиент
  let client = newGraphQLClient("http://localhost:8080/accounting/graphql")
  
  # Получаване на сметка
  let account = await client.getAccountByCode("1100")
  echo "Сметка: ", account["name"].getStr()
  
  # Създаване на нова сметка
  let newAccount = await client.createAccount(
    code = "1550", 
    name = "Материали", 
    accountType = "ASSET"
  )
  echo "Създадена сметка с ID: ", newAccount["id"].getInt()
  
  client.close()

waitFor main()
```

### Karax интеграция

```nim
import karax/[karax, vdom]
import karax_integration

proc AccountsList(): VNode =
  # Автоматично зареждане на данни с кеширане
  let accountsResult = useAccounts(first = 10, accountType = "ASSET")
  
  result = renderData(accountsResult.data, accountsResult.loading, accountsResult.error,
    proc(data: JsonNode): VNode =
      buildHtml(tdiv):
        h2: text "Сметки"
        for edge in data["accounts"]["edges"]:
          AccountCard(edge["node"])
        
        button(onclick = accountsResult.refetch):
          text "Обнови"
  )

# Инициализация
proc main() =
  discard initKaraxGraphQL("http://localhost:8080/accounting/graphql")
  setRenderer(AccountsList)

main()
```

## 📚 Подробна документация

### 1. Основни операции

#### Създаване на клиент

```nim
let client = newGraphQLClient(
  endpoint = "http://localhost:8080/accounting/graphql",
  headers = {"Authorization": "Bearer token"}.toTable,
  timeout = 30,
  retries = 3,
  cacheEnabled = true
)
```

#### Query операции

```nim
# Получаване на сметка по ID
let account = await client.getAccount(123)

# Получаване на сметка по код
let account = await client.getAccountByCode("1100")

# Списък със сметки с пагинация
let accounts = await client.getAccounts(
  first = 20, 
  after = "cursor_string",
  accountType = "ASSET"
)

# Оборотна ведомост
let trialBalance = await client.getTrialBalance("2024-12-31")
```

#### Mutation операции

```nim
# Създаване на сметка
let account = await client.createAccount(
  code = "1200",
  name = "Банкова сметка",
  accountType = "ASSET"
)

# Потребителска мутация
let customMutation = """
  mutation CreateTransaction($input: CreateTransactionInput!) {
    createTransaction(input: $input) {
      id
      transactionNumber
      status
    }
  }
"""

let variables = %* {
  "input": {
    "description": "Плащане към доставчик",
    "totalAmount": "1500.00",
    "entries": [...]
  }
}

let request = newGraphQLRequest(customMutation, variables)
let response = await client.execute(request)
```

### 2. Karax Hooks

#### useQuery Hook

```nim
proc MyComponent(): VNode =
  let query = """
    query GetAccounts($type: AccountType) {
      accounts(accountType: $type) {
        edges {
          node { id code name balance { amount currency } }
        }
      }
    }
  """
  
  let variables = %* {"type": "ASSET"}
  let result = useQuery(query, variables)
  
  # result съдържа: data, loading, error, refetch
  if result.loading:
    return renderLoading()
  
  if result.error.isSome:
    return renderError(result.error.get())
  
  # Рендериране на данните...
```

#### useMutation Hook

```nim
proc CreateAccountForm(): VNode =
  let createAccount = useCreateAccount()
  
  proc handleSubmit(code, name, accountType: string) =
    discard createAccount(code, name, accountType).then(proc(result: JsonNode) =
      echo "Сметка създадена: ", result["id"].getInt()
      redraw()
    ).catch(proc(error: cstring) =
      echo "Грешка: ", $error
      redraw()
    )
  
  # Форма...
```

#### Специализирани hooks

```nim
# За сметки
let account = useAccount(123)
let accountByCode = useAccountByCode("1100")
let accounts = useAccounts(10, "ASSET")

# За отчети
let trialBalance = useTrialBalance("2024-12-31")

# За мутации
let createAccountMutation = useCreateAccount()
```

### 3. Готови компоненти

```nim
# Карта за сметка
proc MyPage(): VNode =
  buildHtml(tdiv):
    AccountCard(accountData)          # Показва детайли за сметка
    AccountsList(20, "ASSET")         # Списък със сметки
    TrialBalanceReport("2024-12-31")  # Оборотна ведомост
```

### 4. Кеш управление

```nim
# Автоматично кеширане (по подразбиране)
let client = newGraphQLClient(endpoint, cacheEnabled = true)

# Ръчно управление на кеша
client.clearCache()                    # Изчистване на целия кеш
client.removeCacheEntry(request)       # Премахване на конкретна заявка

# Валидност на кеша (по подразбиране 5 минути)
let context = initKaraxGraphQL(endpoint)
context.cache.maxAge = 600.0  # 10 минути
```

### 5. Обработка на грешки

```nim
try:
  let account = await client.getAccount(123)
  echo account["name"].getStr()
except GraphQLClientError as e:
  echo "GraphQL грешка: ", e.msg
  echo "Път: ", e.path.join(" -> ")
  if e.extensions != nil:
    echo "Код: ", e.extensions["code"].getStr()
except Exception as e:
  echo "Мрежова грешка: ", e.msg
```

### 6. Query builders

```nim
# Автоматично генериране на заявки
let accountQuery = buildAccountQuery(id = 123)
let accountsQuery = buildAccountsQuery(first = 10, accountType = "ASSET")
let createMutation = buildCreateAccountMutation("1200", "Банка", "ASSET")
let trialBalanceQuery = buildTrialBalanceQuery("2024-12-31")

# Използване
let request = newGraphQLRequest(accountQuery)
let response = await client.execute(request)
```

## 🏗️ Архитектура

### Структура на проекта

```
nim-graphql-client/
├── src/
│   ├── graphql_client.nim        # Основен GraphQL клиент
│   └── karax_integration.nim     # Karax hooks и компоненти
├── examples/
│   ├── basic_usage.nim           # Основни примери
│   └── karax_app.nim            # Пълно Karax приложение
├── tests/
│   └── test_graphql_client.nim   # Unit тестове
├── docs/                         # Генерирана документация
└── nim_graphql_client.nimble     # Package файл
```

### Основни типове

```nim
# Клиент конфигурация
type GraphQLClientConfig = object
  endpoint: string
  headers: Table[string, string]
  timeout: int
  retries: int
  cacheEnabled: bool

# GraphQL заявка
type GraphQLRequest = object
  query: string
  variables: JsonNode
  operationName: Option[string]

# GraphQL отговор
type GraphQLResponse = object
  data: JsonNode
  errors: seq[GraphQLClientError]
  extensions: JsonNode

# Karax hook резултат
type GraphQLHookResult[T] = object
  data: Option[T]
  loading: bool
  error: Option[string]
  refetch: proc()
```

## 🎯 Специализация за счетоводство

Клиентът е оптимизиран за работа със z-prologue счетоводна система и включва:

### Готови типове за счетоводство

```nim
type
  AccountType = enum
    atAsset = "ASSET"
    atLiability = "LIABILITY"
    atEquity = "EQUITY"
    atIncome = "INCOME"
    atExpense = "EXPENSE"
  
  Money = object
    amount: string
    currency: string
  
  Account = object
    id: int
    code: string
    name: string
    accountType: AccountType
    balance: Money
    isActive: bool
```

### Готови заявки

```nim
# Сметки
client.getAccount(123)
client.getAccountByCode("1100")
client.getAccounts(first = 10, accountType = "ASSET")
client.createAccount("1200", "Банка", "ASSET")

# Отчети
client.getTrialBalance("2024-12-31")
client.getBalanceSheet("2024-12-31")
client.getIncomeStatement("2024-01-01", "2024-12-31")

# Транзакции
client.getTransaction(456)
client.createTransaction(description, amount, entries)
client.approveTransaction(456)
```

### Готови компоненти

```nim
# Основни компоненти
AccountCard(account)                    # Карта за сметка
AccountsList(first, accountType)        # Списък със сметки
TrialBalanceReport(asOfDate)           # Оборотна ведомост

# Форми
CreateAccountForm()                     # Форма за създаване на сметка
TransactionForm()                       # Форма за транзакция

# Навигация
AccountingNavBar()                      # Навигационно меню
```

## 🔧 Конфигурация

### За сървърна употреба

```nim
# config.nim
const 
  GRAPHQL_ENDPOINT = "http://localhost:8080/accounting/graphql"
  REQUEST_TIMEOUT = 30
  MAX_RETRIES = 3

let client = newGraphQLClient(
  endpoint = GRAPHQL_ENDPOINT,
  timeout = REQUEST_TIMEOUT,
  retries = MAX_RETRIES
)
```

### За браузърна употреба

```nim
# Компилация за браузър
# nim js -d:release -o:app.js src/main.nim

# main.nim
import karax_integration

proc initApp() =
  discard initKaraxGraphQL("http://localhost:8080/accounting/graphql")
  injectGraphQLStyles()
  setRenderer(App)

initApp()
```

## 🧪 Тестване

```bash
# Всички тестове
nimble test

# Основни примери
nimble example_basic

# Karax пример (генерира JS файл)
nimble example_karax

# Генериране на документация
nimble docs
```

### Unit тестове

```nim
# test_graphql_client.nim включва:
- Тестове за създаване на клиент
- Валидация на GraphQL заявки
- Парсиране на отговори
- Query builders
- Кеш операции
- Обработка на грешки
- Интеграционни тестове (ако има сървър)
```

## 📈 Performance

### Оптимизации

1. **Автоматично кеширане** - заявките се кешират за 5 минути по подразбиране
2. **Connection pooling** - HTTP връзките се преизползват
3. **Retry логика** - автоматично повторение при неуспех
4. **Lazy loading** - данните се зареждат при нужда
5. **Batch operations** - групиране на множество заявки

### Мониторинг

```nim
# Debug информация
proc main() {.async.} =
  let client = newGraphQLClient(endpoint)
  
  let response = await client.execute(request)
  response.printResponse()  # Debug принтиране
  
  if response.isSuccess():
    echo "Заявката е успешна"
  else:
    for error in response.errors:
      echo "Грешка: ", error.message
```

## 🔐 Сигурност

### Автентификация

```nim
# Bearer token
let headers = {"Authorization": "Bearer your-jwt-token"}.toTable
let client = newGraphQLClient(endpoint, headers)

# API ключ
let headers = {"X-API-Key": "your-api-key"}.toTable
let client = newGraphQLClient(endpoint, headers)

# Персонализирани headers
let headers = {
  "Authorization": "Bearer token",
  "X-User-ID": "123",
  "X-Request-ID": "abc"
}.toTable
```

### Валидация

```nim
# Автоматична валидация на заявки
if not validateGraphQLQuery(query):
  raise newException(ValueError, "Невалидна GraphQL заявка")

# Валидация на счетоводни данни
if not validateAccountCode("1100"):
  raise newException(ValueError, "Невалиден код на сметка")

if not validateAmount("1500.00"):
  raise newException(ValueError, "Невалидна сума")
```

## 🤝 Принос

Този проект е отворен за принос! Моля:

1. Fork на проекта
2. Създаване на feature branch
3. Commit на промените
4. Push към branch-а
5. Отваряне на Pull Request

### Развитие

```bash
# Setup за развитие
git clone <repository-url>
cd nim-graphql-client
nimble install -d

# Тестване на промени
nimble test
nimble example_basic

# Генериране на документация
nimble docs
```

## 📄 Лиценз

MIT License - вижте LICENSE файла за подробности.

## 📞 Поддръжка

За въпроси и подкрепа:
- Отворете GitHub issue
- Пишете на екипа на z-prologue

---

**Създадено с ❤️ от z-prologue екипа за Nim общността**