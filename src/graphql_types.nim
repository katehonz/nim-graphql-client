# GraphQL типове за по-добра type safety
import json, options, tables, strutils

type
  # Основни счетоводни типове
  AccountType* = enum
    atAsset = "ASSET"
    atLiability = "LIABILITY"
    atEquity = "EQUITY"
    atIncome = "INCOME"
    atExpense = "EXPENSE"
  
  Currency* = enum
    currBGN = "BGN"
    currEUR = "EUR"
    currUSD = "USD"
    currGBP = "GBP"
  
  TransactionStatus* = enum
    tsDraft = "DRAFT"
    tsPending = "PENDING"
    tsApproved = "APPROVED"
    tsPosted = "POSTED"
    tsCancelled = "CANCELLED"
  
  # Парични суми
  Money* = object
    amount*: string
    currency*: Currency
  
  # Основни обекти
  Account* = object
    id*: int
    code*: string
    name*: string
    accountType*: AccountType
    balance*: Money
    isActive*: bool
    parentId*: Option[int]
    metadata*: JsonNode
    createdAt*: string
    updatedAt*: string
  
  JournalEntry* = object
    id*: int
    accountId*: int
    accountCode*: string
    debit*: Money
    credit*: Money
    description*: string
    referenceNumber*: Option[string]
  
  Transaction* = object
    id*: int
    transactionNumber*: string
    date*: string
    description*: string
    status*: TransactionStatus
    entries*: seq[JournalEntry]
    totalAmount*: Money
    metadata*: JsonNode
    createdAt*: string
    updatedAt*: string
  
  # Отчети
  TrialBalanceEntry* = object
    accountCode*: string
    accountName*: string
    debitBalance*: Money
    creditBalance*: Money
  
  TrialBalance* = object
    asOfDate*: string
    accounts*: seq[TrialBalanceEntry]
    totalDebits*: Money
    totalCredits*: Money
    isBalanced*: bool
  
  # Pagination типове
  PageInfo* = object
    hasNextPage*: bool
    hasPreviousPage*: bool
    startCursor*: Option[string]
    endCursor*: Option[string]
    totalCount*: int
  
  Edge*[T] = object
    node*: T
    cursor*: string
  
  Connection*[T] = object
    edges*: seq[Edge[T]]
    pageInfo*: PageInfo
  
  # Input типове
  AccountFilter* = object
    accountTypes*: Option[seq[AccountType]]
    isActive*: Option[bool]
    parentId*: Option[int]
    searchTerm*: Option[string]
    balanceGreaterThan*: Option[string]
    balanceLessThan*: Option[string]
  
  PaginationInput* = object
    first*: Option[int]
    last*: Option[int]
    after*: Option[string]
    before*: Option[string]
  
  CreateAccountInput* = object
    code*: string
    name*: string
    accountType*: AccountType
    parentId*: Option[int]
    currency*: Currency
    metadata*: Option[JsonNode]
  
  UpdateAccountInput* = object
    id*: int
    name*: Option[string]
    isActive*: Option[bool]
    parentId*: Option[int]
    metadata*: Option[JsonNode]
  
  JournalEntryInput* = object
    accountCode*: string
    debit*: string
    credit*: string
    description*: string
    referenceNumber*: Option[string]
  
  CreateTransactionInput* = object
    date*: string
    description*: string
    entries*: seq[JournalEntryInput]
    metadata*: Option[JsonNode]

# Конвертиращи функции
proc toMoney*(amount: string, currency: Currency): Money =
  result = Money(amount: amount, currency: currency)

proc toMoney*(json: JsonNode): Money =
  result = Money(
    amount: json["amount"].getStr(),
    currency: parseEnum[Currency](json["currency"].getStr())
  )

proc toJson*(money: Money): JsonNode =
  result = %* {
    "amount": money.amount,
    "currency": $money.currency
  }

proc toAccount*(json: JsonNode): Account =
  result = Account(
    id: json["id"].getInt(),
    code: json["code"].getStr(),
    name: json["name"].getStr(),
    accountType: parseEnum[AccountType](json["accountType"].getStr()),
    balance: json["balance"].toMoney(),
    isActive: json["isActive"].getBool(),
    createdAt: json["createdAt"].getStr(),
    updatedAt: json["updatedAt"].getStr()
  )
  
  if json.hasKey("parentId") and json["parentId"].kind != JNull:
    result.parentId = some(json["parentId"].getInt())
  
  if json.hasKey("metadata"):
    result.metadata = json["metadata"]

proc toJson*(account: Account): JsonNode =
  result = %* {
    "id": account.id,
    "code": account.code,
    "name": account.name,
    "accountType": $account.accountType,
    "balance": account.balance.toJson(),
    "isActive": account.isActive,
    "createdAt": account.createdAt,
    "updatedAt": account.updatedAt
  }
  
  if account.parentId.isSome:
    result["parentId"] = %account.parentId.get()
  
  if account.metadata != nil:
    result["metadata"] = account.metadata

