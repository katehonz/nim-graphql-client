# GraphQL Client for Nim with Karax Integration

A powerful and easy-to-use GraphQL client for Nim, specifically designed to work with z-prologue and accounting systems. Features full integration with Karax for frontend development.

## 🌟 Features

- ✅ **Complete GraphQL client** - queries, mutations, subscriptions
- ✅ **Karax integration** - React-like hooks and components
- ✅ **Automatic caching** - intelligent query caching
- ✅ **Async/Sync support** - works in server and browser
- ✅ **Error handling** - detailed error handling and retry logic
- ✅ **TypeScript-like types** - strong typing for GraphQL operations
- ✅ **Ready-made components** - pre-built components for accounting operations
- ✅ **Real-time subscriptions** - WebSocket integration for live updates
- ✅ **Account filtering** - filter accounts by type in UI
- ✅ **Transaction history** - view account transactions with details
- ✅ **CSV export** - export reports to CSV format

## 📦 Installation

```bash
# Clone the project
git clone <repository-url>
cd nim-graphql-client

# Install dependencies
nimble install

# Run tests
nimble test
```

## 🚀 Quick Start

### Important: SSL Support

When working with HTTPS endpoints, you must compile with SSL support:

```bash
# Compile with SSL support
nim c -d:ssl your_file.nim

# Or run directly
nim c -d:ssl -r your_file.nim
```

### Basic Usage

```nim
import graphql_client
import asyncdispatch, json

proc main() {.async.} =
  # Create client
  let client = newGraphQLClient("http://localhost:8080/accounting/graphql")
  
  # Get account
  let account = await client.getAccountByCode("1100")
  echo "Account: ", account["name"].getStr()
  
  # Create new account
  let newAccount = await client.createAccount(
    code = "1550", 
    name = "Materials", 
    accountType = "ASSET"
  )
  echo "Created account with ID: ", newAccount["id"].getInt()
  
  client.close()

waitFor main()
```

### Karax Integration

```nim
import karax/[karax, vdom]
import karax_integration

proc AccountsList(): VNode =
  # Automatic data loading with caching
  let accountsResult = useAccounts(first = 10, accountType = "ASSET")
  
  result = renderData(accountsResult.data, accountsResult.loading, accountsResult.error,
    proc(data: JsonNode): VNode =
      buildHtml(tdiv):
        h2: text "Accounts"
        for edge in data["accounts"]["edges"]:
          AccountCard(edge["node"])
        
        button(onclick = accountsResult.refetch):
          text "Refresh"
  )

# Initialization
proc main() =
  discard initKaraxGraphQL("http://localhost:8080/accounting/graphql")
  setRenderer(AccountsList)

main()
```

## 📚 Detailed Documentation

### 1. Basic Operations

#### Creating a Client

```nim
let client = newGraphQLClient(
  endpoint = "http://localhost:8080/accounting/graphql",
  headers = {"Authorization": "Bearer token"}.toTable,
  timeout = 30,
  retries = 3,
  cacheEnabled = true
)
```

#### Query Operations

```nim
# Get account by ID
let account = await client.getAccount(123)

# Get account by code
let account = await client.getAccountByCode("1100")

# List accounts with pagination
let accounts = await client.getAccounts(
  first = 20, 
  after = "cursor_string",
  accountType = "ASSET"
)

# Trial balance
let trialBalance = await client.getTrialBalance("2024-12-31")
```

#### Mutation Operations

```nim
# Create account
let account = await client.createAccount(
  code = "1200",
  name = "Bank Account",
  accountType = "ASSET"
)

# Custom mutation
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
    "description": "Payment to supplier",
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
  
  # result contains: data, loading, error, refetch
  if result.loading:
    return renderLoading()
  
  if result.error.isSome:
    return renderError(result.error.get())
  
  # Render data...
```

#### useMutation Hook

```nim
proc CreateAccountForm(): VNode =
  let createAccount = useCreateAccount()
  
  proc handleSubmit(code, name, accountType: string) =
    discard createAccount(code, name, accountType).then(proc(result: JsonNode) =
      echo "Account created: ", result["id"].getInt()
      redraw()
    ).catch(proc(error: cstring) =
      echo "Error: ", $error
      redraw()
    )
  
  # Form...
```

