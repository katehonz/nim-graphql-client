import ../src/graphql_client
import asyncdispatch, json, tables

# Основен пример за използване на GraphQL клиент

proc basicExample() {.async.} =
  ## Демонстрира основни операции с GraphQL клиент
  echo "=== Основен GraphQL клиент пример ==="
  
  # Създаване на клиент
  let client = newGraphQLClient(
    endpoint = "http://localhost:8080/accounting/graphql",
    headers = initTable[string, string](),
    timeout = 30,
    cacheEnabled = true
  )
  
  try:
    echo "\n1. Получаване на сметка по код..."
    let account = await client.getAccountByCode("1100")
    if account != nil:
      echo "Сметка намерена:"
      echo "  Код: ", account["code"].getStr()
      echo "  Име: ", account["name"].getStr()
      echo "  Тип: ", account["accountType"].getStr()
      echo "  Баланс: ", account["balance"]["amount"].getStr(), " ", account["balance"]["currency"].getStr()
    else:
      echo "Сметка не е намерена"
    
    echo "\n2. Получаване на списък със сметки..."
    let accounts = await client.getAccounts(first = 5, accountType = "ASSET")
    if accounts != nil and accounts.hasKey("edges"):
      echo "Намерени ", accounts["totalCount"].getInt(), " сметки:"
      for edge in accounts["edges"]:
        let node = edge["node"]
        echo "  - ", node["code"].getStr(), ": ", node["name"].getStr()
    
    echo "\n3. Създаване на нова сметка..."
    let newAccount = await client.createAccount(
      code = "1550",
      name = "Основни средства - тестова",
      accountType = "ASSET"
    )
    
    if newAccount != nil:
      echo "Сметка създадена успешно:"
      echo "  ID: ", newAccount["id"].getInt()
      echo "  Код: ", newAccount["code"].getStr()
      echo "  Име: ", newAccount["name"].getStr()
    
    echo "\n4. Получаване на оборотна ведомост..."
    let trialBalance = await client.getTrialBalance("2024-12-31")
    if trialBalance != nil:
      echo "Оборотна ведомост на ", trialBalance["asOfDate"].getStr(), ":"
      echo "  Общо дебит: ", trialBalance["totalDebits"]["amount"].getStr()
      echo "  Общо кредит: ", trialBalance["totalCredits"]["amount"].getStr()
      echo "  Балансирана: ", trialBalance["isBalanced"].getBool()
      
      echo "  Сметки:"
      for account in trialBalance["accounts"]:
        echo "    ", account["accountCode"].getStr(), " - ", account["accountName"].getStr()
        echo "      Дебит: ", account["debitBalance"]["amount"].getStr()
        echo "      Кредит: ", account["creditBalance"]["amount"].getStr()
    
    echo "\n5. Тестване на кеша..."
    echo "Повторно извикване на същата заявка (трябва да използва кеш):"
    let cachedAccount = await client.getAccountByCode("1100")
    if cachedAccount != nil:
      echo "Данни от кеш: ", cachedAccount["name"].getStr()
    
    echo "\n6. Изчистване на кеша..."
    client.clearCache()
    echo "Кешът е изчистен"
    
  except GraphQLClientError as e:
    echo "GraphQL грешка: ", e.msg
    if e.extensions != nil:
      echo "Допълнителна информация: ", $e.extensions
  except Exception as e:
    echo "Грешка: ", e.msg
  finally:
    client.close()