proc toTransaction*(json: JsonNode): Transaction =
  result = Transaction(
    id: json["id"].getInt(),
    transactionNumber: json["transactionNumber"].getStr(),
    date: json["date"].getStr(),
    description: json["description"].getStr(),
    status: parseEnum[TransactionStatus](json["status"].getStr()),
    totalAmount: json["totalAmount"].toMoney(),
    createdAt: json["createdAt"].getStr(),
    updatedAt: json["updatedAt"].getStr()
  )
  
  if json.hasKey("entries"):
    for entryJson in json["entries"]:
      var entry = JournalEntry(
        id: entryJson["id"].getInt(),
        accountId: entryJson["accountId"].getInt(),
        accountCode: entryJson["accountCode"].getStr(),
        debit: entryJson["debit"].toMoney(),
        credit: entryJson["credit"].toMoney(),
        description: entryJson["description"].getStr()
      )
      
      if entryJson.hasKey("referenceNumber") and entryJson["referenceNumber"].kind != JNull:
        entry.referenceNumber = some(entryJson["referenceNumber"].getStr())
      
      result.entries.add(entry)
  
  if json.hasKey("metadata"):
    result.metadata = json["metadata"]

proc toPageInfo*(json: JsonNode): PageInfo =
  result = PageInfo(
    hasNextPage: json["hasNextPage"].getBool(),
    hasPreviousPage: json["hasPreviousPage"].getBool(),
    totalCount: json.getOrDefault("totalCount").getInt(0)
  )
  
  if json.hasKey("startCursor") and json["startCursor"].kind != JNull:
    result.startCursor = some(json["startCursor"].getStr())
  
  if json.hasKey("endCursor") and json["endCursor"].kind != JNull:
    result.endCursor = some(json["endCursor"].getStr())

proc toConnection*[T](json: JsonNode, converterProc: proc(j: JsonNode): T): Connection[T] =
  result.pageInfo = json["pageInfo"].toPageInfo()
  
  for edgeJson in json["edges"]:
    var edge: Edge[T]
    edge.node = converterProc(edgeJson["node"])
    edge.cursor = edgeJson["cursor"].getStr()
    result.edges.add(edge)

# Валидационни функции
proc isValidAccountCode*(code: string): bool =
  ## Валидира счетоводен код
  result = code.len >= 3 and code.len <= 10
  for c in code:
    if not c.isDigit():
      return false

proc isValidAmount*(amount: string): bool =
  ## Валидира парична сума
  try:
    let parts = amount.split('.')
    if parts.len > 2:
      return false
    
    if parts.len == 2 and parts[1].len > 2:
      return false
    
    discard parseFloat(amount)
    return true
  except:
    return false

proc isBalanced*(entries: seq[JournalEntryInput]): bool =
  ## Проверява дали записите са балансирани
  var totalDebit = 0.0
  var totalCredit = 0.0
  
  for entry in entries:
    totalDebit += parseFloat(entry.debit)
    totalCredit += parseFloat(entry.credit)
  
  return abs(totalDebit - totalCredit) < 0.01

# Query builder типове
type
  QueryBuilder* = object
    operation*: string
    name*: string
    fields*: seq[string]
    arguments*: Table[string, string]
    subQueries*: Table[string, QueryBuilder]
  
proc newQueryBuilder*(operation: string, name: string): QueryBuilder =
  result = QueryBuilder(
    operation: operation,
    name: name,
    fields: @[],
    arguments: initTable[string, string](),
    subQueries: initTable[string, QueryBuilder]()
  )

proc addField*(builder: var QueryBuilder, field: string) =
  builder.fields.add(field)

proc addArgument*(builder: var QueryBuilder, key: string, value: string) =
  builder.arguments[key] = value

proc addSubQuery*(builder: var QueryBuilder, name: string, subQuery: QueryBuilder) =
  builder.subQueries[name] = subQuery

proc build*(builder: QueryBuilder): string =
  result = builder.operation & " " & builder.name & " {\n"
  result &= "  " & builder.name
  
  if builder.arguments.len > 0:
    result &= "("
    var first = true
    for key, value in builder.arguments:
      if not first:
        result &= ", "
      result &= key & ": " & value
      first = false
    result &= ")"
  
  result &= " {\n"
  
  for field in builder.fields:
    result &= "    " & field & "\n"
  
  for name, subQuery in builder.subQueries:
    result &= "    " & name & " {\n"
    for field in subQuery.fields:
      result &= "      " & field & "\n"
    result &= "    }\n"
  
  result &= "  }\n}"