#### Specialized Hooks

```nim
# For accounts
let account = useAccount(123)
let accountByCode = useAccountByCode("1100")
let accounts = useAccounts(10, "ASSET")

# For reports
let trialBalance = useTrialBalance("2024-12-31")

# For mutations
let createAccountMutation = useCreateAccount()
```

### 3. Ready-made Components

```nim
# Account card
proc MyPage(): VNode =
  buildHtml(tdiv):
    AccountCard(accountData)          # Display account details
    AccountsList(20, "ASSET")         # List of accounts
    TrialBalanceReport("2024-12-31")  # Trial balance report
```

### 4. Cache Management

```nim
# Automatic caching (default)
let client = newGraphQLClient(endpoint, cacheEnabled = true)

# Manual cache management
client.clearCache()                    # Clear entire cache
client.removeCacheEntry(request)       # Remove specific query

# Cache validity (default 5 minutes)
let context = initKaraxGraphQL(endpoint)
context.cache.maxAge = 600.0  # 10 minutes
```

### 5. Error Handling

```nim
try:
  let account = await client.getAccount(123)
  echo account["name"].getStr()
except GraphQLClientError as e:
  echo "GraphQL error: ", e.msg
  echo "Path: ", e.path.join(" -> ")
  if e.extensions != nil:
    echo "Code: ", e.extensions["code"].getStr()
except Exception as e:
  echo "Network error: ", e.msg
```

### 6. Query Builders

```nim
# Automatic query generation
let accountQuery = buildAccountQuery(id = 123)
let accountsQuery = buildAccountsQuery(first = 10, accountType = "ASSET")
let createMutation = buildCreateAccountMutation("1200", "Bank", "ASSET")
let trialBalanceQuery = buildTrialBalanceQuery("2024-12-31")

# Usage
let request = newGraphQLRequest(accountQuery)
let response = await client.execute(request)
```

## 🏗️ Architecture

### Project Structure

```
nim-graphql-client/
├── src/
│   ├── graphql_client.nim        # Core GraphQL client
│   └── karax_integration.nim     # Karax hooks and components
├── examples/
│   ├── basic_usage.nim           # Basic examples
│   └── karax_app.nim            # Complete Karax application
├── tests/
│   └── test_graphql_client.nim   # Unit tests
├── docs/                         # Generated documentation
└── nim_graphql_client.nimble     # Package file
```

### Core Types

```nim
# Client configuration
type GraphQLClientConfig = object
  endpoint: string
  headers: Table[string, string]
  timeout: int
  retries: int
  cacheEnabled: bool

# GraphQL request
type GraphQLRequest = object
  query: string
  variables: JsonNode
  operationName: Option[string]

# GraphQL response
type GraphQLResponse = object
  data: JsonNode
  errors: seq[GraphQLClientError]
  extensions: JsonNode

# Karax hook result
type GraphQLHookResult[T] = object
  data: Option[T]
  loading: bool
  error: Option[string]
  refetch: proc()
```

## 🎯 Accounting Specialization

The client is optimized for working with z-prologue accounting systems and includes:

### Ready-made Accounting Types

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

### Ready-made Queries

```nim
# Accounts
client.getAccount(123)
client.getAccountByCode("1100")
client.getAccounts(first = 10, accountType = "ASSET")
client.createAccount("1200", "Bank", "ASSET")

# Reports
client.getTrialBalance("2024-12-31")
client.getBalanceSheet("2024-12-31")
client.getIncomeStatement("2024-01-01", "2024-12-31")

# Transactions
client.getTransaction(456)
client.createTransaction(description, amount, entries)
client.approveTransaction(456)
```

### Ready-made Components

```nim
# Basic components
AccountCard(account)                    # Account card
AccountsList(first, accountType)        # List of accounts
TrialBalanceReport(asOfDate)           # Trial balance report

# Forms
CreateAccountForm()                     # Account creation form
TransactionForm()                       # Transaction form

# Navigation
AccountingNavBar()                      # Navigation menu
```

## 🔧 Configuration