proc customQueryExample() {.async.} =
  ## Демонстрира изпълнение на потребителски GraphQL заявки
  echo "\n=== Потребителски GraphQL заявки ==="
  
  let client = newGraphQLClient("http://localhost:8080/accounting/graphql")
  
  try:
    # Потребителска заявка с променливи
    let customQuery = """
      query GetAccountsWithBalance($accountType: AccountType, $minBalance: String) {
        accounts(first: 10, accountType: $accountType) {
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
          }
          totalCount
        }
      }
    """
    
    let variables = %* {
      "accountType": "ASSET",
      "minBalance": "1000.00"
    }
    
    let request = newGraphQLRequest(customQuery, variables)
    let response = await client.execute(request)
    
    if response.isSuccess():
      echo "Потребителска заявка успешна!"
      echo "Данни: ", $response.data
    else:
      echo "Грешки в заявката:"
      for error in response.errors:
        echo "  - ", error.message
    
    # Мутация за създаване на клиент
    let createCustomerMutation = """
      mutation CreateCustomer($input: CreateCustomerInput!) {
        createCustomer(input: $input) {
          id
          code
          name
          email
          balance {
            amount
            currency
          }
          isActive
        }
      }
    """
    
    let customerVariables = %* {
      "input": {
        "code": "CUST001",
        "name": "Тестов клиент ООД",
        "email": "test@example.com",
        "vatNumber": "123456789",
        "creditLimit": "5000.00"
      }
    }
    
    let mutationRequest = newGraphQLRequest(createCustomerMutation, customerVariables)
    let mutationResponse = await client.execute(mutationRequest)
    
    if mutationResponse.isSuccess():
      echo "Клиент създаден успешно!"
      let customer = mutationResponse.data["createCustomer"]
      echo "ID: ", customer["id"].getInt()
      echo "Име: ", customer["name"].getStr()
    else:
      echo "Грешка при създаване на клиент:"
      for error in mutationResponse.errors:
        echo "  - ", error.message
        
  except Exception as e:
    echo "Грешка: ", e.msg
  finally:
    client.close()

proc errorHandlingExample() {.async.} =
  ## Демонстрира обработка на грешки
  echo "\n=== Обработка на грешки ==="
  
  let client = newGraphQLClient("http://localhost:8080/accounting/graphql")
  
  try:
    # Невалидна заявка
    echo "1. Тестване на невалидна заявка..."
    let invalidQuery = "invalid graphql query"
    let request = newGraphQLRequest(invalidQuery)
    let response = await client.execute(request)
    
    if not response.isSuccess():
      echo "Очаквани грешки при невалидна заявка:"
      for error in response.errors:
        echo "  - ", error.message
        if error.path.len > 0:
          echo "    Път: ", error.path.join(" -> ")
    
    # Заявка към несъществуващ endpoint
    echo "\n2. Тестване на несъществуващ endpoint..."
    let wrongClient = newGraphQLClient("http://localhost:9999/graphql")
    
    let validQuery = buildAccountQuery(id = 1)
    let validRequest = newGraphQLRequest(validQuery)
    
    let wrongResponse = await wrongClient.execute(validRequest)
    if not wrongResponse.isSuccess():
      echo "Очаквани грешки при несъществуващ сървър:"
      for error in wrongResponse.errors:
        echo "  - ", error.message
    
    wrongClient.close()
    
    # Заявка с невалидни данни
    echo "\n3. Тестване на мутация с невалидни данни..."
    let invalidMutation = buildCreateAccountMutation("", "", "INVALID_TYPE")
    let invalidMutationRequest = newGraphQLRequest(invalidMutation)
    let invalidMutationResponse = await client.execute(invalidMutationRequest)
    
    if not invalidMutationResponse.isSuccess():
      echo "Очаквани грешки при невалидни данни:"
      for error in invalidMutationResponse.errors:
        echo "  - ", error.message
        
  except Exception as e:
    echo "Неочаквана грешка: ", e.msg
  finally:
    client.close()

# Главна функция
proc main() {.async.} =
  echo "Стартиране на GraphQL клиент примери..."
  echo "Убедете се, че GraphQL сървърът работи на http://localhost:8080/accounting/graphql"
  echo ""
  
  await basicExample()
  await customQueryExample()
  await errorHandlingExample()
  
  echo "\nПримерите приключиха успешно!"

when isMainModule:
  waitFor main()