### For Server Usage

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

### For Browser Usage

```nim
# Compile for browser
# nim js -d:release -o:app.js src/main.nim

# main.nim
import karax_integration

proc initApp() =
  discard initKaraxGraphQL("http://localhost:8080/accounting/graphql")
  injectGraphQLStyles()
  setRenderer(App)

initApp()
```

## 🧪 Testing

### Quick Test with Public APIs

```bash
# Test with real GraphQL endpoints
nim c -d:ssl -r test_quick.nim

# Run comprehensive public API examples
nim c -d:ssl -r examples/public_api_example.nim
```

### Available Public APIs for Testing

The client has been tested with these public GraphQL APIs:

1. **Countries API** - https://countries.trevorblades.com/graphql
   - No authentication required
   - Provides data about countries, continents, and languages
   - Perfect for basic testing

2. **SpaceX API** - https://spacex-production.up.railway.app/
   - Space exploration data
   - Launches, rockets, missions information
   - No authentication required

3. **Rick and Morty API** - https://rickandmortyapi.com/graphql
   - Character, episode, and location data
   - Great for testing pagination and filtering

### Running Tests

```bash
# All unit tests
nimble test

# Quick test with public API
nimble test_public

# Basic examples
nimble example_basic

# Public API examples
nimble example_public

# Advanced usage examples
nimble example_advanced

# Karax example (generates JS file)
nimble example_karax

# Generate documentation
nimble docs

# Clean build artifacts
nimble clean
```

### Unit Tests

```nim
# test_graphql_client.nim includes:
- Client creation tests
- GraphQL query validation
- Response parsing
- Query builders
- Cache operations
- Error handling
- Integration tests (if server available)
```

### Example: Testing with Countries API

```nim
import graphql_client
import asyncdispatch, json

proc testCountriesAPI() {.async.} =
  # No authentication needed
  let client = newGraphQLClient("https://countries.trevorblades.com/graphql")
  
  # Simple query
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
  
  let request = newGraphQLRequest(query)
  let response = await client.execute(request)
  
  if response.isSuccess():
    echo pretty(response.data)
  
  client.close()

waitFor testCountriesAPI()
```

## 📈 Performance

### Optimizations

1. **Automatic caching** - queries are cached for 5 minutes by default
2. **Connection pooling** - HTTP connections are reused
3. **Retry logic** - automatic retry on failure
4. **Lazy loading** - data is loaded when needed
5. **Batch operations** - grouping of multiple queries

### Monitoring

```nim
# Debug information
proc main() {.async.} =
  let client = newGraphQLClient(endpoint)
  
  let response = await client.execute(request)
  response.printResponse()  # Debug printing
  
  if response.isSuccess():
    echo "Query successful"
  else:
    for error in response.errors:
      echo "Error: ", error.message
```

## 🔐 Security

### Authentication

```nim
# Bearer token
let headers = {"Authorization": "Bearer your-jwt-token"}.toTable
let client = newGraphQLClient(endpoint, headers)

# API key
let headers = {"X-API-Key": "your-api-key"}.toTable
let client = newGraphQLClient(endpoint, headers)

# Custom headers
let headers = {
  "Authorization": "Bearer token",
  "X-User-ID": "123",
  "X-Request-ID": "abc"
}.toTable
```

### Validation

```nim
# Automatic query validation
if not validateGraphQLQuery(query):
  raise newException(ValueError, "Invalid GraphQL query")

# Accounting data validation
if not validateAccountCode("1100"):
  raise newException(ValueError, "Invalid account code")

if not validateAmount("1500.00"):
  raise newException(ValueError, "Invalid amount")
```

## 🤝 Contributing

This project is open for contributions! Please:

1. Fork the project
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

### Development

```bash
# Development setup
git clone <repository-url>
cd nim-graphql-client
nimble install -d

# Test changes
nimble test
nimble example_basic

# Generate documentation
nimble docs
```

## 📄 License

MIT License - see LICENSE file for details.

## 📞 Support

For questions and support:
- Open a GitHub issue
- Contact the z-prologue team

---

**Created with ❤️ by the z-prologue team for the Nim community**
